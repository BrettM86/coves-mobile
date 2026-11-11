import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/image_layout.dart';
import 'package:coves_flutter/widgets/media/gif_codec.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_gif_codec.dart';
import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/theme_pump.dart';

/// Facet over the first occurrence of [span] in [text], with byte offsets.
RichTextFacet _facetOver(
  String text,
  String span,
  List<FacetFeature> features,
) {
  final charStart = text.indexOf(span);
  if (charStart == -1) {
    throw ArgumentError('"$span" not found in "$text"');
  }
  final byteStart = utf8.encode(text.substring(0, charStart)).length;
  return RichTextFacet(
    index: ByteSlice(
      byteStart: byteStart,
      byteEnd: byteStart + utf8.encode(span).length,
    ),
    features: features,
  );
}

PostEmbed _oneImage() => ImagesPostEmbed(
  type: 'social.coves.embed.images#view',
  images: const [
    EmbedImage(
      thumb: 'https://cdn.test/t0.jpg',
      fullsize: 'https://cdn.test/f0.jpg',
    ),
  ],
  data: const {},
);

PostEmbed _threeImages() => ImagesPostEmbed(
  type: 'social.coves.embed.images#view',
  images: const [
    EmbedImage(
      thumb: 'https://cdn.test/t0.jpg',
      fullsize: 'https://cdn.test/f0.jpg',
    ),
    EmbedImage(
      thumb: 'https://cdn.test/t1.jpg',
      fullsize: 'https://cdn.test/f1.jpg',
    ),
    EmbedImage(
      thumb: 'https://cdn.test/t2.jpg',
      fullsize: 'https://cdn.test/f2.jpg',
    ),
  ],
  data: const {},
);

/// Pumps a compact (feed preview) renderer laid out with [_oneImage].
Future<void> _pumpPreview(
  WidgetTester tester,
  String text,
  List<RichTextFacet> facets, {
  PostEmbed? embed,
}) {
  return pumpUnderAppTheme(
    tester,
    RichTextRenderer(
      text: text,
      facets: facets,
      images: imageLayout(embed ?? _oneImage(), text, facets),
      maxLines: 5,
    ),
  );
}

RichText _previewText(WidgetTester tester) => tester.widget<RichText>(
  find.descendant(
    of: find.byType(RichTextRenderer),
    matching: find.byType(RichText),
  ),
);

/// Pumps a full-mode (detail) renderer laid out with [_oneImage] on a phone
/// surface, scrollable so a tall image block cannot overflow.
Future<void> _pumpFull(
  WidgetTester tester,
  String text,
  List<RichTextFacet> facets, {
  PostEmbed? embed,
}) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return pumpUnderAppTheme(
    tester,
    SingleChildScrollView(
      child: RichTextRenderer(
        // A fresh state per pump, so a second pump starts unrevealed
        key: UniqueKey(),
        text: text,
        facets: facets,
        images: imageLayout(embed ?? _oneImage(), text, facets),
      ),
    ),
  );
}

const _block0Key = Key('rich-text-image-0');

Finder _bodyText(String text) => find.textContaining(text, findRichText: true);

/// Matches the blockquote left-bar container used by the renderer
bool _hasLeftBar(Widget w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).border is Border &&
    ((w.decoration! as BoxDecoration).border! as Border).left.width == 3;

Finder _fullsize0() => find.byWidgetPredicate(
  (w) => w is CachedNetworkImage && w.imageUrl == 'https://cdn.test/f0.jpg',
);

