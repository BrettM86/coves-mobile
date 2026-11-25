// RED-phase behavioural tests for UserProfileProvider pagination.
//
// The provider currently funnels first-page and load-more failures into the
// SAME FeedState.error / CommentsState.error field (see loadPosts :210-329
// and loadComments :340-458). profile_screen.dart then has to disambiguate
// by checking `posts.isEmpty` (:478) and re-uses the same string for the
// footer error (:518), so a pagination hiccup poisons the first-page error
// channel.
//
// Target behaviour: a load-more failure is reported on its own channel and
// never touches the first-page error. The load-more channel itself is pinned
// in user_profile_provider_load_more_error_test.dart (compile-red).
//
// This file compiles against today's API on purpose, so the failures are
// real behavioural failures rather than analyzer errors.

import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/liked_item.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_change_broadcast.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart'
    show FakeAuthProvider, unchangingSessionKey;
import '../test_helpers/test_mocks.dart';

const profileDid = 'did:plc:profileowner';

FeedViewPost buildPost(String id) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$id',
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

CommentView buildComment(String id, {CommentViewerState? viewer}) {
  return CommentView(
    uri: 'at://did:plc:author/social.coves.comment.record/$id',
    cid: 'cid-$id',
    record: const CommentRecord(content: 'Test comment content'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: profileDid, handle: 'me.test'),
    post: CommentRef(
      uri: 'at://did:plc:test/social.coves.post.record/123',
      cid: 'post-cid',
    ),
    stats: const CommentStats(score: 1, upvotes: 1),
    viewer: viewer,
  );
}

/// Records the URIs handed to hydrateFeed and hydrateComments, then throws
/// from whichever one [throwsOn] names.
class _ThrowingHydrator extends ViewerStateHydrator {
  _ThrowingHydrator(AuthProvider authProvider, {required this.throwsOn})
    : super(authProvider: authProvider);

  /// 'posts' or 'comments'.
  final String throwsOn;
  final List<String> hydratedPostUris = <String>[];
  final List<String> hydratedCommentUris = <String>[];

  @override
  void hydrateFeed(Iterable<FeedViewPost> feed) {
    hydratedPostUris.addAll(feed.map((item) => item.post.uri));
    if (throwsOn == 'posts') {
      throw StateError('post hydration exploded');
    }
  }

