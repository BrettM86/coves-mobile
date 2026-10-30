import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/utils/rich_text_composer.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils/mention_resolver_fakes.dart';
import 'facet_fixture_helpers.dart';
import 'span_style_helpers.dart';

const mentionType = 'social.coves.richtext.facet#mention';
const linkType = 'social.coves.richtext.facet#link';
const boldType = 'social.coves.richtext.facet#bold';

Map<String, dynamic> mentionJson(String did) => {
  r'$type': mentionType,
  'did': did,
};

Map<String, dynamic> linkJson(String uri) => {r'$type': linkType, 'uri': uri};

FeatureRange mentionAt(String did, int start, int end) =>
    FeatureRange(MentionFacetFeature(did: did), start, end);

FeatureRange linkAt(String uri, int start, int end) =>
    FeatureRange(LinkFacetFeature(uri: uri), start, end);

/// Every handle a fixture below may look up.
const handles = {
  'alice.test': 'did:plc:alice',
  'alicex.test': 'did:plc:alicex',
  'bolice.test': 'did:plc:bolice',
  'bob.test': 'did:plc:bob',
  'carol.test': 'did:plc:carol',
};

/// What submitting a controller produced.
typedef Submitted = ({
  List<String> started,
  List<String> pending,
  List<Map<String, dynamic>> facets,
});

/// Saves [controller], composes the saved content and resolves its mentions
/// through a fake resolver over [handles], the way the composer submits.
Future<Submitted> submit(FacetEditingController controller) async {
  final saved = serializeFormatting(
    controller.text,
    inlineRanges: controller.inlineRanges,
    blockRanges: controller.blockRanges,
    featureRanges: controller.featureRanges,
  );
  final composed = composeFormattedRichText(
    saved.content,
    formattingFacets: saved.facets,
    excludedRanges: saved.codeRanges,
  );
  final resolver = FakeMentionResolver(handles: handles);
  final result = await resolveMentions(composed, resolver);
  return (
    started: resolver.started,
    pending: [for (final mention in composed.mentions) mention.identifier],
    facets: [
      for (final facet in result.facets ?? const <RichTextFacet>[])
        facet.toJson(),
    ],
  );
}

/// 'hi @alice.test and https://example.com ok' with a mention over
/// `@alice.test` [3,14) and a link over `https://example.com` [19,38).
FacetEditingController aliceAndLink() =>
    load('hi @alice.test and https://example.com ok', [
      facetJson(3, 14, [mentionJson('did:plc:alice')]),
      facetJson(19, 38, [linkJson('https://example.com')]),
    ]);

class ShiftCase {
  const ShiftCase(
    this.description, {
    required this.act,
    required this.features,
  });

  final String description;
  final void Function(FacetEditingController controller) act;
  final List<FeatureRange> features;
}

final shiftCases = [
  ShiftCase(
    'typing before both shifts them',
    act: (c) => edit(c, 'Xhi @alice.test and https://example.com ok', 1),
    features: [
      mentionAt('did:plc:alice', 4, 15),
      linkAt('https://example.com', 20, 39),
    ],
  ),
  ShiftCase(
    'typing exactly at the mention start shifts both',
    act: (c) {
      caretAt(c, 3);
      edit(c, 'hi Y@alice.test and https://example.com ok', 4);
    },
    features: [
      mentionAt('did:plc:alice', 4, 15),
      linkAt('https://example.com', 20, 39),
    ],
  ),
  ShiftCase(
    'typing right after the mention leaves it over its own text',
    act: (c) {
      caretAt(c, 14);
      edit(c, 'hi @alice.testx and https://example.com ok', 15);
    },
    features: [
      mentionAt('did:plc:alice', 3, 14),
      linkAt('https://example.com', 20, 39),
    ],
  ),
  ShiftCase(
    'backspacing the character right before the mention shifts both',
    act: (c) => edit(c, 'hi@alice.test and https://example.com ok', 2),
    features: [
      mentionAt('did:plc:alice', 2, 13),
      linkAt('https://example.com', 18, 37),
    ],
  ),
  ShiftCase(
    'forward-deleting the character right after the mention keeps it',
    act: (c) {
      caretAt(c, 14);
      edit(c, 'hi @alice.testand https://example.com ok', 14);
    },
    features: [
      mentionAt('did:plc:alice', 3, 14),
      linkAt('https://example.com', 18, 37),
    ],
  ),
  ShiftCase(
    'typing after both leaves them',
    act: (c) => edit(c, 'hi @alice.test and https://example.com ok!', 42),
    features: [
      mentionAt('did:plc:alice', 3, 14),
      linkAt('https://example.com', 19, 38),
    ],
  ),
];

