import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

// Shared generated mockito mocks (real provider types) so provider lookups
// inside CommentThread/CommentCard resolve correctly.
import '../test_helpers/test_mocks.dart';

void main() {
  const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
  const testPostCid = 'test-post-cid';

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockVoteProvider mockVoteProvider;
  late BlockProvider blockProvider;
  late CommentsProvider commentsProvider;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockVoteProvider = MockVoteProvider();
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );
    navigatorKey = GlobalKey<NavigatorState>();

    // Signed-out rendering keeps CommentCard simple (no action menus)
    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(
      mockVoteProvider.getAdjustedScore(any, any),
    ).thenAnswer((invocation) => invocation.positionalArguments[1] as int);

    // Real CommentsProvider over mocks: drafts are pure local state, so no
    // API stubbing is needed (ReplyScreen never triggers loadComments)
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
    blockProvider.dispose();
  });

  ThreadViewComment createComment(String uri) {
    return ThreadViewComment(
      comment: CommentView(
        uri: uri,
        cid: 'cid-$uri',
        record: CommentRecord(content: 'Parent comment for $uri'),
        createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
        indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
        author: AuthorView(
          did: 'did:plc:author',
          handle: 'test.user',
          displayName: 'Test User',
        ),
        post: CommentRef(uri: testPostUri, cid: testPostCid),
        stats: const CommentStats(score: 10, upvotes: 12, downvotes: 2),
      ),
    );
  }

  /// Pumps a base route; ReplyScreen is pushed on top so pops are visible
  Future<void> pumpBase(WidgetTester tester) async {
    // Without a mock handler, HapticFeedback.lightImpact() (awaited inside
    // _handleSubmit) never completes in widget tests and submit would hang
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
          ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('base route')),
        ),
      ),
    );
  }

  Future<void> pushReply(
    WidgetTester tester, {
    required ThreadViewComment comment,
    Future<void> Function(String content, List<RichTextFacet> facets)? onSubmit,
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder:
              (_) => ReplyScreen(
                comment: comment,
                commentsProvider: commentsProvider,
                onSubmit: onSubmit ?? (content, facets) async {},
              ),
        ),
      ),
    );
    // Settles the push animation, draft restore, and the delayed autofocus
    await tester.pumpAndSettle();
  }

  /// The Send pill's tap target (nearest GestureDetector around 'Send')
  GestureDetector sendButton(WidgetTester tester) {
    return tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('Send'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
  }

  group('ReplyScreen draft round-trip', () {
    testWidgets('type then Cancel saves the draft for the parent URI', (
      tester,
    ) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);
      await pushReply(tester, comment: comment);

      await tester.enterText(find.byType(TextField), 'My draft reply');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('base route'), findsOneWidget);
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'My draft reply',
      );
    });

    testWidgets('re-pushing the same parentUri restores the draft and '
        'enables Send', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);

      await pushReply(tester, comment: comment);
      await tester.enterText(find.byType(TextField), 'Restored draft');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await pushReply(tester, comment: comment);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'Restored draft');
      expect(sendButton(tester).onTap, isNotNull);
    });

    testWidgets('successful submit clears the draft (and the pop must not '
        'resurrect it)', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      String? submitted;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submitted = content;
        },
      );

      await tester.enterText(find.byType(TextField), 'Ship it');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, 'Ship it');
      // Screen popped after success
      expect(find.text('base route'), findsOneWidget);
      // Draft cleared - the pop-time save must not have run (the controller
      // still held the submitted text when the route popped)
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');
    });

    testWidgets('drafts for distinct parentUris are independent', (
      tester,
    ) async {
      final comment1 = createComment('at://did:plc:author/comment/1');
      final comment2 = createComment('at://did:plc:author/comment/2');
      await pumpBase(tester);

      await pushReply(tester, comment: comment1);
      await tester.enterText(find.byType(TextField), 'draft one');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await pushReply(tester, comment: comment2);
      // The other comment's draft must not leak into this composer
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);

      await tester.enterText(find.byType(TextField), 'draft two');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        commentsProvider.getDraft(parentUri: comment1.comment.uri),
        'draft one',
      );
      expect(
        commentsProvider.getDraft(parentUri: comment2.comment.uri),
        'draft two',
      );
    });

    testWidgets('system back saves the draft (not just the Cancel button)', (
      tester,
    ) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);
      await pushReply(tester, comment: comment);

      await tester.enterText(find.byType(TextField), 'Saved by system back');
      await tester.pump();

      // Same path as a hardware/gesture back: root navigator maybePop
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('base route'), findsOneWidget);
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Saved by system back',
      );
    });
  });
}
