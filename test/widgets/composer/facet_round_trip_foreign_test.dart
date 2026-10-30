import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

// Records written by another client, loaded and saved with no edits. The
// editor canonicalizes them (13-a (c)): content trimmed, facets grouped,
// merged and sorted, never losing a feature or a typed attribute. ASCII
// content only, so byte and UTF-16 offsets coincide.

const ns = 'social.coves.richtext.facet';
const bold = '{"\$type":"$ns#bold"}';
const italic = '{"\$type":"$ns#italic"}';
const strikethrough = '{"\$type":"$ns#strikethrough"}';
const quote = '{"\$type":"$ns#blockquote"}';
const quote2 = '{"\$type":"$ns#blockquote","level":2}';
const codeBlock = '{"\$type":"$ns#codeBlock"}';
const dart = '{"\$type":"$ns#codeBlock","language":"dart"}';
const go = '{"\$type":"$ns#codeBlock","language":"go"}';
const tag = r'{"$type":"com.example.richtext#tag","meta":{"tags":["a","b"]}}';

/// A bold facet with keys the lexicon does not define, on the facet and on
/// its feature.
const boldWithExtraKeys =
    '{"index":{"byteStart":0,"byteEnd":5},"note":"extra",'
    '"features":[{"\$type":"$ns#bold","color":"red"}]}';

String spoiler(String reason) => '{"\$type":"$ns#spoiler","reason":"$reason"}';

/// One facet's wire JSON over bytes [start]..[end].
String facetJson(int start, int end, String features) =>
    '{"index":{"byteStart":$start,"byteEnd":$end},"features":[$features]}';

