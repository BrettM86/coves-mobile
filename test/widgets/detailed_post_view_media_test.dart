import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/fullscreen_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _imagesKey = Key('detail-images-embed');
const _pageIndicatorKey = Key('detail-images-page-indicator');
const _videoKey = Key('detail-video-embed');
const _playOverlayKey = Key('detail-video-play-overlay');
const _durationBadgeKey = Key('detail-video-duration-badge');
const _imageViewerKey = Key('image-viewer');
const _viewerIndicatorKey = Key('image-viewer-page-indicator');

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';
const _thumb3 = 'https://cdn.test/t3.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';
const _full3 = 'https://cdn.test/f3.jpg';
const _videoUrl = 'https://cdn.test/video.mp4';
const _videoThumb = 'https://cdn.test/video-thumb.jpg';

/// 16:9 as a width/height double — the fallback ratio when none is given.
const _defaultRatio = 16 / 9;

/// H1 clamp bounds for detail-view media, as width/height doubles.
const _minDetailRatio = 1 / 3;
const _maxDetailRatio = 3.0;

/// Records routes pushed onto the navigator so a synchronous
/// `Navigator.push` can be inspected — and, for the video player,
/// inspected *without* mounting the pushed page.
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  /// Routes pushed by a user interaction.
  ///
  /// MaterialApp's own initial `/` route is a `MaterialPageRoute<dynamic>`,
  /// and Dart treats `dynamic` and `void` as mutual subtypes — so a plain
  /// `whereType<MaterialPageRoute<void>>()` would count it too. Callers
  /// clear the log after pumping, and this getter is what they assert on.
  List<MaterialPageRoute<void>> get pushedPages =>
      pushed.whereType<MaterialPageRoute<void>>().toList();

  /// Forgets routes recorded during setup, so only taps are counted.
  void reset() => pushed.clear();
}

