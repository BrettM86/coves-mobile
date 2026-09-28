import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'comments_provider_test.mocks.dart';

// Acceptance test for the CommentsProvider pagination migration: a failed
// sort change must leave the displayed thread, its sort, and its pagination
// position untouched, and report the failure only through setSortOption's
// return value (the screen shows a snackbar), never through provider.error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
  const testPostCid = 'test-post-cid';

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockVoteProvider mockVoteProvider;
  late CommentsProvider commentsProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockVoteProvider = MockVoteProvider();

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(
      mockAuthProvider.getAccessToken(),
    ).thenAnswer((_) async => 'test-token');

    commentsProvider = CommentsProvider(
      mockAuthProvider,
      postUri: testPostUri,
      postCid: testPostCid,
      apiService: mockApiService,
      voteProvider: mockVoteProvider,
    );
  });

  tearDown(() {
    commentsProvider.dispose();
  });

  test('a failed sort change keeps the hot thread, its sort, and its cursor, '
      'and never surfaces a first-page error', () async {
    final firstPage = [
      _createThreadComment('comment-hot-1'),
      _createThreadComment('comment-hot-2'),
    ];
    final secondPage = [_createThreadComment('comment-hot-3')];

    // Route every getComments call by its sort and cursor:
    // hot first page -> page 1 with cursor C1, hot cursor C1 -> page 2,
    // any 'new' request -> ApiException.
    when(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((invocation) async {
      final sort = invocation.namedArguments[#sort] as String?;
      final cursor = invocation.namedArguments[#cursor] as String?;
      if (sort == 'new') {
        throw ApiException('Failed to load comments', statusCode: 500);
      }
      if (sort == 'hot' && cursor == null) {
        return CommentsResponse(post: {}, comments: firstPage, cursor: 'C1');
      }
      if (sort == 'hot' && cursor == 'C1') {
        return CommentsResponse(post: {}, comments: secondPage);
      }
      throw StateError('Unexpected getComments(sort: $sort, cursor: $cursor)');
    });

    // Given: the first load (sort 'hot') returned page 1 with cursor C1.
    await commentsProvider.loadComments(refresh: true);
    expect(commentsProvider.sort, 'hot');
    expect(
      commentsProvider.comments.map((thread) => thread.comment.uri).toList(),
      ['comment-hot-1', 'comment-hot-2'],
    );
    expect(commentsProvider.hasMore, isTrue);

    final observedErrors = <String>[];
    commentsProvider.addListener(() {
      final error = commentsProvider.error;
      if (error != null) {
        observedErrors.add(error);
      }
    });

    // When: the user switches to 'new' and that request fails.
    final sortChangeSucceeded = await commentsProvider.setSortOption('new');

    // Then: the failure is reported only through the return value.
    expect(
      sortChangeSucceeded,
      isFalse,
      reason: 'a failed, current sort change must report failure',
    );
    expect(
      commentsProvider.sort,
      'hot',
      reason: 'the sort label must revert to the sort actually displayed',
    );
    expect(
      commentsProvider.comments.map((thread) => thread.comment.uri).toList(),
      ['comment-hot-1', 'comment-hot-2'],
      reason: 'the displayed hot page 1 must be kept',
    );
    expect(
      commentsProvider.error,
      isNull,
      reason: 'the snackbar is the only report of a failed sort change',
    );
    expect(
      observedErrors,
      isEmpty,
      reason: 'no listener may observe the first-page error during the revert',
    );

    // And: the next page continues the hot thread from cursor C1.
    clearInteractions(mockApiService);
    await commentsProvider.loadMoreComments();

    final captured = verify(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: captureAnyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: captureAnyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).captured;
    expect(captured, ['hot', 'C1']);
    expect(
      commentsProvider.comments.map((thread) => thread.comment.uri).toList(),
      ['comment-hot-1', 'comment-hot-2', 'comment-hot-3'],
    );
  });
}

ThreadViewComment _createThreadComment(String uri) {
  return ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: const CommentRecord(content: 'Test comment content'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      post: CommentRef(
        uri: 'at://did:plc:test/social.coves.post.record/123',
        cid: 'post-cid',
      ),
      stats: const CommentStats(score: 10, upvotes: 12, downvotes: 2),
    ),
  );
}
