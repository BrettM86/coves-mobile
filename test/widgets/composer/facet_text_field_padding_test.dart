import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_block_painter.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text's start inset inside the field: the editable's left edge less
/// the field's.
double textInset(WidgetTester tester) {
  final field = tester.getRect(find.byType(FacetTextField));
  final editable = tester.getRect(find.byType(EditableText));
  return editable.left - field.left;
}

void toggleOver(
  FacetEditingController controller,
  int start,
  int end,
  BlockFormat format,
) {
  controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..toggleBlock(format);
}

Future<void> pumpField(
  WidgetTester tester,
  FacetEditingController controller,
  EdgeInsets contentPadding, {
  double outerStartMargin = 0,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: FacetTextField(
          controller: controller,
          outerStartMargin: outerStartMargin,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: contentPadding,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('without a quote or code block the text starts at the '
      'decoration content padding', (tester) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);

    await pumpField(tester, controller, EdgeInsets.zero);
    expect(textInset(tester), 0);

    await pumpField(tester, controller, const EdgeInsets.all(16));
    expect(textInset(tester), 16);
  });

  testWidgets('a quote leaves the text where it is when the start padding '
      'has room for the bars', (tester) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);
    await pumpField(tester, controller, const EdgeInsets.all(16));

    toggleOver(controller, 6, 12, BlockFormat.blockquote);
    await tester.pump();
    expect(textInset(tester), 16);
  });

  testWidgets('a quote leaves the text where it is when the margin outside '
      'the field has room for the bars', (tester) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);
    await pumpField(tester, controller, EdgeInsets.zero, outerStartMargin: 16);

    toggleOver(controller, 6, 12, BlockFormat.blockquote);
    await tester.pump();
    expect(textInset(tester), 0);
  });

  testWidgets('with no room a quote raises the start padding to fit one bar, '
      'and removing it gives the room back', (tester) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);
    await pumpField(tester, controller, EdgeInsets.zero);

    toggleOver(controller, 6, 12, BlockFormat.blockquote);
    await tester.pump();
    expect(textInset(tester), FacetBlockPainter.minimumQuoteRoom);

    toggleOver(controller, 6, 12, BlockFormat.blockquote);
    await tester.pump();
    expect(textInset(tester), 0);
  });

  testWidgets('a code block alone reserves only its background lead-in', (
    tester,
  ) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);
    await pumpField(tester, controller, EdgeInsets.zero);

    toggleOver(controller, 6, 12, BlockFormat.codeBlock);
    await tester.pump();
    expect(textInset(tester), FacetBlockPainter.codePadding);
  });

  testWidgets('a heading reserves nothing', (tester) async {
    final controller = FacetEditingController(text: 'plain\nformat');
    addTearDown(controller.dispose);
    await pumpField(tester, controller, EdgeInsets.zero);

    controller
      ..selection = const TextSelection.collapsed(offset: 8)
      ..toggleBlock(BlockFormat.heading);
    await tester.pump();
    expect(textInset(tester), 0);
  });

  testWidgets('swapping controllers follows the new controller only', (
    tester,
  ) async {
    final plain = FacetEditingController(text: 'plain\nformat');
    final quoted = FacetEditingController(text: 'plain\nformat');
    addTearDown(plain.dispose);
    addTearDown(quoted.dispose);
    toggleOver(quoted, 6, 12, BlockFormat.blockquote);

    await pumpField(tester, plain, EdgeInsets.zero);
    expect(textInset(tester), 0);

    await pumpField(tester, quoted, EdgeInsets.zero);
    expect(textInset(tester), FacetBlockPainter.minimumQuoteRoom);

    toggleOver(plain, 6, 12, BlockFormat.blockquote);
    toggleOver(quoted, 6, 12, BlockFormat.blockquote);
    await tester.pump();
    expect(textInset(tester), 0);
  });

  testWidgets('nested quotes keep the text in a 16px room until the bars '
      'would be too thin, then raise the padding', (tester) async {
    for (final (level, inset) in [
      (2, 16.0),
      (3, FacetBlockPainter.quoteRoomFor(3)),
    ]) {
      // Nested levels come only from loaded records; the editor cannot
      // nest quotes itself.
      final controller = FacetEditingController.withRanges(
        'plain\nformat',
        blockRanges: [BlockRange(BlockFormat.blockquote, 6, 12, level: level)],
      );
      addTearDown(controller.dispose);
      await pumpField(tester, controller, const EdgeInsets.all(16));
      expect(
        controller.blockRanges.single.level,
        level,
        reason: 'level $level quote loaded',
      );
      expect(textInset(tester), inset, reason: 'level $level');
    }
  });
}
