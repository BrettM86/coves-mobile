import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/widgets.dart';
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

List<Map<String, dynamic>> facetsJson(List<RichTextFacet> facets) =>
    facets.map((facet) => facet.toJson()).toList();

/// A serializer input and the facets it must produce.
class SerializationCase {
  const SerializationCase(
    this.description,
    this.text, {
    this.inlineRanges = const [],
    this.blockRanges = const [],
    required this.facets,
  });

  final String description;
  final String text;
  final List<InlineRange> inlineRanges;
  final List<BlockRange> blockRanges;
  final List<RichTextFacet> facets;
}

void expectCases(List<SerializationCase> cases) {
  for (final serializationCase in cases) {
    final result = serializeFormatting(
      serializationCase.text,
      inlineRanges: serializationCase.inlineRanges,
      blockRanges: serializationCase.blockRanges,
    );
    expect(
      facetsJson(result.facets),
      facetsJson(serializationCase.facets),
      reason: serializationCase.description,
    );
  }
}

void main() {
  test('B1 trims content and shifts, clips, or drops ranges at the edges', () {
    final result = serializeFormatting(
      '  hello world  ',
      inlineRanges: const [
        InlineRange(InlineFormat.bold, 0, 9), // straddles the leading edge
        InlineRange(InlineFormat.italic, 0, 1), // inside leading whitespace
        InlineRange(InlineFormat.code, 4, 7), // inside content: shifts by 2
        InlineRange(InlineFormat.strikethrough, 13, 15), // trailing whitespace
        InlineRange(InlineFormat.spoiler, 8, 15), // straddles the trailing edge
      ],
    );

    expect(result.content, 'hello world');
    expect(
      facetsJson(result.facets),
      facetsJson([
        facet(0, 7, const [bold]),
        facet(2, 5, const [code]),
        facet(6, 11, const [spoiler]),
      ]),
    );
    expect(result.codeRanges, const [TextRange(start: 2, end: 5)]);
  });

  test('B1 a block on a whitespace-only first line is dropped', () {
    final result = serializeFormatting(
      '   \nhello',
      blockRanges: const [
        BlockRange(BlockFormat.heading, 0, 3),
        BlockRange(BlockFormat.blockquote, 4, 9),
      ],
    );

    expect(result.content, 'hello');
    expect(
      facetsJson(result.facets),
      facetsJson([
        facet(0, 5, const [blockquote]),
      ]),
    );
  });

  test('B2 facet offsets are UTF-8 byte offsets into the trimmed content', () {
    // UTF-16: "  café 😀 🇫🇷 nöt" — café [2,6), 😀 [7,9), 🇫🇷 [10,14),
    // nöt [15,18).
    final result = serializeFormatting(
      '  café 😀 🇫🇷 nöt',
      inlineRanges: const [
        InlineRange(InlineFormat.bold, 2, 6),
        InlineRange(InlineFormat.italic, 7, 9),
        InlineRange(InlineFormat.strikethrough, 10, 14),
        InlineRange(InlineFormat.spoiler, 15, 18),
      ],
    );

    expect(result.content, 'café 😀 🇫🇷 nöt');
    expect(
      facetsJson(result.facets),
      facetsJson([
        facet(0, 5, const [bold]),
        facet(6, 10, const [italic]),
        facet(11, 19, const [strikethrough]),
        facet(20, 24, const [spoiler]),
      ]),
    );
  });

  test('B2 code ranges are sorted UTF-16 offsets into the trimmed content', () {
    // UTF-16: "  é😀 code ok\nblock line\nend" — "code" [6,10), line 1 [14,24),
    // "end" [25,28). Trimmed content shifts every offset by 2.
    final result = serializeFormatting(
      '  é😀 code ok\nblock line\nend',
      inlineRanges: const [
        InlineRange(InlineFormat.code, 25, 28),
        InlineRange(InlineFormat.code, 6, 10),
      ],
      blockRanges: const [BlockRange(BlockFormat.codeBlock, 14, 24)],
    );

    expect(result.content, 'é😀 code ok\nblock line\nend');
    expect(result.codeRanges, const [
      TextRange(start: 4, end: 8),
      TextRange(start: 12, end: 22),
      TextRange(start: 23, end: 26),
    ]);
    expect(
      facetsJson(result.facets),
      facetsJson([
        facet(7, 11, const [code]),
        facet(15, 25, const [codeBlock]),
        facet(26, 29, const [code]),
      ]),
    );
  });

  test('B3 block facets span whole lines without the trailing newline', () {
    expectCases(const [
      SerializationCase(
        'quote over lines 0-1, heading level 2 on line 2',
        'ab\ncd\nef',
        blockRanges: [
          BlockRange(BlockFormat.blockquote, 0, 5),
          BlockRange(BlockFormat.heading, 6, 8, level: 2),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 5),
            features: [blockquote],
          ),
          RichTextFacet(
            index: ByteSlice(byteStart: 6, byteEnd: 8),
            features: [HeadingFacetFeature(level: 2)],
          ),
        ],
      ),
      SerializationCase(
        'code block on the middle line',
        'ab\ncd\nef',
        blockRanges: [BlockRange(BlockFormat.codeBlock, 3, 5)],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 3, byteEnd: 5),
            features: [codeBlock],
          ),
        ],
      ),
    ]);
  });

  test('B4 zero-length and all-empty blocks produce no facet', () {
    expectCases(const [
      SerializationCase(
        'zero-length heading on an empty document',
        '',
        blockRanges: [BlockRange(BlockFormat.heading, 0, 0)],
        facets: [],
      ),
      SerializationCase(
        'zero-length heading on an empty middle line',
        'a\n\nb',
        inlineRanges: [InlineRange(InlineFormat.bold, 0, 1)],
        blockRanges: [BlockRange(BlockFormat.heading, 2, 2)],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 1),
            features: [bold],
          ),
        ],
      ),
      SerializationCase(
        'zero-length quote on an empty last line',
        'ab\n',
        inlineRanges: [InlineRange(InlineFormat.bold, 0, 2)],
        blockRanges: [BlockRange(BlockFormat.blockquote, 3, 3)],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 2),
            features: [bold],
          ),
        ],
      ),
      SerializationCase(
        'quote made only of empty lines',
        'a\n\n\nb',
        blockRanges: [
          BlockRange(BlockFormat.blockquote, 2, 3),
          BlockRange(BlockFormat.heading, 4, 5),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 4, byteEnd: 5),
            features: [HeadingFacetFeature(level: 1)],
          ),
        ],
      ),
    ]);
  });

  test('B4 a block with empty leading, middle and trailing lines covers its '
      'non-empty extent', () {
    // Lines of "a\n\nb\n\nc": "a" [0,1), "" [2,2), "b" [3,4), "" [5,5),
    // "c" [6,7).
    for (final (format, feature) in const [
      (BlockFormat.blockquote, blockquote),
      (BlockFormat.codeBlock, codeBlock),
    ]) {
      for (final (blockStart, blockEnd, facetStart, facetEnd) in const [
        // Lines 0-3: empty middle and trailing lines
        (0, 5, 0, 4),
        // Lines 1-4: empty leading and middle lines
        (2, 7, 3, 7),
      ]) {
        final reason = '${format.name} [$blockStart,$blockEnd)';
        final result = serializeFormatting(
          'a\n\nb\n\nc',
          blockRanges: [BlockRange(format, blockStart, blockEnd)],
        );

        expect(
          facetsJson(result.facets),
          facetsJson([
            facet(facetStart, facetEnd, [feature]),
          ]),
          reason: reason,
        );
        for (final serialized in result.facets) {
          expect(
            serialized.index.byteEnd,
            isNot(serialized.index.byteStart),
            reason: '$reason: zero-length facet ${serialized.toJson()}',
          );
        }
      }
    }
  });

  test('B5 identical ranges group into one facet in lexicon union order', () {
    expectCases(const [
      SerializationCase(
        'inline features supplied in reverse order',
        'hello world',
        inlineRanges: [
          InlineRange(InlineFormat.code, 6, 11),
          InlineRange(InlineFormat.spoiler, 6, 11),
          InlineRange(InlineFormat.italic, 0, 5),
          InlineRange(InlineFormat.strikethrough, 6, 11),
          InlineRange(InlineFormat.bold, 0, 5),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 5),
            features: [bold, italic],
          ),
          RichTextFacet(
            index: ByteSlice(byteStart: 6, byteEnd: 11),
            features: [strikethrough, spoiler, code],
          ),
        ],
      ),
      SerializationCase(
        'heading supplied before quote, with bold over the same lines',
        'ab\ncd',
        inlineRanges: [InlineRange(InlineFormat.bold, 0, 5)],
        blockRanges: [
          BlockRange(BlockFormat.heading, 0, 5, level: 3),
          BlockRange(BlockFormat.blockquote, 0, 5),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 5),
            features: [bold, blockquote, HeadingFacetFeature(level: 3)],
          ),
        ],
      ),
      SerializationCase(
        'code block supplied before quote',
        'ab\ncd',
        blockRanges: [
          BlockRange(BlockFormat.codeBlock, 0, 5),
          BlockRange(BlockFormat.blockquote, 0, 5),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 5),
            features: [blockquote, codeBlock],
          ),
        ],
      ),
    ]);
  });

  test('B5 ranges sharing a start with different ends stay two facets', () {
    final result = serializeFormatting(
      'hello world',
      inlineRanges: const [
        InlineRange(InlineFormat.bold, 0, 5),
        InlineRange(InlineFormat.italic, 0, 11),
      ],
    );

    expect(
      facetsJson(result.facets),
      unorderedEquals(
        facetsJson([
          facet(0, 5, const [bold]),
          facet(0, 11, const [italic]),
        ]),
      ),
    );
  });

  test('B5 unsorted ranges produce facets sorted by byte start', () {
    expectCases(const [
      SerializationCase(
        'inline ranges supplied out of order',
        'one two three',
        inlineRanges: [
          InlineRange(InlineFormat.italic, 8, 13),
          InlineRange(InlineFormat.bold, 0, 3),
          InlineRange(InlineFormat.strikethrough, 4, 7),
        ],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 3),
            features: [bold],
          ),
          RichTextFacet(
            index: ByteSlice(byteStart: 4, byteEnd: 7),
            features: [strikethrough],
          ),
          RichTextFacet(
            index: ByteSlice(byteStart: 8, byteEnd: 13),
            features: [italic],
          ),
        ],
      ),
      SerializationCase(
        'a block before an earlier inline range',
        'ab\ncd',
        inlineRanges: [InlineRange(InlineFormat.bold, 0, 2)],
        blockRanges: [BlockRange(BlockFormat.blockquote, 3, 5)],
        facets: [
          RichTextFacet(
            index: ByteSlice(byteStart: 0, byteEnd: 2),
            features: [bold],
          ),
          RichTextFacet(
            index: ByteSlice(byteStart: 3, byteEnd: 5),
            features: [blockquote],
          ),
        ],
      ),
    ]);
  });

  test('B8 spoiler has no reason and code block has no language', () {
    final result = serializeFormatting(
      'secret\ncode',
      inlineRanges: const [InlineRange(InlineFormat.spoiler, 0, 6)],
      blockRanges: const [BlockRange(BlockFormat.codeBlock, 7, 11)],
    );

    expect(
      facetsJson(result.facets),
      facetsJson([
        facet(0, 6, const [spoiler]),
        facet(7, 11, const [codeBlock]),
      ]),
    );
    expect(result.facets.first.features.single.toJson(), {
      r'$type': SpoilerFacetFeature.typeId,
    });
    expect(result.facets.last.features.single.toJson(), {
      r'$type': CodeBlockFacetFeature.typeId,
    });
  });
}
