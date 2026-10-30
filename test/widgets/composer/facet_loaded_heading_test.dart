import 'dart:ui' show Tristate;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'facet_fixture_helpers.dart';
import 'formatting_toolbar_test_helpers.dart';

/// The effective (inherited) style of every character of [span].
List<TextStyle> characterStyles(InlineSpan span) {
  final styles = <TextStyle>[];
  void visit(InlineSpan span, TextStyle inherited) {
    expect(span, isA<TextSpan>(), reason: 'only TextSpans are rendered');
    final textSpan = span as TextSpan;
    final style = inherited.merge(textSpan.style);
    styles.addAll(List.filled((textSpan.text ?? '').length, style));
    for (final child in textSpan.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(span, const TextStyle());
  return styles;
}

/// 'title\nbody' loaded with a level-5 heading on 'title', caret at [caret].
FacetEditingController loadedHeading5(int caret) =>
    FacetEditingController.fromRecord('title\nbody', [
      facet(0, 5, [const HeadingFacetFeature(level: 5)]),
    ])..selection = TextSelection.collapsed(offset: caret);

void main() {
  testWidgets('loaded H4, H5 and H6 lines build with their scale, weight '
      'and line height', (tester) async {
    final controller = FacetEditingController.fromRecord('h4\nh5\nh6', [
      facet(0, 2, [const HeadingFacetFeature(level: 4)]),
      facet(3, 5, [const HeadingFacetFeature(level: 5)]),
      facet(6, 8, [const HeadingFacetFeature(level: 6)]),
    ]);
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    final styles = characterStyles(
      controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: false,
      ),
    );

    expect(styles, hasLength(8));
    const rows = [
      (name: 'H4', offsets: [0, 1], size: 18.4),
      (name: 'H5', offsets: [3, 4], size: 16.8),
      (name: 'H6', offsets: [6, 7], size: 16.0),
    ];
    for (final row in rows) {
      for (final offset in row.offsets) {
        final style = styles[offset];
        final reason = '${row.name} offset $offset';
        expect(style.fontSize, closeTo(row.size, 0.01), reason: reason);
        expect(style.fontWeight, FontWeight.w600, reason: reason);
        expect(style.height, closeTo(1.3, 0.001), reason: reason);
      }
    }
  });

  group('Heading picker over a loaded H5 line', () {
    toolbarTest('shows Heading 5 selected, and Heading 2 replaces it', (
      tester,
    ) async {
      final controller = loadedHeading5(2);
      await pumpToolbar(tester, controller);

      expect(selectedState(tester, 'Heading'), Tristate.isTrue);
      await openPicker(tester);
      expect(selectedState(tester, 'Heading 5'), Tristate.isTrue);
      expect(selectedState(tester, 'Normal text'), Tristate.isFalse);

      await pickEntry(tester, 'Heading 2');

      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.heading, 0, 5, level: 2),
      ]);
    });

    toolbarTest('offers no Heading 4, 5 or 6 with the caret on a plain line', (
      tester,
    ) async {
      await pumpToolbar(tester, loadedHeading5(8));

      await openPicker(tester);

      for (final label in const ['Heading 4', 'Heading 5', 'Heading 6']) {
        expect(button(label), findsNothing, reason: label);
      }
    });
  });
}
