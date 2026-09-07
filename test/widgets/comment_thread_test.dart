import 'dart:async';

import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    mockApiService = MockCovesApiService();
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );

    // Signed-out by default: CommentCard hides the actions menu and the
    // vote button renders in the un-liked state.
    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
    when(
      mockVoteProvider.toggleVote(
        postUri: anyNamed('postUri'),
        postCid: anyNamed('postCid'),
        direction: anyNamed('direction'),
      ),
    ).thenAnswer((_) async => true);
  });

  /// Helper to create a test comment
  CommentView createComment({
    required String uri,
    String content = 'Test comment',
    String handle = 'test.user',
    int replyCount = 0,
    int score = 4,
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
      author: isDeleted
          ? null
          : AuthorView(did: 'did:plc:author', handle: handle),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: CommentStats(
        upvotes: 5,
        downvotes: 1,
        score: score,
        replyCount: replyCount,
      ),
    );
  }

  /// Helper to create a thread with nested replies
  ThreadViewComment createThread({
    required String uri,
    String content = 'Test comment',
    int replyCount = 0,
    int score = 4,
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
        score: score,
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
    String? focusedCommentUri,
    Key? focusedCommentKey,
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
              focusedCommentUri: focusedCommentUri,
              focusedCommentKey: focusedCommentKey,
            ),
          ),
        ),
      ),
    );
  }

  group('CommentThread rendering', () {
    testWidgets('renders comment content', (tester) async {
      final thread = createThread(uri: 'comment/1', content: 'Hello, world!');

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('formats the vote score through the canonical formatter', (
      tester,
    ) async {
      // CommentCard must agree with every other count surface: uppercase
      // K/M via DisplayUtils.formatCount.
      final thread = createThread(uri: 'comment/1', score: 5234);

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('5.2K'), findsOneWidget);
      expect(find.text('5.2k'), findsNothing);
    });

    testWidgets('formats a millions-scale vote score with an M suffix', (
      tester,
    ) async {
      final thread = createThread(uri: 'comment/1', score: 1500000);

      await tester.pumpWidget(createTestWidget(thread));

      expect(find.text('1.5M'), findsOneWidget);
      expect(find.text('1500.0k'), findsNothing);
    });

    testWidgets('renders nested replies when depth < maxDepth', (tester) async {
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

    testWidgets('shows "Read X more replies" at maxDepth using replyCount', (
      tester,
    ) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'At max depth',
        replyCount: 2,
        replies: [createThread(uri: 'comment/2', content: 'Hidden reply')],
      );

      await tester.pumpWidget(createTestWidget(thread, depth: 5));

      expect(find.text('At max depth'), findsOneWidget);
      // Count comes from the API's replyCount, not loaded replies
      expect(find.text('Read 2 more replies'), findsOneWidget);
      // The hidden reply should NOT be rendered
      expect(find.text('Hidden reply'), findsNothing);
    });

    testWidgets('does not show "Read more" when depth < maxDepth', (
      tester,
    ) async {
      final thread = createThread(
        uri: 'comment/1',
        replies: [createThread(uri: 'comment/2')],
      );

      await tester.pumpWidget(createTestWidget(thread, depth: 3));

      expect(find.textContaining('Read'), findsNothing);
    });

    testWidgets('calls onContinueThread with correct ancestors', (
      tester,
    ) async {
      ThreadViewComment? tappedThread;
      List<ThreadViewComment>? receivedAncestors;

      final thread = createThread(
        uri: 'comment/1',
        replyCount: 1,
        replies: [createThread(uri: 'comment/2')],
      );

      await tester.pumpWidget(
        createTestWidget(
          thread,
          depth: 5,
          onContinueThread: (t, a) {
            tappedThread = t;
            receivedAncestors = a;
          },
        ),
      );

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

    testWidgets('singular reply count reads "Read 1 more reply"', (
      tester,
    ) async {
      final singleReplyThread = createThread(
        uri: 'comment/1',
        replyCount: 1,
        replies: [createThread(uri: 'comment/2')],
      );

      await tester.pumpWidget(createTestWidget(singleReplyThread, depth: 5));

      expect(find.text('Read 1 more reply'), findsOneWidget);
    });

    testWidgets('plural reply count reads "Read 3 more replies"', (
      tester,
    ) async {
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

    testWidgets('collapsed comment hides its content and replies', (
      tester,
    ) async {
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        replyCount: 1,
        replies: [createThread(uri: 'comment/2', content: 'Child')],
      );

      await tester.pumpWidget(
        createTestWidget(thread, collapsedComments: {'comment/1'}),
      );
      await tester.pumpAndSettle();

      // Author row stays visible; content and replies are hidden
      expect(find.text('@test.user'), findsOneWidget);
      expect(find.text('Parent'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    testWidgets('deleted comment with absent author renders placeholder '
        '(regression 652f075)', (tester) async {
      final thread = createThread(
        uri: 'comment/1',
        isDeleted: true,
        deletionReason: 'author',
        replies: [createThread(uri: 'comment/2', content: 'Surviving reply')],
      );

      await tester.pumpWidget(createTestWidget(thread));

      // Placeholder shown instead of content; reply still renders
      expect(find.text('[deleted by user]'), findsOneWidget);
      expect(find.text('Surviving reply'), findsOneWidget);
    });
  });

  group('comment vote group', () {
    const commentUri = 'at://did:plc:author/social.coves.community.comment/123';
    const commentCid = 'cid-$commentUri';
    final thumbsDownPaths = <String>[
      <String>[
        'M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56',
        'l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8',
        'a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11',
        'L12 22a3.13 3.13 0 0 1-3-3.88Z',
      ].join(),
      'M17 14V2',
    ];

    Finder commentCard() => find.byType(CommentCard);

    Finder actionRow() => find.descendant(
      of: commentCard(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Row && widget.children.any((child) => child is Spacer),
        description: 'comment action Row containing its Spacer',
      ),
    );

    Finder ellipsisControl() => find.descendant(
      of: actionRow(),
      matching: find.byTooltip('Comment options'),
    );

    Finder heartControl() => find.descendant(
      of: actionRow(),
      matching: find.byType(AnimatedHeartIcon),
    );

    Finder upvoteControl(String actionLabel) => find.descendant(
      of: actionRow(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == actionLabel,
        description: 'Semantics labelled "$actionLabel"',
      ),
    );

    Finder scoreText(String score) =>
        find.descendant(of: actionRow(), matching: find.text(score));

    Finder downvoteControl(String actionLabel) {
      final semanticDownvote = find.descendant(
        of: actionRow(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == actionLabel,
          description: 'Semantics labelled "$actionLabel"',
        ),
      );
      final tooltipDownvote = find.descendant(
        of: actionRow(),
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == actionLabel,
          description: 'Tooltip labelled "$actionLabel"',
        ),
      );
      return semanticDownvote.evaluate().isNotEmpty
          ? semanticDownvote
          : tooltipDownvote;
    }

    LucideIconPainter? downvotePainter(
      WidgetTester tester,
      String actionLabel,
    ) {
      final downvote = downvoteControl(actionLabel);
      if (downvote.evaluate().length != 1) {
        return null;
      }
      final paints = find.descendant(
        of: downvote,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is LucideIconPainter,
          description: 'CustomPaint with a LucideIconPainter',
        ),
      );
      if (paints.evaluate().length != 1) {
        return null;
      }
      final painter = tester.widget<CustomPaint>(paints.first).painter;
      return painter is LucideIconPainter ? painter : null;
    }

    bool usesCanonicalThumbsDownPaths(LucideIconPainter? painter) {
      final paths = painter?.paths;
      if (paths == null || paths.length != thumbsDownPaths.length) {
        return false;
      }
      for (var index = 0; index < paths.length; index++) {
        if (paths[index] != thumbsDownPaths[index]) {
          return false;
        }
      }
      return true;
    }

    Color? effectiveScoreColor(WidgetTester tester, Finder score) {
      final text = tester.widget<Text>(score);
      return text.style?.color ??
          DefaultTextStyle.of(tester.element(score)).style.color;
    }

    void expectMinimumTapTargets(
      WidgetTester tester,
      Map<String, Finder> controls,
    ) {
      final undersized = <String, Size>{};
      for (final entry in controls.entries) {
        final size = tester.getSize(entry.value);
        if (size.width < 48 || size.height < 48) {
          undersized[entry.key] = size;
        }
      }
      expect(
        undersized,
        isEmpty,
        reason: 'interactive vote render boxes must be at least 48x48',
      );
    }

    Future<void> pumpVoteComment(
      WidgetTester tester, {
      Future<Object?>? hapticFuture,
    }) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) {
          if (hapticFuture != null &&
              methodCall.method == 'HapticFeedback.vibrate') {
            return hapticFuture;
          }
          return Future<Object?>.value();
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return tester.pumpWidget(
        createTestWidget(createThread(uri: commentUri, score: 5)),
      );
    }

    setUp(() {
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.did).thenReturn('did:plc:viewer');
      when(mockVoteProvider.getAdjustedScore(commentUri, 5)).thenReturn(4);
    });

    testWidgets('keeps menu left and heart-score-downvote right', (
      tester,
    ) async {
      await pumpVoteComment(tester);

      final actions = actionRow();
      final ellipsis = ellipsisControl();
      final downvote = downvoteControl('Downvote comment');
      final heart = heartControl();
      final upvote = upvoteControl('Upvote comment');
      final score = scoreText('4');
      expect(actions, findsOneWidget);
      expect(ellipsis, findsOneWidget);
      expect(heart, findsOneWidget);
      expect(upvote, findsOneWidget);
      expect(score, findsOneWidget);
      expect(tester.getTopLeft(score).dx - tester.getTopRight(heart).dx, 5);
      expect(find.descendant(of: upvote, matching: score), findsOneWidget);
      expect(
        tester.widget<Row>(actions).children.whereType<Spacer>(),
        hasLength(1),
      );
      expect(
        downvote,
        findsOneWidget,
        reason: 'the right comment action group needs a downvote control',
      );

      final ellipsisX = tester.getCenter(ellipsis).dx;
      final downvoteX = tester.getCenter(downvote).dx;
      final heartX = tester.getCenter(heart).dx;
      final scoreX = tester.getCenter(score).dx;
      expect(ellipsisX, lessThan(heartX));
      expect(heartX, lessThan(scoreX));
      expect(scoreX, lessThan(downvoteX));
      expect(heartX - ellipsisX, greaterThan(downvoteX - heartX));
      expectMinimumTapTargets(tester, {
        'comment upvote': upvote,
        'comment downvote': downvote,
      });
    });

    testWidgets('liked score is red beside the heart', (tester) async {
      when(mockVoteProvider.isLiked(commentUri)).thenReturn(true);
      await pumpVoteComment(tester);
      expect(effectiveScoreColor(tester, scoreText('4')), AppColors.voteLiked);
    });

    testWidgets('authenticated downvote requests the down direction', (
      tester,
    ) async {
      await pumpVoteComment(tester);

      final downvote = downvoteControl('Downvote comment');
      expect(
        downvote,
        findsOneWidget,
        reason: 'the authenticated comment downvote must be rendered',
      );
      await tester.tap(downvote);
      await tester.pumpAndSettle();

      verify(
        mockVoteProvider.toggleVote(
          postUri: commentUri,
          postCid: commentCid,
          direction: 'down',
        ),
      ).called(1);
    });

    testWidgets(
      'starts comment downvote mutation before haptic feedback completes',
      (tester) async {
        final hapticGate = Completer<Object?>();
        addTearDown(() {
          if (!hapticGate.isCompleted) {
            hapticGate.complete(null);
          }
        });
        await pumpVoteComment(tester, hapticFuture: hapticGate.future);

        await tester.tap(downvoteControl('Downvote comment'));
        await tester.pump();

        try {
          expect(hapticGate.isCompleted, isFalse);
          verify(
            mockVoteProvider.toggleVote(
              postUri: commentUri,
              postCid: commentCid,
              direction: 'down',
            ),
          ).called(1);
        } finally {
          if (!hapticGate.isCompleted) {
            hapticGate.complete(null);
          }
          await tester.pump();
        }
      },
    );

    testWidgets('existing downvote is teal and keeps score neutral', (
      tester,
    ) async {
      when(mockVoteProvider.getVoteState(commentUri))
          .thenReturn(const VoteState(direction: 'down', deleted: false));
      await pumpVoteComment(tester);

      final downvote = downvoteControl('Remove downvote');
      expect(
        find.descendant(
          of: actionRow(),
          matching: find.byTooltip('Remove downvote'),
        ),
        findsOneWidget,
      );
      final painter = downvotePainter(tester, 'Remove downvote');
      final score = scoreText('4');
      final scoreColor = effectiveScoreColor(tester, score);
      expect(score, findsOneWidget);
      expect(
        (
          downvoteVisible: downvote.evaluate().length == 1,
          usesLucidePainter: painter != null,
          usesCanonicalPaths: usesCanonicalThumbsDownPaths(painter),
          selectedIsFilled: painter?.filled ?? false,
          selectedIsTeal: painter?.color == AppColors.teal,
          scoreIsNeutral:
              scoreColor != AppColors.teal && scoreColor != AppColors.voteLiked,
        ),
        (
          downvoteVisible: true,
          usesLucidePainter: true,
          usesCanonicalPaths: true,
          selectedIsFilled: false,
          selectedIsTeal: true,
          scoreIsNeutral: true,
        ),
      );
      verify(mockVoteProvider.getVoteState(commentUri)).called(1);
    });

    testWidgets('pending vote keeps both controls visible and inert', (
      tester,
    ) async {
      final requestedDirections = <String?>[];
      when(mockVoteProvider.isPending(commentUri)).thenReturn(true);
      when(mockVoteProvider.getVoteState(commentUri))
          .thenReturn(const VoteState(direction: 'down', deleted: false));
      when(mockVoteProvider.getAdjustedScore(commentUri, 5)).thenReturn(3);
      when(
        mockVoteProvider.toggleVote(
          postUri: anyNamed('postUri'),
          postCid: anyNamed('postCid'),
          direction: anyNamed('direction'),
        ),
      ).thenAnswer((invocation) async {
        requestedDirections.add(
          invocation.namedArguments[#direction] as String?,
        );
        return true;
      });
      await pumpVoteComment(tester);

      final heart = heartControl();
      final downvote = downvoteControl('Remove downvote');
      final downvoteVisible = downvote.evaluate().length == 1;
      final painter = downvotePainter(tester, 'Remove downvote');
      await tester.tap(heart);
      if (downvoteVisible) {
        await tester.tap(downvote);
      }
      await tester.pumpAndSettle();

      expect(
        (
          heartVisible: heart.evaluate().length == 1,
          downvoteVisible: downvoteVisible,
          optimisticScoreVisible: scoreText('3').evaluate().length == 1,
          optimisticDownvoteSelected: painter?.color == AppColors.teal,
          mutationCalls: requestedDirections.length,
          spinnerVisible: find
              .byType(CircularProgressIndicator)
              .evaluate()
              .isNotEmpty,
        ),
        (
          heartVisible: true,
          downvoteVisible: true,
          optimisticScoreVisible: true,
          optimisticDownvoteSelected: true,
          mutationCalls: 0,
          spinnerVisible: false,
        ),
      );
      verify(mockVoteProvider.isPending(commentUri)).called(1);
    });
  });

  group('Focused comment (deep link)', () {
    testWidgets(
      'attaches the key and highlight to the exact nested comment only',
      (tester) async {
        final thread = createThread(
          uri: 'comment/root',
          content: 'Root',
          replies: [
            createThread(uri: 'comment/a', content: 'Sibling'),
            createThread(
              uri: 'comment/b',
              content: 'Parent of target',
              replies: [createThread(uri: 'comment/target', content: 'Me')],
            ),
          ],
        );
        final focusKey = GlobalKey();

        await tester.pumpWidget(
          createTestWidget(
            thread,
            focusedCommentUri: 'comment/target',
            focusedCommentKey: focusKey,
          ),
        );

        // The key lands on the target's card so the screen can
        // Scrollable.ensureVisible it.
        expect(focusKey.currentContext, isNotNull);
        expect(
          find.descendant(of: find.byKey(focusKey), matching: find.text('Me')),
          findsOneWidget,
        );

        // Only the target is tinted.
        final cards = tester.widgetList<CommentCard>(find.byType(CommentCard));
        final highlighted = cards
            .where((c) => c.isHighlighted)
            .map((c) => c.comment.uri);
        expect(highlighted, ['comment/target']);
      },
    );

    testWidgets('no focus uri: nothing highlighted, key unattached', (
      tester,
    ) async {
      final thread = createThread(uri: 'comment/root', content: 'Root');
      final focusKey = GlobalKey();

      await tester.pumpWidget(
        createTestWidget(thread, focusedCommentKey: focusKey),
      );

      expect(focusKey.currentContext, isNull);
      expect(
        tester
            .widgetList<CommentCard>(find.byType(CommentCard))
            .any((c) => c.isHighlighted),
        isFalse,
      );
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

    testWidgets('tap invokes onLoadMoreReplies with the thread', (
      tester,
    ) async {
      ThreadViewComment? tapped;
      final thread = createThread(
        uri: 'comment/1',
        content: 'Parent',
        hasMore: true,
      );

      await tester.pumpWidget(
        createTestWidget(thread, onLoadMoreReplies: (t) => tapped = t),
      );

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

        await tester.pumpWidget(
          createTestWidget(
            thread,
            onLoadMoreReplies: (_) => tapCount++,
            loadingMoreReplies: {'comment/1'},
          ),
        );

        expect(find.text('Loading replies…'), findsOneWidget);
        expect(find.text('Load more replies'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.add_circle_outline), findsNothing);

        // Tap is disabled while loading
        await tester.tap(find.text('Loading replies…'), warnIfMissed: false);
        await tester.pump();
        expect(tapCount, 0);
      },
    );
  });
}
