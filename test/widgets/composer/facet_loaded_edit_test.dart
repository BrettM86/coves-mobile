import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'facet_fixture_helpers.dart';

const spoilerType = 'social.coves.richtext.facet#spoiler';
const headingType = 'social.coves.richtext.facet#heading';
const blockquoteType = 'social.coves.richtext.facet#blockquote';
const codeBlockType = 'social.coves.richtext.facet#codeBlock';

const sparkleJson = {r'$type': 'com.example.richtext#sparkle', 'intensity': 3};
const sparkle = UnknownFacetFeature(data: sparkleJson);

class EditCase {
  const EditCase(
    this.description, {
    required this.act,
    required this.text,
    this.inline = const [],
    this.blocks = const [],
    this.features = const [],
  });

  final String description;
  final void Function(FacetEditingController controller) act;
  final String text;
  final List<InlineRange> inline;
  final List<BlockRange> blocks;
  final List<FeatureRange> features;
}

void expectRanges(FacetEditingController controller, EditCase editCase) {
  expect(controller.text, editCase.text);
  expect(controller.inlineRanges, unorderedEquals(editCase.inline));
  expect(controller.blockRanges, unorderedEquals(editCase.blocks));
  expect(controller.featureRanges, unorderedEquals(editCase.features));
}

/// "hello world" with "world" [6,11) carrying a spoiler with reason 'r' and
/// an unknown sparkle feature.
FacetEditingController reasonedAndUnknown() => load('hello world', [
  facetJson(6, 11, [
    {r'$type': spoilerType, 'reason': 'r'},
    sparkleJson,
  ]),
]);

InlineRange spoilerR(int start, int end) =>
    InlineRange(InlineFormat.spoiler, start, end, reason: 'r');

FeatureRange sparkleAt(int start, int end) => FeatureRange(sparkle, start, end);

final inlineEditCases = [
  EditCase(
    'insert inside the range extends it',
    act: (c) => edit(c, 'hello woXrld', 9),
    text: 'hello woXrld',
    inline: [spoilerR(6, 12)],
    features: [sparkleAt(6, 12)],
  ),
  EditCase(
    'insert at the start of the text shifts it',
    act: (c) => edit(c, 'Xhello world', 1),
    text: 'Xhello world',
    inline: [spoilerR(7, 12)],
    features: [sparkleAt(7, 12)],
  ),
  EditCase(
    'delete inside the range shrinks it',
    act: (c) => edit(c, 'hello wld', 7),
    text: 'hello wld',
    inline: [spoilerR(6, 9)],
    features: [sparkleAt(6, 9)],
  ),
  EditCase(
    'deleting across the start of the range moves its start to the edit',
    act: (c) => edit(c, 'hellrld', 4),
    text: 'hellrld',
    inline: [spoilerR(4, 7)],
    features: [sparkleAt(4, 7)],
  ),
  EditCase(
    'replacing a selection across the start of the range shifts it past '
    'the replacement',
    act: (c) {
      select(c, 4, 8);
      edit(c, 'hellXrld', 5);
    },
    text: 'hellXrld',
    inline: [spoilerR(5, 8)],
    features: [sparkleAt(5, 8)],
  ),
  EditCase(
    'a combining mark after the range end widens it over the cluster',
    act: (c) => edit(c, 'hello world\u0301', 12),
    text: 'hello world\u0301',
    inline: [spoilerR(6, 12)],
    features: [sparkleAt(6, 12)],
  ),
  EditCase(
    'typing at the end with the caret there extends the spoiler only',
    act: (c) {
      caretAt(c, 11);
      edit(c, 'hello worldX', 12);
    },
    text: 'hello worldX',
    inline: [spoilerR(6, 12)],
    features: [sparkleAt(6, 11)],
  ),
  EditCase(
    'typing at the start with the caret there shifts both',
    act: (c) {
      caretAt(c, 6);
      edit(c, 'hello Xworld', 7);
    },
    text: 'hello Xworld',
    inline: [spoilerR(7, 12)],
    features: [sparkleAt(7, 12)],
  ),
  EditCase(
    'an unformatted paste before the range shifts it',
    act: (c) {
      caretAt(c, 0);
      c.pasteUnformatted('ZZ');
    },
    text: 'ZZhello world',
    inline: [spoilerR(8, 13)],
    features: [sparkleAt(8, 13)],
  ),
  EditCase(
    'a committed composition before the range shifts it',
    act: (c) {
      caretAt(c, 0);
      compose(c, 'ahello world', 1, const TextRange(start: 0, end: 1));
      compose(c, 'abhello world', 2, const TextRange(start: 0, end: 2));
      edit(c, 'abhello world', 2);
    },
    text: 'abhello world',
    inline: [spoilerR(8, 13)],
    features: [sparkleAt(8, 13)],
  ),
  EditCase(
    'a cancelled composition leaves the range where it was',
    act: (c) {
      caretAt(c, 5);
      compose(c, 'hello world', 5, const TextRange(start: 0, end: 5));
      compose(c, 'hel world', 3, const TextRange(start: 0, end: 3));
      edit(c, 'hello world', 5);
    },
    text: 'hello world',
    inline: [spoilerR(6, 11)],
    features: [sparkleAt(6, 11)],
  ),
  EditCase(
    'a cancelled composition inside the range restores it after a caret move',
    act: (c) {
      caretAt(c, 11);
      compose(c, 'hello world', 11, const TextRange(start: 6, end: 11));
      compose(c, 'hello wo', 8, const TextRange(start: 6, end: 8));
      compose(c, 'hello wo', 7, const TextRange(start: 6, end: 8));
      edit(c, 'hello world', 11);
    },
    text: 'hello world',
    inline: [spoilerR(6, 11)],
    features: [sparkleAt(6, 11)],
  ),
];

