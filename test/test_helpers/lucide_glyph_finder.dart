import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Lucide glyphs painting exactly [paths] (by identity), inside [within]
/// when given.
Finder findLucideGlyph(List<String> paths, {Finder? within}) {
  final glyph = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter is LucideIconPainter &&
        identical((widget.painter! as LucideIconPainter).paths, paths),
  );
  return within == null ? glyph : find.descendant(of: within, matching: glyph);
}

/// Expects one Lucide glyph of [paths] inside [within], with real path data,
/// painted in [color] and laid out at [size] square when those are given.
void expectLucideGlyph(
  WidgetTester tester, {
  required Finder within,
  required List<String> paths,
  Color? color,
  double? size,
  String? reason,
}) {
  final glyph = findLucideGlyph(paths, within: within);
  expect(glyph, findsOneWidget, reason: reason);
  final painter =
      tester.widget<CustomPaint>(glyph).painter! as LucideIconPainter;
  // Distinct empty const lists canonicalize to one instance, so identity
  // alone cannot tell glyphs apart until each carries its path data.
  expect(painter.paths, isNotEmpty, reason: reason);
  if (color != null) {
    expect(painter.color, color, reason: reason);
  }
  if (size != null) {
    expect(tester.getSize(glyph), Size(size, size), reason: reason);
  }
}
