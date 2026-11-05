import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/image_layout.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/widgets.dart'
    show TextEditingValue, TextRange, TextSelection;
import 'package:flutter_test/flutter_test.dart';

const _full0 = 'https://cdn.test/f0.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';

List<EmbedImage> _threeImages() => const [
  EmbedImage(thumb: 'https://cdn.test/t0.jpg', fullsize: _full0),
  EmbedImage(thumb: 'https://cdn.test/t1.jpg', fullsize: _full1),
  EmbedImage(thumb: 'https://cdn.test/t2.jpg', fullsize: _full2),
];

PostEmbed _imagesEmbed() => ImagesPostEmbed(
  type: 'social.coves.embed.images#view',
  images: _threeImages(),
  data: const {},
);

/// Byte range of the first occurrence of [span] in [text].
ByteSlice _rangeOf(String text, String span) {
  final charStart = text.indexOf(span);
  if (charStart == -1) {
    throw ArgumentError('"$span" not found in "$text"');
  }
  final byteStart = utf8.encode(text.substring(0, charStart)).length;
  return ByteSlice(
    byteStart: byteStart,
    byteEnd: byteStart + utf8.encode(span).length,
  );
}

RichTextFacet _facet(ByteSlice range, List<FacetFeature> features) =>
    RichTextFacet(index: range, features: features);

RichTextFacet _place(String text, String span, int index) =>
    _facet(_rangeOf(text, span), [ImageFacetFeature(index: index)]);

List<int> _placedIndices(ImageLayout layout) =>
    layout.placed.map((p) => p.index).toList();

List<String> _galleryUrls(ImageLayout layout) =>
    layout.gallery.map((i) => i.fullsize).toList();