class OwnTextCase {
  const OwnTextCase(
    this.description, {
    required this.act,
    required this.text,
    required this.features,
    required this.started,
    required this.facets,
  });

  final String description;
  final void Function(FacetEditingController controller) act;
  final String text;
  final List<FeatureRange> features;
  final List<String> started;
  final List<Map<String, dynamic>> facets;
}

final ownTextCases = [
  OwnTextCase(
    'typing inside the mention',
    act: (c) => edit(c, 'hi @alicex.test and https://example.com ok', 10),
    text: 'hi @alicex.test and https://example.com ok',
    features: [linkAt('https://example.com', 20, 39)],
    started: ['user alicex.test'],
    facets: [
      facetJson(3, 15, [mentionJson('did:plc:alicex')]),
      facetJson(20, 39, [linkJson('https://example.com')]),
    ],
  ),
  OwnTextCase(
    'deleting a character inside the link',
    act: (c) => edit(c, 'hi @alice.test and https://eample.com ok', 28),
    text: 'hi @alice.test and https://eample.com ok',
    features: [mentionAt('did:plc:alice', 3, 14)],
    started: [],
    facets: [
      facetJson(3, 14, [mentionJson('did:plc:alice')]),
      facetJson(19, 37, [linkJson('https://eample.com')]),
    ],
  ),
  OwnTextCase(
    'replacing a selection across the mention start',
    act: (c) {
      select(c, 1, 5);
      edit(c, 'ho @bolice.test and https://example.com ok', 5);
    },
    text: 'ho @bolice.test and https://example.com ok',
    features: [linkAt('https://example.com', 20, 39)],
    started: ['user bolice.test'],
    facets: [
      facetJson(3, 15, [mentionJson('did:plc:bolice')]),
      facetJson(20, 39, [linkJson('https://example.com')]),
    ],
  ),
  OwnTextCase(
    'a combining mark at the mention end changes its last grapheme',
    act: (c) => edit(c, 'hi @alice.test́ and https://example.com ok', 15),
    text: 'hi @alice.test́ and https://example.com ok',
    features: [linkAt('https://example.com', 20, 39)],
    started: [],
    facets: [
      facetJson(21, 40, [linkJson('https://example.com')]),
    ],
  ),
  OwnTextCase(
    'a combining mark at the link end changes its last grapheme',
    act: (c) => edit(c, 'hi @alice.test and https://example.coḿ ok', 39),
    text: 'hi @alice.test and https://example.coḿ ok',
    features: [mentionAt('did:plc:alice', 3, 14)],
    started: [],
    facets: [
      facetJson(3, 14, [mentionJson('did:plc:alice')]),
    ],
  ),
];

class SubmitCase {
  const SubmitCase(
    this.description, {
    required this.content,
    required this.loaded,
    this.act,
    required this.started,
    required this.pending,
    required this.facets,
  });

  final String description;
  final String content;
  final List<Map<String, dynamic>> loaded;
  final void Function(FacetEditingController controller)? act;
  final List<String> started;
  final List<String> pending;
  final List<Map<String, dynamic>> facets;
}

