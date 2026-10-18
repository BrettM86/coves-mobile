// Broadcast removal drops a deleted post from the loaded
// profile posts in place: order is kept, nothing else about the posts state
// changes, and nothing is refetched. A load-more that is in flight when the
// post is removed appends onto the list as it is now, so the post stays gone.

import 'dart:async';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart' show unchangingSessionKey;
import '../test_helpers/test_mocks.dart';

const String profileDid = 'did:plc:profileowner';
const String pageTwoCursor = 'c1';
const String pageThreeCursor = 'c2';

class _RecordingBroadcast extends PostChangeBroadcast {
  int adds = 0;
  int removes = 0;

  @override
  void addPostChangeListener(PostChangeListener listener) {
    adds++;
    super.addPostChangeListener(listener);
  }

  @override
  void removePostChangeListener(PostChangeListener listener) {
    removes++;
    super.removePostChangeListener(listener);
  }
}

String postUri(String id) =>
    'at://did:plc:profileowner/social.coves.community.post/$id';

FeedViewPost buildPost(String id) {
  return FeedViewPost(
    post: PostView(
      uri: postUri(id),
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(did: profileDid, handle: 'me.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: 'Post $id', content: 'body'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
    ),
  );
}

List<String> postUris(UserProfileProvider provider) =>
    provider.postsState.posts.map((feedPost) => feedPost.post.uri).toList();

/// Everything in the posts state except the posts themselves.
Map<String, Object?> nonPostFields(UserProfileProvider provider) {
  final state = provider.postsState;
  return {
    'cursor': state.cursor,
    'hasMore': state.hasMore,
    'isLoading': state.isLoading,
    'isLoadingMore': state.isLoadingMore,
    'error': state.error,
    'loadMoreError': state.loadMoreError,
    'scrollPosition': state.scrollPosition,
    'lastRefreshTime': state.lastRefreshTime,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late ProfileCache profileCache;
  late UserProfileProvider provider;
  late _RecordingBroadcast broadcast;
  var disposed = false;

  setUp(() async {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();

    // Signed in as the profile's owner, who is the one deleting posts.
    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn(profileDid);

    profileCache = ProfileCache(mockAuthProvider);
    broadcast = _RecordingBroadcast();
    disposed = false;
    provider = UserProfileProvider(
      mockAuthProvider,
      apiService: mockApiService,
      commentService: mockCommentService,
      profileCache: profileCache,
      postChangeBroadcast: broadcast,
      sessionKeyOf: unchangingSessionKey,
    );

    when(
      mockApiService.getProfile(actor: anyNamed('actor')),
    ).thenAnswer((_) async => UserProfile(did: profileDid, handle: 'me.test'));

    await provider.loadProfile(profileDid);
  });

  tearDown(() {
    if (!disposed) {
      provider.dispose();
    }
    profileCache.dispose();
  });

  /// Answers getAuthorPosts with [answer], given the requested cursor.
  void stubAuthorPosts(
    Future<TimelineResponse> Function(String? cursor) answer,
  ) {
    when(
      mockApiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (invocation) => answer(invocation.namedArguments[#cursor] as String?),
    );
  }

  final pageOne = TimelineResponse(
    feed: [buildPost('a'), buildPost('b'), buildPost('c')],
    cursor: pageTwoCursor,
  );

  group('with page one [A, B, C] loaded and more to come', () {
    late List<String?> requestedCursors;

    setUp(() async {
      requestedCursors = <String?>[];
      stubAuthorPosts((cursor) {
        requestedCursors.add(cursor);
        return Future.value(pageOne);
      });

      await provider.loadPosts(refresh: true);

      // The fixture is what the tests below rely on.
      expect(postUris(provider), [postUri('a'), postUri('b'), postUri('c')]);
      expect(provider.postsState.cursor, pageTwoCursor);
      expect(provider.postsState.hasMore, isTrue);
      expect(requestedCursors, [null]);
    });

    test('B6 removes the post in place, keeps the rest of the state, notifies '
        'and fetches nothing', () {
      var notifications = 0;
      provider.addListener(() => notifications++);
      final fieldsBefore = nonPostFields(provider);

      broadcast.removePost(postUri('a'));

      expect(postUris(provider), [postUri('b'), postUri('c')]);
      expect(nonPostFields(provider), fieldsBefore);
      expect(notifications, 1);
      expect(requestedCursors, [null]);
    });

    test('B6 a uri that is not loaded changes nothing and does not notify', () {
      var notifications = 0;
      provider.addListener(() => notifications++);
      final fieldsBefore = nonPostFields(provider);

      broadcast.removePost(postUri('not-loaded'));

      expect(postUris(provider), [postUri('a'), postUri('b'), postUri('c')]);
      expect(nonPostFields(provider), fieldsBefore);
      expect(notifications, 0);
      expect(requestedCursors, [null]);
    });
  });

  test('B4 a post removed while load-more is in flight does not come back when '
      'the page lands', () async {
    final pageTwo = Completer<TimelineResponse>();
    final requestedCursors = <String?>[];
    stubAuthorPosts((cursor) {
      requestedCursors.add(cursor);
      if (cursor == null) {
        return Future.value(pageOne);
      }
      return pageTwo.future;
    });

    await provider.loadPosts(refresh: true);
    expect(postUris(provider), [postUri('a'), postUri('b'), postUri('c')]);

    // Page two is requested and held open.
    final loadMore = provider.loadMorePosts();
    expect(requestedCursors, [null, pageTwoCursor]);
    expect(provider.postsState.isLoadingMore, isTrue);

    // The post is removed while page two is pending, and disappears now.
    broadcast.removePost(postUri('a'));
    expect(postUris(provider), [postUri('b'), postUri('c')]);

    pageTwo.complete(
      TimelineResponse(
        feed: [buildPost('a'), buildPost('d')],
        cursor: pageThreeCursor,
      ),
    );
    await loadMore;

    expect(postUris(provider), [
      'at://did:plc:profileowner/social.coves.community.post/b',
      'at://did:plc:profileowner/social.coves.community.post/c',
      'at://did:plc:profileowner/social.coves.community.post/d',
    ]);
    expect(provider.postsState.cursor, pageThreeCursor);
    expect(provider.postsState.hasMore, isTrue);
    expect(provider.postsState.isLoadingMore, isFalse);
    expect(provider.postsState.loadMoreError, isNull);
    expect(requestedCursors, [null, pageTwoCursor]);
  });

  test('B4 a post removed before its page is loaded does not appear when the '
      'in-flight page lands', () async {
    final pageTwo = Completer<TimelineResponse>();
    stubAuthorPosts((cursor) {
      if (cursor == null) {
        return Future.value(
          TimelineResponse(
            feed: [buildPost('b'), buildPost('c')],
            cursor: pageTwoCursor,
          ),
        );
      }
      return pageTwo.future;
    });

    await provider.loadPosts(refresh: true);
    expect(postUris(provider), [postUri('b'), postUri('c')]);

    final loadMore = provider.loadMorePosts();
    expect(provider.postsState.isLoadingMore, isTrue);

    broadcast.removePost(postUri('a'));
    expect(postUris(provider), [postUri('b'), postUri('c')]);

    pageTwo.complete(
      TimelineResponse(
        feed: [buildPost('a'), buildPost('d')],
        cursor: pageThreeCursor,
      ),
    );
    await loadMore;

    expect(postUris(provider), [
      'at://did:plc:profileowner/social.coves.community.post/b',
      'at://did:plc:profileowner/social.coves.community.post/c',
      'at://did:plc:profileowner/social.coves.community.post/d',
    ]);
  });

  test(
    'B5 disposed profile unsubscribes and ignores both post changes',
    () async {
      stubAuthorPosts((cursor) async => pageOne);
      await provider.loadPosts(refresh: true);
      var notifications = 0;
      provider.addListener(() => notifications++);
      expect(broadcast.adds, 1);

      provider.dispose();
      disposed = true;
      expect(broadcast.removes, 1);
      expect(broadcast.adds, broadcast.removes);

      expect(() {
        broadcast
          ..removePost(postUri('a'))
          ..replacePost(buildPost('a').post);
      }, returnsNormally);
      expect(notifications, 0);
    },
  );
}