/// 'aa\nbb\ncc': heading level 5 on line 0, code block 'dart' on line 1,
/// quote level 2 on line 2.
FacetEditingController threeBlockLines() => load('aa\nbb\ncc', [
  facetJson(0, 2, [
    {r'$type': headingType, 'level': 5},
  ]),
  facetJson(3, 5, [
    {r'$type': codeBlockType, 'language': 'dart'},
  ]),
  facetJson(6, 8, [
    {r'$type': blockquoteType, 'level': 2},
  ]),
]);

BlockRange h5(int start, int end) =>
    BlockRange(BlockFormat.heading, start, end, level: 5);

BlockRange dart(int start, int end) =>
    BlockRange(BlockFormat.codeBlock, start, end, language: 'dart');

BlockRange quote2(int start, int end) =>
    BlockRange(BlockFormat.blockquote, start, end, level: 2);

class BlockEditCase extends EditCase {
  const BlockEditCase(
    super.description, {
    required this.build,
    required super.act,
    required super.text,
    super.inline,
    super.blocks,
  });

  final FacetEditingController Function() build;
}

final blockEditCases = [
  BlockEditCase(
    'typing inside the code line keeps its language',
    build: threeBlockLines,
    act: (c) => edit(c, 'aa\nbXb\ncc', 5),
    text: 'aa\nbXb\ncc',
    blocks: [h5(0, 2), dart(3, 6), quote2(7, 9)],
  ),
  BlockEditCase(
    'typing inside the heading line keeps level 5',
    build: threeBlockLines,
    act: (c) => edit(c, 'aXa\nbb\ncc', 2),
    text: 'aXa\nbb\ncc',
    blocks: [h5(0, 3), dart(4, 6), quote2(7, 9)],
  ),
  BlockEditCase(
    'a newline at the start moves every block down with its attributes',
    build: threeBlockLines,
    act: (c) => edit(c, '\naa\nbb\ncc', 1),
    text: '\naa\nbb\ncc',
    blocks: [h5(1, 3), dart(4, 6), quote2(7, 9)],
  ),
  BlockEditCase(
    'Enter inside the code line continues the code block with its language',
    build: threeBlockLines,
    act: (c) {
      caretAt(c, 4);
      edit(c, 'aa\nb\nb\ncc', 5);
    },
    text: 'aa\nb\nb\ncc',
    blocks: [h5(0, 2), dart(3, 6), quote2(7, 9)],
  ),
  BlockEditCase(
    'quoting the code line adds a level-1 quote beside the level-2 quote',
    build: threeBlockLines,
    act: (c) {
      caretAt(c, 4);
      c.toggleBlock(BlockFormat.blockquote);
    },
    text: 'aa\nbb\ncc',
    blocks: [
      h5(0, 2),
      dart(3, 5),
      const BlockRange(BlockFormat.blockquote, 3, 5),
      quote2(6, 8),
    ],
  ),
  BlockEditCase(
    'cutting the middle line out of a code block keeps both halves dart',
    build: () => load('aa\nbb\ncc', [
      facetJson(0, 8, [
        {r'$type': codeBlockType, 'language': 'dart'},
      ]),
    ]),
    act: (c) {
      caretAt(c, 4);
      c.toggleBlock(BlockFormat.codeBlock);
    },
    text: 'aa\nbb\ncc',
    blocks: [dart(0, 2), dart(6, 8)],
  ),
  BlockEditCase(
    'removing a heading keeps the neighbouring code block language',
    build: () => load('aa\nbb', [
      facetJson(0, 2, [
        {r'$type': headingType, 'level': 2},
      ]),
      facetJson(3, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
      ]),
    ]),
    act: (c) {
      caretAt(c, 0);
      c.removeHeadings();
    },
    text: 'aa\nbb',
    blocks: [dart(3, 5)],
  ),
  BlockEditCase(
    'a loaded spoiler on a code line survives an edit on another line',
    build: () => load('aa\nbb', [
      facetJson(3, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
        {r'$type': spoilerType, 'reason': 'r'},
      ]),
    ]),
    act: (c) => edit(c, 'Xaa\nbb', 1),
    text: 'Xaa\nbb',
    inline: [spoilerR(4, 6)],
    blocks: [dart(4, 6)],
  ),
  BlockEditCase(
    'adding a code block keeps a loaded spoiler on a line already code',
    build: () => load('aa\nbb\ncc', [
      facetJson(3, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
        {r'$type': spoilerType, 'reason': 'r'},
      ]),
      facetJson(6, 8, [
        {r'$type': 'social.coves.richtext.facet#bold'},
      ]),
    ]),
    act: (c) {
      caretAt(c, 7);
      c.toggleBlock(BlockFormat.codeBlock);
    },
    text: 'aa\nbb\ncc',
    inline: [spoilerR(3, 5)],
    blocks: [dart(3, 5), const BlockRange(BlockFormat.codeBlock, 6, 8)],
  ),
];

