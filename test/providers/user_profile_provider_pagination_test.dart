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

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

const profileDid = 'did:plc:profileowner';

FeedViewPost buildPost(String id) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$id',
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(did: profileDid, handle: 'me.test'),
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

CommentView buildComment(String id) {
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
      (_) async => UserProfile(did: profileDid, handle: 'me.test'),
    );

    await provider.loadProfile(profileDid);
  });

  tearDown(() {
    provider.dispose();
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
      return page as ActorCommentsResponse;
    });
  }

  group('posts pagination', () {
    test('a load-more failure does not populate the first-page error',
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
    });

    test('a load-more failure keeps the loaded posts, cursor and hasMore',
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
    });

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

    test('a first-page failure still populates the full-screen error',
        () async {
      stubPosts(<Object>[NetworkException('first page exploded')]);

      await provider.loadPosts(refresh: true);

      expect(provider.postsState.error, isNotNull);
      expect(provider.postsState.posts, isEmpty);
      expect(provider.postsState.isLoading, isFalse);
    });

    test('a refresh after a load-more failure leaves no stale error',
        () async {
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
    late UserProfileProvider authedProvider;

    setUp(() async {
      mockVoteProvider = MockVoteProvider();
      final authedAuthProvider = MockAuthProvider();
      when(authedAuthProvider.isAuthenticated).thenReturn(true);
      when(authedAuthProvider.did).thenReturn(profileDid);

      authedProvider = UserProfileProvider(
        authedAuthProvider,
        apiService: mockApiService,
        commentService: mockCommentService,
        voteProvider: mockVoteProvider,
      );

      await authedProvider.loadProfile(profileDid);
    });

    tearDown(() {
      authedProvider.dispose();
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
      when(
        mockCommentService.deleteComment(uri: anyNamed('uri')),
      ).thenAnswer((_) async {});

      await provider.loadComments(refresh: true);

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.deleteComment(commentUri: buildComment('a').uri);

      expect(
        provider.commentsState.comments.map((c) => c.uri),
        <String>[buildComment('b').uri],
      );
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
      when(
        mockCommentService.deleteComment(uri: anyNamed('uri')),
      ).thenThrow(ApiException('forbidden'));

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
    test('a load-more failure does not populate the first-page error',
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
    });

    test('a load-more failure keeps the loaded comments and cursor',
        () async {
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
}
