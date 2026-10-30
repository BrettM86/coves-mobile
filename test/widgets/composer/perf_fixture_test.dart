import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/utils/rich_text_composer.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'perf_fixture.dart';

/// Every grapheme boundary of [text], accumulated from its characters.
Set<int> graphemeBoundaries(String text) {
  final boundaries = <int>{0};
  var offset = 0;
  for (final grapheme in text.characters) {
    offset += grapheme.length;
    boundaries.add(offset);
  }
  return boundaries;
}

/// The (start, end) UTF-16 spans of the graphemes in [text] that satisfy
/// [test].
List<(int, int)> graphemeSpansWhere(String text, bool Function(String) test) {
  final spans = <(int, int)>[];
  var offset = 0;
  for (final grapheme in text.characters) {
    if (test(grapheme)) {
      spans.add((offset, offset + grapheme.length));
    }
    offset += grapheme.length;
  }
  return spans;
}

bool hasSurrogatePair(String grapheme) =>
    grapheme.codeUnits.any((unit) => unit >= 0xD800 && unit <= 0xDFFF);

bool hasCombiningMark(String grapheme) =>
    grapheme.length > 1 &&
    grapheme.codeUnits.any((unit) => unit >= 0x0300 && unit <= 0x036F);

bool lineStartsAt(String text, int offset) =>
    offset == 0 || text.codeUnitAt(offset - 1) == 0x0A;

bool lineEndsAt(String text, int offset) =>
    offset == text.length || text.codeUnitAt(offset) == 0x0A;

bool liesWithin(BlockRange inner, BlockRange outer) =>
    inner.start >= outer.start && inner.end <= outer.end;

List<(String, int, int)> allRanges(PerfFixture fixture) => [
  for (final range in fixture.inlineRanges)
    ('inline ${range.format.name}', range.start, range.end),
  for (final range in fixture.blockRanges)
    ('block ${range.format.name}', range.start, range.end),
  for (final range in fixture.featureRanges)
    ('feature ${range.feature}', range.start, range.end),
];