BlockRange code(int start, int end) =>
    BlockRange(BlockFormat.codeBlock, start, end);

BlockRange quote(int start, int end) =>
    BlockRange(BlockFormat.blockquote, start, end);

/// Selects [start] to [end], then toggles [format].
void Function(FacetEditingController) toggleOver(
  BlockFormat format,
  int start,
  int end,
) => (c) {
  select(c, start, end);
  c.toggleBlock(format);
};

/// A quote or code block added over lines that already hold a block of the
/// same format with another level or language is added only on the other
/// lines; the loaded block keeps its lines, level and language, and the
/// result has no crossing or nested same-format blocks.
final otherKindCases = [
  BlockEditCase(
    'a code block partly over a dart block covers only the uncovered line',
    build: () => load('aa\nbb\ncc\ndd', [
      facetJson(0, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
      ]),
    ]),
    act: toggleOver(BlockFormat.codeBlock, 3, 8),
    text: 'aa\nbb\ncc\ndd',
    blocks: [dart(0, 5), code(6, 8)],
  ),
  BlockEditCase(
    'a code block starting on a dart line covers only the line below it',
    build: () => load('aa\nbb\ncc', [
      facetJson(3, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
      ]),
    ]),
    act: toggleOver(BlockFormat.codeBlock, 3, 8),
    text: 'aa\nbb\ncc',
    blocks: [dart(3, 5), code(6, 8)],
  ),
  BlockEditCase(
    'a code block around a dart line splits into the lines on each side',
    build: () => load('aa\nbb\ncc', [
      facetJson(3, 5, [
        {r'$type': codeBlockType, 'language': 'dart'},
      ]),
    ]),
    act: toggleOver(BlockFormat.codeBlock, 0, 8),
    text: 'aa\nbb\ncc',
    blocks: [code(0, 2), dart(3, 5), code(6, 8)],
  ),
  BlockEditCase(
    'a quote over a level-2 quote line adds level 1 only above it',
    build: () => load('aa\nbb\ncc', [
      facetJson(6, 8, [
        {r'$type': blockquoteType, 'level': 2},
      ]),
    ]),
    act: toggleOver(BlockFormat.blockquote, 0, 8),
    text: 'aa\nbb\ncc',
    blocks: [quote(0, 5), quote2(6, 8)],
  ),
  BlockEditCase(
    'a quote around a level-2 quote line splits into the lines on each side',
    build: () => load('aa\nbb\ncc', [
      facetJson(3, 5, [
        {r'$type': blockquoteType, 'level': 2},
      ]),
    ]),
    act: toggleOver(BlockFormat.blockquote, 0, 8),
    text: 'aa\nbb\ncc',
    blocks: [quote(0, 2), quote2(3, 5), quote(6, 8)],
  ),
  BlockEditCase(
    'a quote partly over a level-2 quote covers only the uncovered line',
    build: () => load('aa\nbb\ncc\ndd', [
      facetJson(3, 8, [
        {r'$type': blockquoteType, 'level': 2},
      ]),
    ]),
    act: toggleOver(BlockFormat.blockquote, 0, 5),
    text: 'aa\nbb\ncc\ndd',
    blocks: [quote(0, 2), quote2(3, 8)],
  ),
];

