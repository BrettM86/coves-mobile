import 'dart:async';
import 'dart:convert';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
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
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);

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
          builder: (_) => ReplyScreen(
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

  group('ReplyScreen draft when system back interrupts an in-flight send', () {
    final sendPill = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Send comment',
    );

    /// Taps Send and pumps a bounded number of frames: the in-flight spinner
    /// animates indefinitely, so pumpAndSettle would time out. Two frames
    /// cover the awaited (mocked) haptic call, the setState, and the rebuild.
    Future<void> tapSendAndPumpUntilInFlight(WidgetTester tester) async {
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();
    }

    void expectSendInFlight() {
      expect(find.text('Send'), findsNothing);
      expect(
        find.descendant(
          of: sendPill,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    }

    /// System back, then pumps past the reverse page transition (longer than
    /// any default Material transition) so the reply route is removed and
    /// its State disposed before the send settles
    Future<void> systemBackAndFinishTransition(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    }

    testWidgets('send fails after the screen was popped: reopening restores '
        'the typed text', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      String? submittedContent;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) {
          submittedContent = content;
          return submitCompleter.future;
        },
      );

      await tester.enterText(find.byType(TextField), 'Reply that must survive');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);

      expect(submittedContent, 'Reply that must survive');
      expectSendInFlight();

      final replyState = tester.state(find.byType(ReplyScreen));
      await systemBackAndFinishTransition(tester);

      expect(find.text('base route'), findsOneWidget);
      expect(find.byType(ReplyScreen), findsNothing);
      expect(replyState.mounted, isFalse);

      submitCompleter.completeError(Exception('network unreachable'));
      await tester.pump();

      await pushReply(tester, comment: comment);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'Reply that must survive');
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Reply that must survive',
      );
    });

    testWidgets('send succeeds after the screen was popped: the sent text is '
        'never left in the draft', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      String? submittedContent;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) {
          submittedContent = content;
          return submitCompleter.future;
        },
      );

      await tester.enterText(
        find.byType(TextField),
        'Fresh reply sent before back',
      );
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);

      expect(submittedContent, 'Fresh reply sent before back');
      expectSendInFlight();

      final replyState = tester.state(find.byType(ReplyScreen));
      await systemBackAndFinishTransition(tester);

      expect(find.text('base route'), findsOneWidget);
      expect(find.byType(ReplyScreen), findsNothing);
      expect(replyState.mounted, isFalse);
      // The text being sent must not sit in the draft slot during the send
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');

      submitCompleter.complete();
      await tester.pump();

      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');

      await pushReply(tester, comment: comment);

      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, isEmpty);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');
    });

    testWidgets('successful send without a user pop clears the restored '
        'draft: reopening shows an empty field', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      commentsProvider.saveDraft(
        'Previously saved draft',
        parentUri: comment.comment.uri,
      );
      String? submittedContent;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submittedContent = content;
        },
      );

      final restoredField = tester.widget<TextField>(find.byType(TextField));
      expect(restoredField.controller!.text, 'Previously saved draft');

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submittedContent, 'Previously saved draft');
      // The submit path popped the screen itself
      expect(find.text('base route'), findsOneWidget);
      expect(find.byType(ReplyScreen), findsNothing);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');

      await pushReply(tester, comment: comment);

      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, isEmpty);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');
    });

    testWidgets('reopening the composer while the send is in flight shows an '
        'empty field', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submitCompleter.future,
      );

      await tester.enterText(find.byType(TextField), 'Reply still sending');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);
      expectSendInFlight();

      await systemBackAndFinishTransition(tester);
      expect(find.text('base route'), findsOneWidget);

      await pushReply(tester, comment: comment);

      // A prefilled field here would invite sending the same reply twice
      expect(submitCompleter.isCompleted, isFalse);
      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, isEmpty);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');

      // Settle the first send so nothing is left pending
      submitCompleter.complete();
      await tester.pump();
    });

    testWidgets('Cancel during an in-flight send leaves the draft empty; a '
        'failed send restores the text', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submitCompleter.future,
      );

      await tester.enterText(find.byType(TextField), 'Cancelled mid-send');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);
      expectSendInFlight();

      final replyState = tester.state(find.byType(ReplyScreen));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text('base route'), findsOneWidget);
      expect(replyState.mounted, isFalse);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), '');

      submitCompleter.completeError(Exception('network unreachable'));
      await tester.pump();

      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Cancelled mid-send',
      );
    });

    testWidgets('a newer draft saved by a second composer survives the first '
        'send succeeding', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submitCompleter.future,
      );

      await tester.enterText(find.byType(TextField), 'First reply in flight');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);
      expectSendInFlight();
      await systemBackAndFinishTransition(tester);

      // Composer B: write a newer draft and leave
      await pushReply(tester, comment: comment);
      await tester.enterText(find.byType(TextField), 'Newer draft');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Newer draft',
      );

      submitCompleter.complete();
      await tester.pump();

      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Newer draft',
      );
      await pushReply(tester, comment: comment);
      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, 'Newer draft');
    });

    testWidgets('a newer draft saved by a second composer survives the first '
        'send failing', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submitCompleter.future,
      );

      await tester.enterText(find.byType(TextField), 'First reply in flight');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);
      expectSendInFlight();
      await systemBackAndFinishTransition(tester);

      // Composer B: write a newer draft and leave
      await pushReply(tester, comment: comment);
      await tester.enterText(find.byType(TextField), 'Newer draft');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      submitCompleter.completeError(Exception('network unreachable'));
      await tester.pump();

      // The failed send must not overwrite the newer draft with its text
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri),
        'Newer draft',
      );
      await pushReply(tester, comment: comment);
      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, 'Newer draft');
    });

    testWidgets('send succeeding during the back transition does not also pop '
        'the route below', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submitCompleter = Completer<void>();
      await pumpBase(tester);
      // A middle route stands in for post detail, so a second pop is visible
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('post detail route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submitCompleter.future,
      );

      await tester.enterText(find.byType(TextField), 'Reply sent during back');
      await tester.pump();
      await tapSendAndPumpUntilInFlight(tester);
      expectSendInFlight();

      final replyState = tester.state(find.byType(ReplyScreen));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid exit transition: the send must complete inside this window
      expect(replyState.mounted, isTrue);

      submitCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(ReplyScreen), findsNothing);
      expect(find.text('post detail route'), findsOneWidget);
      expect(find.text('base route'), findsNothing);
    });
  });

  group('ReplyScreen link facets', () {
    testWidgets('submits trimmed content with exactly the scheme-prefixed '
        'links as UTF-8 byte-range link facets', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      final submissions = <(String, List<RichTextFacet>)>[];
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submissions.add((content, facets));
        },
      );

      await tester.enterText(
        find.byType(TextField),
        '  Https://en.wikipedia.org/wiki/Foo_(bar), see e.g. node.js 👋 '
        '"https://a.com/x".  ',
      );
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      const expectedContent =
          'Https://en.wikipedia.org/wiki/Foo_(bar), see e.g. node.js 👋 '
          '"https://a.com/x".';
      // Expected second range comes from the literal content, measured in
      // UTF-8 bytes (the emoji before it is 4 bytes but 2 UTF-16 units)
      const secondLink = 'https://a.com/x';
      final secondStart = utf8
          .encode(
            expectedContent.substring(0, expectedContent.indexOf(secondLink)),
          )
          .length;
      final secondEnd = secondStart + utf8.encode(secondLink).length;

      expect(submissions, hasLength(1));
      final (content, facets) = submissions.single;
      expect(content, expectedContent);
      // One string per facet: its byte range and every feature it carries,
      // so a wrong uri, wrong range, extra feature or extra facet all fail
      String describeFeature(FacetFeature feature) =>
          feature is LinkFacetFeature ? 'link ${feature.uri}' : feature.type;
      String describeFacet(RichTextFacet facet) {
        final range = '[${facet.index.byteStart},${facet.index.byteEnd})';
        return '$range ${facet.features.map(describeFeature).toList()}';
      }

      final described = facets.map(describeFacet).toList();
      expect(described, [
        '[0,39) [link https://en.wikipedia.org/wiki/Foo_(bar)]',
        '[$secondStart,$secondEnd) [link https://a.com/x]',
      ]);
    });
  });
}
