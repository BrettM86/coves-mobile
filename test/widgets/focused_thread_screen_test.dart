import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

// Shared generated mockito mocks (real provider types) so provider lookups
// inside the screen and CommentCard resolve correctly.
import '../test_helpers/test_mocks.dart';

void main() {
  const postUri = 'at://did:plc:test/social.coves.community.post/123';
  const postCid = 'post-cid';
  const authorDid = 'did:plc:author';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late BlockProvider blockProvider;
  late CommentsProvider commentsProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );

    // Signed-out by default: CommentCard hides the actions menu and the
    // vote button renders in the un-liked state.
    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any)).thenAnswer(
      (invocation) => invocation.positionalArguments[1] as int,
    );

    commentsProvider = CommentsProvider(
      mockAuthProvider,
      postUri: postUri,
      postCid: postCid,
      apiService: mockApiService,
      voteProvider: mockVoteProvider,
      commentService: mockCommentService,
    );
  });

  tearDown(() {
    commentsProvider.dispose();
  });

  /// Stubs every getComments call. [responder] receives the parentRkey of
  /// the request (null for a top-level thread fetch) and returns the
  /// response to serve.
  void stubGetComments(
    CommentsResponse Function(String? parentRkey) responder,
  ) {
    when(mockApiService.getComments(
      postUri: anyNamed('postUri'),
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      depth: anyNamed('depth'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      parentRkey: anyNamed('parentRkey'),
    )).thenAnswer(
      (invocation) async =>
          responder(invocation.namedArguments[#parentRkey] as String?),
    );
  }

  /// Helper to create a test comment. The rkey (last URI segment) is what
  /// loadMoreReplies sends as parentRkey.
  CommentView createComment({
    required String rkey,
    String content = 'Test comment',
    String handle = 'test.user',
    int replyCount = 0,
  }) {
    final uri = 'at://did:plc:test/social.coves.community.comment/$rkey';
    return CommentView(
      uri: uri,
      cid: 'cid-$rkey',
      record: CommentRecord(content: content),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: authorDid, handle: handle),
      post: CommentRef(uri: postUri, cid: postCid),
      stats: CommentStats(
        upvotes: 5,
        downvotes: 1,
        score: 4,
        replyCount: replyCount,
      ),
    );
  }

  /// Helper to create a thread with nested replies
  ThreadViewComment createThread({
    required String rkey,
    String content = 'Test comment',
    int replyCount = 0,
    List<ThreadViewComment>? replies,
    bool hasMore = false,
  }) {
    return ThreadViewComment(
      comment: createComment(
        rkey: rkey,
        content: content,
        replyCount: replyCount,
      ),
      replies: replies,
      hasMore: hasMore,
    );
  }

  CommentsResponse response(
    List<ThreadViewComment> comments, {
    String? cursor,
  }) {
    return CommentsResponse(post: null, cursor: cursor, comments: comments);
  }

  Widget createTestWidget({
    required ThreadViewComment thread,
    List<ThreadViewComment> ancestors = const [],
    Future<void> Function(String, List<RichTextFacet>, ThreadViewComment)?
        onReply,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
      ],
      child: MaterialApp(
        home: FocusedThreadScreen(
          thread: thread,
          ancestors: ancestors,
          onReply: onReply ?? (content, facets, parent) async {},
          commentsProvider: commentsProvider,
        ),
      ),
    );
  }

  /// The screen auto-scrolls the anchor to the top on entry, which hides
  /// the floating app bar and pushes ancestors out of the sliver viewport.
  /// Scroll back to the top so those widgets are built again.
  Future<void> scrollBackToTop(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
  }

  group('FocusedThreadScreen rendering', () {
    setUp(() {
      // Entry hydration resolves to an empty subtree page: the screen keeps
      // rendering the snapshot it was given.
      stubGetComments((_) => response([]));
    });

    testWidgets('renders anchor comment', (tester) async {
      final thread = createThread(
        rkey: 'anchor',
        content: 'This is the anchor comment',
      );

      await tester.pumpWidget(createTestWidget(thread: thread));
      await tester.pumpAndSettle();

      expect(find.text('This is the anchor comment'), findsOneWidget);
    });

    testWidgets('renders ancestor comments', (tester) async {
      final ancestor1 = createThread(rkey: 'a1', content: 'First ancestor');
      final ancestor2 = createThread(rkey: 'a2', content: 'Second ancestor');
      final anchor = createThread(rkey: 'anchor', content: 'Anchor comment');

      await tester.pumpWidget(createTestWidget(
        thread: anchor,
        ancestors: [ancestor1, ancestor2],
      ));
      await tester.pumpAndSettle();
      await scrollBackToTop(tester);

      expect(find.text('First ancestor'), findsOneWidget);
      expect(find.text('Second ancestor'), findsOneWidget);
      expect(find.text('Anchor comment'), findsOneWidget);
    });

    testWidgets('renders replies below anchor', (tester) async {
      final thread = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [
          createThread(rkey: 'r1', content: 'First reply'),
          createThread(rkey: 'r2', content: 'Second reply'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread: thread));
      await tester.pumpAndSettle();

      expect(find.text('Anchor comment'), findsOneWidget);
      expect(find.text('First reply'), findsOneWidget);
      expect(find.text('Second reply'), findsOneWidget);
    });

    testWidgets('shows empty state when no replies', (tester) async {
      final thread = createThread(
        rkey: 'anchor',
        content: 'Anchor with no replies',
      );

      await tester.pumpWidget(createTestWidget(thread: thread));
      await tester.pumpAndSettle();

      expect(find.text('No replies yet'), findsOneWidget);
      expect(
        find.text('Be the first to reply to this comment'),
        findsOneWidget,
      );
    });

    testWidgets('does not duplicate thread in ancestors', (tester) async {
      final ancestor = createThread(rkey: 'a1', content: 'Ancestor content');
      final anchor = createThread(rkey: 'anchor', content: 'Anchor content');

      await tester.pumpWidget(createTestWidget(
        thread: anchor,
        ancestors: [ancestor],
      ));
      await tester.pumpAndSettle();
      await scrollBackToTop(tester);

      expect(find.text('Anchor content'), findsOneWidget);
      expect(find.text('Ancestor content'), findsOneWidget);
    });

    testWidgets('shows Thread title in app bar', (tester) async {
      final thread = createThread(rkey: 'anchor');

      await tester.pumpWidget(createTestWidget(thread: thread));
      await tester.pumpAndSettle();
      await scrollBackToTop(tester);

      expect(find.text('Thread'), findsOneWidget);
    });

    testWidgets('ancestors are styled with reduced opacity', (tester) async {
      final ancestor = createThread(rkey: 'a1', content: 'Ancestor');
      final anchor = createThread(rkey: 'anchor', content: 'Anchor');

      await tester.pumpWidget(createTestWidget(
        thread: anchor,
        ancestors: [ancestor],
      ));
      await tester.pumpAndSettle();
      await scrollBackToTop(tester);

      final opacityFinder = find.ancestor(
        of: find.text('Ancestor'),
        matching: find.byType(Opacity),
      );

      expect(opacityFinder, findsOneWidget);

      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(opacity.opacity, 0.6);
    });
  });

  group('FocusedThreadScreen hydration', () {
    testWidgets('hydrates the anchor subtree on entry (deep replies render)',
        (tester) async {
      // Snapshot truncated by the original fetch depth: only one shallow
      // reply. The server has a deeper tree behind it.
      final snapshot = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [createThread(rkey: 'r1', content: 'Shallow reply')],
      );

      stubGetComments((parentRkey) {
        expect(parentRkey, 'anchor');
        return response([
          createThread(
            rkey: 'anchor',
            content: 'Anchor comment',
            replies: [
              createThread(
                rkey: 'r1',
                content: 'Shallow reply',
                replies: [
                  createThread(rkey: 'r1a', content: 'Deep hydrated reply'),
                ],
              ),
            ],
          ),
        ]);
      });

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('Shallow reply'), findsOneWidget);
      expect(find.text('Deep hydrated reply'), findsOneWidget);
    });

    testWidgets('hydration failure keeps the snapshot visible (non-fatal)',
        (tester) async {
      final snapshot = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [createThread(rkey: 'r1', content: 'Existing reply')],
      );

      stubGetComments((_) => throw ApiException('boom'));

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      // Snapshot still renders, and no error/empty state is shown
      expect(find.text('Anchor comment'), findsOneWidget);
      expect(find.text('Existing reply'), findsOneWidget);
      expect(find.byType(InlineError), findsNothing);
      expect(find.text('No replies yet'), findsNothing);
    });

    testWidgets(
        'hydration failure with an empty snapshot shows a retryable error, '
        'and retry recovers', (tester) async {
      final snapshot = createThread(rkey: 'anchor', content: 'Anchor comment');

      var shouldFail = true;
      stubGetComments((_) {
        if (shouldFail) {
          throw ApiException('boom');
        }
        return response([
          createThread(
            rkey: 'anchor',
            content: 'Anchor comment',
            replies: [createThread(rkey: 'r1', content: 'Recovered reply')],
          ),
        ]);
      });

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      // Unknown state must not claim "No replies yet" - show retryable error
      expect(find.byType(InlineError), findsOneWidget);
      expect(find.text('No replies yet'), findsNothing);

      shouldFail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(InlineError), findsNothing);
      expect(find.text('Recovered reply'), findsOneWidget);
    });
  });

  group('FocusedThreadScreen load more', () {
    testWidgets('nested load-more renders newly fetched grandchild',
        (tester) async {
      final snapshot = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [createThread(rkey: 'r1', content: 'Child reply')],
      );

      stubGetComments((parentRkey) {
        if (parentRkey == 'anchor') {
          // Hydration: child has more replies behind the sibling cap
          return response([
            createThread(
              rkey: 'anchor',
              content: 'Anchor comment',
              replies: [
                createThread(
                  rkey: 'r1',
                  content: 'Child reply',
                  replyCount: 1,
                  hasMore: true,
                ),
              ],
            ),
          ]);
        }
        expect(parentRkey, 'r1');
        return response([
          createThread(
            rkey: 'r1',
            content: 'Child reply',
            replies: [
              createThread(rkey: 'r1a', content: 'Grandchild reply'),
            ],
          ),
        ]);
      });

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('Grandchild reply'), findsNothing);
      expect(find.text('Load more replies'), findsOneWidget);

      await tester.tap(find.text('Load more replies'));
      await tester.pumpAndSettle();

      expect(find.text('Grandchild reply'), findsOneWidget);
    });

    testWidgets(
        'anchor with more direct replies shows a load-more affordance '
        'that fetches the next page', (tester) async {
      final snapshot = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [createThread(rkey: 'r1', content: 'First page reply')],
      );

      var anchorFetches = 0;
      stubGetComments((parentRkey) {
        expect(parentRkey, 'anchor');
        anchorFetches++;
        if (anchorFetches == 1) {
          // Hydration: first page of the anchor's direct replies
          return response(
            [
              createThread(
                rkey: 'anchor',
                content: 'Anchor comment',
                replies: [
                  createThread(rkey: 'r1', content: 'First page reply'),
                ],
              ),
            ],
            cursor: 'page-2',
          );
        }
        return response([
          createThread(
            rkey: 'anchor',
            content: 'Anchor comment',
            replies: [
              createThread(rkey: 'r1', content: 'First page reply'),
              createThread(rkey: 'r2', content: 'Second page reply'),
            ],
          ),
        ]);
      });

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      // The anchor's own hasMore renders the affordance at the anchor level
      expect(find.text('Load more replies'), findsOneWidget);
      expect(find.text('Second page reply'), findsNothing);

      await tester.tap(find.text('Load more replies'));
      await tester.pumpAndSettle();

      expect(anchorFetches, 2);
      expect(find.text('First page reply'), findsOneWidget);
      expect(find.text('Second page reply'), findsOneWidget);
      expect(find.text('Load more replies'), findsNothing);
    });
  });

  group('FocusedThreadScreen delete', () {
    testWidgets('deleting a reply refetches the subtree and removes it',
        (tester) async {
      // The delete flow awaits HapticFeedback; without a handler the
      // platform channel raises MissingPluginException in tests.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => null,
      );

      // Signed in as the reply's author so the delete menu item shows
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.did).thenReturn(authorDid);

      var deleted = false;
      when(mockCommentService.deleteComment(uri: anyNamed('uri')))
          .thenAnswer((_) async => deleted = true);

      stubGetComments((parentRkey) {
        if (parentRkey == null) {
          // Top-level refresh triggered by deleteComment
          return response([]);
        }
        expect(parentRkey, 'anchor');
        return response([
          createThread(
            rkey: 'anchor',
            content: 'Anchor comment',
            replies: [
              createThread(rkey: 'keep', content: 'Reply to keep'),
              if (!deleted)
                createThread(rkey: 'gone', content: 'Reply to remove'),
            ],
          ),
        ]);
      });

      final snapshot = createThread(
        rkey: 'anchor',
        content: 'Anchor comment',
        replies: [
          createThread(rkey: 'keep', content: 'Reply to keep'),
          createThread(rkey: 'gone', content: 'Reply to remove'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('Reply to remove'), findsOneWidget);

      // Open the actions menu on the reply's card and delete it
      final replyCard = find
          .ancestor(
            of: find.text('Reply to remove'),
            matching: find.byType(CommentCard),
          )
          .first;
      await tester.tap(
        find.descendant(of: replyCard, matching: find.byIcon(Icons.more_horiz)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete comment'), findsOneWidget);
      await tester.tap(find.text('Delete comment'));
      await tester.pumpAndSettle();

      // Confirm in the dialog
      expect(find.text('Delete Comment'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Dialog dismissed after confirming
      expect(find.text('Delete Comment'), findsNothing);

      verify(mockCommentService.deleteComment(uri: anyNamed('uri'))).called(1);
      expect(find.text('Reply to remove'), findsNothing);
      expect(find.text('Reply to keep'), findsOneWidget);
    });
  });
}
