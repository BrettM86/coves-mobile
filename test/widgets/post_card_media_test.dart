import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/fullscreen_video_player.dart';
import 'package:coves_flutter/widgets/media/gif_codec.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_gif_codec.dart';
import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/fake_providers.dart';

const _imagesKey = Key('post-images-embed');
const _countBadgeKey = Key('post-images-count-badge');
const _pageIndicatorKey = Key('post-images-page-indicator');
const _videoKey = Key('post-video-embed');
const _playOverlayKey = Key('post-video-play-overlay');
const _durationBadgeKey = Key('post-video-duration-badge');
const _viewerKey = Key('image-viewer');

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';
const _thumb3 = 'https://cdn.test/t3.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';
const _videoUrl = 'https://cdn.test/video.mp4';
const _videoThumb = 'https://cdn.test/video-thumb.jpg';

const _detailMarker = 'DETAIL SCREEN';

/// 16:9 and 3:4 as width/height doubles — the clamp bounds from B1.
const _widestRatio = 16 / 9;
const _tallestRatio = 3 / 4;

/// Records routes pushed onto the root navigator so a tap handler's
/// `Navigator.push` can be inspected without mounting the pushed page.
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  late FakeAuthProvider auth;
  late _RecordingObserver observer;

  setUp(() {
    auth = FakeAuthProvider();
    observer = _RecordingObserver();
  });

  /// Gives the card a phone-sized surface. The default 800x600 test view is
  /// too short for a full-width media block plus header and actions, and the
  /// resulting RenderFlex overflow would fail tests for the wrong reason.
  void useMediaSizedSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(
    FeedViewPost post, {
    bool disableNavigation = false,
    FakeGifCodecLoader? gifLoader,
  }) {
    final router = GoRouter(
      observers: [observer],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: PostCard(
              post: post,
              sessionStamp: null,
              disableNavigation: disableNavigation,
            ),
          ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) =>
              const Scaffold(body: Text(_detailMarker)),
        ),
      ],
    );
    addTearDown(router.dispose);

    Widget app = MaterialApp.router(routerConfig: router);
    if (gifLoader != null) {
      app = GifCodecScope(
        loader: gifLoader.load,
        child: ImageCacheScope(
          cacheManager: FakeImageCacheManager(),
          child: app,
        ),
      );
    }

    return MultiProvider(
      providers: postCardProviders(auth: auth),
      child: app,
    );
  }

  FeedViewPost makePost({
    PostEmbed? embed,
    String? title = 'Test Post Title',
    String text = '',
  }) {
    return FeedViewPost(
      post: PostView(
        uri: 'at://did:example/post/123',
        cid: 'cid123',
        rkey: '123',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: PostRecord(title: title, content: text),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        embed: embed,
      ),
    );
  }

  /// Builds an `images#view` embed through the real model parser, so these
  /// tests double as an integration check of the model -> widget flow.
  PostEmbed imagesEmbed(List<Map<String, dynamic>> images) {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.images#view',
      'images': images,
    });
  }

  PostEmbed videoEmbed({
    String video = _videoUrl,
    String? thumbnail,
    String? alt,
    int? duration,
  }) {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.video#view',
      'video': video,
      'thumbnail': ?thumbnail,
      'alt': ?alt,
      'duration': ?duration,
    });
  }

  Finder inBlock(Key blockKey, Finder matching) {
    return find.descendant(
      of: find.byKey(blockKey),
      matching: matching,
      matchRoot: true,
    );
  }

  /// The aspect ratio the media block actually renders at.
  double renderedAspectRatio(WidgetTester tester, Key blockKey) {
    final finder = inBlock(blockKey, find.byType(AspectRatio));
    expect(
      finder,
      findsWidgets,
      reason: 'media block $blockKey should size itself with an AspectRatio',
    );
    return tester.widget<AspectRatio>(finder.first).aspectRatio;
  }

  /// The feed gallery's page dots.
  MediaPageDots feedDots(WidgetTester tester) {
    final finder = inBlock(_pageIndicatorKey, find.byType(MediaPageDots));
    expect(finder, findsOneWidget, reason: 'the gallery shows page dots');
    return tester.widget<MediaPageDots>(finder);
  }

  group('PostCard images embed', () {
    testWidgets('B1 renders the first image thumb full width', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
          {'thumb': _thumb2, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);

      final imageFinder = inBlock(_imagesKey, find.byType(CachedNetworkImage));
      expect(imageFinder, findsOneWidget);
      expect(
        tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
        _thumb1,
        reason: 'only the FIRST image renders on the feed card',
      );
    });

    testWidgets('B1 uses 16:9 when aspectRatio is absent', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_widestRatio, 0.01),
      );
    });

    testWidgets('B1 honours an in-range aspectRatio unchanged', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            'aspectRatio': {'width': 3, 'height': 2},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(renderedAspectRatio(tester, _imagesKey), closeTo(1.5, 0.01));
    });

    testWidgets('B1 a 3:4 phone-camera portrait survives uncropped', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            'aspectRatio': {'width': 3, 'height': 4},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_tallestRatio, 0.001),
        reason: 'the floor sits exactly at 3:4 so standard portraits pass',
      );
    });

    testWidgets('B1 clamps an extremely tall image to 3:4', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            // 9:21 == 0.43, far taller than the 3:4 == 0.75 floor
            'aspectRatio': {'width': 9, 'height': 21},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_tallestRatio, 0.01),
      );
    });

    testWidgets('B1 clamps an extremely wide image to 16:9', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            // 32:9 == 3.56, far wider than the 16:9 == 1.78 ceiling
            'aspectRatio': {'width': 32, 'height': 9},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_widestRatio, 0.01),
      );
    });

    testWidgets('B1 exposes alt text as image semantics', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1, 'alt': 'A red barn at dusk'},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        find.bySemanticsLabel('A red barn at dusk'),
        findsOneWidget,
        reason: 'alt text must reach the semantics tree for screen readers',
      );
    });

    testWidgets('B1 omits image semantics when alt is absent', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.bySemanticsLabel('A red barn at dusk'), findsNothing);
    });

    testWidgets('B2 a multi-image embed shows page dots, not a count badge', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
          {'thumb': _thumb2, 'fullsize': _full1},
          {'thumb': _thumb3, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(feedDots(tester).count, 3);
      expect(feedDots(tester).index, 0);
      expect(find.byKey(_countBadgeKey), findsNothing);
      expect(find.text('1/3'), findsNothing);
    });

    testWidgets('B2 omits the badge for a single image', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byKey(_countBadgeKey), findsNothing);
      expect(find.byType(MediaPageDots), findsNothing);
    });

    testWidgets('B3 tapping the images block opens the fullscreen viewer', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_viewerKey),
        findsOneWidget,
        reason: 'an image tap opens the viewer, not the post detail screen',
      );
      expect(find.text(_detailMarker), findsNothing);

      final viewerImages = tester
          .widgetList<CachedNetworkImage>(
            find.descendant(
              of: find.byKey(_viewerKey),
              matching: find.byType(CachedNetworkImage),
            ),
          )
          .map((w) => w.imageUrl);
      expect(
        viewerImages,
        contains(_full1),
        reason: 'the viewer shows the fullsize rendering, not the feed thumb',
      );
    });

    testWidgets('B3 disableNavigation suppresses the images tap', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post, disableNavigation: true));
      await tester.pump();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(find.text(_detailMarker), findsNothing);
      expect(find.byKey(_viewerKey), findsNothing);
      expect(find.byKey(_imagesKey), findsOneWidget);
    });
    testWidgets(
      'B2 disableNavigation: a gallery still swipes but a tap opens nothing',
      (tester) async {
        useMediaSizedSurface(tester);
        final handle = tester.ensureSemantics();
        final post = makePost(
          embed: imagesEmbed([
            {'thumb': _thumb1, 'fullsize': _full1},
            {'thumb': _thumb2, 'fullsize': _full2},
            {'thumb': _thumb3, 'fullsize': _full1},
          ]),
        );

        await tester.pumpWidget(harness(post, disableNavigation: true));
        await tester.pump();

        await tester.drag(find.byKey(_imagesKey), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(feedDots(tester).index, 1);

        await tester.tap(find.byKey(_imagesKey));
        await tester.pumpAndSettle();

        expect(find.byKey(_viewerKey), findsNothing);
        expect(find.text(_detailMarker), findsNothing);
        expect(find.bySemanticsLabel('View full image'), findsNothing);
        handle.dispose();
      },
    );
  });

  group('H3 tappable image semantics', () {
    testWidgets('the images block announces itself as a button', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('View full image')),
        isSemantics(isButton: true, label: 'View full image'),
      );
      handle.dispose();
    });

    testWidgets('the button semantics survive a multi-image embed', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
          {'thumb': _thumb2, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('View full image')),
        isSemantics(isButton: true, label: 'View full image'),
      );
      handle.dispose();
    });

    testWidgets('a text-only post exposes no image button', (tester) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(text: 'Plain text post');

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Plain text post'), findsOneWidget);
      expect(find.bySemanticsLabel('View full image'), findsNothing);
      handle.dispose();
    });

    testWidgets('H11 a non-tappable images block announces no button', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post, disableNavigation: true));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(
        find.bySemanticsLabel('View full image'),
        findsNothing,
        reason: 'a dead actionable node is worse than no node at all',
      );
      handle.dispose();
    });

    testWidgets('H11 the tappable block still announces a button', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('View full image')),
        isSemantics(isButton: true, label: 'View full image'),
      );
      handle.dispose();
    });

    testWidgets('video alt text reaches the semantics tree', (tester) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: videoEmbed(
          thumbnail: _videoThumb,
          alt: 'A timelapse of the harbour',
        ),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.bySemanticsLabel('A timelapse of the harbour'), findsWidgets);
      handle.dispose();
    });

    testWidgets('H6 the play button label survives a duration badge', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      // A sibling node inside the block — here the duration badge's text —
      // absorbs the wrapper's label unless the Semantics sets
      // container: true, explicitChildNodes: true.
      final post = makePost(
        embed: videoEmbed(thumbnail: _videoThumb, duration: 42),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_durationBadgeKey), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        isSemantics(isButton: true, label: 'Play video'),
      );
      handle.dispose();
    });
  });

  group('PostCard video embed', () {
    testWidgets('B4 renders the thumbnail when present', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);

      final imageFinder = inBlock(_videoKey, find.byType(CachedNetworkImage));
      expect(imageFinder, findsOneWidget);
      expect(
        tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
        _videoThumb,
      );
    });

    testWidgets('B4 renders a 16:9 placeholder when thumbnail is null', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed());

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(
        inBlock(_videoKey, find.byType(CachedNetworkImage)),
        findsNothing,
        reason: 'no thumbnail URL means nothing to fetch',
      );
      expect(
        renderedAspectRatio(tester, _videoKey),
        closeTo(_widestRatio, 0.01),
      );
    });

    testWidgets('B4 always shows the play overlay (with thumbnail)', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_playOverlayKey), findsOneWidget);
    });

    testWidgets('B4 always shows the play overlay (no thumbnail)', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed());

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_playOverlayKey), findsOneWidget);
    });

    testWidgets('B5 shows the duration badge when duration is set', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        embed: videoEmbed(thumbnail: _videoThumb, duration: 42),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_durationBadgeKey), findsOneWidget);
      expect(inBlock(_durationBadgeKey, find.text('0:42')), findsOneWidget);
    });

    testWidgets('B5 omits the duration badge when duration is null', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(find.byKey(_durationBadgeKey), findsNothing);
    });

    testWidgets('B6 tapping the video pushes the fullscreen player', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.tap(find.byKey(_videoKey));
      // Deliberately NOT pumping: mounting FullscreenVideoPlayer would hit
      // the video_player platform channel, which throws UnimplementedError
      // under flutter_test. Inspecting the pushed route instead asserts the
      // same contract without building the page.

      final videoRoutes = observer.pushed
          .whereType<MaterialPageRoute<void>>()
          .toList();
      expect(
        videoRoutes,
        hasLength(1),
        reason: 'video tap should push exactly one page route',
      );

      final page = videoRoutes.single.builder(
        tester.element(find.byKey(_videoKey)),
      );
      expect(page, isA<FullscreenVideoPlayer>());
      expect((page as FullscreenVideoPlayer).videoUrl, _videoUrl);
    });

    testWidgets('B6 video tap still plays when navigation is disabled', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post, disableNavigation: true));
      await tester.pump();

      await tester.tap(find.byKey(_videoKey));

      final videoRoutes = observer.pushed
          .whereType<MaterialPageRoute<void>>()
          .toList();
      expect(
        videoRoutes,
        hasLength(1),
        reason: 'media plays in place regardless of disableNavigation',
      );

      final page = videoRoutes.single.builder(
        tester.element(find.byKey(_videoKey)),
      );
      expect((page as FullscreenVideoPlayer).videoUrl, _videoUrl);
    });
  });

  group('PostCard media layout and fallbacks', () {
    testWidgets('B7 renders images for a post with no title and no text', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        title: null,
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
    });

    testWidgets('B7 renders video for a post with no title and no text', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        title: null,
        embed: videoEmbed(thumbnail: _videoThumb),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(find.byKey(_playOverlayKey), findsOneWidget);
    });

    testWidgets('B9 media sits between the title and the post text', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        text: 'Body text below the media',
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      final titleBottom = tester.getBottomLeft(find.text('Test Post Title')).dy;
      final mediaTop = tester.getTopLeft(find.byKey(_imagesKey)).dy;
      final mediaBottom = tester.getBottomLeft(find.byKey(_imagesKey)).dy;
      final textTop = tester
          .getTopLeft(find.text('Body text below the media'))
          .dy;

      expect(
        mediaTop - titleBottom,
        greaterThanOrEqualTo(12.0),
        reason: 'B9: the title->media gap must survive the new variants',
      );
      expect(
        textTop,
        greaterThan(mediaBottom),
        reason: 'media renders above the post text',
      );
    });

    testWidgets('B9 the title gap holds when media is the only content', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      // No body text and no external embed: the media clause of
      // hasContentBelowTitle is the only thing that can open the gap.
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      final titleBottom = tester.getBottomLeft(find.text('Test Post Title')).dy;
      final mediaTop = tester.getTopLeft(find.byKey(_imagesKey)).dy;

      expect(mediaTop - titleBottom, greaterThanOrEqualTo(12.0));
    });

    testWidgets('B8 an unknown embed renders as a text-only post', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final post = makePost(
        text: 'Just body text',
        embed: PostEmbed.fromJson({
          r'$type': 'social.coves.embed.somethingNew',
          'payload': {'a': 1},
        }),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Test Post Title'), findsOneWidget);
      expect(find.text('Just body text'), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.byKey(_videoKey), findsNothing);
      expect(find.byKey(_playOverlayKey), findsNothing);
      expect(find.byKey(_durationBadgeKey), findsNothing);
      expect(find.byKey(_countBadgeKey), findsNothing);
    });

    testWidgets('B8 an unhydrated images record renders no media', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      // Record shape (no #view) with blob refs — hydration failed upstream,
      // so the card must show no media rather than build a blob URL itself.
      final post = makePost(
        text: 'Hydration failed upstream',
        embed: PostEmbed.fromJson({
          r'$type': 'social.coves.embed.images',
          'images': [
            {
              'image': {
                r'$type': 'blob',
                'ref': {r'$link': 'bafyimage1'},
                'mimeType': 'image/jpeg',
                'size': 123456,
              },
            },
          ],
        }),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Hydration failed upstream'), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.byKey(_countBadgeKey), findsNothing);
    });

    testWidgets('B8 a post with no embed renders no media', (tester) async {
      useMediaSizedSurface(tester);
      final post = makePost(text: 'Plain text post');

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Plain text post'), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.byKey(_videoKey), findsNothing);
    });
  });

  group('B5 a GIF on the feed card', () {
    late FakeGifFrames frames;

    setUpAll(() async {
      frames = await FakeGifFrames.create();
    });

    tearDownAll(() => frames.dispose());

    testWidgets('shows Play GIF over the thumb; play loads fullsize in place '
        'and opens no viewer or ALT badge', (tester) async {
      useMediaSizedSurface(tester);
      const gifFull = 'https://cdn.test/cat-full.gif';
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      final post = makePost(
        embed: ImagesPostEmbed(
          type: 'social.coves.embed.images#view',
          images: const [
            EmbedImage(
              thumb: _thumb1,
              fullsize: gifFull,
              alt: 'A cat chasing a laser dot',
              isGif: true,
            ),
          ],
          data: const {},
        ),
      );

      await tester.pumpWidget(harness(post, gifLoader: loader));
      await tester.pump();

      final playGif = find.bySemanticsLabel('Play GIF');
      expect(playGif, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedNetworkImage && widget.imageUrl == gifFull,
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('image-viewer-alt-badge')), findsNothing);

      await tester.tap(playGif);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(loader.requests, [gifFull]);
      expect(find.byKey(gifFrameKey), findsOneWidget);
      expect(find.byKey(_viewerKey), findsNothing);
      expect(find.text(_detailMarker), findsNothing);
    });
  });
}
