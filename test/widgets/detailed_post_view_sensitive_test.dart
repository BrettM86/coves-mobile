import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/media/media_aspect.dart';
import 'package:coves_flutter/widgets/media/streamable_video_embed.dart';
import 'package:coves_flutter/widgets/source_link_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _bannerKey = Key('sensitive-content-banner');
const _placeholderKey = Key('sensitive-image-placeholder');
const _imagesKey = Key('detail-images-embed');
const _pageIndicatorKey = Key('detail-images-page-indicator');
const _videoKey = Key('detail-video-embed');

const _uriA = 'at://did:plc:author/social.coves.community.post/aaa';
const _uriB = 'at://did:plc:author/social.coves.community.post/bbb';

const _title = 'A post behind the NSFW gate';
const _body = 'Body text that must stay hidden while concealed';

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';
const _thumb3 = 'https://cdn.test/t3.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';
const _full3 = 'https://cdn.test/f3.jpg';
const _alt = 'A photograph the author marked as sensitive';

const _videoUrl = 'https://cdn.test/video.mp4';
const _videoThumb = 'https://cdn.test/video-thumb.jpg';

const _linkUri = 'https://example.com/article';
const _sourceUri = 'https://example.com/source-one';

/// A 1:5 portrait. The feed would clamp it to 3:4; the detail view's floor is
/// 1:3, so a placeholder sized with the wrong bounds is visibly wrong here.
const _extremeRatio = {'width': 1, 'height': 5};

