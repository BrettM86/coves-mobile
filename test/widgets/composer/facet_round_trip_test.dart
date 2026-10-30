import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

const ns = 'social.coves.richtext.facet';
const boldJson = {r'$type': '$ns#bold'};
const italicJson = {r'$type': '$ns#italic'};
const strikethroughJson = {r'$type': '$ns#strikethrough'};
const codeJson = {r'$type': '$ns#code'};

/// A facet's wire JSON, written as a record stores it.
Map<String, dynamic> facetJson(
  int byteStart,
  int byteEnd,
  List<Map<String, dynamic>> features,
) => {
  'index': {'byteStart': byteStart, 'byteEnd': byteEnd},
  'features': features,
};

/// Parses wire JSON facets the way a fetched record is parsed.
List<RichTextFacet> parseFacets(List<Map<String, dynamic>> json) =>
    json.map(RichTextFacet.fromJson).toList();

List<Map<String, dynamic>> facetsJson(List<RichTextFacet> facets) =>
    facets.map((facet) => facet.toJson()).toList();

FacetEditingController load(String content, List<RichTextFacet> facets) {
  final controller = FacetEditingController.fromRecord(content, facets);
  addTearDown(controller.dispose);
  return controller;
}

/// Saves [controller] with no edits.
SerializedFormatting save(FacetEditingController controller) =>
    serializeFormatting(
      controller.text,
      inlineRanges: controller.inlineRanges,
      blockRanges: controller.blockRanges,
      featureRanges: controller.featureRanges,
    );

/// A feature range as comparable data: its feature's wire JSON (so nested
/// unknown data compares by content) and its UTF-16 bounds.
Map<String, dynamic> featureRangeJson(FeatureRange range) => {
  'feature': range.feature.toJson(),
  'start': range.start,
  'end': range.end,
};