final removalCases = [
  EditCase(
    'deleting exactly its text',
    act: (c) => edit(c, 'hello ', 6),
    text: 'hello ',
  ),
  EditCase(
    'deleting its text and the space before it',
    act: (c) => edit(c, 'hello', 5),
    text: 'hello',
  ),
  EditCase('setting text to empty', act: (c) => c.text = '', text: ''),
  EditCase('clear()', act: (c) => c.clear(), text: ''),
];

InlineRange spoiler(int start, int end, [String? reason]) =>
    InlineRange(InlineFormat.spoiler, start, end, reason: reason);

class SpoilerCase {
  const SpoilerCase(
    this.description, {
    required this.facets,
    required this.act,
    required this.inline,
  });

  final String description;
  final List<Map<String, dynamic>> facets;
  final void Function(FacetEditingController controller) act;
  final List<InlineRange> inline;
}

Map<String, dynamic> spoilerJson(int start, int end, String reason) =>
    facetJson(start, end, [
      {r'$type': spoilerType, 'reason': reason},
    ]);

final spoilerCases = [
  SpoilerCase(
    'adjacent reasons: typing inside the first grows only the first',
    facets: [spoilerJson(0, 5, 'a'), spoilerJson(5, 11, 'b')],
    act: (c) => edit(c, 'heXllo world', 3),
    inline: [spoiler(0, 6, 'a'), spoiler(6, 12, 'b')],
  ),
  SpoilerCase(
    'overlapping reasons load as two ranges',
    facets: [spoilerJson(0, 7, 'a'), spoilerJson(4, 11, 'b')],
    act: (c) {},
    inline: [spoiler(0, 7, 'a'), spoiler(4, 11, 'b')],
  ),
  SpoilerCase(
    'overlapping reasons: deleting a shared character shrinks both',
    facets: [spoilerJson(0, 7, 'a'), spoilerJson(4, 11, 'b')],
    act: (c) => edit(c, 'helloworld', 5),
    inline: [spoiler(0, 6, 'a'), spoiler(4, 10, 'b')],
  ),
  SpoilerCase(
    'toggling spoiler off inside a reasoned spoiler keeps the reason',
    facets: [spoilerJson(0, 5, 'a')],
    act: (c) {
      select(c, 1, 3);
      c.toggleInline(InlineFormat.spoiler);
    },
    inline: [spoiler(0, 1, 'a'), spoiler(3, 5, 'a')],
  ),
  SpoilerCase(
    'toggling spoiler on beside a reasoned spoiler stays separate',
    facets: [spoilerJson(0, 5, 'a')],
    act: (c) {
      select(c, 5, 8);
      c.toggleInline(InlineFormat.spoiler);
    },
    inline: [spoiler(0, 5, 'a'), spoiler(5, 8)],
  ),
  SpoilerCase(
    'replacing the first characters of a reasoned spoiler keeps its reason',
    facets: [spoilerJson(6, 11, 'r')],
    act: (c) {
      select(c, 6, 8);
      edit(c, 'hello Xrld', 7);
    },
    inline: [spoiler(6, 10, 'r')],
  ),
  SpoilerCase(
    'replacing all of a reasoned spoiler keeps its reason',
    facets: [spoilerJson(6, 11, 'r')],
    act: (c) {
      select(c, 6, 11);
      edit(c, 'hello X', 7);
    },
    inline: [spoiler(6, 7, 'r')],
  ),
  SpoilerCase(
    'replacing across two reasons from inside the first takes the first',
    facets: [spoilerJson(0, 5, 'a'), spoilerJson(5, 11, 'b')],
    act: (c) {
      select(c, 3, 7);
      edit(c, 'helXorld', 4);
    },
    inline: [spoiler(0, 4, 'a'), spoiler(4, 8, 'b')],
  ),
  SpoilerCase(
    'replacing from the start of the second reason takes the second',
    facets: [spoilerJson(0, 5, 'a'), spoilerJson(5, 11, 'b')],
    act: (c) {
      select(c, 5, 7);
      edit(c, 'helloXorld', 6);
    },
    inline: [spoiler(0, 5, 'a'), spoiler(5, 10, 'b')],
  ),
];

