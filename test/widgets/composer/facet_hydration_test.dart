import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

const bold = BoldFacetFeature();
const italic = ItalicFacetFeature();
const strikethrough = StrikethroughFacetFeature();
const spoiler = SpoilerFacetFeature();
const code = CodeFacetFeature();
const blockquote = BlockquoteFacetFeature();
const codeBlock = CodeBlockFacetFeature();

RichTextFacet facet(int byteStart, int byteEnd, List<FacetFeature> features) =>
    RichTextFacet(
      index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
      features: features,
    );

FacetEditingController load(String content, List<RichTextFacet> facets) {
  final controller = FacetEditingController.fromRecord(content, facets);
  addTearDown(controller.dispose);
  return controller;
}

/// Asserts the loaded text and every range collection, in any order.
void expectLoaded(
  FacetEditingController controller, {
  required String text,
  List<InlineRange> inline = const [],
  List<BlockRange> block = const [],
  List<FeatureRange> feature = const [],
}) {
  expect(controller.inlineRanges, unorderedEquals(inline));
  expect(controller.blockRanges, unorderedEquals(block));
  expect(controller.featureRanges, unorderedEquals(feature));
  expect(controller.text, text);
}

/// A record whose facets must load into exactly the expected ranges.
class HydrationCase {
  const HydrationCase(
    this.description,
    this.content,
    this.facets, {
    this.inline = const [],
    this.block = const [],
    this.feature = const [],
  });

  final String description;
  final String content;
  final List<RichTextFacet> facets;
  final List<InlineRange> inline;
  final List<BlockRange> block;
  final List<FeatureRange> feature;
}

void runCases(List<HydrationCase> cases) {
  for (final c in cases) {
    test(c.description, () {
      expectLoaded(
        load(c.content, c.facets),
        text: c.content,
        inline: c.inline,
        block: c.block,
        feature: c.feature,
      );
    });
  }
}

