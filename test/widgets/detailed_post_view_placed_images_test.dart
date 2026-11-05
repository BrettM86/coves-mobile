import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _galleryKey = Key('detail-images-embed');
const _block0Key = Key('rich-text-image-0');
const _block1Key = Key('rich-text-image-1');

const _full0 = 'https://cdn.test/f0.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';

const _text = 'Intro\n\n[image]\n\nHarbor at dusk\n\nOutro';

/// Image 0: no aspectRatio, alt "Boat". Image 1: 2:1, alt "Harbor at dusk".
/// Image 2: plain.
PostEmbed _threeImages() => PostEmbed.fromJson({
  r'$type': 'social.coves.embed.images#view',
  'images': [
    {'thumb': 'https://cdn.test/t0.jpg', 'fullsize': _full0, 'alt': 'Boat'},
    {
      'thumb': 'https://cdn.test/t1.jpg',
      'fullsize': _full1,
      'alt': 'Harbor at dusk',
      'aspectRatio': {'width': 1600, 'height': 800},
    },
    {'thumb': 'https://cdn.test/t2.jpg', 'fullsize': _full2},
  ],
});

RichTextFacet _place(String span, int index, {String text = _text}) {
  final charStart = text.indexOf(span);
  final byteStart = utf8.encode(text.substring(0, charStart)).length;
  return RichTextFacet(
    index: ByteSlice(
      byteStart: byteStart,
      byteEnd: byteStart + utf8.encode(span).length,
    ),
    features: [ImageFacetFeature(index: index)],
  );
}

FeedViewPost _post(
  List<RichTextFacet>? facets, {
  String text = _text,
  bool sensitive = false,
}) => FeedViewPost(
  post: PostView(
    uri: 'at://did:example/post/123',
    cid: 'cid123',
    rkey: '123',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
    createdAt: DateTime(2024),
    indexedAt: DateTime(2024),
    record: PostRecord(
      title: 'Test Post Title',
      content: text,
      facets: facets,
      labels: sensitive ? const ['nsfw'] : const [],
    ),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    embed: _threeImages(),
  ),
);