  @override
  void hydrateComments(Iterable<CommentView> comments) {
    hydratedCommentUris.addAll(comments.map((comment) => comment.uri));
    if (throwsOn == 'comments') {
      throw StateError('comment hydration exploded');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late ProfileCache profileCache;
  late UserProfileProvider provider;

  setUp(() async {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();

    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockAuthProvider.did).thenReturn(null);

    profileCache = ProfileCache(mockAuthProvider);
    provider = UserProfileProvider(
      mockAuthProvider,
      apiService: mockApiService,
      commentService: mockCommentService,
      profileCache: profileCache,
      postChangeBroadcast: PostChangeBroadcast(),
      sessionKeyOf: unchangingSessionKey,
    );

    when(
      mockApiService.getProfile(actor: anyNamed('actor')),
    ).thenAnswer((_) async => UserProfile(did: profileDid, handle: 'me.test'));

    await provider.loadProfile(profileDid);
  });

  tearDown(() {
    provider.dispose();
    profileCache.dispose();
  });

  /// Answers getAuthorPosts with [pages] in order; a page may be an
  /// exception to throw instead.
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

  void stubComments(List<Object> pages) {
    var call = 0;
    when(
      mockApiService.getActorComments(
        actor: anyNamed('actor'),
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
      if (page is Future<ActorCommentsResponse>) {
        return page;
      }
      return page as ActorCommentsResponse;
    });
  }

  group('posts pagination', () {
    test(
      'a load-more failure does not populate the first-page error',
      () async {
        stubPosts(<Object>[
          TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
          NetworkException('page 2 exploded'),
        ]);

        await provider.loadPosts(refresh: true);
        expect(provider.postsState.error, isNull);

        await provider.loadMorePosts();

        // The full-screen error channel must stay clean: only the first page
        // failing is a full-screen condition.
        expect(provider.postsState.error, isNull);
      },
    );

    test(
      'a load-more failure keeps the loaded posts, cursor and hasMore',
      () async {
        stubPosts(<Object>[
          TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
          NetworkException('page 2 exploded'),
        ]);

        await provider.loadPosts(refresh: true);
        await provider.loadMorePosts();

        expect(provider.postsState.posts, hasLength(1));
        expect(provider.postsState.cursor, 'c1');
        expect(provider.postsState.hasMore, isTrue);
        expect(provider.postsState.isLoadingMore, isFalse);
        expect(provider.postsState.isLoading, isFalse);
      },
    );

    // SPEC CHANGE (multi-model review, FIX 6): plain loadMorePosts() no
    // longer resumes after a failure — the scroll trigger keeps calling it
    // while the user sits at the bottom, which retried a failing page ~10
    // times a second. Resuming is now an explicit user action.
    test('a load-more retry after a failure still appends', () async {
      stubPosts(<Object>[
        TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
        NetworkException('page 2 exploded'),
        TimelineResponse(feed: <FeedViewPost>[buildPost('b')], cursor: 'c2'),
      ]);

      await provider.loadPosts(refresh: true);
      await provider.loadMorePosts();
      await provider.retryLoadMorePosts();

      expect(provider.postsState.posts, hasLength(2));
      expect(provider.postsState.error, isNull);
      expect(provider.postsState.loadMoreError, isNull);
    });

    test('the scroll trigger cannot re-fire a failed page', () async {
      var requests = 0;
      when(
        mockApiService.getAuthorPosts(
          actor: anyNamed('actor'),
          filter: anyNamed('filter'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async {
        requests++;
        if (requests == 1) {
          return TimelineResponse(
            feed: <FeedViewPost>[buildPost('a')],
            cursor: 'c1',
          );
        }
        throw NetworkException('offline');
      });

      await provider.loadPosts(refresh: true);
      await provider.loadMorePosts();
      await provider.loadMorePosts();
      await provider.loadMorePosts();

      expect(requests, 2);
      expect(provider.postsState.loadMoreError, isNotNull);
    });

    test('an overlapping page is not appended twice', () async {
      // Cursor drift on the server: page 2 repeats a post from page 1. The
      // list keys rows by post URI, so a duplicate is an assertion crash.
      stubPosts(<Object>[
        TimelineResponse(
          feed: <FeedViewPost>[buildPost('a'), buildPost('b')],
          cursor: 'c1',
        ),
        TimelineResponse(
          feed: <FeedViewPost>[buildPost('b'), buildPost('c')],
          cursor: 'c2',
        ),
      ]);

      await provider.loadPosts(refresh: true);
      await provider.loadMorePosts();

      expect(
        provider.postsState.posts.map((p) => p.post.uri).toList(),
        hasLength(3),
      );
      expect(
        provider.postsState.posts.map((p) => p.post.uri).toSet(),
        hasLength(3),
      );
    });

    test(
      'a first-page failure still populates the full-screen error',
      () async {
        stubPosts(<Object>[NetworkException('first page exploded')]);

        await provider.loadPosts(refresh: true);

        expect(provider.postsState.error, isNotNull);
        expect(provider.postsState.posts, isEmpty);
        expect(provider.postsState.isLoading, isFalse);
      },
    );

    test('a refresh after a load-more failure leaves no stale error', () async {
      stubPosts(<Object>[
        TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
        NetworkException('page 2 exploded'),
        TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
      ]);

      await provider.loadPosts(refresh: true);
      await provider.loadMorePosts();
      await provider.loadPosts(refresh: true);

      expect(provider.postsState.error, isNull);
    });
  });

  group('vote hydration', () {
    late MockVoteProvider mockVoteProvider;
    late ProfileCache authedProfileCache;
    late UserProfileProvider authedProvider;

    setUp(() async {
      mockVoteProvider = MockVoteProvider();
      final authedAuthProvider = MockAuthProvider();
      when(authedAuthProvider.isAuthenticated).thenReturn(true);
      when(authedAuthProvider.did).thenReturn(profileDid);

      authedProfileCache = ProfileCache(authedAuthProvider);
      authedProvider = UserProfileProvider(
        authedAuthProvider,
        apiService: mockApiService,
        commentService: mockCommentService,
        profileCache: authedProfileCache,
        voteProvider: mockVoteProvider,
        postChangeBroadcast: PostChangeBroadcast(),
        sessionKeyOf: unchangingSessionKey,
      );

      await authedProvider.loadProfile(profileDid);
    });

    tearDown(() {
      authedProvider.dispose();
      authedProfileCache.dispose();
    });

    test('seeds viewer vote state once per post, page by page', () async {
      // The profile is often a post's first surface this session, so a
      // liked post must show a lit heart. Re-seeding page 1 on every
      // append is how double-counted scores have happened before.
      stubPosts(<Object>[
        TimelineResponse(
          feed: <FeedViewPost>[buildPost('a'), buildPost('b')],
          cursor: 'c1',
        ),
        TimelineResponse(feed: <FeedViewPost>[buildPost('c')], cursor: 'c2'),
      ]);

      await authedProvider.loadPosts(refresh: true);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: buildPost('a').post.uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);

      await authedProvider.loadMorePosts();

      // Page 2 seeds only page 2.
      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: buildPost('c').post.uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);
      verifyNever(
        mockVoteProvider.applyServerVoteState(
          postUri: buildPost('a').post.uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      );
    });

    test('a duplicated post on page 2 is not re-seeded', () async {
      stubPosts(<Object>[
        TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
        TimelineResponse(
          feed: <FeedViewPost>[buildPost('a'), buildPost('b')],
          cursor: 'c2',
        ),
      ]);

      await authedProvider.loadPosts(refresh: true);
      clearInteractions(mockVoteProvider);
      await authedProvider.loadMorePosts();

      verifyNever(
        mockVoteProvider.applyServerVoteState(
          postUri: buildPost('a').post.uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      );
      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: buildPost('b').post.uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);
    });

    test('seeds viewer vote state for comments too', () async {
      stubComments(<Object>[
        ActorCommentsResponse(
          comments: <CommentView>[buildComment('a')],
          cursor: 'c1',
        ),
      ]);

      await authedProvider.loadComments(refresh: true);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: buildComment('a').uri,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);
    });
  });

  group('deleting a comment', () {
    test('removes it from the loaded comments and notifies', () async {
      stubComments(<Object>[
        ActorCommentsResponse(
          comments: <CommentView>[buildComment('a'), buildComment('b')],
          cursor: 'c1',
        ),
      ]);
      when(mockCommentService.deleteComment(uri: anyNamed('uri')))
          .thenAnswer((_) async {});

      await provider.loadComments(refresh: true);

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.deleteComment(commentUri: buildComment('a').uri);

      expect(provider.commentsState.comments.map((c) => c.uri), <String>[
        buildComment('b').uri,
      ]);
      expect(notifications, greaterThanOrEqualTo(1));
      // Page boundaries on the server did not move.
      expect(provider.commentsState.cursor, 'c1');
      expect(provider.commentsState.hasMore, isTrue);
    });

    test('a failed delete leaves the list alone and rethrows', () async {
      stubComments(<Object>[
        ActorCommentsResponse(
          comments: <CommentView>[buildComment('a')],
          cursor: 'c1',
        ),
      ]);
      when(mockCommentService.deleteComment(uri: anyNamed('uri')))
          .thenThrow(ApiException('forbidden'));

      await provider.loadComments(refresh: true);

      await expectLater(
        provider.deleteComment(commentUri: buildComment('a').uri),
        throwsA(isA<ApiException>()),
      );
      expect(provider.commentsState.comments, hasLength(1));
    });
  });

  group('a failed refresh with posts on screen', () {
    test('keeps the posts and reports on the first-page channel', () async {
      // profile_screen only shows the full-screen error when the list is
      // empty, and surfaces this in the list footer otherwise.
      stubPosts(<Object>[
        TimelineResponse(feed: <FeedViewPost>[buildPost('a')], cursor: 'c1'),
        NetworkException('refresh exploded'),
      ]);

      await provider.loadPosts(refresh: true);
      final firstRefreshTime = provider.postsState.lastRefreshTime;
      await provider.loadPosts(refresh: true);

      expect(provider.postsState.posts, hasLength(1));
      expect(provider.postsState.cursor, 'c1');
      expect(provider.postsState.error, isNotNull);
      expect(provider.postsState.isLoading, isFalse);
      // A refresh that never landed must not move "last refreshed".
      expect(provider.postsState.lastRefreshTime, firstRefreshTime);
    });
  });

  group('comments pagination', () {
    test(
      'a load-more failure does not populate the first-page error',
      () async {
        stubComments(<Object>[
          ActorCommentsResponse(
            comments: <CommentView>[buildComment('a')],
            cursor: 'c1',
          ),
          NetworkException('page 2 exploded'),
        ]);

        await provider.loadComments(refresh: true);
        expect(provider.commentsState.error, isNull);

        await provider.loadMoreComments();

        expect(provider.commentsState.error, isNull);
      },
    );

    test('a load-more failure keeps the loaded comments and cursor', () async {
      stubComments(<Object>[
        ActorCommentsResponse(
          comments: <CommentView>[buildComment('a')],
          cursor: 'c1',
        ),
        NetworkException('page 2 exploded'),
      ]);

      await provider.loadComments(refresh: true);
      await provider.loadMoreComments();

      expect(provider.commentsState.comments, hasLength(1));
      expect(provider.commentsState.cursor, 'c1');
      expect(provider.commentsState.isLoadingMore, isFalse);
    });
  });

  group('likes', () {
    // Likes are private to their owner: the tab exists only on the
    // signed-in viewer's own profile.
    late FakeAuthProvider ownerAuth;
    late MockVoteProvider mockVoteProvider;
    late ProfileCache ownerProfileCache;
    late PostChangeBroadcast ownerBroadcast;
    late CommentChangeBroadcast ownerCommentBroadcast;
    late UserProfileProvider ownerProvider;

    /// Every getActorLikes request as (actor, filter, cursor).
    late List<(String, LikesFilter?, String?)> likesRequests;

    setUp(() async {
      ownerAuth = FakeAuthProvider(signedInDid: profileDid);
      mockVoteProvider = MockVoteProvider();
      ownerProfileCache = ProfileCache(ownerAuth);
      ownerBroadcast = PostChangeBroadcast();
      ownerCommentBroadcast = CommentChangeBroadcast();
      ownerProvider = UserProfileProvider(
        ownerAuth,
        apiService: mockApiService,
        commentService: mockCommentService,
        profileCache: ownerProfileCache,
        voteProvider: mockVoteProvider,
        postChangeBroadcast: ownerBroadcast,
        commentChangeBroadcast: ownerCommentBroadcast,
        sessionKeyOf: unchangingSessionKey,
      );
      likesRequests = <(String, LikesFilter?, String?)>[];

      await ownerProvider.loadProfile(profileDid);
    });

    tearDown(() {
      ownerProvider.dispose();
      ownerProfileCache.dispose();
      ownerAuth.dispose();
    });

    /// Answers getActorLikes with [pages] in order; a page may be an
    /// exception to throw, or a Future (a Completer's) to answer later.
    void stubLikes(List<Object> pages) {
      var call = 0;
      when(
        mockApiService.getActorLikes(
          actor: anyNamed('actor'),
          filter: anyNamed('filter'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((invocation) async {
        likesRequests.add((
          invocation.namedArguments[#actor] as String,
          invocation.namedArguments[#filter] as LikesFilter?,
          invocation.namedArguments[#cursor] as String?,
        ));
        final page = pages[call < pages.length ? call : pages.length - 1];
        call++;
        if (page is Exception) {
          throw page;
        }
        if (page is Future<LikesResponse>) {
          return page;
        }
        return page as LikesResponse;
      });
    }

    LikedItem likedPost(String id) => LikedPost(buildPost(id));

    LikedItem likedComment(String id, {required String root}) =>
        LikedComment(comment: buildComment(id), post: buildPost(root).post);

    String describeLike(LikedItem item) => switch (item) {
      LikedPost(:final feedViewPost) => 'post ${feedViewPost.post.uri}',
      LikedComment(:final comment, :final post) =>
        'comment ${comment.uri} on ${post.uri}',
    };

    List<String> likedRows(UserProfileProvider provider) =>
        provider.likesState.items.map(describeLike).toList();

    List<String> likedUris(UserProfileProvider provider) => provider
        .likesState
        .items
        .map(
          (item) => switch (item) {
            LikedPost(:final feedViewPost) => feedViewPost.post.uri,
            LikedComment(:final comment) => comment.uri,
          },
        )
        .toList();

    const postA = 'at://did:plc:author/social.coves.community.post/a';
    const postB = 'at://did:plc:author/social.coves.community.post/b';
    const postRoot = 'at://did:plc:author/social.coves.community.post/root';
    const commentX = 'at://did:plc:author/social.coves.comment.record/x';
    const commentY = 'at://did:plc:author/social.coves.comment.record/y';

    test('loads the first page of the owner\'s likes', () async {
      stubLikes(<Object>[
        LikesResponse(
          feed: <LikedItem>[likedPost('a'), likedPost('b')],
          cursor: 'c1',
        ),
      ]);

      await ownerProvider.loadLikes(refresh: true);

      expect(likedUris(ownerProvider), <String>[postA, postB]);
      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
      ]);
      expect(ownerProvider.likesFilter, LikesFilter.all);
      expect(ownerProvider.likesState.cursor, 'c1');
      expect(ownerProvider.likesState.hasMore, isTrue);
      expect(ownerProvider.likesState.isLoading, isFalse);
      expect(ownerProvider.likesState.error, isNull);
    });

    test(
      'a mixed page lands as liked posts and liked comments in order',
      () async {
        stubLikes(<Object>[
          LikesResponse(
            feed: <LikedItem>[
              likedPost('a'),
              likedComment('x', root: 'root'),
              likedPost('b'),
            ],
            cursor: 'c1',
          ),
        ]);

        await ownerProvider.loadLikes(refresh: true);

        expect(likedRows(ownerProvider), <String>[
          'post $postA',
          'comment $commentX on $postRoot',
          'post $postB',
        ]);
      },
    );

    test('load more appends the next page using the cursor', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        LikesResponse(feed: <LikedItem>[likedPost('b')]),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.loadMoreLikes();

      expect(likedUris(ownerProvider), <String>[postA, postB]);
      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, 'c1'),
      ]);
      expect(ownerProvider.likesState.hasMore, isFalse);
    });

    test('load more passes the cursor and the selected filter', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c0'),
        LikesResponse(
          feed: <LikedItem>[likedComment('x', root: 'root')],
          cursor: 'c1',
        ),
        LikesResponse(feed: <LikedItem>[likedComment('y', root: 'root')]),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.setLikesFilter(LikesFilter.comments);
      await ownerProvider.loadMoreLikes();

      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.comments, null),
        (profileDid, LikesFilter.comments, 'c1'),
      ]);
      expect(likedRows(ownerProvider), <String>[
        'comment $commentX on $postRoot',
        'comment $commentY on $postRoot',
      ]);
    });

    test('retryLikes reloads after a first-page failure', () async {
      stubLikes(<Object>[
        NetworkException('first page exploded'),
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      expect(ownerProvider.likesState.error, isNotNull);
      expect(ownerProvider.likesState.items, isEmpty);

      await ownerProvider.retryLikes();

      expect(likedUris(ownerProvider), <String>[postA]);
      expect(ownerProvider.likesState.error, isNull);
    });

    test('a load-more failure keeps the likes and retryLoadMoreLikes '
        'appends', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        NetworkException('page 2 exploded'),
        LikesResponse(feed: <LikedItem>[likedPost('b')], cursor: 'c2'),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.loadMoreLikes();

      expect(ownerProvider.likesState.loadMoreError, isNotNull);
      expect(ownerProvider.likesState.error, isNull);
      expect(likedUris(ownerProvider), <String>[postA]);

      await ownerProvider.retryLoadMoreLikes();

      expect(likedUris(ownerProvider), <String>[postA, postB]);
      expect(ownerProvider.likesState.loadMoreError, isNull);
      expect(likesRequests.last, (profileDid, LikesFilter.all, 'c1'));
    });

    test('retryLoadMoreLikes after an InvalidCursor load-more reloads from '
        'the first page instead of resending the stale cursor', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        ApiException(
          'That cursor is no longer valid',
          statusCode: 400,
          errorCode: 'InvalidCursor',
        ),
        LikesResponse(
          feed: <LikedItem>[
            likedPost('b'),
            likedComment('x', root: 'root'),
          ],
          cursor: 'c2',
        ),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.loadMoreLikes();
      expect(ownerProvider.likesState.loadMoreError, isNotNull);

      await ownerProvider.retryLoadMoreLikes();

      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, 'c1'),
        (profileDid, LikesFilter.all, null),
      ]);
      expect(likedRows(ownerProvider), <String>[
        'post $postB',
        'comment $commentX on $postRoot',
      ]);
      expect(ownerProvider.likesState.cursor, 'c2');
      expect(ownerProvider.likesState.loadMoreError, isNull);
      expect(ownerProvider.likesState.error, isNull);
    });

    test('a second retryLoadMoreLikes after a failed InvalidCursor recovery '
        'requests the first page again instead of the stale cursor', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        ApiException(
          'That cursor is no longer valid',
          statusCode: 400,
          errorCode: 'InvalidCursor',
        ),
        NetworkException('first page exploded'),
        LikesResponse(
          feed: <LikedItem>[
            likedPost('b'),
            likedComment('x', root: 'root'),
          ],
          cursor: 'c2',
        ),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.loadMoreLikes();
      await ownerProvider.retryLoadMoreLikes();
      await ownerProvider.retryLoadMoreLikes();

      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, 'c1'),
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, null),
      ]);
      expect(likedRows(ownerProvider), <String>[
        'post $postB',
        'comment $commentX on $postRoot',
      ]);
    });

    // One kind failing to hydrate must not leave the other kind's hearts
    // unlit.
    for (final row in <({String throwsOn, String name})>[
      (throwsOn: 'posts', name: 'liked posts fail, liked comments'),
      (throwsOn: 'comments', name: 'liked comments fail, liked posts'),
    ]) {
      test('when hydrating ${row.name} are still hydrated', () async {
        final hydrator = _ThrowingHydrator(ownerAuth, throwsOn: row.throwsOn);
        final hydratedProvider = UserProfileProvider(
          ownerAuth,
          apiService: mockApiService,
          commentService: mockCommentService,
          profileCache: ownerProfileCache,
          voteProvider: mockVoteProvider,
          hydrator: hydrator,
          postChangeBroadcast: ownerBroadcast,
          commentChangeBroadcast: ownerCommentBroadcast,
          sessionKeyOf: unchangingSessionKey,
        );
        addTearDown(hydratedProvider.dispose);
        stubLikes(<Object>[
          LikesResponse(
            feed: <LikedItem>[
              likedPost('a'),
              likedComment('x', root: 'root'),
            ],
          ),
        ]);

        await hydratedProvider.loadProfile(profileDid);
        await hydratedProvider.loadLikes(refresh: true);

        expect(hydrator.hydratedPostUris, <String>[postA]);
        expect(hydrator.hydratedCommentUris, <String>[commentX]);
      });
    }

    group('switching the filter', () {
      test('clears the old rows while the new first page is pending, then '
          'loads it with the new filter', () async {
        final commentsPage = Completer<LikesResponse>();
        stubLikes(<Object>[
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
          commentsPage.future,
        ]);
        await ownerProvider.loadLikes(refresh: true);

        final switching = ownerProvider.setLikesFilter(LikesFilter.comments);

        expect(ownerProvider.likesFilter, LikesFilter.comments);
        expect(ownerProvider.likesState.items, isEmpty);
        expect(likesRequests.last, (profileDid, LikesFilter.comments, null));

        commentsPage.complete(
          LikesResponse(feed: <LikedItem>[likedComment('x', root: 'root')]),
        );
        await switching;

        expect(likedRows(ownerProvider), <String>[
          'comment $commentX on $postRoot',
        ]);
      });

      test('a failed first page for the new filter leaves the old rows '
          'absent', () async {
        stubLikes(<Object>[
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
          NetworkException('comments page exploded'),
        ]);
        await ownerProvider.loadLikes(refresh: true);

        await ownerProvider.setLikesFilter(LikesFilter.comments);

        expect(likesRequests.last, (profileDid, LikesFilter.comments, null));
        expect(ownerProvider.likesState.items, isEmpty);
        expect(ownerProvider.likesState.error, isNotNull);
      });

      test('choosing the selected filter again makes no request', () async {
        stubLikes(<Object>[
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
          LikesResponse(feed: <LikedItem>[likedComment('x', root: 'root')]),
        ]);
        await ownerProvider.loadLikes(refresh: true);

        await ownerProvider.setLikesFilter(LikesFilter.comments);
        await ownerProvider.setLikesFilter(LikesFilter.comments);

        expect(likesRequests, <(String, LikesFilter?, String?)>[
          (profileDid, LikesFilter.all, null),
          (profileDid, LikesFilter.comments, null),
        ]);
        expect(likedRows(ownerProvider), <String>[
          'comment $commentX on $postRoot',
        ]);
      });

      test('a first page for the old filter arriving after the switch does '
          'not land', () async {
        final oldFirstPage = Completer<LikesResponse>();
        stubLikes(<Object>[
          oldFirstPage.future,
          LikesResponse(feed: <LikedItem>[likedComment('x', root: 'root')]),
        ]);

        final oldLoad = ownerProvider.loadLikes(refresh: true);
        await ownerProvider.setLikesFilter(LikesFilter.comments);
        oldFirstPage.complete(
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        );
        await oldLoad;

        expect(likedRows(ownerProvider), <String>[
          'comment $commentX on $postRoot',
        ]);
        expect(ownerProvider.likesState.cursor, isNull);
      });

      test('a load-more for the old filter arriving after the switch does '
          'not land', () async {
        final oldSecondPage = Completer<LikesResponse>();
        stubLikes(<Object>[
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
          oldSecondPage.future,
          LikesResponse(feed: <LikedItem>[likedComment('x', root: 'root')]),
        ]);
        await ownerProvider.loadLikes(refresh: true);

        final oldLoadMore = ownerProvider.loadMoreLikes();
        await ownerProvider.setLikesFilter(LikesFilter.comments);
        oldSecondPage.complete(
          LikesResponse(feed: <LikedItem>[likedPost('b')], cursor: 'c2'),
        );
        await oldLoadMore;

        expect(likedRows(ownerProvider), <String>[
          'comment $commentX on $postRoot',
        ]);
        expect(ownerProvider.likesState.cursor, isNull);
      });
    });

    test('seeds viewer vote state from each liked post', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
      ]);

      await ownerProvider.loadLikes(refresh: true);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postA,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);
    });

    test('seeds viewer vote state for liked comments alongside liked '
        'posts', () async {
      const commentXVote =
          'at://did:plc:profileowner/social.coves.feed.vote/vx';
      stubLikes(<Object>[
        LikesResponse(
          feed: <LikedItem>[
            likedPost('a'),
            LikedComment(
              comment: buildComment(
                'x',
                viewer: CommentViewerState(vote: 'up', voteUri: commentXVote),
              ),
              post: buildPost('root').post,
            ),
          ],
          cursor: 'c1',
        ),
      ]);

      await ownerProvider.loadLikes(refresh: true);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postA,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      ).called(1);
      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: commentX,
          voteDirection: 'up',
          voteUri: commentXVote,
        ),
      ).called(1);
      // The liked comment's root post is context, not a liked item.
      verifyNever(
        mockVoteProvider.applyServerVoteState(
          postUri: postRoot,
          voteDirection: anyNamed('voteDirection'),
          voteUri: anyNamed('voteUri'),
        ),
      );
    });

    test('a removed post leaves the loaded likes', () async {
      stubLikes(<Object>[
        LikesResponse(
          feed: <LikedItem>[likedPost('a'), likedPost('b')],
          cursor: 'c1',
        ),
      ]);
      await ownerProvider.loadLikes(refresh: true);

      ownerBroadcast.removePost(postA);

      expect(likedUris(ownerProvider), <String>[postB]);
      expect(ownerProvider.likesState.cursor, 'c1');
    });

    test('signing out drops the loaded likes', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
      ]);
      await ownerProvider.loadLikes(refresh: true);
      expect(likedUris(ownerProvider), hasLength(1));

      ownerAuth.setSignedInDid(null);

      expect(ownerProvider.likesState.items, isEmpty);
      expect(ownerProvider.likesState.cursor, isNull);
    });

    final sessionChangeRows = <({String name, String? nextDid})>[
      (name: 'signing out', nextDid: null),
      (name: 'switching accounts', nextDid: 'did:plc:someoneelse'),
    ];
    for (final row in sessionChangeRows) {
      test(
        '${row.name} resets the filter to all and drops the likes',
        () async {
          stubLikes(<Object>[
            LikesResponse(
              feed: <LikedItem>[likedComment('x', root: 'root')],
              cursor: 'c1',
            ),
          ]);
          await ownerProvider.setLikesFilter(LikesFilter.comments);
          expect(ownerProvider.likesFilter, LikesFilter.comments);

          ownerAuth.setSignedInDid(row.nextDid);

          expect(ownerProvider.likesFilter, LikesFilter.all);
          expect(ownerProvider.likesState.items, isEmpty);
        },
      );
    }

    // The server drops liked posts the viewer can no longer see (deleted,
    // blocked) after paging, so a page can be empty yet carry a cursor:
    // the list keeps paging past it instead of ending.
    test('load more follows the cursor past an empty page', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        LikesResponse(feed: <LikedItem>[], cursor: 'c2'),
        LikesResponse(feed: <LikedItem>[likedPost('b')]),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      await ownerProvider.loadMoreLikes();
      expect(ownerProvider.likesState.hasMore, isTrue);
      expect(ownerProvider.likesState.cursor, 'c2');
      await ownerProvider.loadMoreLikes();

      expect(likedUris(ownerProvider), <String>[postA, postB]);
      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, 'c1'),
        (profileDid, LikesFilter.all, 'c2'),
      ]);
      expect(ownerProvider.likesState.hasMore, isFalse);
    });

    test('an empty first page with a cursor still has more', () async {
      stubLikes(<Object>[
        LikesResponse(feed: <LikedItem>[], cursor: 'c1'),
        LikesResponse(feed: <LikedItem>[likedPost('a')]),
      ]);

      await ownerProvider.loadLikes(refresh: true);
      expect(ownerProvider.likesState.items, isEmpty);
      expect(ownerProvider.likesState.hasMore, isTrue);
      await ownerProvider.loadMoreLikes();

      expect(likedUris(ownerProvider), <String>[postA]);
      expect(likesRequests, <(String, LikesFilter?, String?)>[
        (profileDid, LikesFilter.all, null),
        (profileDid, LikesFilter.all, 'c1'),
      ]);
    });

    test('a replaced post updates the loaded likes', () async {
      stubLikes(<Object>[
        LikesResponse(
          feed: <LikedItem>[likedPost('a'), likedPost('b')],
          cursor: 'c1',
        ),
      ]);
      await ownerProvider.loadLikes(refresh: true);

      final replacement = buildPost('a').post.copyWith(
        record: const PostRecord(title: 'Edited title', content: 'body'),
      );
      ownerBroadcast.replacePost(replacement);

      expect(
        ownerProvider.likesState.items.map(
          (item) => (item as LikedPost).feedViewPost.post.record?.title,
        ),
        <String?>['Edited title', 'Post b'],
      );
      expect(ownerProvider.likesState.cursor, 'c1');
    });

    group('liked comments follow comment changes', () {
      /// Each liked comment as (uri, content, cid, root post uri); liked
      /// posts as their uri alone.
      List<Object> likedCommentStates() => ownerProvider.likesState.items
          .map(
            (item) => switch (item) {
              LikedPost(:final feedViewPost) => feedViewPost.post.uri,
              LikedComment(:final comment, :final post) => (
                comment.uri,
                comment.content,
                comment.cid,
                post.uri,
              ),
            },
          )
          .toList();

      setUp(() async {
        stubLikes(<Object>[
          LikesResponse(
            feed: <LikedItem>[
              likedPost('a'),
              likedComment('x', root: 'root'),
              likedComment('y', root: 'root'),
            ],
            cursor: 'c1',
          ),
        ]);
        await ownerProvider.loadLikes(refresh: true);
      });

      test('deleting a liked comment removes it from the likes', () async {
        when(mockCommentService.deleteComment(uri: anyNamed('uri')))
            .thenAnswer((_) async {});

        await ownerProvider.deleteComment(commentUri: commentX);

        expect(likedRows(ownerProvider), <String>[
          'post $postA',
          'comment $commentY on $postRoot',
        ]);
        expect(ownerProvider.likesState.cursor, 'c1');
      });

      test('editing a liked comment patches it in the likes', () async {
        when(
          mockCommentService.updateComment(
            uri: anyNamed('uri'),
            content: anyNamed('content'),
            facets: anyNamed('facets'),
            record: anyNamed('record'),
          ),
        ).thenAnswer(
          (invocation) async => UpdateCommentResponse(
            uri: invocation.namedArguments[#uri] as String,
            cid: 'cid-edited',
          ),
        );

        await ownerProvider.updateComment(
          comment: buildComment('x'),
          content: 'Edited here',
        );

        expect(likedCommentStates(), <Object>[
          postA,
          (commentX, 'Edited here', 'cid-edited', postRoot),
          (commentY, 'Test comment content', 'cid-y', postRoot),
        ]);
      });

      test('deleting a liked comment while the Comments first page is in '
          'flight keeps it out of the comments', () async {
        final commentsPage = Completer<ActorCommentsResponse>();
        stubComments(<Object>[commentsPage.future]);
        when(mockCommentService.deleteComment(uri: anyNamed('uri')))
            .thenAnswer((_) async {});

        final loading = ownerProvider.loadComments(refresh: true);
        await ownerProvider.deleteComment(commentUri: commentX);
        commentsPage.complete(
          ActorCommentsResponse(
            comments: <CommentView>[buildComment('x'), buildComment('y')],
            cursor: 'c1',
          ),
        );
        await loading;

        expect(ownerProvider.commentsState.comments.map((c) => c.uri), <String>[
          commentY,
        ]);
      });

      test('editing a comment loaded in both Comments and Likes patches '
          'both copies', () async {
        stubComments(<Object>[
          ActorCommentsResponse(
            comments: <CommentView>[buildComment('x'), buildComment('y')],
            cursor: 'c1',
          ),
        ]);
        await ownerProvider.loadComments(refresh: true);
        when(
          mockCommentService.updateComment(
            uri: anyNamed('uri'),
            content: anyNamed('content'),
            facets: anyNamed('facets'),
            record: anyNamed('record'),
          ),
        ).thenAnswer(
          (invocation) async => UpdateCommentResponse(
            uri: invocation.namedArguments[#uri] as String,
            cid: 'cid-edited',
          ),
        );

        await ownerProvider.updateComment(
          comment: buildComment('x'),
          content: 'Edited in both',
        );

        expect(
          ownerProvider.commentsState.comments.map(
            (c) => (c.uri, c.content, c.cid),
          ),
          <(String, String, String)>[
            (commentX, 'Edited in both', 'cid-edited'),
            (commentY, 'Test comment content', 'cid-y'),
          ],
        );
        expect(likedCommentStates(), <Object>[
          postA,
          (commentX, 'Edited in both', 'cid-edited', postRoot),
          (commentY, 'Test comment content', 'cid-y', postRoot),
        ]);
      });

      test('an edit broadcast from another screen patches the liked '
          'comment', () async {
        ownerCommentBroadcast.replaceComment(
          buildComment('x').withEditedRecord(
            record: const CommentRecord(content: 'Edited elsewhere'),
            cid: 'cid-broadcast',
          ),
        );

        expect(likedCommentStates(), <Object>[
          postA,
          (commentX, 'Edited elsewhere', 'cid-broadcast', postRoot),
          (commentY, 'Test comment content', 'cid-y', postRoot),
        ]);
      });
    });

    final nonOwnerRows = <({String name, String? viewerDid})>[
      (name: 'signed out', viewerDid: null),
      (name: 'signed in as someone else', viewerDid: 'did:plc:someoneelse'),
    ];
    for (final row in nonOwnerRows) {
      test('makes no likes request when the viewer is ${row.name}', () async {
        stubLikes(<Object>[
          LikesResponse(feed: <LikedItem>[likedPost('a')], cursor: 'c1'),
        ]);
        final viewerAuth = FakeAuthProvider(signedInDid: row.viewerDid);
        final viewerCache = ProfileCache(viewerAuth);
        final viewerProvider = UserProfileProvider(
          viewerAuth,
          apiService: mockApiService,
          commentService: mockCommentService,
          profileCache: viewerCache,
          postChangeBroadcast: PostChangeBroadcast(),
          sessionKeyOf: unchangingSessionKey,
        );
        addTearDown(() {
          viewerProvider.dispose();
          viewerCache.dispose();
          viewerAuth.dispose();
        });
        await viewerProvider.loadProfile(profileDid);

        await viewerProvider.loadLikes(refresh: true);
        await viewerProvider.loadMoreLikes();
        await viewerProvider.retryLikes();
        await viewerProvider.setLikesFilter(LikesFilter.comments);

        expect(likesRequests, isEmpty);
        expect(viewerProvider.likesState.items, isEmpty);
      });
    }
  });
}
