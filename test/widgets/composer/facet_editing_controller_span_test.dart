import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const baseStyle = TextStyle(fontSize: 14, color: Color(0xFF000000));

FacetEditingController controllerWith(
  String text,
  List<InlineRange> ranges,
  int caret,
) {
  final controller = FacetEditingController(text: text);
  for (final range in ranges) {
    controller
      ..selection = TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      )
      ..toggleInline(range.format);
  }
  controller.selection = TextSelection.collapsed(offset: caret);
  return controller;
}

Future<void> pumpField(
  WidgetTester tester,
  FacetEditingController controller,
) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: EditableText(
        controller: controller,
        focusNode: focusNode,
        style: baseStyle,
        cursorColor: const Color(0xFF000000),
        backgroundCursorColor: const Color(0xFF808080),
      ),
    ),
  );
}

/// The effective (inherited) style of every character of the rendered span.
/// Fails on any WidgetSpan and when the span text differs from [text].
List<TextStyle> characterStyles(WidgetTester tester, String text) {
  final root = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable
      .text!;
  final rendered = StringBuffer();
  final styles = <TextStyle>[];
  void visit(InlineSpan span, TextStyle inherited) {
    expect(span, isA<TextSpan>(), reason: 'only TextSpans are rendered');
    final textSpan = span as TextSpan;
    final style = inherited.merge(textSpan.style);
    final spanText = textSpan.text ?? '';
    rendered.write(spanText);
    styles.addAll(List.filled(spanText.length, style));
    for (final child in textSpan.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(root, const TextStyle());
  expect(rendered.toString(), text, reason: 'concatenated span text');
  return styles;
}

bool isBold(TextStyle style) => style.fontWeight == FontWeight.w700;
bool isItalic(TextStyle style) => style.fontStyle == FontStyle.italic;
bool isStruck(TextStyle style) =>
    style.decoration?.contains(TextDecoration.lineThrough) ?? false;
bool isUnderlined(TextStyle style) =>
    style.decoration?.contains(TextDecoration.underline) ?? false;
bool isCode(TextStyle style) =>
    style.fontFamily == 'monospace' &&
    listEquals(style.fontFamilyFallback, const [
      'Menlo',
      'Courier New',
      'Courier',
    ]);
bool isSpoiler(TextStyle style) =>
    style.backgroundColor ==
        AppColors.backgroundTertiary.withValues(alpha: 0.5) &&
    style.color != null &&
    style.color!.a > 0;

/// Expects [has] to hold on exactly the characters of [start, end).
void expectExactly(
  List<TextStyle> styles,
  bool Function(TextStyle) has,
  int start,
  int end,
  String label,
) {
  for (var index = 0; index < styles.length; index++) {
    expect(
      has(styles[index]),
      start <= index && index < end,
      reason: '$label at index $index (expected [$start, $end))',
    );
  }
}

void main() {
  testWidgets('B4 spans stay safe and decorated at every composing update', (
    tester,
  ) async {
    final controller = controllerWith('abcd efgh', const [
      InlineRange(InlineFormat.bold, 0, 4),
      InlineRange(InlineFormat.strikethrough, 5, 9),
    ], 9);
    await pumpField(tester, controller);
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump();

    const steps = [
      (
        text: 'abcd efgh',
        caret: 9,
        composing: (5, 9),
        bold: (0, 4),
        struck: (5, 9),
      ),
      (
        text: 'abcd ef',
        caret: 7,
        composing: (5, 7),
        bold: (0, 4),
        struck: (5, 7),
      ),
      (
        text: 'abcd efghijkl',
        caret: 13,
        composing: (5, 13),
        bold: (0, 4),
        struck: (5, 13),
      ),
      (
        text: 'abcd efghijkl',
        caret: 13,
        composing: (0, 0),
        bold: (0, 4),
        struck: (5, 13),
      ),
      (
        text: 'abcd efghijkl',
        caret: 4,
        composing: (0, 4),
        bold: (0, 4),
        struck: (5, 13),
      ),
      (
        text: 'ab efghijkl',
        caret: 2,
        composing: (0, 2),
        bold: (0, 2),
        struck: (3, 11),
      ),
    ];
    for (final (index, step) in steps.indexed) {
      final (composingStart, composingEnd) = step.composing;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: step.text,
          selection: TextSelection.collapsed(offset: step.caret),
          composing: composingStart == composingEnd
              ? TextRange.empty
              : TextRange(start: composingStart, end: composingEnd),
        ),
      );
      await tester.pump();

      final label = 'step ${index + 1}';
      final styles = characterStyles(tester, step.text);
      expectExactly(
        styles,
        isUnderlined,
        composingStart,
        composingEnd,
        '$label underline',
      );
      expectExactly(styles, isBold, step.bold.$1, step.bold.$2, '$label bold');
      expectExactly(
        styles,
        isStruck,
        step.struck.$1,
        step.struck.$2,
        '$label strikethrough',
      );
    }
  });

  testWidgets('B5 inline styles cover exactly their ranges', (tester) async {
    const text = 'bold ital strk code spoil plain';
    final controller = controllerWith(text, const [
      InlineRange(InlineFormat.bold, 0, 4),
      InlineRange(InlineFormat.italic, 3, 9),
      InlineRange(InlineFormat.strikethrough, 10, 14),
      InlineRange(InlineFormat.code, 15, 19),
      InlineRange(InlineFormat.spoiler, 20, 25),
    ], 31);
    await pumpField(tester, controller);

    void expectInlineStyles(String label) {
      final styles = characterStyles(tester, text);
      expectExactly(styles, isBold, 0, 4, '$label bold');
      expectExactly(styles, isItalic, 3, 9, '$label italic');
      expectExactly(styles, isStruck, 10, 14, '$label strikethrough');
      expectExactly(styles, isCode, 15, 19, '$label code');
      expectExactly(styles, isSpoiler, 20, 25, '$label spoiler');
      expectExactly(styles, isUnderlined, 0, 0, '$label underline');
    }

    expectInlineStyles('no composing');

    controller.value = const TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    await tester.pump();
    expectInlineStyles('unfocused composing');
  });
}