void main() {
  group('compact preview with placed images', () {
    testWidgets('leaves out a valid placement and its blank line, keeps a '
        'rejected one', (tester) async {
      const text = 'Intro\n\n[image]\n\nOutro';

      await _pumpPreview(tester, text, [
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
      ]);
      expect(_previewText(tester).text.toPlainText(), 'Intro\n\nOutro');

      // Index 3 does not resolve against a one-image embed
      await _pumpPreview(tester, text, [
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 3)]),
      ]);
      expect(
        _previewText(tester).text.toPlainText(),
        'Intro\n\n[image]\n\nOutro',
      );
    });

    testWidgets('consecutive placements leave one paragraph break between '
        'the kept text', (tester) async {
      final previews = <String, String>{
        'Intro\n\n[a]\n\n[b]\n\nOutro': 'Intro\n\nOutro',
        '[a]\n\n[b]\n\nOutro': 'Outro',
        'Intro\n\n[a]\n\n[b]': 'Intro',
      };
      for (final MapEntry(key: text, value: preview) in previews.entries) {
        await _pumpPreview(tester, text, [
          _facetOver(text, '[a]', const [ImageFacetFeature(index: 0)]),
          _facetOver(text, '[b]', const [ImageFacetFeature(index: 1)]),
        ], embed: _threeImages());
        expect(_previewText(tester).text.toPlainText(), preview, reason: text);
      }
    });

    testWidgets('keeps a later spoiler on the right text after multi-byte '
        'characters', (tester) async {
      const text = 'Café ☕\n\n[image]\n\nThe end is a secret';

      await _pumpPreview(tester, text, [
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
        _facetOver(text, 'secret', const [SpoilerFacetFeature()]),
      ]);

      final span = _previewText(tester).text;
      expect(
        span.toPlainText(includeSemanticsLabels: false),
        'Café ☕\n\nThe end is a xxxxxx',
      );

      final concealed = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text != null &&
            child.style?.color == Colors.transparent) {
          concealed.add(child.text!);
        }
        return true;
      });
      // The placeholder covers exactly the six characters of "secret"
      expect(concealed, ['xxxxxx']);
    });
  });

  group('full mode with placed images', () {
    testWidgets('a placement inside a blockquote renders inside the quote', (
      tester,
    ) async {
      const text = 'Plain\n\nQuoted\n[image]';

      await _pumpFull(tester, text, [
        _facetOver(text, 'Quoted\n[image]', const [BlockquoteFacetFeature()]),
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
      ]);

      final block = find.byKey(_block0Key);
      expect(block, findsOneWidget);
      expect(
        find.ancestor(of: block, matching: find.byWidgetPredicate(_hasLeftBar)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(block).dx,
        greaterThan(tester.getTopLeft(_bodyText('Plain')).dx),
      );
    });

    testWidgets('a placement inside a spoiler stays hidden until the spoiler '
        'is revealed', (tester) async {
      const text = 'Secret\n\n[image]\n\nOutro';
      final placement = _facetOver(text, '[image]', const [
        ImageFacetFeature(index: 0),
      ]);

      // Without the spoiler the image renders
      await _pumpFull(tester, text, [placement]);
      expect(find.byKey(_block0Key), findsOneWidget);

      await _pumpFull(tester, text, [
        _facetOver(text, 'Secret\n\n[image]', const [SpoilerFacetFeature()]),
        placement,
      ]);
      expect(find.byKey(_block0Key), findsNothing);
      expect(_fullsize0(), findsNothing);

      // Hidden "Secret" renders as its placeholder glyphs, never the real
      // text. Its semantics label stands in for the text, so match glyphs.
      Finder bodyGlyphs(String glyphs) => find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText(includeSemanticsLabels: false).contains(glyphs),
      );
      expect(bodyGlyphs('Secret'), findsNothing);
      final secret = bodyGlyphs('xxxxxx');
      await tester.tapAt(tester.getTopLeft(secret) + const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(bodyGlyphs('Secret'), findsOneWidget);
      expect(bodyGlyphs('xxxxxx'), findsNothing);
      expect(find.byKey(_block0Key), findsOneWidget);
      expect(_fullsize0(), findsOneWidget);
    });

    testWidgets('a mid-line placement keeps the text on both sides', (
      tester,
    ) async {
      const text = 'Before [image] after';

      await _pumpFull(tester, text, [
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
      ]);

      expect(find.byKey(_block0Key), findsOneWidget);
      expect(_bodyText('Before'), findsOneWidget);
      expect(_bodyText('after'), findsOneWidget);
    });

    testWidgets('every accepted placement is drawn as an image block', (
      tester,
    ) async {
      const text = 'Title [h]\n\nQuoted\n[q]\nmore\n\n[s]\n\nend';
      final facets = [
        _facetOver(text, 'Title [h]', const [HeadingFacetFeature(level: 1)]),
        _facetOver(text, '[h]', const [ImageFacetFeature(index: 0)]),
        _facetOver(text, 'Quoted\n[q]', const [BlockquoteFacetFeature()]),
        _facetOver(text, '[q]\nmore', const [ImageFacetFeature(index: 1)]),
        _facetOver(text, '[s]', const [ImageFacetFeature(index: 2)]),
      ];
      final layout = imageLayout(_threeImages(), text, facets);
      expect(layout.placed, isNotEmpty);

      await _pumpFull(tester, text, facets, embed: _threeImages());

      for (final placement in layout.placed) {
        expect(
          find.byKey(Key('rich-text-image-${placement.index}')),
          findsOneWidget,
          reason: 'placed image ${placement.index}',
        );
      }
    });

    testWidgets('a rejected multi-feature facet over the same range does not '
        'break an accepted placement', (tester) async {
      const text = 'Intro\n\n[image]\n\nEnd';

      await _pumpFull(tester, text, [
        _facetOver(text, '[image]', const [
          ImageFacetFeature(index: 0),
          BoldFacetFeature(),
        ]),
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.byKey(_block0Key), findsOneWidget);
    });

    testWidgets('a second placement of the same image renders as plain text', (
      tester,
    ) async {
      const text = 'Top\n\n[first]\n\n[second]\n\nEnd';

      await _pumpFull(tester, text, [
        _facetOver(text, '[first]', const [ImageFacetFeature(index: 0)]),
        _facetOver(text, '[second]', const [ImageFacetFeature(index: 0)]),
      ]);

      expect(find.byKey(_block0Key), findsOneWidget);
      expect(_bodyText('[second]'), findsOneWidget);
    });
  });

  group('B5 a placed GIF', () {
    late FakeGifFrames frames;

    setUpAll(() async {
      frames = await FakeGifFrames.create();
    });

    tearDownAll(() => frames.dispose());

    testWidgets('shows Play GIF over the thumb; play loads fullsize in place '
        'and opens no viewer', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const gifThumb = 'https://cdn.test/cat-thumb.jpg';
      const gifFull = 'https://cdn.test/cat-full.gif';
      const text = 'Intro\n\n[image]\n\nOutro';
      final facets = [
        _facetOver(text, '[image]', const [ImageFacetFeature(index: 0)]),
      ];
      final embed = ImagesPostEmbed(
        type: 'social.coves.embed.images#view',
        images: const [
          EmbedImage(thumb: gifThumb, fullsize: gifFull, isGif: true),
        ],
        data: const {},
      );
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));

      await pumpUnderAppTheme(
        tester,
        GifCodecScope(
          loader: loader.load,
          child: ImageCacheScope(
            cacheManager: FakeImageCacheManager(),
            child: SingleChildScrollView(
              child: RichTextRenderer(
                text: text,
                facets: facets,
                images: imageLayout(embed, text, facets),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final playGif = find.descendant(
        of: find.byKey(_block0Key),
        matching: find.bySemanticsLabel('Play GIF'),
      );
      expect(playGif, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CachedNetworkImage && w.imageUrl == gifFull,
        ),
        findsNothing,
      );

      await tester.tap(playGif);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(loader.requests, [gifFull]);
      expect(find.byKey(gifFrameKey), findsOneWidget);
      expect(find.byKey(const Key('image-viewer')), findsNothing);
    });
  });
}