void main() {
  // Each row's input facets are separate JSON strings, decoded one by one,
  // so equal nested data in two facets arrives as distinct map instances.
  final rows =
      <
        ({
          String name,
          String content,
          List<String> facets,
          String savedContent,
          String savedFacets,
        })
      >[
        (
          name: 'F1 padded content is trimmed and the facet shifts',
          content: '  hello world\n',
          facets: [facetJson(2, 7, bold)],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 5, bold)}]',
        ),
        (
          name: 'F2 an explicit quote level 1 is written without a level',
          content: 'quoted',
          facets: [facetJson(0, 6, '{"\$type":"$ns#blockquote","level":1}')],
          savedContent: 'quoted',
          savedFacets: '[${facetJson(0, 6, quote)}]',
        ),
        (
          name: 'F3 facets over one range group into one, duplicates collapse',
          content: 'hello world',
          facets: [
            facetJson(0, 5, bold),
            facetJson(0, 5, bold),
            facetJson(0, 5, italic),
          ],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 5, '$bold,$italic')}]',
        ),
        (
          name:
              'R8 two identical unknown features with nested data collapse '
              'to one',
          content: 'hello world',
          facets: [facetJson(0, 5, tag), facetJson(0, 5, tag)],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 5, tag)}]',
        ),
        (
          name: 'F4 overlapping bold ranges merge',
          content: 'hello world',
          facets: [facetJson(0, 5, bold), facetJson(3, 8, bold)],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 8, bold)}]',
        ),
        (
          name: 'F4 touching bold ranges merge',
          content: 'hello world',
          facets: [facetJson(0, 5, bold), facetJson(5, 8, bold)],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 8, bold)}]',
        ),
        (
          name: 'F4 overlapping spoilers with one reason merge',
          content: 'hello world',
          facets: [
            facetJson(0, 5, spoiler('x')),
            facetJson(3, 8, spoiler('x')),
          ],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 8, spoiler('x'))}]',
        ),
        (
          name:
              'R7 interleaved spoilers merge by reason around a different '
              'reason',
          content: 'hello world',
          facets: [
            facetJson(0, 5, spoiler('x')),
            facetJson(1, 2, spoiler('y')),
            facetJson(4, 8, spoiler('x')),
          ],
          savedContent: 'hello world',
          savedFacets:
              '[${facetJson(0, 8, spoiler('x'))},'
              '${facetJson(1, 2, spoiler('y'))}]',
        ),
        (
          name: 'F5 adjacent quotes of one level merge',
          content: 'aa\nbb',
          facets: [facetJson(0, 2, quote), facetJson(3, 5, quote)],
          savedContent: 'aa\nbb',
          savedFacets: '[${facetJson(0, 5, quote)}]',
        ),
        (
          name: 'F5 adjacent quotes of different levels stay separate',
          content: 'aa\nbb',
          facets: [facetJson(0, 2, quote), facetJson(3, 5, quote2)],
          savedContent: 'aa\nbb',
          savedFacets: '[${facetJson(0, 2, quote)},${facetJson(3, 5, quote2)}]',
        ),
        (
          name: 'F5 adjacent code blocks of different languages stay separate',
          content: 'aa\nbb',
          facets: [facetJson(0, 2, dart), facetJson(3, 5, go)],
          savedContent: 'aa\nbb',
          savedFacets: '[${facetJson(0, 2, dart)},${facetJson(3, 5, go)}]',
        ),
        (
          name: 'F5 adjacent code blocks of one language merge',
          content: 'aa\nbb',
          facets: [facetJson(0, 2, dart), facetJson(3, 5, dart)],
          savedContent: 'aa\nbb',
          savedFacets: '[${facetJson(0, 5, dart)}]',
        ),
        (
          name: 'F6 a quote crossing a code block widens over its lines',
          content: 'aa\nbb\ncc',
          facets: [facetJson(0, 5, quote), facetJson(3, 8, codeBlock)],
          savedContent: 'aa\nbb\ncc',
          savedFacets:
              '[${facetJson(0, 8, quote)},${facetJson(3, 8, codeBlock)}]',
        ),
        (
          name: 'F5 adjacent level-2 quotes merge and keep level 2',
          content: 'aa\nbb',
          facets: [facetJson(0, 2, quote2), facetJson(3, 5, quote2)],
          savedContent: 'aa\nbb',
          savedFacets: '[${facetJson(0, 5, quote2)}]',
        ),
        (
          name: 'F6 a level-2 quote crossing a code block widens at level 2',
          content: 'aa\nbb\ncc',
          facets: [facetJson(0, 5, quote2), facetJson(3, 8, codeBlock)],
          savedContent: 'aa\nbb\ncc',
          savedFacets:
              '[${facetJson(0, 8, quote2)},${facetJson(3, 8, codeBlock)}]',
        ),
        (
          name: 'F7 out-of-order facets are sorted by byteStart, byteEnd',
          content: 'hello world',
          facets: [
            facetJson(6, 11, italic),
            facetJson(0, 11, strikethrough),
            facetJson(0, 5, bold),
          ],
          savedContent: 'hello world',
          savedFacets:
              '[${facetJson(0, 5, bold)},${facetJson(0, 11, strikethrough)},'
              '${facetJson(6, 11, italic)}]',
        ),
        (
          name: 'F8 extra JSON keys on the facet and the feature are dropped',
          content: 'hello world',
          facets: [boldWithExtraKeys],
          savedContent: 'hello world',
          savedFacets: '[${facetJson(0, 5, bold)}]',
        ),
      ];

  group('foreign-writer records load and save canonically', () {
    for (final row in rows) {
      test(row.name, () {
        final controller = FacetEditingController.fromRecord(row.content, [
          for (final json in row.facets)
            RichTextFacet.fromJson(jsonDecode(json) as Map<String, dynamic>),
        ]);
        addTearDown(controller.dispose);

        final saved = serializeFormatting(
          controller.text,
          inlineRanges: controller.inlineRanges,
          blockRanges: controller.blockRanges,
          featureRanges: controller.featureRanges,
        );

        expect(saved.content, row.savedContent);
        expect(
          jsonEncode([for (final facet in saved.facets) facet.toJson()]),
          row.savedFacets,
        );
      });
    }
  });
}
