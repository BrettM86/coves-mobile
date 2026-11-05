// B7: a CommentCard renders its unplaced images as a swipeable gallery with
// page dots after the body text; a tap opens the viewer at the current page,
// alt text reaches semantics, an empty-bodied comment still shows its image,
// and a comment's NSFW label never conceals its images.
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/media/gif_codec.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_gif_codec.dart';
import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/test_mocks.dart';

const _gridKey = Key('comment-images-grid');
const _galleryKey = Key('comment-images-embed');
const _pageIndicatorKey = Key('comment-images-page-indicator');
const _viewerKey = Key('image-viewer');
const _viewerIndicatorKey = Key('image-viewer-page-indicator');

const _body = 'Here are the photos from the meetup';
const _alt = 'A crowd gathered around a long wooden table';

const _sixImages = [
  EmbedImage(
    thumb: 'https://cdn.test/t1.jpg',
    fullsize: 'https://cdn.test/f1.jpg',
    alt: _alt,
  ),
  EmbedImage(
    thumb: 'https://cdn.test/t2.jpg',
    fullsize: 'https://cdn.test/f2.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/t3.jpg',
    fullsize: 'https://cdn.test/f3.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/t4.jpg',
    fullsize: 'https://cdn.test/f4.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/t5.jpg',
    fullsize: 'https://cdn.test/f5.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/t6.jpg',
    fullsize: 'https://cdn.test/f6.jpg',
  ),
];

const _nsfwModeration = ModerationView(
  state: ModerationState.clear,
  contentLabels: [ContentLabelView(value: 'nsfw')],
);

Map<String, dynamic> _rawEmbed(List<EmbedImage> images) => {
  r'$type': 'social.coves.embed.images#view',
  'images': [
    for (final image in images)
      {
        'thumb': image.thumb,
        'fullsize': image.fullsize,
        if (image.alt != null) 'alt': image.alt,
      },
  ],
};

