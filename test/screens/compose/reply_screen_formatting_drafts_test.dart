import 'dart:async';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/composer/composer_draft.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import 'reply_screen_test_harness.dart';

/// The namespace every Coves facet feature type is under
const _facet = 'social.coves.richtext.facet';

const _parentUri = 'at://did:plc:author/comment/1';

void main() {
  late ReplyScreenHarness harness;

  setUp(() => harness = ReplyScreenHarness());
  tearDown(() => harness.dispose());

  Future<void> reopen(WidgetTester tester) =>
      harness.pushReply(tester, comment: createComment(_parentUri));

  /// Types [text] and gives the field [selection]
  Future<void> typeAndSelect(
    WidgetTester tester,
    String text,
    TextSelection selection,
  ) async {
    await tester.enterText(find.byType(EditableText), text);
    await tester.pump();
    await focusField(tester, selection);
  }

  void expectField(
    WidgetTester tester, {
    required String text,
    List<InlineRange> inlineRanges = const [],
    List<BlockRange> blockRanges = const [],
    List<FeatureRange> featureRanges = const [],
  }) {
    final controller = fieldController(tester);
    expect(controller.text, text);
    expect(controller.inlineRanges, inlineRanges);
    expect(controller.blockRanges, blockRanges);
    expect(controller.featureRanges, featureRanges);
  }

  group('ReplyScreen drafts keep formatting on close', () {
    const closes = [
      (name: 'Cancel', systemBack: false),
      (name: 'system back', systemBack: true),
    ];

    for (final close in closes) {
      toolbarTest('closing by ${close.name} then reopening restores the '
          'untrimmed text with its bold and quote', (tester) async {
        await harness.openRecordingReply(tester);
        await typeAndSelect(
          tester,
          '  hello  ',
          const TextSelection(baseOffset: 2, extentOffset: 7),
        );
        await tapButton(tester, 'Bold');
        await tapButton(tester, 'Quote');

        if (close.systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ReplyScreen), findsNothing);

        await reopen(tester);

        expectField(
          tester,
          text: '  hello  ',
          inlineRanges: const [InlineRange(InlineFormat.bold, 2, 7)],
          blockRanges: const [BlockRange(BlockFormat.blockquote, 0, 9)],
        );
      });
    }

    testWidgets('a stored mention range survives open, Cancel and reopen', (
      tester,
    ) async {
      harness.commentsProvider.saveDraft(
        ComposerDraft(
          text: 'hi @alice.test',
          featureRanges: const [
            FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 3, 14),
          ],
        ),
        parentUri: _parentUri,
      );
      await harness.pumpBase(tester);
      await reopen(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await reopen(tester);

      expectField(
        tester,
        text: 'hi @alice.test',
        featureRanges: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 3, 14),
        ],
      );
    });
  });

  group('ReplyScreen submit snapshot', () {
    toolbarTest('edits and formatting changes made while a mention lookup is '
        'pending do not change what is sent', (tester) async {
      final lookup = Completer<String>();
      when(harness.mockApiService.resolveHandle(handle: 'alice.test'))
          .thenAnswer((_) => lookup.future);
      final submissions = await harness.openRecordingReply(tester);
      await typeAndSelect(
        tester,
        '  Hi @alice.test  ',
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      await tapButton(tester, 'Bold');

      await tapSendAndPumpUntilInFlight(tester);
      await focusField(
        tester,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      await tapButton(tester, 'Bold');
      expect(fieldController(tester).inlineRanges, isEmpty);
      await tester.enterText(
        find.byType(EditableText),
        '  Hi @alice.test edited  ',
      );
      await tester.pump();

      lookup.complete('did:plc:alice');
      await tester.pumpAndSettle();

      expect(submissions, hasLength(1));
      final (content, facets) = submissions.single;
      expect(content, 'Hi @alice.test');
      expect(
        facets,
        unorderedEquals([
          '[0,2) [{"\$type":"$_facet#bold"}]',
          '[3,14) [{"\$type":"$_facet#mention","did":"did:plc:alice"}]',
        ]),
      );
    });
  });

  group('ReplyScreen draft after a failed send', () {
    toolbarTest('a mention lookup that fails after system back restores the '
        'text and formatting from Send, not the later edits', (tester) async {
      final lookup = Completer<String>();
      when(harness.mockApiService.resolveHandle(handle: 'alice.test'))
          .thenAnswer((_) => lookup.future);
      await harness.openRecordingReply(tester);
      await typeAndSelect(
        tester,
        'hi @alice.test',
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      await tapButton(tester, 'Bold');

      await tapSendAndPumpUntilInFlight(tester);
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      await tapButton(tester, 'Bold');
      await tester.enterText(find.byType(EditableText), 'hi @alice.test more');
      await tester.pump();
      await systemBackAndFinishTransition(tester);
      expect(find.byType(ReplyScreen), findsNothing);

      lookup.completeError(
        ServerException('Mention lookup unavailable', statusCode: 503),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await reopen(tester);
      expectField(
        tester,
        text: 'hi @alice.test',
        inlineRanges: const [InlineRange(InlineFormat.bold, 0, 2)],
      );
    });

    toolbarTest('a send that fails after system back restores the text and '
        'formatting from Send, not the later edits', (tester) async {
      final submit = Completer<void>();
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: createComment(_parentUri),
        onSubmit: (content, facets) => submit.future,
      );
      await typeAndSelect(
        tester,
        'hello world',
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Quote');

      await tapSendAndPumpUntilInFlight(tester);
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Quote');
      await tester.enterText(find.byType(EditableText), 'hello world again');
      await tester.pump();
      await systemBackAndFinishTransition(tester);
      expect(find.byType(ReplyScreen), findsNothing);

      submit.completeError(Exception('network unreachable'));
      await tester.pump();

      await reopen(tester);
      expectField(
        tester,
        text: 'hello world',
        inlineRanges: const [InlineRange(InlineFormat.bold, 0, 5)],
        blockRanges: const [BlockRange(BlockFormat.blockquote, 0, 11)],
      );
    });

    toolbarTest('a newer draft saved while the send is pending wins over the '
        'failed send, text and formatting', (tester) async {
      final submit = Completer<void>();
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: createComment(_parentUri),
        onSubmit: (content, facets) => submit.future,
      );
      await typeAndSelect(
        tester,
        'First reply in flight',
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tapButton(tester, 'Bold');

      await tapSendAndPumpUntilInFlight(tester);
      await systemBackAndFinishTransition(tester);
      expect(find.byType(ReplyScreen), findsNothing);

      harness.commentsProvider.saveDraft(
        ComposerDraft(
          text: 'Newer draft',
          inlineRanges: const [InlineRange(InlineFormat.italic, 6, 11)],
          blockRanges: const [BlockRange(BlockFormat.heading, 0, 11, level: 2)],
        ),
        parentUri: _parentUri,
      );

      submit.completeError(Exception('network unreachable'));
      await tester.pump();

      await reopen(tester);
      expectField(
        tester,
        text: 'Newer draft',
        inlineRanges: const [InlineRange(InlineFormat.italic, 6, 11)],
        blockRanges: const [BlockRange(BlockFormat.heading, 0, 11, level: 2)],
      );
    });
  });

  group('ReplyScreen over the facet limit', () {
    testWidgets('formatting over 200 facets blocks the send with the '
        'over-limit message and keeps the text and formatting', (tester) async {
      // 201 letters apart by spaces, each bold on its own: 201 facets
      final text = List.filled(201, 'a').join(' ');
      final ranges = [
        for (var index = 0; index < 201; index++)
          InlineRange(InlineFormat.bold, 2 * index, 2 * index + 1),
      ];
      harness.commentsProvider.saveDraft(
        ComposerDraft(text: text, inlineRanges: ranges),
        parentUri: _parentUri,
      );
      final submissions = await harness.openRecordingReply(tester);
      expect(fieldController(tester).inlineRanges, hasLength(201));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submissions, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Too much formatting to send. Remove some and try again.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(ReplyScreen), findsOneWidget);
      expectField(tester, text: text, inlineRanges: ranges);
    });
  });
}
