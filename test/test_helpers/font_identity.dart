import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [style] renders in exactly [family].
///
/// A null [family] is a real expectation, not "don't care": it asserts the
/// app sets no family at all and the platform picks the face. That is the
/// current design, and this still fails if someone bundles a font without
/// updating `AppTypography.fontFamily`.
///
/// Exact equality, and that is the point. The looser "starts with the family
/// name" test is what let a real defect through: `google_fonts` registers one
/// family per weight (`Inter_regular`, `Inter_w600`, `Inter_700`), and
/// `'Inter_regular'.startsWith('Inter')` is true - so a style that could only
/// ever render Regular, synthetically emboldened at every heavier weight,
/// looked like a pass. With the font bundled as a single variable family,
/// the family name is plain `Inter` at every weight, and anything else is a
/// symptom worth failing on.
bool rendersInFamily(TextStyle? style, String? family) =>
    style?.fontFamily == family;

/// A piece of text as it actually renders, with the style that applies to it.
class RenderedSpan {
  const RenderedSpan(this.text, this.style);

  final String text;

  /// The style with every ancestor span's style merged in, so it reflects
  /// what the reader sees rather than what one nested span happened to set.
  final TextStyle? style;

  @override
  String toString() => '"$text" (family: ${style?.fontFamily})';
}

/// Every non-blank leaf text span rendered under [within].
///
/// Reads the realized [RichText]s rather than the widgets that built them,
/// which is the only way to see a style that arrived by inheritance - the
/// interesting case whenever a style sheet stops naming a family.
List<RenderedSpan> renderedSpans(WidgetTester tester, Finder within) {
  final spans = <RenderedSpan>[];

  void visit(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) {
      return;
    }
    final effective = inherited?.merge(span.style) ?? span.style;
    final text = span.text;
    if (text != null && text.trim().isNotEmpty) {
      spans.add(RenderedSpan(text, effective));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, effective);
    }
  }

  final richTexts = find.descendant(
    of: within,
    matching: find.byType(RichText),
    matchRoot: true,
  );
  for (final richText in tester.widgetList<RichText>(richTexts)) {
    visit(richText.text, null);
  }

  return spans;
}
