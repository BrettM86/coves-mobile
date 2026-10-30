import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/theme/rich_text_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The effective style of every character of [span], failing when its text
/// differs from [text]
List<TextStyle> characterStylesOf(InlineSpan span, String text) {
  final rendered = StringBuffer();
  final styles = <TextStyle>[];
  void visit(InlineSpan span, TextStyle inherited) {
    expect(span, isA<TextSpan>(), reason: 'only TextSpans are built');
    final textSpan = span as TextSpan;
    final style = inherited.merge(textSpan.style);
    final spanText = textSpan.text ?? '';
    rendered.write(spanText);
    styles.addAll(List.filled(spanText.length, style));
    for (final child in textSpan.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(span, const TextStyle());
  expect(rendered.toString(), text, reason: 'concatenated span text');
  return styles;
}

/// The runs of characters carrying the mention or link color, as
/// (color name, start, end) in UTF-16 offsets
List<(String, int, int)> coloredRuns(List<TextStyle> styles) {
  String? colorName(TextStyle style) => style.color == RichTextPalette.mention
      ? 'mention'
      : style.color == RichTextPalette.link
      ? 'link'
      : null;
  final runs = <(String, int, int)>[];
  var index = 0;
  while (index < styles.length) {
    final name = colorName(styles[index]);
    if (name == null) {
      index++;
      continue;
    }
    final start = index;
    while (index < styles.length && colorName(styles[index]) == name) {
      index++;
    }
    runs.add((name, start, index));
  }
  return runs;
}

/// A build context under the app's dark theme, for building spans
Future<BuildContext> buildContextFor(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: const SizedBox()),
  );
  return tester.element(find.byType(SizedBox));
}
