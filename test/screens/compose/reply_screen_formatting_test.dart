import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/composer/facet_block_painter.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:coves_flutter/widgets/composer/formatting_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/semantics_helpers.dart';
import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import '../../widgets/composer/span_style_helpers.dart';
import 'reply_screen_test_harness.dart';

/// The namespace every Coves facet feature type is under
const _facet = 'social.coves.richtext.facet';

void main() {
  late ReplyScreenHarness harness;

  setUp(() => harness = ReplyScreenHarness());
  tearDown(() => harness.dispose());

  /// Pushes a reply to a comment, recording every submission
  Future<List<(String, List<String>)>> openReply(WidgetTester tester) =>
      harness.openRecordingReply(tester);

  /// The text the field renders, as laid out
  TextSpan fieldSpan(WidgetTester tester) =>
      tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable
              .text!
          as TextSpan;

  group('ReplyScreen bottom bar', () {
    toolbarTest('focused: the formatting toolbar sits beside @, image and '
        'Send, over a FacetTextField with autocorrect off and suggestions '
        'on', (tester) async {
      await openReply(tester);
      // pushReply settles past the screen's delayed autofocus
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
        reason: 'the body field is focused on open',
      );

      expect(button('Bold'), findsOneWidget);
      expect(find.byType(FormattingToolbar), findsOneWidget);
      expect(button('Mention user'), findsOneWidget);
      expect(button('Add image'), findsOneWidget);
      expect(button('Send comment'), findsOneWidget);

      expect(find.byType(FacetTextField), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(FacetTextField),
          matching: find.byType(TextField),
        ),
      );
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isTrue);
    });

    toolbarTest('unfocused: the formatting toolbar hides; @ shows its banner, '
        'image opens the source picker, and Send still submits', (
      tester,
    ) async {
      final submissions = await openReply(tester);
      await tester.enterText(find.byType(EditableText), 'Sent unfocused');
      await tester.pump();
      expect(button('Bold'), findsOneWidget, reason: 'toolbar while focused');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(button('Bold'), findsNothing);
      expect(find.byType(FormattingToolbar), findsNothing);
      expect(button('Mention user'), findsOneWidget);
      expect(button('Add image'), findsOneWidget);
      expect(button('Send comment'), findsOneWidget);

      await tester.tap(button('Mention user'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsOneWidget);
      // The banner hides itself after two seconds
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);

      // Add image asks where the images come from
      await tester.tap(button('Add image'));
      await tester.pumpAndSettle();
      expect(find.text('Select Image Source'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Select Image Source'), findsNothing);

      await tester.tap(button('Send comment'));
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.single.$1, 'Sent unfocused');
      expect(submissions.single.$2, isEmpty);
    });

    toolbarTest('a screen reader activates Send through its semantics tap '
        'action and submits', (tester) async {
      final submissions = await openReply(tester);
      await tester.enterText(find.byType(EditableText), 'Sent by TalkBack');
      await tester.pump();

      activateBySemantics(tester, button('Send comment'));
      await tester.pumpAndSettle();

      expect(submissions, hasLength(1));
      expect(submissions.single.$1, 'Sent by TalkBack');
    });
  });

  group('ReplyScreen formats from the toolbar', () {
    // Each format applied over all of 'hello': the facet it sends
    const rows = [
      (label: 'Bold', facet: '[0,5) [{"\$type":"$_facet#bold"}]'),
      (label: 'Italic', facet: '[0,5) [{"\$type":"$_facet#italic"}]'),
      (
        label: 'Strikethrough',
        facet: '[0,5) [{"\$type":"$_facet#strikethrough"}]',
      ),
      (label: 'Spoiler', facet: '[0,5) [{"\$type":"$_facet#spoiler"}]'),
      (label: 'Code', facet: '[0,5) [{"\$type":"$_facet#code"}]'),
      (label: 'Quote', facet: '[0,5) [{"\$type":"$_facet#blockquote"}]'),
      (
        label: 'Heading 1',
        facet: '[0,5) [{"\$type":"$_facet#heading","level":1}]',
      ),
      (label: 'Code block', facet: '[0,5) [{"\$type":"$_facet#codeBlock"}]'),
    ];

    for (final row in rows) {
      toolbarTest('${row.label} shows in the field and is sent as its facet', (
        tester,
      ) async {
        final submissions = await openReply(tester);
        await tester.enterText(find.byType(EditableText), 'hello');
        await focusField(
          tester,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
        final plainStyles = characterStylesOf(fieldSpan(tester), 'hello');

        if (row.label == 'Heading 1') {
          await openPicker(tester);
          await pickEntry(tester, 'Heading 1');
        } else {
          await tapButton(tester, row.label);
        }

        if (row.label == 'Quote') {
          // A quote is drawn by the field's block painter, not as a style
          final painters = tester
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byType(FacetTextField),
                  matching: find.byType(CustomPaint),
                ),
              )
              .map((paint) => paint.foregroundPainter)
              .whereType<FacetBlockPainter>()
              .toList();
          expect(painters, hasLength(1));
          expect(painters.single.layer, FacetBlockLayer.quoteBars);
          expect(painters.single.controller.blockRanges, const [
            BlockRange(BlockFormat.blockquote, 0, 5),
          ]);
        } else {
          final styles = characterStylesOf(fieldSpan(tester), 'hello');
          for (var i = 0; i < 5; i++) {
            expect(
              styles[i],
              isNot(plainStyles[i]),
              reason: 'character $i of hello shows ${row.label}',
            );
          }
        }

        await tester.tap(button('Send comment'));
        await tester.pumpAndSettle();

        expect(submissions, hasLength(1));
        expect(submissions.single.$1, 'hello');
        expect(submissions.single.$2, [row.facet]);
      });
    }
  });

  group('ReplyScreen submit with formatting and mentions', () {
    toolbarTest('sends trimmed content with the formatting facets and the '
        'resolved mention; an unknown handle and anything inside inline code '
        'stay plain text', (tester) async {
      when(harness.mockApiService.resolveHandle(handle: 'alice.test'))
          .thenAnswer((_) async => 'did:plc:alice');
      // The AppView answers an unknown handle with a not-found status
      when(
        harness.mockApiService.resolveHandle(handle: 'ghost.test'),
      ).thenAnswer(
        (_) =>
            Future<String>.error(NotFoundException('Unable to resolve handle')),
      );
      when(harness.mockApiService.resolveHandle(handle: 'bob.test'))
          .thenAnswer((_) async => 'did:plc:bob');
      final submissions = await openReply(tester);

      // UTF-16 offsets: 'Hi' [2,4), '@bob.test https://x.com' [33,56)
      await tester.enterText(
        find.byType(EditableText),
        '  Hi @alice.test and @ghost.test @bob.test https://x.com  ',
      );
      await focusField(
        tester,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      await tapButton(tester, 'Bold');
      await focusField(
        tester,
        const TextSelection(baseOffset: 33, extentOffset: 56),
      );
      await tapButton(tester, 'Code');

      await tester.tap(button('Send comment'));
      await tester.pumpAndSettle();

      expect(submissions, hasLength(1));
      final (content, facets) = submissions.single;
      expect(content, 'Hi @alice.test and @ghost.test @bob.test https://x.com');
      expect(
        facets,
        unorderedEquals([
          '[0,2) [{"\$type":"$_facet#bold"}]',
          '[3,14) [{"\$type":"$_facet#mention","did":"did:plc:alice"}]',
          '[31,54) [{"\$type":"$_facet#code"}]',
        ]),
      );
      verifyNever(harness.mockApiService.resolveHandle(handle: 'bob.test'));
    });
  });
}