/// The raw embed plus the parsed one, built directly so a failure here is
/// about rendering, not parsing.
CommentView _comment({
  required List<EmbedImage> images,
  String content = _body,
  List<RichTextFacet>? facets,
  ModerationView? moderation,
}) {
  return CommentView(
    uri: 'at://did:plc:author/social.coves.community.comment/c1',
    cid: 'cid-c1',
    record: CommentRecord(content: content, facets: facets),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    author: AuthorView(did: 'did:plc:author', handle: 'commenter.test'),
    post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
    stats: const CommentStats(upvotes: 5, downvotes: 1, score: 4),
    embed: _rawEmbed(images),
    parsedEmbed: ImagesPostEmbed(
      type: 'social.coves.embed.images#view',
      images: images,
      data: _rawEmbed(images),
    ),
    moderation: moderation,
  );
}

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late BlockProvider blockProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    blockProvider = BlockProvider(
      apiService: MockCovesApiService(),
      authProvider: mockAuthProvider,
    );

    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
  });

  /// A phone-sized surface so the grid has room under the comment body.
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpCard(
    WidgetTester tester,
    CommentView comment, {
    FakeGifCodecLoader? gifLoader,
  }) async {
    usePhoneSurface(tester);
    Widget app = MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CommentCard(comment: comment, sessionStamp: null),
        ),
      ),
    );
    if (gifLoader != null) {
      app = GifCodecScope(
        loader: gifLoader.load,
        child: ImageCacheScope(
          cacheManager: FakeImageCacheManager(),
          child: app,
        ),
      );
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
          ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
        ],
        child: app,
      ),
    );
    await tester.pump();
  }

  /// The dots inside the indicator keyed [indicatorKey].
  MediaPageDots dots(WidgetTester tester, Key indicatorKey) {
    final finder = find.descendant(
      of: find.byKey(indicatorKey),
      matching: find.byType(MediaPageDots),
      matchRoot: true,
    );
    expect(finder, findsOneWidget, reason: '$indicatorKey should hold dots');
    return tester.widget<MediaPageDots>(finder);
  }

  /// The url of the image under the centre of the comment gallery: the page
  /// the user is looking at.
  String visibleGalleryUrl(WidgetTester tester) {
    final centre = tester.getRect(find.byKey(_galleryKey)).center;
    final visible = find
        .descendant(
          of: find.byKey(_galleryKey),
          matching: find.byType(CachedNetworkImage),
        )
        .evaluate()
        .where((element) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          return rect.contains(centre);
        })
        .toList();
    expect(visible, hasLength(1), reason: 'one page fills the gallery');
    return (visible.single.widget as CachedNetworkImage).imageUrl;
  }

  group('CommentCard images gallery', () {
    testWidgets(
      'B7 six images show a swipeable gallery after the body text with page '
      'dots and no grid',
      (tester) async {
        await pumpCard(tester, _comment(images: _sixImages));

        expect(find.byKey(_galleryKey), findsOneWidget);
        expect(dots(tester, _pageIndicatorKey).count, 6);
        expect(dots(tester, _pageIndicatorKey).index, 0);
        expect(visibleGalleryUrl(tester), 'https://cdn.test/t1.jpg');
        expect(
          tester.getTopLeft(find.byKey(_galleryKey)).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.text(_body)).dy),
          reason: 'the gallery sits after the body text',
        );
        expect(find.byKey(_gridKey), findsNothing);
        expect(find.text('+2'), findsNothing);
      },
    );

    testWidgets(
      'B7 a drag pages the gallery and a tap opens the viewer over all six '
      'at that page',
      (tester) async {
        await pumpCard(tester, _comment(images: _sixImages));
        expect(find.byKey(_galleryKey), findsOneWidget);

        await tester.drag(find.byKey(_galleryKey), const Offset(-300, 0));
        await tester.pumpAndSettle();

        expect(dots(tester, _pageIndicatorKey).index, 1);
        expect(visibleGalleryUrl(tester), 'https://cdn.test/t2.jpg');

        await tester.tap(find.byKey(_galleryKey));
        await tester.pumpAndSettle();

        expect(find.byKey(_viewerKey), findsOneWidget);
        expect(dots(tester, _viewerIndicatorKey).count, 6);
        expect(dots(tester, _viewerIndicatorKey).index, 1);
      },
    );

    testWidgets('B7 alt text reaches the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester, _comment(images: _sixImages));

      expect(find.bySemanticsLabel(RegExp(RegExp.escape(_alt))), findsWidgets);
      handle.dispose();
    });

    testWidgets('B7 one image with empty content renders a one-page gallery '
        'without dots', (tester) async {
      await pumpCard(tester, _comment(images: [_sixImages.first], content: ''));

      expect(find.byKey(_galleryKey), findsOneWidget);
      expect(visibleGalleryUrl(tester), 'https://cdn.test/t1.jpg');
      expect(find.byType(MediaPageDots), findsNothing);
    });

    testWidgets('B7 an NSFW-labelled comment shows its gallery with no '
        'sensitive placeholder', (tester) async {
      await pumpCard(
        tester,
        _comment(images: _sixImages, moderation: _nsfwModeration),
      );

      expect(find.byKey(_galleryKey), findsOneWidget);
      expect(visibleGalleryUrl(tester), 'https://cdn.test/t1.jpg');
      expect(find.byType(SensitiveImagePlaceholder), findsNothing);
      expect(find.byType(SensitiveContentBanner), findsNothing);
    });
  });

  group('CommentCard placed images', () {
    const content = 'Look at this\n\n[image]\n\nNice';
    final placeImage1 = RichTextFacet(
      index: ByteSlice(
        byteStart: utf8.encode('Look at this\n\n').length,
        byteEnd: utf8.encode('Look at this\n\n[image]').length,
      ),
      features: const [ImageFacetFeature(index: 1)],
    );
    final comment = _comment(
      images: _sixImages.sublist(0, 3),
      content: content,
      facets: [placeImage1],
    );

    String firstImageUrl(WidgetTester tester, Finder scope) => tester
        .widget<CachedNetworkImage>(
          find
              .descendant(of: scope, matching: find.byType(CachedNetworkImage))
              .first,
        )
        .imageUrl;

    testWidgets('B7 a placed image renders in the body and leaves the '
        'gallery', (tester) async {
      await pumpCard(tester, comment);

      expect(
        find.descendant(
          of: find.byType(RichTextRenderer),
          matching: find.byKey(const Key('rich-text-image-1')),
        ),
        findsOneWidget,
      );
      expect(dots(tester, _pageIndicatorKey).count, 2);
      expect(visibleGalleryUrl(tester), 'https://cdn.test/t1.jpg');
    });

    testWidgets('B7 gallery page 0 opens the viewer after the placed image', (
      tester,
    ) async {
      await pumpCard(tester, comment);
      expect(find.byKey(_galleryKey), findsOneWidget);

      await tester.tap(find.byKey(_galleryKey));
      await tester.pumpAndSettle();

      expect(dots(tester, _viewerIndicatorKey).count, 3);
      expect(dots(tester, _viewerIndicatorKey).index, 1);
      expect(
        firstImageUrl(tester, find.byKey(const Key('image-viewer-image-slot'))),
        'https://cdn.test/f1.jpg',
      );
    });
  });

  group('B5 a GIF in the comment gallery', () {
    late FakeGifFrames frames;

    setUpAll(() async {
      frames = await FakeGifFrames.create();
    });

    tearDownAll(() => frames.dispose());

    testWidgets('shows Play GIF over the thumb; play loads fullsize in place '
        'and opens no viewer', (tester) async {
      const gifFull = 'https://cdn.test/cat-full.gif';
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await pumpCard(
        tester,
        _comment(
          images: const [
            EmbedImage(
              thumb: 'https://cdn.test/cat-thumb.jpg',
              fullsize: gifFull,
              isGif: true,
            ),
          ],
        ),
        gifLoader: loader,
      );

      final playGif = find.descendant(
        of: find.byKey(_galleryKey),
        matching: find.bySemanticsLabel('Play GIF'),
      );
      expect(playGif, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedNetworkImage && widget.imageUrl == gifFull,
        ),
        findsNothing,
      );

      await tester.tap(playGif);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(loader.requests, [gifFull]);
      expect(find.byKey(gifFrameKey), findsOneWidget);
      expect(find.byKey(_viewerKey), findsNothing);
    });
  });
}