void main() {
  group('FacetEditingController.fromRecord byte to UTF-16 conversion', () {
    // 'a' bytes [0,1) utf16 [0,1); 'é' (U+00E9) bytes [1,3) utf16 [1,2);
    // '中' bytes [3,6) utf16 [2,3); '😀' bytes [6,10) utf16 [3,5);
    // 'b' bytes [10,11) utf16 [5,6).
    const content = 'aé中\u{1F600}b';

    runCases([
      HydrationCase(
        'multi-byte content maps each facet byte range to its UTF-16 range',
        content,
        [
          facet(1, 3, [bold]),
          facet(3, 6, [italic]),
          facet(6, 10, [strikethrough]),
          facet(10, 11, [code]),
          facet(0, 11, [spoiler]),
          facet(3, 10, [const MentionFacetFeature(did: 'did:plc:alice')]),
        ],
        inline: const [
          InlineRange(InlineFormat.bold, 1, 2),
          InlineRange(InlineFormat.italic, 2, 3),
          InlineRange(InlineFormat.strikethrough, 3, 5),
          InlineRange(InlineFormat.code, 5, 6),
          InlineRange(InlineFormat.spoiler, 0, 6),
        ],
        feature: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 2, 5),
        ],
      ),
    ]);
  });

  group('FacetEditingController.fromRecord multi-feature facets', () {
    runCases([
      HydrationCase(
        'one facet with several features yields one range per feature',
        'hi @alice.test ok',
        [
          facet(3, 14, [
            bold,
            italic,
            const MentionFacetFeature(did: 'did:plc:alice'),
          ]),
        ],
        inline: const [
          InlineRange(InlineFormat.bold, 3, 14),
          InlineRange(InlineFormat.italic, 3, 14),
        ],
        feature: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 3, 14),
        ],
      ),
    ]);
  });

  group('FacetEditingController.fromRecord block widening', () {
    // 'aa\nbb\ncc': line 0 [0,2), line 1 [3,5), line 2 [6,8).
    const lines = 'aa\nbb\ncc';
    // 'é\nx中y': 'é' bytes [0,2) utf16 [0,1); '\n' byte 2 utf16 1;
    // 'x' byte 3 utf16 2; '中' bytes [4,7) utf16 3; 'y' byte 7 utf16 4.
    // Line 0 is utf16 [0,1), line 1 is utf16 [2,5).
    const multiByteLines = 'é\nx中y';

    runCases([
      HydrationCase(
        'a heading over part of a line widens to that line',
        lines,
        [
          facet(4, 5, [const HeadingFacetFeature(level: 2)]),
        ],
        block: const [BlockRange(BlockFormat.heading, 3, 5, level: 2)],
      ),
      HydrationCase(
        'a blockquote over the start of the first line widens to that line',
        lines,
        [
          facet(0, 1, [blockquote]),
        ],
        block: const [BlockRange(BlockFormat.blockquote, 0, 2)],
      ),
      HydrationCase(
        'a code block over parts of two lines widens to both lines',
        lines,
        [
          facet(1, 4, [codeBlock]),
        ],
        block: const [BlockRange(BlockFormat.codeBlock, 0, 5)],
      ),
      HydrationCase(
        'a heading from mid line 1 to mid line 2 widens to lines 1 and 2',
        lines,
        [
          facet(4, 7, [const HeadingFacetFeature(level: 1)]),
        ],
        block: const [BlockRange(BlockFormat.heading, 3, 8)],
      ),
      HydrationCase(
        'a blockquote over a multi-byte character widens in UTF-16 units',
        multiByteLines,
        [
          facet(4, 7, [blockquote]),
        ],
        block: const [BlockRange(BlockFormat.blockquote, 2, 5)],
      ),
    ]);

    // 'one\ntwo @x\nend': line 0 [0,3), line 1 [4,10), line 2 [11,14).
    runCases([
      HydrationCase(
        'only the block feature of a mixed partial-line facet widens',
        'one\ntwo @x\nend',
        [
          facet(8, 10, [
            const HeadingFacetFeature(level: 3),
            bold,
            const MentionFacetFeature(did: 'did:plc:x'),
            const UnknownFacetFeature(
              data: {r'$type': 'app.example.facet#tag', 'tag': 't'},
            ),
          ]),
        ],
        inline: const [InlineRange(InlineFormat.bold, 8, 10)],
        block: const [BlockRange(BlockFormat.heading, 4, 10, level: 3)],
        feature: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:x'), 8, 10),
          FeatureRange(
            UnknownFacetFeature(
              data: {r'$type': 'app.example.facet#tag', 'tag': 't'},
            ),
            8,
            10,
          ),
        ],
      ),
    ]);
  });

  group('FacetEditingController.fromRecord block boundary newlines', () {
    // 'aa\nbb\ncc': line 0 [0,2), '\n' 2, line 1 [3,5), '\n' 5,
    // line 2 [6,8).
    const lines = 'aa\nbb\ncc';

    runCases([
      HydrationCase(
        'a heading that ends after its trailing newline covers only its line',
        'Title\nbody',
        [
          facet(0, 6, [const HeadingFacetFeature(level: 1)]),
        ],
        block: const [BlockRange(BlockFormat.heading, 0, 5)],
      ),
      HydrationCase(
        'a blockquote starting on the previous newline covers only its line',
        lines,
        [
          facet(2, 5, [blockquote]),
        ],
        block: const [BlockRange(BlockFormat.blockquote, 3, 5)],
      ),
      HydrationCase(
        'a code block over leading and trailing newlines covers its lines',
        lines,
        [
          facet(2, 6, [codeBlock]),
        ],
        block: const [BlockRange(BlockFormat.codeBlock, 3, 5)],
      ),
      HydrationCase('a block over only a newline loads no block', lines, [
        facet(2, 3, [const HeadingFacetFeature(level: 2), blockquote]),
      ]),
    ]);
  });

  group('FacetEditingController.fromRecord zero-length facets', () {
    // 'aa\nbb\ncc' is 8 bytes: offset 0 is the content start, 4 is mid
    // line 1 and 8 is the content end.
    const content = 'aa\nbb\ncc';
    const features = <FacetFeature>[
      bold,
      HeadingFacetFeature(level: 1),
      blockquote,
      codeBlock,
    ];

    for (final (description, offset) in [
      ('at the content start', 0),
      ('mid content', 4),
      ('at the content end', 8),
    ]) {
      test('a zero-length facet $description loads nothing and saves '
          'no block', () {
        final controller = load(content, [facet(offset, offset, features)]);
        expectLoaded(controller, text: content);

        final saved = serializeFormatting(
          controller.text,
          inlineRanges: controller.inlineRanges,
          blockRanges: controller.blockRanges,
          featureRanges: controller.featureRanges,
        );
        expect(saved.facets, isEmpty);
      });
    }
  });

  group('FacetEditingController.fromRecord invalid byte bounds', () {
    // 'a' bytes [0,1) utf16 0; 'é' bytes [1,3) utf16 1; '中' bytes [3,6)
    // utf16 2; 'b' bytes [6,7) utf16 3. 7 bytes, 4 UTF-16 units.
    const content = 'aé中b';
    final goodFacets = [
      facet(3, 6, [bold]),
      facet(6, 7, [const MentionFacetFeature(did: 'did:plc:good')]),
      facet(0, 7, [const HeadingFacetFeature(level: 1)]),
    ];
    const badFeatures = <FacetFeature>[
      italic,
      blockquote,
      MentionFacetFeature(did: 'did:plc:bad'),
    ];
    const badBounds = [
      ('start inside a two-byte character', 2, 3),
      ('end inside a three-byte character', 3, 5),
      ('end beyond the content', 6, 8),
      ('start and end beyond the content', 8, 9),
    ];

    runCases([
      for (final (description, start, end) in badBounds)
        HydrationCase(
          'a facet with its $description is dropped and the others load',
          content,
          [
            goodFacets[0],
            facet(start, end, badFeatures),
            goodFacets[1],
            goodFacets[2],
          ],
          inline: const [InlineRange(InlineFormat.bold, 2, 3)],
          block: const [BlockRange(BlockFormat.heading, 0, 4)],
          feature: const [
            FeatureRange(MentionFacetFeature(did: 'did:plc:good'), 3, 4),
          ],
        ),
    ]);
  });

  group('FacetEditingController.fromRecord grapheme-splitting bounds', () {
    // 'e' bytes [0,1) utf16 0; U+0301 bytes [1,3) utf16 1; ' ' byte 3
    // utf16 2; U+1F1EB bytes [4,8) utf16 [3,5); U+1F1F7 bytes [8,12)
    // utf16 [5,7); ' ' byte 12 utf16 7; U+1F468 bytes [13,17) utf16 [8,10);
    // U+200D bytes [17,20) utf16 10; U+1F469 bytes [20,24) utf16 [11,13);
    // U+200D bytes [24,27) utf16 13; U+1F467 bytes [27,31) utf16 [14,16);
    // ' ' byte 31 utf16 16; 'ok' bytes [32,34) utf16 [17,19).
    const content =
        'é \u{1F1EB}\u{1F1F7} '
        '\u{1F468}‍\u{1F469}‍\u{1F467} ok';
    final goodFacets = [
      facet(0, 3, [bold]),
      facet(4, 12, [italic]),
      facet(13, 31, [const MentionFacetFeature(did: 'did:plc:family')]),
      facet(32, 34, [code]),
      facet(0, 34, [blockquote]),
    ];
    const badFeatures = <FacetFeature>[
      strikethrough,
      HeadingFacetFeature(level: 4),
      LinkFacetFeature(uri: 'https://example.com'),
    ];
    const badBounds = [
      ('ending between a base letter and its combining mark', 0, 1),
      ('starting at a combining mark', 1, 3),
      ('ending between the regional indicators of a flag', 4, 8),
      ('starting between the regional indicators of a flag', 8, 12),
      ('ending inside a ZWJ sequence', 13, 17),
      ('starting inside a ZWJ sequence', 20, 31),
    ];

    runCases([
      for (final (description, start, end) in badBounds)
        HydrationCase(
          'a facet $description is dropped and the others load',
          content,
          [
            goodFacets[0],
            goodFacets[1],
            facet(start, end, badFeatures),
            goodFacets[2],
            goodFacets[3],
            goodFacets[4],
          ],
          inline: const [
            InlineRange(InlineFormat.bold, 0, 2),
            InlineRange(InlineFormat.italic, 3, 7),
            InlineRange(InlineFormat.code, 17, 19),
          ],
          block: const [BlockRange(BlockFormat.blockquote, 0, 19)],
          feature: const [
            FeatureRange(MentionFacetFeature(did: 'did:plc:family'), 8, 16),
          ],
        ),
    ]);
  });
}
