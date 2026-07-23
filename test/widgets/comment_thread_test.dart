import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

// Shared generated mockito mocks (real provider types) so
// Consumer<AuthProvider>/Consumer<VoteProvider> lookups inside CommentCard
// resolve correctly.
import '../test_helpers/test_mocks.dart';

// NOTE: CommentThread.countDescendants was removed in e134a88 — the widget
// now uses the API-provided `stats.replyCount` for collapsed/continue-thread
// counts, so the old descendant-counting unit tests are obsolete. The
// rendering tests below cover the current behavior.
void main() {
  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late MockCovesApiService mockApiService;
  late BlockProvider blockProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    when(mockVoteProvider.hasStateFor(any)).thenReturn(false);
    mockApiService = MockCovesApiService();
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
  });

  /// Helper to create a test comment
  CommentView createComment({
    required String uri,
    String content = 'Test comment',
    String handle = 'test.user',
    int replyCount = 0,
    bool isDeleted = false,
    String? deletionReason,
  }) {
    return CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: isDeleted ? null : CommentRecord(content: content),
      isDeleted: isDeleted,
      deletionReason: deletionReason,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      // Backend omits author entirely for deleted comments.
      author:
          isDeleted ? null : AuthorView(did: 'did:plc:author', handle: handle),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
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
    required String uri,
    String content = 'Test comment',
    int replyCount = 0,
    bool isDeleted = false,
    String? deletionReason,
    List<ThreadViewComment>? replies,
    bool hasMore = false,
    String? repliesCursor,
  }) {
    return ThreadViewComment(
      comment: createComment(
        uri: uri,
        content: content,
        replyCount: replyCount,
        isDeleted: isDeleted,
        deletionReason: deletionReason,
      ),
      replies: replies,
      hasMore: hasMore,
      repliesCursor: repliesCursor,
    );
  }

  Widget createTestWidget(
    ThreadViewComment thread, {
    int depth = 0,
    int maxDepth = 5,
    void Function(ThreadViewComment)? onCommentTap,
    void Function(String uri)? onCollapseToggle,
    void Function(ThreadViewComment, List<ThreadViewComment>)? onContinueThread,
    void Function(ThreadViewComment)? onLoadMoreReplies,
    Set<String> loadingMoreReplies = const {},
    Set<String> collapsedComments = const {},
    List<ThreadViewComment> ancestors = const [],
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommentThread(
              thread: thread,
              depth: depth,
              maxDepth: maxDepth,
              onCommentTap: onCommentTap,
              onCollapseToggle: onCollapseToggle,
              onContinueThread: onContinueThread,
              onLoadMoreReplies: onLoadMoreReplies,
              loadingMoreReplies: loadingMoreReplies,
              collapsedComments: collapsedComments,
              ancestors: ancestors,
            ),
          ),
        ),
      ),
    );
  }

  group('CommentThread rendering', () {
    testWidgets('renders comment content', (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'Hello, world!',
      );

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('renders nested replies when depth < maxDepth',
        (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        replies: [
          createThread(uri: 'comment/2', content: 'Child 1'),
          createThread(uri: 'comment/3', content: 'Child 2'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('Parent'), findsOneWidget);
      expect(find.text('Child 1'), findsOneWidget);
      expect(find.text('Child 2'), findsOneWidget);
    });

    testWidgets('shows "Read X more replies" at maxDepth using replyCount',
        (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'At max depth',
        replyCount: 2,
        replies: [
          createThread(uri: 'comment/2', content: 'Hidden reply'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread, depth: 5));

      expect(find.text('At max depth'), findsOneWidget);
      // Count comes from the API's replyCount, not loaded replies
      expect(find.text('Read 2 more replies'), findsOneWidget);
      // The hidden reply should NOT be rendered
      expect(find.text('Hidden reply'), findsNothing);
    });

    testWidgets('does not show "Read more" when depth < maxDepth',
        (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        replies: [
          createThread(uri: 'comment/2'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread, depth: 3));

      expect(find.textContaining('Read'), findsNothing);
    });

    testWidgets('calls onContinueThread with correct ancestors',
        (tester) async {
      ThreadViewComment? tappedThread;
      List<ThreadViewComment>? receivedAncestors;

      final thread = createThread(
        uri: 'comment/1',
        replyCount: 1,
        replies: [
          createThread(uri: 'comment/2'),
        ],
      );

      await tester.pumpWidget(createTestWidget(
        thread,
        depth: 5,
        onContinueThread: (t, a) {
          tappedThread = t;
          receivedAncestors = a;
        },
      ));

      // Find and tap the "Read more" link
      final readMoreFinder = find.textContaining('Read');
      expect(readMoreFinder, findsOneWidget);

      await tester.tap(readMoreFinder);
      await tester.pump();

      expect(tappedThread, isNotNull);
      expect(tappedThread!.comment.uri, 'comment/1');
      expect(receivedAncestors, isNotNull);
      // ancestors should NOT include the thread itself
      expect(receivedAncestors, isEmpty);
    });

    testWidgets('singular reply count reads "Read 1 more reply"',
        (tester) async {
      final singleReplyThread = createThread(
        uri: 'comment/1',
        replyCount: 1,
        replies: [
          createThread(uri: 'comment/2'),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(singleReplyThread, depth: 5),
      );

      expect(find.text('Read 1 more reply'), findsOneWidget);
    });

    testWidgets('plural reply count reads "Read 3 more replies"',
        (tester) async {
      final multiReplyThread = createThread(
        uri: 'comment/1',
        replyCount: 3,
        replies: [
          createThread(uri: 'comment/2'),
          createThread(uri: 'comment/3'),
          createThread(uri: 'comment/4'),
        ],
      );

      await tester.pumpWidget(createTestWidget(multiReplyThread, depth: 5));

      expect(find.text('Read 3 more replies'), findsOneWidget);
    });

    testWidgets('collapsed comment hides its content and replies',
        (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        replyCount: 1,
        replies: [
          createThread(uri: 'comment/2', content: 'Child'),
        ],
      );

      await tester.pumpWidget(createTestWidget(
        thread,
        collapsedComments: {'comment/1'},
      ));
      await tester.pumpAndSettle();

      // Author row stays visible; content and replies are hidden
      expect(find.text('@test.user'), findsOneWidget);
      expect(find.text('Parent'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    testWidgets(
        'deleted comment with absent author renders placeholder '
        '(regression 652f075)', (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        isDeleted: true,
        deletionReason: 'author',
        replies: [
          createThread(uri: 'comment/2', content: 'Surviving reply'),
        ],
      );

      await tester.pumpWidget(createTestWidget(thread));

      // Placeholder shown instead of content; reply still renders
      expect(find.text('[deleted by user]'), findsOneWidget);
      expect(find.text('Surviving reply'), findsOneWidget);
    });
  });

  group('Load more replies button', () {
    testWidgets('renders when the thread has more replies', (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        hasMore: true,
      );

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('Load more replies'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('does not render without more replies', (tester) async {
      final thread = createThread(uri: 'comment/1', content: 'Parent');

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('Load more replies'), findsNothing);
    });

    testWidgets('tap invokes onLoadMoreReplies with the thread',
        (tester) async {
      ThreadViewComment? tapped;
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        hasMore: true,
      );

      await tester.pumpWidget(createTestWidget(
        thread,
        onLoadMoreReplies: (t) => tapped = t,
      ));

      await tester.tap(find.text('Load more replies'));
      await tester.pump();

      expect(tapped, isNotNull);
      expect(tapped!.comment.uri, 'comment/1');
    });

    testWidgets(
        'in-flight fetch shows spinner, loading label, and disables tap',
        (tester) async {
      var tapCount = 0;
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        hasMore: true,
      );

      await tester.pumpWidget(createTestWidget(
        thread,
        onLoadMoreReplies: (_) => tapCount++,
        loadingMoreReplies: {'comment/1'},
      ));

      expect(find.text('Loading replies…'), findsOneWidget);
      expect(find.text('Load more replies'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);

      // Tap is disabled while loading
      await tester.tap(find.text('Loading replies…'), warnIfMissed: false);
      await tester.pump();
      expect(tapCount, 0);
    });
  });
}
