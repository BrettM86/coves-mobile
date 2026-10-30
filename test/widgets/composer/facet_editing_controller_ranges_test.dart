import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selects [baseOffset, extentOffset) and toggles [format] over it.
void toggleOver(
  FacetEditingController controller,
  InlineFormat format,
  int baseOffset,
  int extentOffset,
) {
  select(controller, baseOffset, extentOffset);
  controller.toggleInline(format);
}

void select(
  FacetEditingController controller,
  int baseOffset,
  int extentOffset,
) {
  controller.selection = TextSelection(
    baseOffset: baseOffset,
    extentOffset: extentOffset,
  );
}

void main() {
  test('B1 toggling a format on an unformatted selection applies it', () {
    for (final format in InlineFormat.values) {
      final controller = FacetEditingController(text: 'hello world');
      toggleOver(controller, format, 0, 5);
      expect(controller.inlineRanges, [
        InlineRange(format, 0, 5),
      ], reason: format.name);
    }
  });

  test('B1 a reversed selection applies the normalized range', () {
    final controller = FacetEditingController(text: 'hello world');
    toggleOver(controller, InlineFormat.bold, 5, 0);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 5),
    ]);
  });

  test('B2 toggling a format over a fully formatted range removes it', () {
    for (final format in InlineFormat.values) {
      final controller = FacetEditingController(text: 'hello world');
      toggleOver(controller, format, 0, 5);
      toggleOver(controller, format, 6, 11);
      toggleOver(controller, format, 0, 5);
      expect(controller.inlineRanges, [
        InlineRange(format, 6, 11),
      ], reason: format.name);
    }
  });

  test('B3 removing part of a range keeps the remainder', () {
    const cases = [
      (
        removeStart: 3,
        removeEnd: 6,
        expected: [
          InlineRange(InlineFormat.bold, 0, 3),
          InlineRange(InlineFormat.bold, 6, 10),
        ],
      ),
      (
        removeStart: 0,
        removeEnd: 3,
        expected: [InlineRange(InlineFormat.bold, 3, 10)],
      ),
      (
        removeStart: 7,
        removeEnd: 10,
        expected: [InlineRange(InlineFormat.bold, 0, 7)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'hello world!');
      toggleOver(controller, InlineFormat.bold, 0, 10);
      toggleOver(
        controller,
        InlineFormat.bold,
        testCase.removeStart,
        testCase.removeEnd,
      );
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'remove [${testCase.removeStart}, ${testCase.removeEnd})',
      );
    }
  });

  test('B4 a partially formatted selection applies the format', () {
    final controller = FacetEditingController(text: 'hello world!');
    toggleOver(controller, InlineFormat.bold, 4, 6);
    toggleOver(controller, InlineFormat.bold, 2, 8);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 2, 8),
    ]);
  });

  test('B5 touching, overlapping, and bridged same-format ranges merge', () {
    const cases = [
      (
        name: 'touching',
        toggles: [(0, 4), (4, 8)],
        expected: [InlineRange(InlineFormat.bold, 0, 8)],
      ),
      (
        name: 'overlapping',
        toggles: [(0, 4), (2, 8)],
        expected: [InlineRange(InlineFormat.bold, 0, 8)],
      ),
      (
        name: 'bridging',
        toggles: [(0, 2), (4, 6), (2, 4)],
        expected: [InlineRange(InlineFormat.bold, 0, 6)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'hello world!');
      for (final (start, end) in testCase.toggles) {
        toggleOver(controller, InlineFormat.bold, start, end);
      }
      expect(controller.inlineRanges, testCase.expected, reason: testCase.name);
    }
  });

  test('B6 overlapping ranges of different formats stay separate', () {
    final controller = FacetEditingController(text: 'hello world!');
    toggleOver(controller, InlineFormat.bold, 0, 6);
    toggleOver(controller, InlineFormat.italic, 3, 9);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 6),
      InlineRange(InlineFormat.italic, 3, 9),
    ]);
  });

  test('B6 toggling one format leaves another format untouched', () {
    final controller = FacetEditingController(text: 'hello world!');
    toggleOver(controller, InlineFormat.bold, 0, 6);
    toggleOver(controller, InlineFormat.italic, 3, 9);
    toggleOver(controller, InlineFormat.bold, 0, 6);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.italic, 3, 9),
    ]);
  });

  test('B6 ranges are sorted by start, then end, then format index', () {
    final controller = FacetEditingController(text: 'hello world!');
    toggleOver(controller, InlineFormat.italic, 3, 9);
    toggleOver(controller, InlineFormat.code, 0, 6);
    toggleOver(controller, InlineFormat.bold, 0, 6);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 6),
      InlineRange(InlineFormat.code, 0, 6),
      InlineRange(InlineFormat.italic, 3, 9),
    ]);
  });

  test('B7 a format is active only when it covers the whole selection', () {
    // bold [0,6), italic [3,9), code [0,12) covers every selection below so
    // each expected set is non-empty.
    const cases = [
      (base: 1, extent: 4, expected: {InlineFormat.bold, InlineFormat.code}),
      (base: 4, extent: 8, expected: {InlineFormat.italic, InlineFormat.code}),
      (
        base: 3,
        extent: 6,
        expected: {InlineFormat.bold, InlineFormat.italic, InlineFormat.code},
      ),
      (base: 5, extent: 8, expected: {InlineFormat.italic, InlineFormat.code}),
      (base: 0, extent: 6, expected: {InlineFormat.bold, InlineFormat.code}),
      (
        base: 6,
        extent: 3,
        expected: {InlineFormat.bold, InlineFormat.italic, InlineFormat.code},
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'hello world!');
      toggleOver(controller, InlineFormat.bold, 0, 6);
      toggleOver(controller, InlineFormat.italic, 3, 9);
      toggleOver(controller, InlineFormat.code, 0, 12);
      select(controller, testCase.base, testCase.extent);
      expect(
        controller.activeInlineFormats(),
        testCase.expected,
        reason: 'selection base ${testCase.base} extent ${testCase.extent}',
      );
    }
  });

  test('B7 a gap between two ranges of a format makes it inactive', () {
    final controller = FacetEditingController(text: 'hello world!');
    toggleOver(controller, InlineFormat.bold, 0, 3);
    toggleOver(controller, InlineFormat.bold, 6, 10);
    toggleOver(controller, InlineFormat.code, 0, 12);
    select(controller, 2, 7);
    expect(controller.activeInlineFormats(), {InlineFormat.code});
  });

  test('B7 a stale selection past the end of the text activates no format '
      'and toggles nothing', () {
    final controller = FacetEditingController(text: 'hello')
      ..value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 8, extentOffset: 12),
      );
    expect(controller.activeInlineFormats(), isEmpty);
    controller.toggleInline(InlineFormat.bold);
    expect(controller.inlineRanges, isEmpty);
  });

  group('B8 snapToGraphemeBoundaries widens to cluster boundaries', () {
    // Each text is 'x<cluster>y' or 'x<cluster>', so the cluster starts at
    // UTF-16 offset 1.
    const cases = [
      (
        // U+1F600 is one surrogate pair: 2 code units, cluster [1,3).
        name: 'surrogate pair',
        text: 'x\u{1F600}y',
        rows: [
          (start: 2, end: 4, expected: (1, 4)),
          (start: 0, end: 2, expected: (0, 3)),
          (start: 1, end: 3, expected: (1, 3)),
        ],
      ),
      (
        // The surrogate pair is the last thing in the text, cluster [1,3).
        name: 'surrogate pair at end of text',
        text: 'x\u{1F600}',
        rows: [(start: 0, end: 2, expected: (0, 3))],
      ),
      (
        // U+1F469 (2) + ZWJ (1) + U+1F469 (2) + ZWJ (1) + U+1F467 (2) = 8
        // code units, cluster [1,9).
        name: 'ZWJ sequence',
        text: 'x\u{1F469}\u200D\u{1F469}\u200D\u{1F467}y',
        rows: [
          (start: 2, end: 10, expected: (1, 10)),
          (start: 0, end: 5, expected: (0, 9)),
          (start: 1, end: 9, expected: (1, 9)),
        ],
      ),
      (
        // The ZWJ sequence is the last thing in the text, cluster [1,9).
        name: 'ZWJ sequence at end of text',
        text: 'x\u{1F469}\u200D\u{1F469}\u200D\u{1F467}',
        rows: [(start: 0, end: 5, expected: (0, 9))],
      ),
      (
        // Regional indicators U+1F1F3 (2) + U+1F1FF (2) = 4 code units,
        // cluster [1,5); offset 3 sits between the two indicators.
        name: 'flag',
        text: 'x\u{1F1F3}\u{1F1FF}y',
        rows: [
          (start: 3, end: 6, expected: (1, 6)),
          (start: 0, end: 2, expected: (0, 5)),
          (start: 1, end: 5, expected: (1, 5)),
        ],
      ),
      (
        // 'e' (1) + U+0301 combining acute (1) = 2 code units, cluster [1,3).
        name: 'combining mark',
        text: 'xe\u0301y',
        rows: [
          (start: 2, end: 4, expected: (1, 4)),
          (start: 0, end: 2, expected: (0, 3)),
          (start: 1, end: 3, expected: (1, 3)),
        ],
      ),
    ];
    for (final testCase in cases) {
      test(testCase.name, () {
        for (final row in testCase.rows) {
          final snapped = snapToGraphemeBoundaries(
            testCase.text,
            TextRange(start: row.start, end: row.end),
          );
          expect(
            (snapped.start, snapped.end),
            row.expected,
            reason: 'range [${row.start}, ${row.end})',
          );
        }
      });
    }
  });

  test('B8 snapToGraphemeBoundaries agrees with segmenting the whole text '
      'for every range', () {
    // Plain text between CR LF, a combining mark, a flag run that re-pairs
    // from its start, a ZWJ sequence, CJK, Hangul jamo, an emoji with a skin
    // tone, a ZWJ sequence starting below U+0300 and Cyrillic with a
    // combining mark, so the boundaries in each stretch depend on its context.
    const text =
        'ab\r\nc e\u0301\u0301 \u{1F1F3}\u{1F1FF}\u{1F1FA}\u{1F1F8}\u{1F1EC}'
        ' x\u{1F469}\u200D\u{1F469}\u200D\u{1F467}y \u4F60\u597D\u4E16\u754C '
        '\u1100\u1161\u11A8 \u{1F44D}\u{1F3FD} a\u00A9\u200D\u2764b '
        '\u0438\u0306!\r\n';
    final boundaries = [0];
    for (final cluster in text.characters) {
      boundaries.add(boundaries.last + cluster.length);
    }
    for (var start = 0; start <= text.length; start++) {
      for (var end = start; end <= text.length; end++) {
        final snapped = snapToGraphemeBoundaries(
          text,
          TextRange(start: start, end: end),
        );
        expect(
          (snapped.start, snapped.end),
          (
            boundaries.lastWhere((b) => b <= start),
            boundaries.firstWhere((b) => b >= end),
          ),
          reason: 'range [$start, $end)',
        );
      }
    }
  });

  test('B8 toggling over a selection ending inside a cluster stores the '
      'widened range', () {
    // 'x' [0,1), U+1F600 surrogate pair [1,3), 'y' [3,4); selection end 2 is
    // inside the pair, so the stored range widens to [0,3).
    final controller = FacetEditingController(text: 'x\u{1F600}y');
    toggleOver(controller, InlineFormat.bold, 0, 2);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 3),
    ]);
  });
}
