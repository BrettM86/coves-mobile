// RED-phase API pin for the separated load-more error channel.
//
// Compile-red until FeedState and CommentsState carry a `loadMoreError`
// field alongside `error` (the same split CursorPaginationController makes).
// Self-contained: only this file references the new field, so the rest of
// the suite keeps compiling.
//
// Pinned decision: the load-more error is exposed on the existing state
// objects the screens already read (profile_screen.dart:466/548), so the
// provider's public surface (postsState / commentsState / loadPosts /
// loadMorePosts / loadComments / loadMoreComments / retryPosts /
// retryComments) is unchanged.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

const _profileDid = 'did:plc:profileowner';

FeedViewPost _post(String id) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$id',
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(did: _profileDid, handle: 'me.test'),
      community: CommunityRef(
        did: 'did:plc:community',
        name: 'test-community',
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: 'Post $id', content: 'body'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late UserProfileProvider provider;

  setUp(() async {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();

    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockAuthProvider.did).thenReturn(null);

    provider = UserProfileProvider(
      mockAuthProvider,
      apiService: mockApiService,
      commentService: mockCommentService,
    );

    when(mockApiService.getProfile(actor: anyNamed('actor'))).thenAnswer(
      (_) async => UserProfile(did: _profileDid, handle: 'me.test'),
    );

    await provider.loadProfile(_profileDid);
  });

  tearDown(() {
    provider.dispose();
  });

  void stubPosts(List<Object> pages) {
    var call = 0;
    when(
      mockApiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      final page = pages[call < pages.length ? call : pages.length - 1];
      call++;
      if (page is Exception) {
        throw page;
      }
      return page as TimelineResponse;
    });
  }

  test('a load-more failure lands on postsState.loadMoreError', () async {
    stubPosts(<Object>[
      TimelineResponse(feed: <FeedViewPost>[_post('a')], cursor: 'c1'),
      NetworkException('page 2 exploded'),
    ]);

    await provider.loadPosts(refresh: true);
    await provider.loadMorePosts();

    expect(provider.postsState.loadMoreError, isNotNull);
    expect(provider.postsState.error, isNull);
  });

  test('a refresh clears a stale postsState.loadMoreError', () async {
    stubPosts(<Object>[
      TimelineResponse(feed: <FeedViewPost>[_post('a')], cursor: 'c1'),
      NetworkException('page 2 exploded'),
      TimelineResponse(feed: <FeedViewPost>[_post('a')], cursor: 'c1'),
    ]);

    await provider.loadPosts(refresh: true);
    await provider.loadMorePosts();
    expect(provider.postsState.loadMoreError, isNotNull);

    await provider.loadPosts(refresh: true);

    expect(provider.postsState.loadMoreError, isNull);
  });

  test('commentsState carries its own loadMoreError', () async {
    var call = 0;
    when(
      mockApiService.getActorComments(
        actor: anyNamed('actor'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      call++;
      if (call > 1) {
        throw NetworkException('page 2 exploded');
      }
      return ActorCommentsResponse(
        comments: <CommentView>[
          CommentView(
            uri: 'at://did:plc:author/social.coves.comment.record/a',
            cid: 'cid-a',
            record: const CommentRecord(content: 'Test comment content'),
            createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
            indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
            author: AuthorView(did: _profileDid, handle: 'me.test'),
            post: CommentRef(
              uri: 'at://did:plc:test/social.coves.post.record/123',
              cid: 'post-cid',
            ),
            stats: const CommentStats(score: 1, upvotes: 1),
          ),
        ],
        cursor: 'c1',
      );
    });

    await provider.loadComments(refresh: true);
    await provider.loadMoreComments();

    expect(provider.commentsState.loadMoreError, isNotNull);
    expect(provider.commentsState.error, isNull);
  });
}