void main() {
  group('B1a loaded reasoned and unknown ranges follow edits', () {
    for (final editCase in inlineEditCases) {
      test(editCase.description, () {
        final controller = reasonedAndUnknown();
        editCase.act(controller);
        expectRanges(controller, editCase);
      });
    }

    test('a composition rebased by a caret move carries the feature range', () {
      final controller = load('hello world', [
        facetJson(6, 11, [sparkleJson]),
      ]);
      caretAt(controller, 11);
      compose(
        controller,
        'hello world',
        11,
        const TextRange(start: 6, end: 11),
      );
      compose(controller, 'hello wo', 8, const TextRange(start: 6, end: 8));
      expect(controller.featureRanges, [sparkleAt(6, 8)]);
      // The caret move rebases the composition onto 'hello wo'.
      compose(controller, 'hello wo', 7, const TextRange(start: 6, end: 8));
      expect(controller.featureRanges, [sparkleAt(6, 8)]);
      edit(controller, 'hello woX', 9);
      expect(controller.featureRanges, [sparkleAt(6, 8)]);
    });
  });

  group('B1d a loaded code-line spoiler during a composition', () {
    test('survives a bold toggle mid-composition on another line', () {
      final controller = load('aa\nbb', [
        facetJson(3, 5, [
          {r'$type': codeBlockType, 'language': 'dart'},
          {r'$type': spoilerType, 'reason': 'r'},
        ]),
      ]);
      caretAt(controller, 2);
      compose(controller, 'aaX\nbb', 3, const TextRange(start: 2, end: 3));
      controller.toggleInline(InlineFormat.bold);
      const bold = InlineRange(InlineFormat.bold, 2, 3);
      expect(controller.inlineRanges, unorderedEquals([bold, spoilerR(4, 6)]));
      edit(controller, 'aaX\nbb', 3);
      expect(controller.inlineRanges, unorderedEquals([bold, spoilerR(4, 6)]));
      expect(controller.blockRanges, [dart(4, 6)]);
    });
  });

  group('B1b loaded block attributes survive edits', () {
    for (final editCase in blockEditCases) {
      test(editCase.description, () {
        final controller = editCase.build();
        editCase.act(controller);
        expectRanges(controller, editCase);
      });
    }
  });

  group('B1c a block added over a loaded block of another kind', () {
    for (final editCase in otherKindCases) {
      test(editCase.description, () {
        final controller = editCase.build();
        editCase.act(controller);
        expectRanges(controller, editCase);
      });
    }

    test('a code block around a dart line saves three code-block facets', () {
      final controller = load('aa\nbb\ncc', [
        facetJson(3, 5, [
          {r'$type': codeBlockType, 'language': 'dart'},
        ]),
      ]);
      toggleOver(BlockFormat.codeBlock, 0, 8)(controller);
      final saved = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
        featureRanges: controller.featureRanges,
      );
      expect(
        [for (final facet in saved.facets) facet.toJson()],
        [
          facetJson(0, 2, [
            {r'$type': codeBlockType},
          ]),
          facetJson(3, 5, [
            {r'$type': codeBlockType, 'language': 'dart'},
          ]),
          facetJson(6, 8, [
            {r'$type': codeBlockType},
          ]),
        ],
      );
    });

    test('a code block across quotes of two levels splits per quote', () {
      final controller = load('aa\nbb', [
        facetJson(0, 2, [
          {r'$type': blockquoteType, 'level': 1},
        ]),
        facetJson(3, 5, [
          {r'$type': blockquoteType, 'level': 2},
        ]),
      ]);
      toggleOver(BlockFormat.codeBlock, 0, 5)(controller);
      expect(
        controller.blockRanges,
        unorderedEquals([quote(0, 2), quote2(3, 5), code(0, 2), code(3, 5)]),
      );
      expect(controller.activeBlockFormats(), contains(BlockFormat.codeBlock));
      final saved = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
        featureRanges: controller.featureRanges,
      );
      expect(
        [for (final facet in saved.facets) facet.toJson()],
        unorderedEquals([
          facetJson(0, 2, [
            {r'$type': blockquoteType},
            {r'$type': codeBlockType},
          ]),
          facetJson(3, 5, [
            {r'$type': blockquoteType, 'level': 2},
            {r'$type': codeBlockType},
          ]),
        ]),
      );
    });
  });

  group('B2 a loaded range is removed when all its text is deleted', () {
    for (final editCase in removalCases) {
      test(editCase.description, () {
        final controller = reasonedAndUnknown();
        editCase.act(controller);
        expectRanges(controller, editCase);
      });
    }
  });

  group('B8 settling a large loaded record stays fast', () {
    // 200 lines, each covered by one facet with 20 code-block features in
    // languages l1..l20: the most code blocks a record can load.
    List<RichTextFacet> codeLines(String content) {
      final facets = <RichTextFacet>[];
      var offset = 0;
      for (final line in content.split('\n')) {
        if (line.isNotEmpty) {
          facets.add(
            facet(offset, offset + line.length, [
              for (var i = 1; i <= 20; i++)
                CodeBlockFacetFeature(language: 'l$i'),
            ]),
          );
        }
        offset += line.length + 1;
      }
      return facets;
    }

    test('200 adjacent lines of 20 languages each load as 20 code blocks', () {
      final content = List.filled(200, 'aa').join('\n');
      final stopwatch = Stopwatch()..start();
      final controller = FacetEditingController.fromRecord(
        content,
        codeLines(content),
      );
      stopwatch.stop();
      addTearDown(controller.dispose);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        controller.blockRanges,
        unorderedEquals([
          for (var i = 1; i <= 20; i++)
            BlockRange(
              BlockFormat.codeBlock,
              0,
              content.length,
              language: 'l$i',
            ),
        ]),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('200 separated lines of 20 languages each load and edit quickly', () {
      final content = List.filled(200, 'aa').join('\n\n');
      final stopwatch = Stopwatch()..start();
      final controller = FacetEditingController.fromRecord(
        content,
        codeLines(content),
      );
      addTearDown(controller.dispose);
      // A newline at the start changes the line count, so it settles;
      // the first code blocks also cover the new empty line above.
      edit(controller, '\n$content', 1);
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        controller.blockRanges,
        unorderedEquals([
          for (var line = 0; line < 200; line++)
            for (var i = 1; i <= 20; i++)
              BlockRange(
                BlockFormat.codeBlock,
                line == 0 ? 0 : 1 + line * 4,
                3 + line * 4,
                language: 'l$i',
              ),
        ]),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('201 lines of chained quotes and code in reverse order load fast', () {
      // Facet i covers lines i and i+1 with quote levels 1..6 and code
      // languages l1..l14, supplied from the last line up, so a quote that
      // widened one code block at a time would grow a line per sweep.
      final content = List.filled(201, 'aa').join('\n');
      final facets = [
        for (var line = 199; line >= 0; line--)
          facet(line * 3, line * 3 + 5, [
            for (var level = 1; level <= 6; level++)
              BlockquoteFacetFeature(level: level),
            for (var i = 1; i <= 14; i++)
              CodeBlockFacetFeature(language: 'l$i'),
          ]),
      ];
      final stopwatch = Stopwatch()..start();
      final controller = FacetEditingController.fromRecord(content, facets);
      stopwatch.stop();
      addTearDown(controller.dispose);
      // Sweep-by-sweep widening took about 800 ms here; one sorted pass
      // takes a few tens of milliseconds.
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 400)));
      expect(
        controller.blockRanges,
        unorderedEquals([
          for (var level = 1; level <= 6; level++)
            BlockRange(BlockFormat.blockquote, 0, content.length, level: level),
          for (var i = 1; i <= 14; i++)
            BlockRange(
              BlockFormat.codeBlock,
              0,
              content.length,
              language: 'l$i',
            ),
        ]),
      );
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  group('B7 spoilers with different reasons stay apart', () {
    for (final spoilerCase in spoilerCases) {
      test(spoilerCase.description, () {
        final controller = load('hello world', spoilerCase.facets);
        spoilerCase.act(controller);
        expect(controller.inlineRanges, unorderedEquals(spoilerCase.inline));
      });
    }

    test('adjacent reasons save as two spoiler facets after an edit', () {
      final controller = load('hello world', [
        spoilerJson(0, 5, 'a'),
        spoilerJson(5, 11, 'b'),
      ]);
      edit(controller, 'heXllo world', 3);
      final saved = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
        featureRanges: controller.featureRanges,
      );
      expect(saved.content, 'heXllo world');
      expect(
        [for (final facet in saved.facets) facet.toJson()],
        [spoilerJson(0, 6, 'a'), spoilerJson(6, 12, 'b')],
      );
    });
  });
}