Future<void> _pumpDetail(WidgetTester tester, FeedViewPost post) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Provider<StreamableService>.value(
      value: StreamableService(),
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailedPostView(
              // A fresh state per post, so a second pump re-lays out
              key: ObjectKey(post),
              post: post,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _bodyText(String text) => find.textContaining(text, findRichText: true);

List<String> _imageUrlsIn(WidgetTester tester, Finder scope) => tester
    .widgetList<CachedNetworkImage>(
      find.descendant(of: scope, matching: find.byType(CachedNetworkImage)),
    )
    .map((image) => image.imageUrl)
    .toList();

const _viewerKey = Key('image-viewer');

/// The open viewer's page dots, showing page [index] (zero-based) of
/// [count].
Finder _viewerPage({required int index, required int count}) => find.descendant(
  of: find.byKey(const Key('image-viewer-page-indicator')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is MediaPageDots &&
        widget.index == index &&
        widget.count == count,
  ),
);

/// The fullsize URL shown in the viewer's on-screen page.
String _viewerImageUrl(WidgetTester tester) => tester
    .widget<CachedNetworkImage>(
      find
          .descendant(
            of: find.byKey(const Key('image-viewer-image-slot')),
            matching: find.byType(CachedNetworkImage),
          )
          .first,
    )
    .imageUrl;

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('placed images render as blocks in the body; the rest of the '
      'gallery sits above the body', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDetail(
      tester,
      _post([_place('[image]', 0), _place('Harbor at dusk', 1)]),
    );

    final block0 = find.byKey(_block0Key);
    final block1 = find.byKey(_block1Key);
    expect(block0, findsOneWidget);
    expect(block1, findsOneWidget);

    // Between "Intro" and "Outro"
    final introBottom = tester.getBottomLeft(_bodyText('Intro')).dy;
    final outroTop = tester.getTopLeft(_bodyText('Outro')).dy;
    for (final block in [block0, block1]) {
      expect(tester.getTopLeft(block).dy, greaterThanOrEqualTo(introBottom));
      expect(tester.getBottomLeft(block).dy, lessThanOrEqualTo(outroTop));
    }

    expect(_imageUrlsIn(tester, block0), [_full0]);
    expect(_imageUrlsIn(tester, block1), [_full1]);

    // Missing aspectRatio falls back to 4:3; image 1 keeps its 2:1
    final size0 = tester.getSize(block0);
    final size1 = tester.getSize(block1);
    expect(size0.width / size0.height, closeTo(4 / 3, 0.01));
    expect(size1.width / size1.height, closeTo(2, 0.01));

    final bodyWidth = tester.getSize(find.byType(RichTextRenderer)).width;
    expect(size0.width, lessThanOrEqualTo(bodyWidth));
    expect(size1.width, lessThanOrEqualTo(bodyWidth));

    expect(
      find.descendant(
        of: block0,
        matching: find.bySemanticsLabel(RegExp('Boat')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: block1,
        matching: find.bySemanticsLabel(RegExp('Harbor at dusk')),
      ),
      findsOneWidget,
    );

    // The unplaced image 2 alone, above the body
    final gallery = find.byKey(_galleryKey);
    expect(gallery, findsOneWidget);
    expect(
      tester.getBottomLeft(gallery).dy,
      lessThanOrEqualTo(tester.getTopLeft(_bodyText('Intro')).dy),
    );
    expect(_imageUrlsIn(tester, gallery), [_full2]);
    semantics.dispose();
  });

  testWidgets('the gallery sits above the body without placements and is '
      'absent when every image is placed', (tester) async {
    await _pumpDetail(tester, _post(null));

    final gallery = find.byKey(_galleryKey);
    expect(gallery, findsOneWidget);
    expect(
      tester.getBottomLeft(gallery).dy,
      lessThanOrEqualTo(tester.getTopLeft(_bodyText('Intro')).dy),
    );

    await _pumpDetail(
      tester,
      _post([
        _place('Intro', 2),
        _place('[image]', 0),
        _place('Harbor at dusk', 1),
      ]),
    );

    expect(find.byKey(_galleryKey), findsNothing);
  });

  testWidgets('B4 with one placed and two unplaced images the gallery leads '
      'the post and the lightbox follows screen order', (tester) async {
    await _pumpDetail(tester, _post([_place('[image]', 0)]));

    final gallery = find.byKey(_galleryKey);
    final placed = find.byKey(_block0Key);
    expect(gallery, findsOneWidget);
    expect(placed, findsOneWidget);
    final galleryBottom = tester.getBottomLeft(gallery).dy;
    expect(
      galleryBottom,
      lessThanOrEqualTo(tester.getTopLeft(_bodyText('Intro')).dy),
    );
    expect(galleryBottom, lessThanOrEqualTo(tester.getTopLeft(placed).dy));

    final galleryDots = find.descendant(
      of: find.byKey(const Key('detail-images-page-indicator')),
      matching: find.byType(MediaPageDots),
      matchRoot: true,
    );
    expect(galleryDots, findsOneWidget);
    expect(tester.widget<MediaPageDots>(galleryDots).count, 2);
    expect(tester.widget<MediaPageDots>(galleryDots).index, 0);

    await _tapVisible(tester, gallery);
    expect(_viewerPage(index: 0, count: 3), findsOneWidget);
    expect(_viewerImageUrl(tester), _full1);

    await tester.tap(
      find.descendant(
        of: find.byKey(_viewerKey),
        matching: find.byTooltip('Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_viewerKey), findsNothing);

    await _tapVisible(tester, placed);
    expect(_viewerPage(index: 2, count: 3), findsOneWidget);
    expect(_viewerImageUrl(tester), _full0);
  });

  group('lightbox order', () {
    const text = 'Intro\n\n[two]\n\nMiddle\n\n[zero]\n\nOutro';
    // Body places image 2 before image 0; image 1 stays in the gallery
    final post = _post([
      _place('[two]', 2, text: text),
      _place('[zero]', 0, text: text),
    ], text: text);

    testWidgets('a placed image opens at its body position after the '
        'gallery, then pages back through the body', (tester) async {
      await _pumpDetail(tester, post);

      await _tapVisible(tester, find.byKey(_block0Key));

      expect(find.byKey(_viewerKey), findsOneWidget);
      expect(_viewerPage(index: 2, count: 3), findsOneWidget);
      expect(_viewerImageUrl(tester), _full0);

      await tester.fling(
        find.descendant(
          of: find.byKey(_viewerKey),
          matching: find.byType(PageView),
        ),
        // A short fling: one page back on a 400-wide surface
        const Offset(150, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(_viewerPage(index: 1, count: 3), findsOneWidget);
      expect(_viewerImageUrl(tester), _full2);
    });

    testWidgets('the gallery opens first, before the placed images', (
      tester,
    ) async {
      await _pumpDetail(tester, post);

      await _tapVisible(tester, find.byKey(_galleryKey));

      expect(find.byKey(_viewerKey), findsOneWidget);
      expect(_viewerImageUrl(tester), _full1);

      await tester.fling(
        find.descendant(
          of: find.byKey(_viewerKey),
          matching: find.byType(PageView),
        ),
        // A short fling: one page on a 400-wide surface
        const Offset(-150, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(
        _viewerImageUrl(tester),
        _full2,
        reason:
            'after the gallery the viewer pages on to the first placed '
            'image',
      );
      expect(_viewerPage(index: 1, count: 3), findsOneWidget);
    });
  });

  group('lightbox with a spoilered placement', () {
    const text = 'Intro\n\n[zero]\n\nSecret\n[two]\n\nOutro';
    RichTextFacet spoiler() {
      const span = 'Secret\n[two]';
      final byteStart = utf8
          .encode(text.substring(0, text.indexOf(span)))
          .length;
      return RichTextFacet(
        index: ByteSlice(
          byteStart: byteStart,
          byteEnd: byteStart + utf8.encode(span).length,
        ),
        features: const [SpoilerFacetFeature()],
      );
    }

    final post = _post([
      _place('[zero]', 0, text: text),
      spoiler(),
      _place('[two]', 2, text: text),
    ], text: text);

    Future<void> revealSpoiler(WidgetTester tester) async {
      final secret = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text
                .toPlainText(includeSemanticsLabels: false)
                .contains('Secret'),
      );
      await tester.ensureVisible(secret);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(secret) + const Offset(4, 4));
      await tester.pumpAndSettle();
    }

    testWidgets('an unrevealed placement is left out of the sequence', (
      tester,
    ) async {
      await _pumpDetail(tester, post);

      await _tapVisible(tester, find.byKey(_block0Key));
      expect(_viewerPage(index: 1, count: 2), findsOneWidget);
      expect(_viewerImageUrl(tester), _full0);
    });

    testWidgets('the gallery never pages to a spoilered placement', (
      tester,
    ) async {
      await _pumpDetail(tester, post);

      await _tapVisible(tester, find.byKey(_galleryKey));
      expect(_viewerPage(index: 0, count: 2), findsOneWidget);
      expect(_viewerImageUrl(tester), _full1);
    });

    testWidgets('once revealed, the body pages to it in screen order', (
      tester,
    ) async {
      await _pumpDetail(tester, post);
      await revealSpoiler(tester);

      await _tapVisible(tester, find.byKey(const Key('rich-text-image-2')));
      expect(_viewerPage(index: 2, count: 3), findsOneWidget);
      expect(_viewerImageUrl(tester), _full2);
    });
  });

  testWidgets('an NSFW post with every image placed is concealed behind the '
      'sensitive placeholder', (tester) async {
    final facets = [
      _place('Intro', 2),
      _place('[image]', 0),
      _place('Harbor at dusk', 1),
    ];

    await _pumpDetail(tester, _post(facets));
    expect(find.byKey(_block0Key), findsOneWidget);

    await _pumpDetail(tester, _post(facets, sensitive: true));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('sensitive-image-placeholder')),
      findsOneWidget,
    );
    expect(find.byKey(_block0Key), findsNothing);
  });
}