/// `@alice.test` [0,11) and `Alice` [16,21) each under a loaded mention,
/// `https://example.com` [25,44) under a loaded link.
final untouchedRecord = [
  facetJson(0, 11, [mentionJson('did:plc:alice')]),
  facetJson(16, 21, [mentionJson('did:plc:alice')]),
  facetJson(25, 44, [linkJson('https://example.com')]),
];

final untouchedCases = [
  SubmitCase(
    'an untouched record looks nothing up and saves its facets as loaded',
    content: '@alice.test met Alice at https://example.com',
    loaded: untouchedRecord,
    started: [],
    pending: [],
    facets: untouchedRecord,
  ),
  SubmitCase(
    'a mention typed after the record is still looked up',
    content: '@alice.test met Alice at https://example.com',
    loaded: untouchedRecord,
    act: (c) =>
        edit(c, '@alice.test met Alice at https://example.com @bob.test', 54),
    started: ['user bob.test'],
    pending: ['bob.test'],
    facets: [
      ...untouchedRecord,
      facetJson(45, 54, [mentionJson('did:plc:bob')]),
    ],
  ),
];

/// Each content starts with 'é ' (2 UTF-16 units, 3 UTF-8 bytes), so a
/// byte/UTF-16 mix-up misplaces the overlap.
final overlapCases = [
  SubmitCase(
    'a URL extending past a loaded link',
    content: 'é https://example.com/x @bob.test',
    loaded: [
      facetJson(11, 22, [linkJson('https://example.com')]),
    ],
    started: ['user bob.test'],
    pending: ['bob.test'],
    facets: [
      facetJson(11, 22, [linkJson('https://example.com')]),
      facetJson(25, 34, [mentionJson('did:plc:bob')]),
    ],
  ),
  SubmitCase(
    'a mention inside a loaded link',
    content: 'é see @bob.test now @carol.test',
    loaded: [
      facetJson(3, 16, [linkJson('https://example.com/bob')]),
    ],
    started: ['user carol.test'],
    pending: ['carol.test'],
    facets: [
      facetJson(3, 16, [linkJson('https://example.com/bob')]),
      facetJson(21, 32, [mentionJson('did:plc:carol')]),
    ],
  ),
  SubmitCase(
    'a URL starting exactly at a loaded link end',
    content: 'é see https://example.com/x',
    loaded: [
      facetJson(3, 7, [linkJson('https://example.com/see')]),
    ],
    started: [],
    pending: [],
    facets: [
      facetJson(3, 7, [linkJson('https://example.com/see')]),
      facetJson(7, 28, [linkJson('https://example.com/x')]),
    ],
  ),
  SubmitCase(
    'a mention extending past a loaded mention',
    content: 'é hi @alice.test @bob.test',
    loaded: [
      facetJson(6, 12, [mentionJson('did:plc:alice')]),
    ],
    started: ['user bob.test'],
    pending: ['bob.test'],
    facets: [
      facetJson(6, 12, [mentionJson('did:plc:alice')]),
      facetJson(18, 27, [mentionJson('did:plc:bob')]),
    ],
  ),
];

/// 'hi @alice.test ok' with a mention over `@alice.test` [3,14).
FacetEditingController loadedAlice() => load('hi @alice.test ok', [
  facetJson(3, 14, [mentionJson('did:plc:alice')]),
]);

/// Starts composing `alice.test` with the caret at its end, then deletes
/// its last two characters inside the composition.
void composeInsideAlice(FacetEditingController c) {
  caretAt(c, 14);
  compose(c, 'hi @alice.test ok', 14, const TextRange(start: 4, end: 14));
  compose(c, 'hi @alice.te ok', 12, const TextRange(start: 4, end: 12));
}

/// Moves the caret back one inside the composition, which rebases it.
void moveCaretInComposition(FacetEditingController c) =>
    compose(c, 'hi @alice.te ok', 11, const TextRange(start: 4, end: 12));

