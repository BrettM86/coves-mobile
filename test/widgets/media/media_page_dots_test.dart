// B1: the MediaPageDots primitive — one dot per page in a dark translucent
// rounded pill, the current page's dot highlighted, announced as
// "Image i of N", and nothing at all for a single page.
import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: Center(child: child)),
);

/// The fill colour a widget paints, whichever box widget draws it.
Color? _paintedColor(Widget widget) {
  return switch (widget) {
    Container(:final color?) => color,
    Container(decoration: BoxDecoration(:final color?)) => color,
    DecoratedBox(decoration: BoxDecoration(:final color?)) => color,
    ColoredBox(:final color) => color,
    _ => null,
  };
}

/// The colour dot [index] is drawn in: the first painted colour at or under
/// the keyed dot.
Color _dotColor(WidgetTester tester, int index) {
  final colors = tester
      .widgetList(
        find.descendant(
          of: find.byKey(Key('media-page-dot-$index')),
          matching: find.byWidgetPredicate((w) => _paintedColor(w) != null),
          matchRoot: true,
        ),
      )
      .map(_paintedColor);
  expect(colors, isNotEmpty, reason: 'dot $index should paint a colour');
  return colors.first!;
}

/// Box decorations above dot 0 that read as the pill: rounded, with a
/// translucent dark fill.
Finder _pill() => find.ancestor(
  of: find.byKey(const Key('media-page-dot-0')),
  matching: find.byWidgetPredicate((w) {
    final decoration = switch (w) {
      Container(:final decoration?) => decoration,
      DecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    if (decoration is! BoxDecoration) {
      return false;
    }
    final color = decoration.color;
    return color != null &&
        color.a < 1 &&
        color.computeLuminance() < 0.2 &&
        decoration.borderRadius != null;
  }),
);

void main() {
  testWidgets('seven pages on page three: seven dots, the third highlighted', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const MediaPageDots(count: 7, index: 2)));

    for (var i = 0; i < 7; i++) {
      expect(find.byKey(Key('media-page-dot-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('media-page-dot-7')), findsNothing);

    expect(_dotColor(tester, 2), AppColors.textPrimary);
    final dimmer = _dotColor(tester, 0);
    expect(dimmer, isNot(AppColors.textPrimary));
    for (final i in [1, 3, 4, 5, 6]) {
      expect(_dotColor(tester, i), dimmer);
    }

    expect(_pill(), findsWidgets);
    expect(find.bySemanticsLabel('Image 3 of 7'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('eight pages on the last page highlights the eighth dot', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const MediaPageDots(count: 8, index: 7)));

    for (var i = 0; i < 8; i++) {
      expect(find.byKey(Key('media-page-dot-$i')), findsOneWidget);
    }
    expect(_dotColor(tester, 7), AppColors.textPrimary);
    expect(_dotColor(tester, 0), isNot(AppColors.textPrimary));
  });

  testWidgets('a single page draws no dot and announces nothing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const MediaPageDots(count: 1, index: 0)));

    expect(find.byKey(const Key('media-page-dot-0')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Image ')), findsNothing);
    handle.dispose();
  });
}