void main() {
  group('imageLayout placements', () {
    test('placements come out in body order, not facet-array order', () {
      const text = 'First [a] then [b] end';
      final layout = imageLayout(_imagesEmbed(), text, [
        _place(text, '[b]', 2),
        _place(text, '[a]', 0),
      ]);

      expect(_placedIndices(layout), [0, 2]);
      expect(layout.placed.map((p) => p.image.fullsize).toList(), [
        _full0,
        _full2,
      ]);
      expect(layout.placed.map((p) => p.range).toList(), [
        _rangeOf(text, '[a]'),
        _rangeOf(text, '[b]'),
      ]);
      expect(_galleryUrls(layout), [_full1]);
    });

    test('a repeated index is placed once, at its first body position', () {
      const text = '[a]\n\n[b]\n\nend';
      final layout = imageLayout(_imagesEmbed(), text, [
        _place(text, '[b]', 0),
        _place(text, '[a]', 0),
      ]);

      expect(_placedIndices(layout), [0]);
      expect(layout.placed.single.range, _rangeOf(text, '[a]'));
      expect(_galleryUrls(layout), [_full1, _full2]);
    });

    test('imagesWithAttachment main images lay out the same way', () {
      const text = 'Look [a] here';
      final embed = ImagesWithAttachmentPostEmbed(
        type: 'social.coves.embed.imagesWithAttachment#view',
        images: _threeImages(),
        data: const {},
      );
      final layout = imageLayout(embed, text, [_place(text, '[a]', 1)]);

      expect(_placedIndices(layout), [1]);
      expect(_galleryUrls(layout), [_full0, _full2]);
    });
  });

  group('imageLayout guards', () {
    // Every row also carries a valid placement of image 0 over "[a]", so the
    // expected result is always: placed [0], gallery [image1, image2].
    const text = '[a]\n\n[b]\n\nCafé\n\ncode [c] here\n\nblock [d] here\n\nend';
    final textBytes = utf8.encode(text).length;
    final cafeStart = _rangeOf(text, 'Café').byteStart;
    final bStart = _rangeOf(text, '[b]').byteStart;

    final rows = <String, List<RichTextFacet>>{
      'index out of range (5 with 3 images)': [_place(text, '[b]', 5)],
      'image plus another feature in the same facet': [
        _facet(_rangeOf(text, '[b]'), const [
          ImageFacetFeature(index: 1),
          BoldFacetFeature(),
        ]),
      ],
      'empty range': [
        _facet(ByteSlice(byteStart: bStart, byteEnd: bStart), const [
          ImageFacetFeature(index: 1),
        ]),
      ],
      'range past the end of the text': [
        _facet(ByteSlice(byteStart: textBytes - 3, byteEnd: textBytes + 4), [
          const ImageFacetFeature(index: 1),
        ]),
      ],
      'range splitting a multi-byte character': [
        // "Caf" plus the first byte of the two-byte "é"
        _facet(ByteSlice(byteStart: cafeStart, byteEnd: cafeStart + 4), [
          const ImageFacetFeature(index: 1),
        ]),
      ],
      'inside a #code range': [
        _facet(_rangeOf(text, 'code [c] here'), const [CodeFacetFeature()]),
        _place(text, '[c]', 1),
      ],
      'inside a #codeBlock range': [
        _facet(_rangeOf(text, 'block [d] here'), const [
          CodeBlockFacetFeature(),
        ]),
        _place(text, '[d]', 1),
      ],
    };

    for (final MapEntry(key: name, value: bad) in rows.entries) {
      test('rejects: $name', () {
        final layout = imageLayout(_imagesEmbed(), text, [
          _place(text, '[a]', 0),
          ...bad,
        ]);

        expect(_placedIndices(layout), [0]);
        expect(_galleryUrls(layout), [_full1, _full2]);
      });
    }
  });

  group('imageLayout block-structure guards', () {
    // Each row has one placement the renderer cannot draw where its facet
    // sits. It must fall back to the gallery, and every image stays in
    // exactly one of placed or gallery.
    final rows = <String, (String, List<RichTextFacet> Function(String), int)>{
      '(a) inside a #heading line': (
        'Title [b] here\n\nend',
        (t) => [
          _facet(_rangeOf(t, 'Title [b] here'), const [
            HeadingFacetFeature(level: 1),
          ]),
          _place(t, '[b]', 1),
        ],
        1,
      ),
      '(a) the same range as a #heading': (
        '[b]\n\nend',
        (t) => [
          _facet(_rangeOf(t, '[b]'), const [HeadingFacetFeature(level: 1)]),
          _place(t, '[b]', 1),
        ],
        1,
      ),
      '(b) straddling a #blockquote boundary': (
        'Quoted\n[b]\nmore\n\nend',
        (t) => [
          _facet(_rangeOf(t, 'Quoted\n[b]'), const [BlockquoteFacetFeature()]),
          _place(t, '[b]\nmore', 1),
        ],
        1,
      ),
      '(c) overlapping an earlier placement': (
        '[bc]\n\nend',
        (t) => [_place(t, '[bc]', 1), _place(t, 'c]', 2)],
        2,
      ),
      '(d) the same line as a mid-line #codeBlock': (
        'see [b] then code\n\nend',
        (t) => [
          _facet(_rangeOf(t, 'code'), const [CodeBlockFacetFeature()]),
          _place(t, '[b]', 1),
        ],
        1,
      ),
      '(d) the same line as a mid-line #heading': (
        'see [b] then title\n\nend',
        (t) => [
          _facet(_rangeOf(t, 'title'), const [HeadingFacetFeature(level: 1)]),
          _place(t, '[b]', 1),
        ],
        1,
      ),
      '(e) starting on the newline that ends the previous placement': (
        'A\nB',
        (t) => [
          _facet(const ByteSlice(byteStart: 0, byteEnd: 1), const [
            ImageFacetFeature(index: 1),
          ]),
          _facet(const ByteSlice(byteStart: 1, byteEnd: 3), const [
            ImageFacetFeature(index: 2),
          ]),
        ],
        2,
      ),
    };

    for (final MapEntry(key: name, value: (text, facets, rejected))
        in rows.entries) {
      test('falls back to the gallery: $name', () {
        final layout = imageLayout(_imagesEmbed(), text, facets(text));

        expect(_placedIndices(layout), isNot(contains(rejected)));
        expect(
          _galleryUrls(layout),
          contains(_threeImages()[rejected].fullsize),
        );
        expect(
          {
            ...layout.placed.map((p) => p.image.fullsize),
            ..._galleryUrls(layout),
          },
          {_full0, _full1, _full2},
        );
        expect(layout.placed.length + layout.gallery.length, 3);
      });
    }

    test('two placements over the same range place one image', () {
      const text = '[b]\n\nend';
      final layout = imageLayout(_imagesEmbed(), text, [
        _place(text, '[b]', 1),
        _place(text, '[b]', 2),
      ]);

      expect(layout.placed, hasLength(1));
      expect(layout.gallery, hasLength(2));
    });

    test('a placement fully inside a #blockquote is still accepted', () {
      const text = 'Quoted\n[b]\n\nend';
      final layout = imageLayout(_imagesEmbed(), text, [
        _facet(_rangeOf(text, 'Quoted\n[b]'), const [BlockquoteFacetFeature()]),
        _place(text, '[b]', 1),
      ]);

      expect(_placedIndices(layout), [1]);
    });
  });

  group('imageLayout without placements', () {
    test('no facets puts every image in the gallery; no images, nothing', () {
      const text = 'First [a] end';

      for (final facets in <List<RichTextFacet>?>[null, const []]) {
        final layout = imageLayout(_imagesEmbed(), text, facets);
        expect(_placedIndices(layout), isEmpty, reason: 'facets $facets');
        expect(_galleryUrls(layout), [
          _full0,
          _full1,
          _full2,
        ], reason: 'facets $facets');
      }

      final facets = [_place(text, '[a]', 0)];
      final nonImageEmbeds = <String, PostEmbed?>{
        'null embed': null,
        'video embed': const VideoPostEmbed(
          type: 'social.coves.embed.video#view',
          video: 'https://cdn.test/v.mp4',
          data: {},
        ),
      };
      for (final MapEntry(key: name, value: embed) in nonImageEmbeds.entries) {
        final layout = imageLayout(embed, text, facets);
        expect(layout.placed, isEmpty, reason: name);
        expect(layout.gallery, isEmpty, reason: name);
      }
    });
  });

  group('placements and combined block facets', () {
    test('a quote sharing a facet with a heading still makes the heading '
        'line refuse a placement', () {
      const text = 'Title [a]\nbody';
      final layout = imageLayout(_imagesEmbed(), text, [
        _facet(_rangeOf(text, 'Title [a]'), [
          const BlockquoteFacetFeature(),
          const HeadingFacetFeature(level: 2),
        ]),
        _place(text, '[a]', 0),
      ]);

      expect(_placedIndices(layout), isEmpty);
      expect(_galleryUrls(layout), [_full0, _full1, _full2]);
    });
  });

  group('placements survive editing a comment', () {
    test('a placement over the same text as a spoiler is serialized as its '
        'own facet and still placed', () {
      const text = 'See [a] here';
      final facets = [
        _facet(_rangeOf(text, '[a]'), [const SpoilerFacetFeature()]),
        _place(text, '[a]', 0),
      ];
      final controller = FacetEditingController.fromRecord(text, facets);
      addTearDown(controller.dispose);

      final serialized = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
        featureRanges: controller.featureRanges,
      );

      expect(
        serialized.facets.where(
          (facet) => facet.features.any((f) => f is ImageFacetFeature),
        ),
        everyElement(
          predicate<RichTextFacet>((facet) => facet.features.length == 1),
        ),
      );
      final layout = imageLayout(
        _imagesEmbed(),
        serialized.content,
        serialized.facets,
      );
      expect(_placedIndices(layout), [0]);
      expect(layout.placed.single.spoilered, isTrue);
      expect(
        serialized.codeRanges,
        contains(const TextRange(start: 4, end: 7)),
        reason: 'covered text is kept out of link and mention detection',
      );
    });
  });

  test('typing inside a placement\'s covered text drops the placement, so '
      'the typed words are not hidden under the image', () {
    const text = 'See [a] here';
    final controller = FacetEditingController.fromRecord(text, [
      _place(text, '[a]', 0),
    ]);
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'See [ab] here',
      selection: TextSelection.collapsed(offset: 7),
    );

    expect(
      controller.featureRanges.where((r) => r.feature is ImageFacetFeature),
      isEmpty,
    );
    final serialized = serializeFormatting(
      controller.text,
      featureRanges: controller.featureRanges,
    );
    final layout = imageLayout(
      _imagesEmbed(),
      serialized.content,
      serialized.facets,
    );
    expect(_placedIndices(layout), isEmpty);
    expect(_galleryUrls(layout), contains(_full0));
  });
}