void main() {
  final fixture = buildPerfFixture();
  final blocks = fixture.blockRanges;
  final blockquotes = [
    for (final block in blocks)
      if (block.format == BlockFormat.blockquote) block,
  ];
  final headings = [
    for (final block in blocks)
      if (block.format == BlockFormat.heading) block,
  ];
  final codeBlocks = [
    for (final block in blocks)
      if (block.format == BlockFormat.codeBlock) block,
  ];
  final quotedHeadings = [
    for (final heading in headings)
      if (blockquotes.any((quote) => liesWithin(heading, quote))) heading,
  ];
  final quotedCodeBlocks = [
    for (final codeBlock in codeBlocks)
      if (blockquotes.any((quote) => liesWithin(codeBlock, quote))) codeBlock,
  ];

  test('B1: text is 10000 UTF-16 units with a surrogate pair and a '
      'combining sequence', () {
    expect(fixture.text.length, 10000, reason: 'text UTF-16 length');
    expect(fixture.text.characters.length, lessThanOrEqualTo(10000));
    expect(
      graphemeSpansWhere(fixture.text, hasSurrogatePair),
      isNotEmpty,
      reason: 'text has no surrogate-pair emoji grapheme',
    );
    expect(
      graphemeSpansWhere(fixture.text, hasCombiningMark),
      isNotEmpty,
      reason: 'text has no combining-sequence grapheme',
    );
  });

  test('B2: inline, block and feature ranges number 200 together', () {
    expect(
      fixture.inlineRanges.length +
          fixture.blockRanges.length +
          fixture.featureRanges.length,
      200,
      reason: 'total range count',
    );
  });

  test('B3: covers every format, both features, nested blocks and '
      'multi-unit graphemes', () {
    expect(
      {for (final range in fixture.inlineRanges) range.format},
      containsAll(InlineFormat.values),
      reason: 'inline formats present',
    );
    expect(
      {for (final block in blocks) block.format},
      containsAll(BlockFormat.values),
      reason: 'block formats present',
    );
    expect(
      fixture.featureRanges.where((r) => r.feature is MentionFacetFeature),
      isNotEmpty,
      reason: 'no mention feature range',
    );
    expect(
      fixture.featureRanges.where((r) => r.feature is LinkFacetFeature),
      isNotEmpty,
      reason: 'no link feature range',
    );
    expect(quotedHeadings, isNotEmpty, reason: 'no heading in a blockquote');
    expect(
      quotedCodeBlocks,
      isNotEmpty,
      reason: 'no code block in a blockquote',
    );

    bool strictlyContainedByInline((int, int) span) => fixture.inlineRanges.any(
      (range) => range.start < span.$1 && range.end > span.$2,
    );
    expect(
      graphemeSpansWhere(
        fixture.text,
        hasSurrogatePair,
      ).any(strictlyContainedByInline),
      isTrue,
      reason: 'no inline range strictly contains a surrogate-pair emoji',
    );
    expect(
      graphemeSpansWhere(
        fixture.text,
        hasCombiningMark,
      ).any(strictlyContainedByInline),
      isTrue,
      reason: 'no inline range strictly contains a combining sequence',
    );
  });

  test('B4: every range is non-empty, in bounds and on grapheme '
      'boundaries', () {
    final ranges = allRanges(fixture);
    expect(ranges, isNotEmpty, reason: 'fixture has no ranges to check');
    final boundaries = graphemeBoundaries(fixture.text);
    final violations = [
      for (final (name, start, end) in ranges)
        if (start < 0 ||
            start >= end ||
            end > 10000 ||
            !boundaries.contains(start) ||
            !boundaries.contains(end))
          '$name [$start, $end)',
    ];
    expect(violations, isEmpty);
  });

  test('B5: loads unchanged, stays within budget and serializes to 200 '
      'facets', () {
    expect(fixture.inlineRanges, isNotEmpty, reason: 'no inline ranges');
    expect(fixture.blockRanges, isNotEmpty, reason: 'no block ranges');
    expect(fixture.featureRanges, isNotEmpty, reason: 'no feature ranges');

    final controller = FacetEditingController.withRanges(
      fixture.text,
      inlineRanges: fixture.inlineRanges,
      blockRanges: fixture.blockRanges,
      featureRanges: fixture.featureRanges,
    );
    addTearDown(controller.dispose);

    expect(controller.inlineRanges, unorderedEquals(fixture.inlineRanges));
    expect(controller.blockRanges, unorderedEquals(fixture.blockRanges));
    expect(controller.featureRanges, unorderedEquals(fixture.featureRanges));
    expect(controller.formattingBudget.isOverLimit, isFalse);

    final serialized = serializeFormatting(
      fixture.text,
      inlineRanges: fixture.inlineRanges,
      blockRanges: fixture.blockRanges,
      featureRanges: fixture.featureRanges,
    );
    expect(serialized.facets, hasLength(200));
  });

  test('B6: headings are single whole lines away from code, and no inline '
      'range touches a code-block line', () {
    expect(headings, isNotEmpty, reason: 'no heading ranges');
    expect(codeBlocks, isNotEmpty, reason: 'no code-block ranges');
    expect(fixture.inlineRanges, isNotEmpty, reason: 'no inline ranges');

    final text = fixture.text;
    for (final heading in headings) {
      expect(
        lineStartsAt(text, heading.start) &&
            lineEndsAt(text, heading.end) &&
            !text.substring(heading.start, heading.end).contains('\n'),
        isTrue,
        reason: 'heading [${heading.start}, ${heading.end}) is not one line',
      );
      expect(
        codeBlocks.where(
          (code) => heading.start <= code.end && heading.end >= code.start,
        ),
        isEmpty,
        reason: 'heading [${heading.start}, ${heading.end}) is on a code line',
      );
    }
    final touching = [
      for (final range in fixture.inlineRanges)
        for (final code in codeBlocks)
          if (range.start <= code.end && range.end >= code.start)
            '${range.format.name} [${range.start}, ${range.end})',
    ];
    expect(touching, isEmpty, reason: 'inline ranges touching code lines');
  });

  test('B7: the edit offset sits near quoted blocks, outside features and '
      'code, with detectable mentions and links', () {
    final edit = fixture.editOffset;
    final codeRanges = [
      for (final code in codeBlocks)
        TextRange(start: code.start, end: code.end),
      for (final range in fixture.inlineRanges)
        if (range.format == InlineFormat.code)
          TextRange(start: range.start, end: range.end),
    ];

    expect(graphemeBoundaries(fixture.text), contains(edit));
    expect(
      [
        for (final range in fixture.featureRanges)
          if (range.start < edit && edit < range.end) range,
      ],
      isEmpty,
      reason: 'edit offset is inside a feature range',
    );
    expect(
      [
        for (final range in codeRanges)
          if (range.start < edit && edit < range.end) range,
      ],
      isEmpty,
      reason: 'edit offset is inside code',
    );

    bool near(BlockRange block) =>
        block.start >= edit - 600 && block.end <= edit + 600;
    expect(
      quotedHeadings.where(near),
      isNotEmpty,
      reason: 'no quoted heading within 600 units of the edit offset',
    );
    expect(
      quotedCodeBlocks.where(near),
      isNotEmpty,
      reason: 'no quoted code block within 600 units of the edit offset',
    );

    final detected = detectRichTextSpans(
      fixture.text,
      excludedRanges: [
        for (final range in fixture.featureRanges)
          TextRange(start: range.start, end: range.end),
        ...codeRanges,
      ],
    );
    expect(
      detected.where((span) => span.kind == RichTextSpanKind.mention),
      isNotEmpty,
      reason: 'no detectable mention outside stored ranges',
    );
    expect(
      detected.where((span) => span.kind == RichTextSpanKind.link),
      isNotEmpty,
      reason: 'no detectable link outside stored ranges',
    );
  });
}