final imeCases = [
  const ShiftCase(
    'composing inside the mention drops it while composing',
    act: composeInsideAlice,
    features: [],
  ),
  ShiftCase(
    'the drop holds after a caret move rebases the composition',
    act: (c) {
      composeInsideAlice(c);
      moveCaretInComposition(c);
    },
    features: [],
  ),
  ShiftCase(
    'committing changed text keeps it dropped',
    act: (c) {
      composeInsideAlice(c);
      compose(c, 'hi @alice.tex ok', 13, const TextRange(start: 4, end: 13));
      edit(c, 'hi @alice.tex ok', 13);
    },
    features: [],
  ),
  ShiftCase(
    'cancelling the composition restores the mention',
    act: (c) {
      composeInsideAlice(c);
      edit(c, 'hi @alice.test ok', 14);
    },
    features: [mentionAt('did:plc:alice', 3, 14)],
  ),
  ShiftCase(
    'cancelling after a caret move restores the mention',
    act: (c) {
      composeInsideAlice(c);
      moveCaretInComposition(c);
      edit(c, 'hi @alice.test ok', 14);
    },
    features: [mentionAt('did:plc:alice', 3, 14)],
  ),
];

void main() {
  // GUARD: the remap this run changes must keep shifting and keeping ranges
  // whose own text is untouched; expected to pass before the change.
  group('B1 loaded mentions and links follow edits around them', () {
    for (final shiftCase in shiftCases) {
      test(shiftCase.description, () {
        final controller = aliceAndLink();
        shiftCase.act(controller);
        expect(controller.featureRanges, unorderedEquals(shiftCase.features));
      });
    }
  });

  group('B2 a loaded mention or link whose own text changes is dropped', () {
    for (final ownTextCase in ownTextCases) {
      test(ownTextCase.description, () async {
        final controller = aliceAndLink();
        ownTextCase.act(controller);
        expect(controller.text, ownTextCase.text);
        expect(controller.featureRanges, unorderedEquals(ownTextCase.features));
        final submitted = await submit(controller);
        expect(submitted.started, ownTextCase.started);
        expect(submitted.facets, ownTextCase.facets);
      });
    }
  });

  group('B3 untouched loaded mentions and links are kept, not re-detected', () {
    for (final submitCase in [...untouchedCases, ...overlapCases]) {
      test(submitCase.description, () async {
        final controller = load(submitCase.content, submitCase.loaded);
        submitCase.act?.call(controller);
        final submitted = await submit(controller);
        expect(submitted.pending, submitCase.pending);
        expect(submitted.started, submitCase.started);
        expect(submitted.facets, submitCase.facets);
      });
    }
  });

  group('B4 loaded mentions and links keep their facet slots', () {
    test('new links fill only the slots left after the loaded ones', () async {
      // 195 bold 'b's at [2i, 2i+1), five new links, then a loaded mention
      // over 'Alice' and a loaded link over 'click here' after them.
      final content =
          '${List.filled(195, 'b').join(' ')} '
          'https://example.com/0 https://example.com/1 https://example.com/2 '
          'https://example.com/3 https://example.com/4 Alice click here';
      final controller = load(content, [
        for (var i = 0; i < 195; i++)
          facetJson(2 * i, 2 * i + 1, [
            {r'$type': boldType},
          ]),
        facetJson(500, 505, [mentionJson('did:plc:alice')]),
        facetJson(506, 516, [linkJson('https://example.com/c')]),
      ]);
      final submitted = await submit(controller);
      expect(submitted.facets, [
        for (var i = 0; i < 195; i++)
          facetJson(2 * i, 2 * i + 1, [
            {r'$type': boldType},
          ]),
        facetJson(390, 411, [linkJson('https://example.com/0')]),
        facetJson(412, 433, [linkJson('https://example.com/1')]),
        facetJson(434, 455, [linkJson('https://example.com/2')]),
        facetJson(500, 505, [mentionJson('did:plc:alice')]),
        facetJson(506, 516, [linkJson('https://example.com/c')]),
      ]);
    });
  });

  group('B6 a composition inside a loaded mention', () {
    for (final imeCase in imeCases) {
      test(imeCase.description, () {
        final controller = loadedAlice();
        imeCase.act(controller);
        expect(controller.featureRanges, imeCase.features);
      });
    }
  });

  group('B7 a loaded link or mention that fails policy is not kept', () {
    final policyCases = [
      SubmitCase(
        'a link with a javascript: uri',
        content: 'see click here now',
        loaded: [
          facetJson(4, 14, [linkJson('javascript:alert(1)')]),
        ],
        started: [],
        pending: [],
        facets: [],
      ),
      SubmitCase(
        'a mention with a malformed DID is looked up again',
        content: 'hi @alice.test ok',
        loaded: [
          facetJson(3, 14, [mentionJson('not-a-did')]),
        ],
        started: ['user alice.test'],
        pending: ['alice.test'],
        facets: [
          facetJson(3, 14, [mentionJson('did:plc:alice')]),
        ],
      ),
      // fromJson reads these malformed known types as unknown features; the
      // backend rejects them, so they are not kept either.
      SubmitCase(
        'a link with an empty uri',
        content: 'see https://example.com now',
        loaded: [
          facetJson(4, 23, [
            {r'$type': linkType, 'uri': ''},
          ]),
        ],
        started: [],
        pending: [],
        facets: [
          facetJson(4, 23, [linkJson('https://example.com')]),
        ],
      ),
      SubmitCase(
        'a link with no uri',
        content: 'see https://example.com now',
        loaded: [
          facetJson(4, 23, [
            {r'$type': linkType},
          ]),
        ],
        started: [],
        pending: [],
        facets: [
          facetJson(4, 23, [linkJson('https://example.com')]),
        ],
      ),
      SubmitCase(
        'a mention with no did is looked up again',
        content: 'hi @alice.test ok',
        loaded: [
          facetJson(3, 14, [
            {r'$type': mentionType},
          ]),
        ],
        started: ['user alice.test'],
        pending: ['alice.test'],
        facets: [
          facetJson(3, 14, [mentionJson('did:plc:alice')]),
        ],
      ),
    ];
    for (final policyCase in policyCases) {
      test(policyCase.description, () async {
        final controller = load(policyCase.content, policyCase.loaded);
        expect(controller.featureRanges, isEmpty);
        final saved = serializeFormatting(
          controller.text,
          inlineRanges: controller.inlineRanges,
          blockRanges: controller.blockRanges,
          featureRanges: controller.featureRanges,
        );
        expect(saved.facets, isEmpty);
        final submitted = await submit(controller);
        expect(submitted.pending, policyCase.pending);
        expect(submitted.started, policyCase.started);
        expect(submitted.facets, policyCase.facets);
      });
    }
  });

  testWidgets(
    'B5 loaded mentions and links are colored over exactly their text',
    (tester) async {
      final context = await buildContextFor(tester);
      // 'Alice' [0,5) and '@bob' [23,27) are loaded mentions; 'click here'
      // [11,21) and 'example.com' [45,56) are loaded links. '@bob.test'
      // [23,32) and 'https://example.com/x' [37,58) would be detected.
      const text = 'Alice said click here, @bob.test and https://example.com/x';
      final controller = load(text, [
        facetJson(0, 5, [mentionJson('did:plc:alice')]),
        facetJson(11, 21, [linkJson('https://example.com/c')]),
        facetJson(23, 27, [mentionJson('did:plc:bob')]),
        facetJson(45, 56, [linkJson('https://example.com')]),
      ]);

      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
        withComposing: false,
      );

      expect(coloredRuns(characterStylesOf(span, text)), [
        ('mention', 0, 5),
        ('link', 11, 21),
        ('mention', 23, 27),
        ('link', 45, 56),
      ]);
    },
  );
}