void main() {
  group('round trip of every lexicon feature', () {
    // 'Heading' [0,7) '\n' 'Quote' [8,13) '\n' 'fn main' [14,21) '\n'
    // 'bold' [22,26) 'italic' [27,33) 'strike' [34,40) 'spoiler' [41,48)
    // 'code' [49,53) '@alice' [54,60) 'link' [61,65) 'mix' [66,69).
    // ASCII only, so byte and UTF-16 offsets coincide.
    const content =
        'Heading\nQuote\nfn main\n'
        'bold italic strike spoiler code @alice link mix';
    const mentionJson = {r'$type': '$ns#mention', 'did': 'did:plc:alice'};
    const linkJson = {r'$type': '$ns#link', 'uri': 'https://example.com/page'};
    const unknownJson = {
      r'$type': 'com.example.facet#tag',
      'tag': 'mix',
      'meta': {
        'weight': 3,
        'labels': ['a', 'b'],
      },
    };
    final record = [
      facetJson(0, 7, [
        {r'$type': '$ns#heading', 'level': 2},
      ]),
      facetJson(8, 13, [
        {r'$type': '$ns#blockquote'},
      ]),
      facetJson(14, 21, [
        {r'$type': '$ns#codeBlock'},
      ]),
      facetJson(22, 26, [boldJson]),
      facetJson(27, 33, [italicJson]),
      facetJson(34, 40, [strikethroughJson]),
      facetJson(41, 48, [
        {r'$type': '$ns#spoiler'},
      ]),
      facetJson(49, 53, [codeJson]),
      facetJson(54, 60, [mentionJson]),
      facetJson(61, 65, [linkJson]),
      facetJson(66, 69, [unknownJson]),
    ];

    test('loads each feature into its range collection', () {
      final controller = load(content, parseFacets(record));

      expect(controller.text, content);
      expect(
        controller.inlineRanges,
        unorderedEquals(const [
          InlineRange(InlineFormat.bold, 22, 26),
          InlineRange(InlineFormat.italic, 27, 33),
          InlineRange(InlineFormat.strikethrough, 34, 40),
          InlineRange(InlineFormat.spoiler, 41, 48),
          InlineRange(InlineFormat.code, 49, 53),
        ]),
      );
      expect(
        controller.blockRanges,
        unorderedEquals(const [
          BlockRange(BlockFormat.heading, 0, 7, level: 2),
          BlockRange(BlockFormat.blockquote, 8, 13),
          BlockRange(BlockFormat.codeBlock, 14, 21),
        ]),
      );
      expect(
        controller.featureRanges.map(featureRangeJson),
        unorderedEquals([
          {'feature': mentionJson, 'start': 54, 'end': 60},
          {'feature': linkJson, 'start': 61, 'end': 65},
          {'feature': unknownJson, 'start': 66, 'end': 69},
        ]),
      );
    });

    test('saving with no edits writes every feature back', () {
      final saved = save(load(content, parseFacets(record)));

      expect(saved.content, content);
      expect(facetsJson(saved.facets), record);
    });
  });

  group('round trip of feature attributes', () {
    // 'Small' [0,5) '\n' 'Deep' [6,10) '\n' 'x = 1' [11,16) '\n'
    // 'secret' [17,23). ASCII only.
    const content = 'Small\nDeep\nx = 1\nsecret';
    final record = [
      facetJson(0, 5, [
        {r'$type': '$ns#heading', 'level': 5},
      ]),
      facetJson(6, 10, [
        {r'$type': '$ns#blockquote', 'level': 3},
      ]),
      facetJson(11, 16, [
        {r'$type': '$ns#codeBlock', 'language': 'python'},
      ]),
      facetJson(17, 23, [
        {r'$type': '$ns#spoiler', 'reason': 'plot twist'},
      ]),
    ];

    test('loads spoiler reason, code block language and levels', () {
      final controller = load(content, parseFacets(record));

      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.spoiler, 17, 23, reason: 'plot twist'),
      ]);
      expect(
        controller.blockRanges,
        unorderedEquals(const [
          BlockRange(BlockFormat.heading, 0, 5, level: 5),
          BlockRange(BlockFormat.blockquote, 6, 10, level: 3),
          BlockRange(BlockFormat.codeBlock, 11, 16, language: 'python'),
        ]),
      );
    });

    test('saving with no edits writes the attributes back unchanged', () {
      final saved = save(load(content, parseFacets(record)));

      expect(saved.content, content);
      expect(facetsJson(saved.facets), record);
    });

    test('serializeFormatting writes attributed ranges and feature ranges', () {
      // 'Small' [0,5) '\n' 'Deep' [6,10) '\n' 'x = 1' [11,16) '\n'
      // 'secret @bo link tag' with 'secret' [17,23) '@bo' [24,27)
      // 'link' [28,32) 'tag' [33,36). ASCII only.
      final saved = serializeFormatting(
        'Small\nDeep\nx = 1\nsecret @bo link tag',
        inlineRanges: const [
          InlineRange(InlineFormat.spoiler, 17, 23, reason: 'plot twist'),
        ],
        blockRanges: const [
          BlockRange(BlockFormat.heading, 0, 5, level: 5),
          BlockRange(BlockFormat.blockquote, 6, 10, level: 3),
          BlockRange(BlockFormat.codeBlock, 11, 16, language: 'python'),
        ],
        featureRanges: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:bo'), 24, 27),
          FeatureRange(LinkFacetFeature(uri: 'https://example.com/x'), 28, 32),
          FeatureRange(
            UnknownFacetFeature(
              data: {
                r'$type': 'com.example.facet#tag',
                'tag': 'tag',
                'meta': {'weight': 3},
              },
            ),
            33,
            36,
          ),
        ],
      );

      expect(facetsJson(saved.facets), [
        ...record,
        facetJson(24, 27, [
          {r'$type': '$ns#mention', 'did': 'did:plc:bo'},
        ]),
        facetJson(28, 32, [
          {r'$type': '$ns#link', 'uri': 'https://example.com/x'},
        ]),
        facetJson(33, 36, [
          {
            r'$type': 'com.example.facet#tag',
            'tag': 'tag',
            'meta': {'weight': 3},
          },
        ]),
      ]);
    });

    test('serializeFormatting omits feature ranges bounded inside a '
        'surrogate pair', () {
      // 'a' [0,1) '😀' [1,3) 'b' [3,4) ' ' [4,5) 'link' [5,9); index 2 is
      // between the halves of 😀. Bytes: 'link' [7,11).
      final saved = serializeFormatting(
        'a\u{1F600}b link',
        featureRanges: const [
          FeatureRange(MentionFacetFeature(did: 'did:plc:bo'), 2, 4),
          FeatureRange(LinkFacetFeature(uri: 'https://example.com/bad'), 0, 2),
          FeatureRange(LinkFacetFeature(uri: 'https://example.com/x'), 5, 9),
        ],
      );

      expect(facetsJson(saved.facets), [
        facetJson(7, 11, [
          {r'$type': '$ns#link', 'uri': 'https://example.com/x'},
        ]),
      ]);
    });
  });

  test('an editor-produced record loads and saves byte-identically', () {
    // Trimmed content; block facets cover whole lines without the newline;
    // facets sorted by byteStart then byteEnd; features in union order;
    // blockquote level 1 omitted.
    // bytes / UTF-16: 'Café notes' [0,11) / [0,10); 'Quoted 中文' [12,25) /
    // [11,20); 'let x = 1;' [26,36) / [21,31); '@bob.test' [40,49) /
    // [35,44); 'docs' [54,58) / [49,53); 'docs 😀' [54,63) / [49,56);
    // 'old' [64,67) / [57,60); 'secret' [68,74) / [61,67); 'code' [75,79) /
    // [68,72).
    const content =
        'Café notes\nQuoted 中文\nlet x = 1;\n'
        'Hi @bob.test see docs \u{1F600} old secret code';
    final record = [
      facetJson(0, 11, [
        {r'$type': '$ns#heading', 'level': 1},
      ]),
      facetJson(12, 25, [
        {r'$type': '$ns#blockquote'},
      ]),
      facetJson(26, 36, [
        {r'$type': '$ns#codeBlock', 'language': 'rust'},
      ]),
      facetJson(40, 49, [
        {r'$type': '$ns#mention', 'did': 'did:plc:bob'},
        boldJson,
        italicJson,
      ]),
      facetJson(54, 58, [
        {r'$type': '$ns#link', 'uri': 'https://docs.example.com/start'},
        boldJson,
      ]),
      facetJson(54, 63, [italicJson]),
      facetJson(64, 67, [strikethroughJson]),
      facetJson(68, 74, [
        {r'$type': '$ns#spoiler', 'reason': 'ending'},
      ]),
      facetJson(75, 79, [codeJson]),
    ];

    final saved = save(load(content, parseFacets(record)));

    expect(saved.content, content);
    expect(jsonEncode(facetsJson(saved.facets)), jsonEncode(record));
  });
}