void main() {
  /// A tall phone surface. DetailedPostView is an unbounded Column, so the
  /// harness scrolls it exactly like the real SliverList in
  /// post_detail_screen.dart.
  void useDetailSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// One app, one DetailedPostView slot, driven by a notifier.
  ///
  /// Swapping [post]'s value rebuilds the same State rather than mounting a
  /// fresh one, which is the only way to observe whether reveal state is
  /// carried across posts or reset with them.
  Widget harness(ValueNotifier<FeedViewPost> post) {
    return MultiProvider(
      providers: [
        Provider<StreamableService>.value(value: StreamableService()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<FeedViewPost>(
              valueListenable: post,
              builder: (context, value, _) => DetailedPostView(post: value),
            ),
          ),
        ),
      ),
    );
  }

  /// Pumps [post] into the shared slot and returns the notifier that owns it.
  ///
  /// `showSources` defaults to true on DetailedPostView, so a megathread's
  /// source list is in the tree for every case here.
  Future<ValueNotifier<FeedViewPost>> pumpDetail(
    WidgetTester tester,
    FeedViewPost post,
  ) async {
    useDetailSurface(tester);
    final notifier = ValueNotifier<FeedViewPost>(post);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(harness(notifier));
    await tester.pump();
    return notifier;
  }

  FeedViewPost makePost({
    String uri = _uriA,
    PostEmbed? embed,
    String content = _body,
    String? title = _title,
    bool sensitive = true,
  }) {
    return FeedViewPost(
      post: PostView(
        uri: uri,
        cid: 'cid-$uri',
        rkey: uri.split('/').last,
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: PostRecord(
          title: title,
          content: content,
          labels: sensitive ? const ['nsfw'] : const [],
        ),
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

  PostEmbed singleImageEmbed() {
    return imagesEmbed([
      {
        'thumb': _thumb1,
        'fullsize': _full1,
        'alt': _alt,
        'aspectRatio': _extremeRatio,
      },
    ]);
  }

  PostEmbed galleryEmbed() {
    return imagesEmbed([
      {'thumb': _thumb1, 'fullsize': _full1, 'aspectRatio': _extremeRatio},
      {'thumb': _thumb2, 'fullsize': _full2},
      {'thumb': _thumb3, 'fullsize': _full3},
    ]);
  }

  PostEmbed videoEmbed() {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.video#view',
      'video': _videoUrl,
      'thumbnail': _videoThumb,
    });
  }

  /// Legacy `external#view` embed — the shape the detail view renders as a
  /// link card, a carousel, or a Streamable player depending on its fields.
  PostEmbed externalEmbed({
    String uri = _linkUri,
    String? thumb,
    String? embedType,
    String? provider,
    List<Map<String, dynamic>>? images,
    List<Map<String, dynamic>>? sources,
  }) {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.external#view',
      'external': {
        'uri': uri,
        'thumb': ?thumb,
        'embedType': ?embedType,
        'provider': ?provider,
        'images': ?images,
        'sources': ?sources,
      },
    });
  }

  PostEmbed blueskyEmbed() {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.post#view',
      'post': {
        'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
        'cid': 'bafyquotecid',
      },
    });
  }

  Iterable<String> imageUrls(WidgetTester tester) {
    return tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .map((image) => image.imageUrl);
  }

  group('DetailedPostView conceals a sensitive post', () {
    testWidgets('a single image is replaced by the placeholder', (
      tester,
    ) async {
      await pumpDetail(tester, makePost(embed: singleImageEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(
        find.text(_body),
        findsNothing,
        reason: 'body text is concealed along with the media',
      );
      expect(find.text(_title), findsOneWidget);
      expect(
        imageUrls(tester),
        isNot(contains(_full1)),
        reason: 'the fullsize rendering must never be fetched while concealed',
      );
    });

    testWidgets('the banner sits under the title', (tester) async {
      await pumpDetail(tester, makePost(embed: singleImageEmbed()));

      final titleBottom = tester.getBottomLeft(find.text(_title)).dy;
      final bannerTop = tester.getTopLeft(find.byKey(_bannerKey)).dy;
      final bannerBottom = tester.getBottomLeft(find.byKey(_bannerKey)).dy;
      final placeholderTop = tester.getTopLeft(find.byKey(_placeholderKey)).dy;

      expect(bannerTop, greaterThanOrEqualTo(titleBottom));
      expect(bannerBottom, lessThanOrEqualTo(placeholderTop));
    });

    testWidgets('the placeholder reserves the detail-sized space', (
      tester,
    ) async {
      await pumpDetail(tester, makePost(embed: singleImageEmbed()));

      final expected = clampMediaRatio(
        EmbedAspectRatio(width: 1, height: 5),
        min: kDetailRatioBounds.min,
        max: kDetailRatioBounds.max,
      );

      final ratios = find.descendant(
        of: find.byKey(_placeholderKey),
        matching: find.byType(AspectRatio),
        matchRoot: true,
      );
      expect(ratios, findsWidgets);
      expect(
        tester.widget<AspectRatio>(ratios.first).aspectRatio,
        closeTo(expected, 0.001),
        reason: 'the detail view clamps at 1:3, not the feed card\'s 3:4',
      );
    });

    testWidgets('the alt text stays out of the semantics tree', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpDetail(tester, makePost(embed: singleImageEmbed()));

      expect(
        find.bySemanticsLabel(_alt),
        findsNothing,
        reason: 'alt text describes the concealed image and must not leak',
      );

      semantics.dispose();
    });

    testWidgets('a gallery loses its pager and its indicator', (tester) async {
      await pumpDetail(tester, makePost(embed: galleryEmbed()));

      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.byKey(_pageIndicatorKey), findsNothing);
      expect(
        find.byType(PageView),
        findsNothing,
        reason: 'a swipeable pager would expose every concealed image',
      );
    });

    testWidgets('a native video is hidden', (tester) async {
      await pumpDetail(tester, makePost(embed: videoEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byKey(_videoKey), findsNothing);
      expect(
        find.byKey(_placeholderKey),
        findsNothing,
        reason: 'only native image embeds get a blurred stand-in',
      );
    });

    testWidgets('an external card, its link bar and its sources are hidden', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        makePost(
          embed: externalEmbed(
            thumb: _thumb1,
            sources: const [
              {
                'uri': _sourceUri,
                'title': 'Source One',
                'domain': 'example.com',
              },
            ],
          ),
        ),
      );

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason: 'the link thumbnail is part of the concealed content',
      );
      expect(find.byType(ExternalLinkBar), findsNothing);
      expect(
        find.byType(SourceLinkBar),
        findsNothing,
        reason: 'a megathread source list describes the concealed content',
      );
    });

    testWidgets('an external carousel is hidden', (tester) async {
      await pumpDetail(
        tester,
        makePost(
          embed: externalEmbed(
            thumb: _thumb1,
            images: const [
              {'thumb': _thumb1},
              {'thumb': _thumb2},
            ],
          ),
        ),
      );

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a Streamable player is hidden', (tester) async {
      await pumpDetail(
        tester,
        makePost(
          embed: externalEmbed(
            uri: 'https://streamable.com/abc123',
            thumb: _thumb1,
            embedType: 'video',
            provider: 'streamable',
          ),
        ),
      );

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byType(StreamableVideoEmbed), findsNothing);
    });

    testWidgets('a quoted Bluesky post is hidden', (tester) async {
      await pumpDetail(tester, makePost(embed: blueskyEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byType(BlueskyPostCard), findsNothing);
    });

    testWidgets('a post with no nsfw label renders as it always has', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        makePost(embed: singleImageEmbed(), sensitive: false),
      );

      expect(find.byKey(_bannerKey), findsNothing);
      expect(find.byKey(_placeholderKey), findsNothing);
      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
    });
  });

  group('DetailedPostView reveal lifecycle', () {
    Future<void> tapBanner(WidgetTester tester) async {
      await tester.tap(find.byKey(_bannerKey));
      await tester.pump();
    }

    testWidgets('tapping the banner reveals the post', (tester) async {
      await pumpDetail(tester, makePost(embed: singleImageEmbed()));
      await tapBanner(tester);

      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsNothing);
      expect(find.text('Hide'), findsOneWidget);
    });

    testWidgets('a different post in the same slot arrives concealed', (
      tester,
    ) async {
      final notifier = await pumpDetail(
        tester,
        makePost(embed: singleImageEmbed()),
      );
      await tapBanner(tester);

      notifier.value = makePost(uri: _uriB, embed: singleImageEmbed());
      await tester.pump();

      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.text(_body), findsNothing);
    });

    testWidgets('re-showing a carousel resets its page indicator', (
      tester,
    ) async {
      // Concealing unmounts the PageView, so re-showing rebuilds it at page
      // one. The counter is drawn from the view's own index, which must be
      // reset with it or it advertises a page the reader is not on.
      await pumpDetail(
        tester,
        makePost(
          embed: externalEmbed(
            thumb: _thumb1,
            images: const [
              {'thumb': _thumb1},
              {'thumb': _thumb2},
              {'thumb': _thumb3},
            ],
          ),
        ),
      );

      await tapBanner(tester);
      expect(find.text('1/3'), findsOneWidget);

      for (var page = 0; page < 2; page++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('3/3'), findsOneWidget);

      await tapBanner(tester);
      await tapBanner(tester);

      expect(find.byType(PageView), findsOneWidget);
      expect(
        find.text('3/3'),
        findsNothing,
        reason: 'the counter must agree with the page the carousel remounts on',
      );
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('returning to a revealed post finds it concealed again', (
      tester,
    ) async {
      // A -> B -> A in one slot: the reveal must be keyed to the post that
      // is showing now, not merely differ from the last uri seen.
      final postA = makePost(embed: singleImageEmbed());
      final notifier = await pumpDetail(tester, postA);
      await tapBanner(tester);

      notifier.value = makePost(uri: _uriB, embed: singleImageEmbed());
      await tester.pump();

      notifier.value = postA;
      await tester.pump();

      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.text(_body), findsNothing);
    });
  });
}
