import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

import 'facet_fixture_helpers.dart';

const bold = BoldFacetFeature();
const italic = ItalicFacetFeature();

const boldJson = {r'$type': 'social.coves.richtext.facet#bold'};
const italicJson = {r'$type': 'social.coves.richtext.facet#italic'};

/// Loads [facets] over [content] and saves with no edits, returning the
/// saved facets' wire JSON.
List<Map<String, dynamic>> loadAndSave(
  String content,
  List<RichTextFacet> facets,
) {
  final controller = FacetEditingController.fromRecord(content, facets);
  addTearDown(controller.dispose);
  final saved = serializeFormatting(
    controller.text,
    inlineRanges: controller.inlineRanges,
    blockRanges: controller.blockRanges,
    featureRanges: controller.featureRanges,
  );
  return saved.facets.map((facet) => facet.toJson()).toList();
}

void main() {
  group('a grouped range with more than 20 features', () {
    // 'word' is bytes and UTF-16 [0,4).
    const content = 'word';

    test('splits 22 unknown features into facets of 20 and 2', () {
      expect(
        loadAndSave(content, [
          facet(0, 4, unknowns(1, 11)),
          facet(0, 4, unknowns(12, 22)),
        ]),
        [
          facetJson(0, 4, unknownsJson(1, 20)),
          facetJson(0, 4, unknownsJson(21, 22)),
        ],
      );
    });

    test('puts lexicon features first, then unknowns in load order', () {
      expect(
        loadAndSave(content, [
          facet(0, 4, unknowns(1, 10)),
          facet(0, 4, [bold, ...unknowns(11, 20)]),
        ]),
        [
          facetJson(0, 4, [boldJson, ...unknownsJson(1, 19)]),
          facetJson(0, 4, [unknownJson(20)]),
        ],
      );
    });
  });

  test('unknown features with one type and different data both survive', () {
    expect(
      loadAndSave('word', [
        facet(0, 4, const [
          UnknownFacetFeature(
            data: {
              r'$type': 'com.example.tag',
              'value': {'name': 'a'},
            },
          ),
        ]),
        facet(0, 4, const [
          UnknownFacetFeature(
            data: {
              r'$type': 'com.example.tag',
              'value': {'name': 'b'},
            },
          ),
        ]),
      ]),
      [
        facetJson(0, 4, [
          {
            r'$type': 'com.example.tag',
            'value': {'name': 'a'},
          },
          {
            r'$type': 'com.example.tag',
            'value': {'name': 'b'},
          },
        ]),
      ],
    );
  });

  test('splits a 41-feature range in place among many other facets', () {
    // Forty words 'w00 w01 ... w39', word i at bytes and UTF-16
    // [4i, 4i + 3). Word 11, [44,47), carries bold and unknowns 1-40 across
    // three facets; every other word carries a single italic facet. Word 11
    // sits where List.sort would reorder equal-range facets, so an unstable
    // sort without a tie-break shows up here.
    final content = [
      for (var i = 0; i < 40; i++) 'w${i.toString().padLeft(2, '0')}',
    ].join(' ');
    final facets = [
      for (var i = 0; i < 11; i++) facet(4 * i, 4 * i + 3, const [italic]),
      facet(44, 47, unknowns(1, 13)),
      facet(44, 47, [...unknowns(14, 27), bold]),
      facet(44, 47, unknowns(28, 40)),
      for (var i = 12; i < 40; i++) facet(4 * i, 4 * i + 3, const [italic]),
    ];

    expect(loadAndSave(content, facets), [
      for (var i = 0; i < 11; i++) facetJson(4 * i, 4 * i + 3, [italicJson]),
      facetJson(44, 47, [boldJson, ...unknownsJson(1, 19)]),
      facetJson(44, 47, unknownsJson(20, 39)),
      facetJson(44, 47, [unknownJson(40)]),
      for (var i = 12; i < 40; i++) facetJson(4 * i, 4 * i + 3, [italicJson]),
    ]);
  });
}
