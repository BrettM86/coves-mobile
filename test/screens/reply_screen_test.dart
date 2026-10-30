import 'dart:async';
import 'dart:convert';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/composer/composer_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';
import 'compose/reply_screen_test_harness.dart';

void main() {
  late ReplyScreenHarness harness;
  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late CommentsProvider commentsProvider;

  setUp(() {
    harness = ReplyScreenHarness();
    mockAuthProvider = harness.mockAuthProvider;
    mockApiService = harness.mockApiService;
    commentsProvider = harness.commentsProvider;
  });

  tearDown(() => harness.dispose());

  Future<void> pumpBase(WidgetTester tester) => harness.pumpBase(tester);

  Future<void> pushReply(
    WidgetTester tester, {
    required ThreadViewComment comment,
    Future<void> Function(String content, List<RichTextFacet> facets)? onSubmit,
  }) => harness.pushReply(tester, comment: comment, onSubmit: onSubmit);

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
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
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
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);
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
        commentsProvider.getDraft(parentUri: comment1.comment.uri)?.text,
        'draft one',
      );
      expect(
        commentsProvider.getDraft(parentUri: comment2.comment.uri)?.text,
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
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'Saved by system back',
      );
    });
  });

  group('ReplyScreen draft when system back interrupts an in-flight send', () {
    final sendPill = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Send comment',
    );

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
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
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
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);

      submitCompleter.complete();
      await tester.pump();

      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);

      await pushReply(tester, comment: comment);

      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, isEmpty);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);
    });

    testWidgets('successful send without a user pop clears the restored '
        'draft: reopening shows an empty field', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      commentsProvider.saveDraft(
        ComposerDraft(text: 'Previously saved draft'),
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
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);

      await pushReply(tester, comment: comment);

      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedField.controller!.text, isEmpty);
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);
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
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);

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
      expect(commentsProvider.getDraft(parentUri: comment.comment.uri), isNull);

      submitCompleter.completeError(Exception('network unreachable'));
      await tester.pump();

      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
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
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'Newer draft',
      );

      submitCompleter.complete();
      await tester.pump();

      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
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
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
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
        harness.navigatorKey.currentState!.push(
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

  group('ReplyScreen mention facets', () {
    testWidgets('resolves a handle mention through the API and submits it as '
        'a mention facet', (tester) async {
      when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
          .thenAnswer((_) async => 'did:plc:alice');
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

      await tester.enterText(find.byType(TextField), 'hi @alice.coves.social');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submissions, hasLength(1));
      final (content, facets) = submissions.single;
      expect(content, 'hi @alice.coves.social');
      // One string per facet: its byte range and every feature it carries,
      // so a wrong did, wrong range, extra feature or extra facet all fail
      String describeFeature(FacetFeature feature) =>
          feature is MentionFacetFeature
          ? 'mention ${feature.did}'
          : feature.type;
      String describeFacet(RichTextFacet facet) {
        final range = '[${facet.index.byteStart},${facet.index.byteEnd})';
        return '$range ${facet.features.map(describeFeature).toList()}';
      }

      final described = facets.map(describeFacet).toList();
      expect(described, ['[3,22) [mention did:plc:alice]']);
    });

    testWidgets('a failed mention lookup blocks the send, shows the error and '
        'saves the draft for the parent', (tester) async {
      when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
          .thenAnswer(
            (_) => Future<String>.error(
              ServerException('Mention lookup unavailable', statusCode: 503),
            ),
          );
      final comment = createComment('at://did:plc:author/comment/1');
      var submitCalls = 0;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submitCalls++;
        },
      );

      await tester.enterText(find.byType(TextField), 'hi @alice.coves.social');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitCalls, 0);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Mention lookup unavailable'),
        ),
        findsOneWidget,
      );
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'hi @alice.coves.social',
      );
    });

    testWidgets('a switch to another account while a mention lookup is '
        'pending blocks the send and saves the draft for the parent', (
      tester,
    ) async {
      final lookup = Completer<String>();
      when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
          .thenAnswer((_) => lookup.future);
      when(mockAuthProvider.did).thenReturn('did:plc:testuser');
      final comment = createComment('at://did:plc:author/comment/1');
      var submitCalls = 0;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submitCalls++;
        },
      );

      await tester.enterText(find.byType(TextField), 'hi @alice.coves.social');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();
      when(mockAuthProvider.did).thenReturn('did:plc:otheruser');
      lookup.complete('did:plc:alice');
      await tester.pumpAndSettle();

      expect(submitCalls, 0);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Your account changed'),
        ),
        findsOneWidget,
      );
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'hi @alice.coves.social',
      );
    });

    testWidgets('a mention lookup that fails after system back closed the '
        'screen shows the error on the screen below and saves the draft for '
        'the parent', (tester) async {
      final lookup = Completer<String>();
      when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
          .thenAnswer((_) => lookup.future);
      final comment = createComment('at://did:plc:author/comment/1');
      var submitCalls = 0;
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          submitCalls++;
        },
      );

      await tester.enterText(find.byType(TextField), 'hi @alice.coves.social');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();
      await systemBackAndFinishTransition(tester);
      expect(find.byType(ReplyScreen), findsNothing);

      lookup.completeError(
        ServerException('Mention lookup unavailable', statusCode: 503),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('base route'), findsOneWidget);
      expect(submitCalls, 0);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Mention lookup unavailable'),
        ),
        findsOneWidget,
      );
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'hi @alice.coves.social',
      );
    });
  });

  group('ReplyScreen submit', () {
    testWidgets('a second Send tap before the first one rebuilds the screen '
        'does not submit twice', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);
      final submit = Completer<void>();
      var submitCalls = 0;
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) {
          submitCalls++;
          return submit.future;
        },
      );

      await tester.enterText(find.byType(TextField), 'Ship it');
      await tester.pump();
      // Both taps land in the same frame, before any rebuild disables Send
      final onTap = sendButton(tester).onTap!;
      onTap();
      onTap();
      await tester.pump();
      await tester.pump();

      submit.complete();
      await tester.pumpAndSettle();

      expect(submitCalls, 1);
    });

    testWidgets('Cancel while the Send haptic is still pending keeps the '
        'draft when that send then fails', (tester) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);
      // Haptic feedback stays pending until the composer has been closed
      final haptic = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          await haptic.future;
          return null;
        },
      );
      final submit = Completer<void>();
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) => submit.future,
      );

      await tester.enterText(find.byType(TextField), 'Reply that must survive');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ReplyScreen), findsNothing);

      haptic.complete();
      await tester.pump();
      submit.completeError(Exception('network unreachable'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'Reply that must survive',
      );
    });

    testWidgets('an onSubmit failure is left to the parent screen to report', (
      tester,
    ) async {
      final comment = createComment('at://did:plc:author/comment/1');
      await pumpBase(tester);
      await pushReply(
        tester,
        comment: comment,
        onSubmit: (content, facets) async {
          throw ServerException('Comment service unavailable', statusCode: 503);
        },
      );

      await tester.enterText(find.byType(TextField), 'Ship it');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to submit'), findsNothing);
    });
  });
}