void main() {
  late _RecordingObserver observer;

  setUp(() {
    observer = _RecordingObserver();
  });

  /// A tall phone surface. DetailedPostView is an unbounded Column, so the
  /// harness scrolls it exactly like the real SliverList in
  /// post_detail_screen.dart; the extra height just keeps media on screen
  /// so taps land without an explicit scroll.
  void useDetailSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(FeedViewPost post) {
    return MultiProvider(
      providers: [
        Provider<StreamableService>.value(value: StreamableService()),
      ],
      child: MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: SingleChildScrollView(child: DetailedPostView(post: post)),
        ),
      ),
    );
  }

  FeedViewPost makePost({
    PostEmbed? embed,
    String? title = 'Test Post Title',
    String text = '',
    String uri = 'at://did:example/post/123',
  }) {
    return FeedViewPost(
      post: PostView(
        uri: uri,
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

  /// Native `images#view` built through the real model parser.
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
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (alt != null) 'alt': alt,
      if (duration != null) 'duration': duration,
    });
  }

  /// Legacy `external#view` embed — the shape slice C must not regress.
  PostEmbed externalEmbed({
    String uri = 'https://example.com/article',
    String? thumb,
    String? embedType,
    String? provider,
    List<Map<String, dynamic>>? images,
  }) {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.external#view',
      'external': {
        'uri': uri,
        if (thumb != null) 'thumb': thumb,
        if (embedType != null) 'embedType': embedType,
        if (provider != null) 'provider': provider,
        if (images != null) 'images': images,
      },
    });
  }

  Finder inBlock(Key blockKey, Finder matching) {
    return find.descendant(
      of: find.byKey(blockKey),
      matching: matching,
      matchRoot: true,
    );
  }

  double renderedAspectRatio(WidgetTester tester, Key blockKey) {
    final finder = inBlock(blockKey, find.byType(AspectRatio));
    expect(
      finder,
      findsWidgets,
      reason: 'media block $blockKey should size itself with an AspectRatio',
    );
    return tester.widget<AspectRatio>(finder.first).aspectRatio;
  }

  List<String> imageUrlsIn(WidgetTester tester, Key blockKey) {
    return tester
        .widgetList<CachedNetworkImage>(
          inBlock(blockKey, find.byType(CachedNetworkImage)),
        )
        .map((image) => image.imageUrl)
        .toList();
  }

  group('C1 legacy external rendering is untouched', () {
    testWidgets('single external image still renders thumb and link bar', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: externalEmbed(thumb: _thumb1));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      final images = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((image) => image.imageUrl);
      expect(
        images,
        contains(_thumb1),
        reason: 'external single image renders its thumb, not a fullsize',
      );
      expect(find.text('example.com/article'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsWidgets);
    });

    testWidgets('external multi-image carousel still renders with counter', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: externalEmbed(
          thumb: _thumb1,
          images: const [
            {'thumb': _thumb1},
            {'thumb': _thumb2},
            {'thumb': _thumb3},
          ],
        ),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('example.com/article'), findsOneWidget);
    });

    testWidgets('external Streamable video still renders its play button', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: externalEmbed(
          uri: 'https://streamable.com/abc123',
          thumb: _thumb1,
          embedType: 'video',
          provider: 'streamable',
        ),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((image) => image.imageUrl),
        contains(_thumb1),
      );
    });

    testWidgets('external link without a thumb renders no media carousel', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: externalEmbed());

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byType(PageView), findsNothing);
      expect(find.byType(ExternalLinkBar), findsOneWidget);
    });

    testWidgets('quoted bluesky post still renders its card', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: PostEmbed.fromJson({
          r'$type': 'social.coves.embed.post#view',
          'post': {
            'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
            'cid': 'bafyrei123',
          },
        }),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byType(BlueskyPostCard), findsOneWidget);
    });
  });

  group('C2 single native image', () {
    testWidgets('renders the FULLSIZE url, not the thumb', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(
        imageUrlsIn(tester, _imagesKey),
        [_full1],
        reason: 'detail view shows fullsize; thumb is the feed-card size',
      );
    });

    testWidgets('uses 16:9 when aspectRatio is absent', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_defaultRatio, 0.01),
      );
    });

    testWidgets('honours an ordinary aspectRatio', (tester) async {
      useDetailSurface(tester);
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

    testWidgets('keeps a tall 9:21 image, well inside the H1 clamp', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            // 9:21 == 0.4286. The feed card clamps this to 4:5 == 0.8; the
            // detail view keeps it, since it is inside [1/3 … 3].
            'aspectRatio': {'width': 9, 'height': 21},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(renderedAspectRatio(tester, _imagesKey), closeTo(9 / 21, 0.01));
    });

    testWidgets('keeps a 9:16 portrait unchanged', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            'aspectRatio': {'width': 9, 'height': 16},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(renderedAspectRatio(tester, _imagesKey), closeTo(9 / 16, 0.01));
    });

    testWidgets('H1 clamps a wider-than-3:1 image to 3:1', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            // 32:9 == 3.5556, past the 3:1 ceiling.
            'aspectRatio': {'width': 32, 'height': 9},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_maxDetailRatio, 0.01),
      );
    });

    testWidgets('H1 clamps a hostile 1:1000000 ratio to 1:3', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            // The backend never validates aspectRatio, so this is reachable
            // from a federated repo. Unclamped it would lay out a media
            // block hundreds of millions of pixels tall.
            'aspectRatio': {'width': 1, 'height': 1000000},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_minDetailRatio, 0.01),
      );
    });

    testWidgets('H1 clamps a hostile 1000000:1 ratio to 3:1', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {
            'thumb': _thumb1,
            'fullsize': _full1,
            'aspectRatio': {'width': 1000000, 'height': 1},
          },
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        renderedAspectRatio(tester, _imagesKey),
        closeTo(_maxDetailRatio, 0.01),
      );
    });

    testWidgets('H1 leaves the clamp boundaries themselves untouched', (
      tester,
    ) async {
      useDetailSurface(tester);

      for (final ratio in const [
        {'width': 1, 'height': 3},
        {'width': 3, 'height': 1},
      ]) {
        final post = makePost(
          embed: imagesEmbed([
            {'thumb': _thumb1, 'fullsize': _full1, 'aspectRatio': ratio},
          ]),
        );

        await tester.pumpWidget(harness(post));
        await tester.pump();

        final expected = (ratio['width']! / ratio['height']!).toDouble();
        expect(
          renderedAspectRatio(tester, _imagesKey),
          closeTo(expected, 0.01),
          reason: 'ratio: $ratio',
        );
      }
    });

    testWidgets('shows no page indicator for a single image', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byKey(_pageIndicatorKey), findsNothing);
    });

    testWidgets('shows no external link bar for a native image', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(
        find.byType(ExternalLinkBar),
        findsNothing,
        reason: 'a native gallery has no uri, so there is no link to show',
      );
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });
  });

  group('C3 native multi-image carousel', () {
    List<Map<String, dynamic>> threeImages() => const [
      {'thumb': _thumb1, 'fullsize': _full1},
      {'thumb': _thumb2, 'fullsize': _full2},
      {'thumb': _thumb3, 'fullsize': _full3},
    ];

    testWidgets('renders a PageView of fullsize urls', (tester) async {
      useDetailSurface(tester);
      final post = makePost(embed: imagesEmbed(threeImages()));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(inBlock(_imagesKey, find.byType(PageView)), findsOneWidget);
      expect(
        imageUrlsIn(tester, _imagesKey),
        contains(_full1),
        reason: 'carousel pages use fullsize urls',
      );
      expect(imageUrlsIn(tester, _imagesKey), isNot(contains(_thumb1)));
    });

    testWidgets('shows an i/N indicator starting at 1/3', (tester) async {
      useDetailSurface(tester);
      final post = makePost(embed: imagesEmbed(threeImages()));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_pageIndicatorKey), findsOneWidget);
      expect(inBlock(_pageIndicatorKey, find.text('1/3')), findsOneWidget);
    });

    testWidgets('indicator advances to 2/3 after a swipe', (tester) async {
      useDetailSurface(tester);
      final post = makePost(embed: imagesEmbed(threeImages()));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.drag(
        inBlock(_imagesKey, find.byType(PageView)),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(inBlock(_pageIndicatorKey, find.text('2/3')), findsOneWidget);
    });

    testWidgets('shows no external link bar for a native gallery', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: imagesEmbed(threeImages()));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byType(ExternalLinkBar), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });
  });

  group('C4 native image alt semantics', () {
    testWidgets('exposes alt text on the rendered image', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1, 'alt': 'A red barn at dusk'},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.bySemanticsLabel('A red barn at dusk'), findsOneWidget);
    });

    testWidgets('omits image semantics when alt is absent', (tester) async {
      useDetailSurface(tester);
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
  });

  group('H3 tappable image semantics', () {
    testWidgets('a single native image announces itself as a button', (
      tester,
    ) async {
      useDetailSurface(tester);
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
        containsSemantics(isButton: true, label: 'View full image'),
      );
      handle.dispose();
    });

    testWidgets('a carousel page announces itself as a button', (tester) async {
      useDetailSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(
        embed: imagesEmbed(const [
          {'thumb': _thumb1, 'fullsize': _full1},
          {'thumb': _thumb2, 'fullsize': _full2},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('View full image').first),
        containsSemantics(isButton: true, label: 'View full image'),
      );
      handle.dispose();
    });

    testWidgets('a video embed does not claim to open an image', (
      tester,
    ) async {
      useDetailSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(find.bySemanticsLabel('View full image'), findsNothing);
      handle.dispose();
    });

    testWidgets('a text-only post exposes no image button', (tester) async {
      useDetailSurface(tester);
      final handle = tester.ensureSemantics();

      final post = makePost(text: 'Plain text post');

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Plain text post'), findsOneWidget);
      expect(find.bySemanticsLabel('View full image'), findsNothing);
      handle.dispose();
    });

    testWidgets('video alt text reaches the semantics tree', (tester) async {
      useDetailSurface(tester);
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
      useDetailSurface(tester);
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
        containsSemantics(isButton: true, label: 'Play video'),
      );
      handle.dispose();
    });
  });

  group('H12 gallery state resets across posts', () {
    const nextFull1 = 'https://cdn.test/n1.jpg';
    const nextFull2 = 'https://cdn.test/n2.jpg';

    FeedViewPost threeImagePost() => makePost(
      embed: imagesEmbed(const [
        {'thumb': _thumb1, 'fullsize': _full1},
        {'thumb': _thumb2, 'fullsize': _full2},
        {'thumb': _thumb3, 'fullsize': _full3},
      ]),
    );

    /// Swipes the gallery to its third page (index 2).
    Future<void> swipeToLastPage(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        await tester.drag(
          inBlock(_imagesKey, find.byType(PageView)),
          const Offset(-400, 0),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a new post starts at page 1 of its own gallery', (
      tester,
    ) async {
      useDetailSurface(tester);

      await tester.pumpWidget(harness(threeImagePost()));
      await tester.pump();
      await swipeToLastPage(tester);
      expect(inBlock(_pageIndicatorKey, find.text('3/3')), findsOneWidget);

      // Same widget position and type, so the State is reused — exactly the
      // scroll-to-next-post case where a stale index survives.
      await tester.pumpWidget(
        harness(
          makePost(
            uri: 'at://did:example/post/999',
            embed: imagesEmbed(const [
              {'thumb': _thumb1, 'fullsize': nextFull1},
              {'thumb': _thumb2, 'fullsize': nextFull2},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(inBlock(_pageIndicatorKey, find.text('1/2')), findsOneWidget);

      final pageView = tester.widget<PageView>(
        inBlock(_imagesKey, find.byType(PageView)),
      );
      expect(
        pageView.controller?.page ?? 0,
        closeTo(0, 0.01),
        reason: 'the controller must rewind, not just the index counter',
      );
    });

    testWidgets('tapping after a post change opens the new first image', (
      tester,
    ) async {
      useDetailSurface(tester);

      await tester.pumpWidget(harness(threeImagePost()));
      await tester.pump();
      await swipeToLastPage(tester);

      await tester.pumpWidget(
        harness(
          makePost(
            uri: 'at://did:example/post/999',
            embed: imagesEmbed(const [
              {'thumb': _thumb1, 'fullsize': nextFull1},
              {'thumb': _thumb2, 'fullsize': nextFull2},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(
        imageUrlsIn(tester, _imageViewerKey),
        contains(nextFull1),
        reason: 'the viewer must open what the carousel is showing',
      );
    });

    testWidgets('a single-image post shows no stale indicator', (tester) async {
      useDetailSurface(tester);

      await tester.pumpWidget(harness(threeImagePost()));
      await tester.pump();
      await swipeToLastPage(tester);

      await tester.pumpWidget(
        harness(
          makePost(
            uri: 'at://did:example/post/999',
            embed: imagesEmbed(const [
              {'thumb': _thumb1, 'fullsize': nextFull1},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byKey(_pageIndicatorKey), findsNothing);
      expect(imageUrlsIn(tester, _imagesKey), contains(nextFull1));
    });
  });

  group('H4 viewer placeholder', () {
    testWidgets('the viewer shows the thumb while fullsize loads', (
      tester,
    ) async {
      useDetailSurface(tester);
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

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      // While fullsize is still loading, BOTH images are mounted: the
      // fullsize itself and the thumb standing in for it. That pair is the
      // H4 behaviour, so assert the mounted reality rather than reaching
      // into the placeholder builder.
      expect(
        imageUrlsIn(tester, _imageViewerKey),
        containsAll(<String>[_full1, _thumb1]),
        reason: 'the feed-cached thumb is what makes the viewer feel instant',
      );
    });
  });

  group('C5 fullscreen image viewer', () {
    testWidgets('tapping a single image pushes a zoomable viewer', (
      tester,
    ) async {
      useDetailSurface(tester);
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
      observer.reset();

      await tester.tap(find.byKey(_imagesKey));

      // The push must be synchronous — assert before pumping a frame.
      expect(
        observer.pushedPages,
        hasLength(1),
        reason: 'image tap pushes exactly one MaterialPageRoute',
      );

      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsOneWidget);
      expect(
        inBlock(_imageViewerKey, find.byType(InteractiveViewer)),
        findsOneWidget,
        reason: 'the viewer must support pinch-zoom',
      );
      expect(imageUrlsIn(tester, _imageViewerKey), contains(_full1));
    });

    testWidgets('the viewer can be dismissed back to the post', (tester) async {
      useDetailSurface(tester);
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

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(
        navigator.canPop(),
        isTrue,
        reason: 'the viewer sits on a poppable route',
      );

      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsNothing);
      expect(find.byKey(_imagesKey), findsOneWidget);
    });

    testWidgets('a vertical swipe dismisses the viewer', (tester) async {
      useDetailSurface(tester);
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

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsOneWidget);

      await tester.drag(find.byKey(_imageViewerKey), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_imageViewerKey),
        findsNothing,
        reason: 'swiping the image away pops the viewer, like the video',
      );
      expect(find.byKey(_imagesKey), findsOneWidget);
    });

    testWidgets('a short drag snaps back instead of dismissing', (
      tester,
    ) async {
      useDetailSurface(tester);
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

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(_imageViewerKey), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_imageViewerKey),
        findsOneWidget,
        reason: 'a sub-threshold drag releases the image back to center',
      );
    });

    testWidgets('a tap does NOT dismiss the viewer', (tester) async {
      useDetailSurface(tester);
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

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_imageViewerKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_imageViewerKey),
        findsOneWidget,
        reason: 'only the close button and the swipe gesture dismiss',
      );
    });

    testWidgets('tapping a carousel page opens THAT page fullsize', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed(const [
          {'thumb': _thumb1, 'fullsize': _full1},
          {'thumb': _thumb2, 'fullsize': _full2},
          {'thumb': _thumb3, 'fullsize': _full3},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.drag(
        inBlock(_imagesKey, find.byType(PageView)),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(inBlock(_imagesKey, find.byType(PageView)));
      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsOneWidget);
      expect(
        imageUrlsIn(tester, _imageViewerKey),
        contains(_full2),
        reason: 'the viewer opens the image the user was looking at',
      );
      expect(
        find.descendant(
          of: find.byKey(_viewerIndicatorKey),
          matching: find.text('2/3'),
        ),
        findsOneWidget,
        reason: 'the indicator must agree with the page the viewer opened on',
      );
    });

    testWidgets('the viewer shows no page indicator for a single image', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_imageViewerKey), findsOneWidget);
      expect(find.byKey(_viewerIndicatorKey), findsNothing);
    });

    testWidgets('the close button dismisses the viewer', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_imageViewerKey),
        findsNothing,
        reason: 'the close button must not be swallowed by the tap eater',
      );
    });

    testWidgets('an upward swipe also dismisses the viewer', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: imagesEmbed([
          {'thumb': _thumb1, 'fullsize': _full1},
        ]),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      await tester.tap(find.byKey(_imagesKey));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(_imageViewerKey), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_imageViewerKey),
        findsNothing,
        reason: 'dismissal works in both directions, not just downward',
      );
    });
  });

  group('C6 native video', () {
    testWidgets('renders the thumbnail when present', (tester) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(imageUrlsIn(tester, _videoKey), [_videoThumb]);
    });

    testWidgets('renders a 16:9 placeholder when thumbnail is null', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed());

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(
        inBlock(_videoKey, find.byType(CachedNetworkImage)),
        findsNothing,
        reason: 'no thumbnail url means nothing to fetch',
      );
      expect(
        renderedAspectRatio(tester, _videoKey),
        closeTo(_defaultRatio, 0.01),
      );
    });

    testWidgets('always shows the play overlay (with thumbnail)', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_playOverlayKey), findsOneWidget);
    });

    testWidgets('always shows the play overlay (no thumbnail)', (tester) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed());

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_playOverlayKey), findsOneWidget);
    });

    testWidgets('shows a m:ss duration badge', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: videoEmbed(thumbnail: _videoThumb, duration: 42),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_durationBadgeKey), findsOneWidget);
      expect(inBlock(_durationBadgeKey, find.text('0:42')), findsOneWidget);
    });

    testWidgets('shows an h:mm:ss badge for long videos', (tester) async {
      useDetailSurface(tester);
      final post = makePost(
        embed: videoEmbed(thumbnail: _videoThumb, duration: 3723),
      );

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(
        inBlock(_durationBadgeKey, find.text('1:02:03')),
        findsOneWidget,
        reason: 'must reuse formatVideoDuration, not a naive m:ss formatter',
      );
    });

    testWidgets('omits the duration badge when duration is null', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.byKey(_videoKey), findsOneWidget);
      expect(find.byKey(_durationBadgeKey), findsNothing);
    });

    testWidgets('tapping the video pushes the fullscreen player', (
      tester,
    ) async {
      useDetailSurface(tester);
      final post = makePost(embed: videoEmbed(thumbnail: _videoThumb));

      await tester.pumpWidget(harness(post));
      await tester.pump();
      observer.reset();

      await tester.tap(find.byKey(_videoKey));
      // Deliberately NOT pumping: mounting FullscreenVideoPlayer hits the
      // video_player platform channel, which throws UnimplementedError
      // under flutter_test (an Error, so the widget's own catch misses it).

      final videoRoutes = observer.pushedPages;
      expect(videoRoutes, hasLength(1));

      final page = videoRoutes.single.builder(
        tester.element(find.byKey(_videoKey)),
      );
      expect(page, isA<FullscreenVideoPlayer>());
      expect((page as FullscreenVideoPlayer).videoUrl, _videoUrl);
    });
  });

  group('C7 no renderable media', () {
    testWidgets('an unknown embed renders text only', (tester) async {
      useDetailSurface(tester);
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
      expect(find.byKey(_pageIndicatorKey), findsNothing);
      expect(find.byKey(_durationBadgeKey), findsNothing);
    });

    testWidgets('an unhydrated images record renders no media', (tester) async {
      useDetailSurface(tester);
      // Record shape (no #view) carrying blob refs: hydration failed
      // upstream, so the client must render nothing rather than build a
      // getBlob url itself.
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
      expect(find.byKey(_pageIndicatorKey), findsNothing);
    });

    testWidgets('a post with no embed renders no media', (tester) async {
      useDetailSurface(tester);
      final post = makePost(text: 'Plain text post');

      await tester.pumpWidget(harness(post));
      await tester.pump();

      expect(find.text('Plain text post'), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.byKey(_videoKey), findsNothing);
    });
  });
}
