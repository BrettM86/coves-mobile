import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/post_card_actions.dart';
import 'package:coves_flutter/widgets/source_link_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _bannerKey = Key('sensitive-content-banner');
const _placeholderKey = Key('sensitive-image-placeholder');
const _imagesKey = Key('post-images-embed');
const _videoKey = Key('post-video-embed');

const _uriA = 'at://did:plc:author/social.coves.community.post/aaa';
const _uriB = 'at://did:plc:author/social.coves.community.post/bbb';

const _title = 'A post behind the NSFW gate';
const _body = 'Body text that must stay hidden while concealed';

const _thumb = 'https://cdn.test/nsfw-thumb.jpg';
const _fullsize = 'https://cdn.test/nsfw-fullsize.jpg';
const _alt = 'A photograph the author marked as sensitive';

const _linkThumb = 'https://cdn.test/link-thumb.jpg';
const _linkUri = 'https://example.com/article';
const _sourceUri = 'https://example.com/source-one';

const _videoUrl = 'https://cdn.test/video.mp4';
const _videoThumb = 'https://cdn.test/video-thumb.jpg';

const _detailMarker = 'DETAIL SCREEN';

/// The PostCard flags a host screen sets. The same card renders in the feed,
/// under a megathread's source list, and inline on the reply screen, and
/// concealment has to survive every one of those shapes.
typedef CardConfig = ({
  bool showHeader,
  bool disableNavigation,
  bool showActions,
  bool showFullText,
  bool showBorder,
  bool showSources,
});

const CardConfig feedConfig = (
  showHeader: true,
  disableNavigation: false,
  showActions: true,
  showFullText: false,
  showBorder: true,
  showSources: false,
);

const CardConfig megathreadConfig = (
  showHeader: true,
  disableNavigation: false,
  showActions: true,
  showFullText: false,
  showBorder: true,
  showSources: true,
);

/// How the reply screen embeds the post being replied to: no chrome, no
/// navigation, and the full body rather than a preview.
const CardConfig replyConfig = (
  showHeader: false,
  disableNavigation: true,
  showActions: false,
  showFullText: true,
  showBorder: false,
  showSources: false,
);

void main() {
  /// Gives the card a phone-sized surface. The default 800x600 test view is
  /// too short for a full-width media block plus header and actions, and the
  /// resulting RenderFlex overflow would fail tests for the wrong reason.
  void useMediaSizedSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// One router, one PostCard slot, driven by a notifier.
  ///
  /// Swapping [post]'s value rebuilds the same element rather than mounting a
  /// fresh one, which is the only way to observe whether reveal state is
  /// carried across posts or reset with them.
  Widget harness(
    ValueNotifier<FeedViewPost> post, {
    required CardConfig config,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: ValueListenableBuilder<FeedViewPost>(
              valueListenable: post,
              builder: (context, value, _) => PostCard(
                post: value,
                showHeader: config.showHeader,
                disableNavigation: config.disableNavigation,
                showActions: config.showActions,
                showFullText: config.showFullText,
                showBorder: config.showBorder,
                showSources: config.showSources,
              ),
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

    return MultiProvider(
      providers: postCardProviders(auth: FakeAuthProvider()),
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  /// Pumps [post] into the shared slot and returns the notifier that owns it.
  Future<ValueNotifier<FeedViewPost>> pumpCard(
    WidgetTester tester,
    FeedViewPost post, {
    CardConfig config = feedConfig,
  }) async {
    useMediaSizedSurface(tester);
    final notifier = ValueNotifier<FeedViewPost>(post);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(harness(notifier, config: config));
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

  /// A deleted post: the appview serves no record at all, so nothing can be
  /// labelled and nothing may be concealed.
  FeedViewPost deletedPost() {
    return FeedViewPost(
      post: PostView(
        uri: _uriA,
        cid: 'cid-deleted',
        rkey: 'aaa',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        isDeleted: true,
        deletionReason: 'author',
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      ),
    );
  }

  /// Built through the real parser, so these tests double as an integration
  /// check of the model -> widget flow.
  PostEmbed imagesEmbed() {
    return PostEmbed.fromJson({
      r'$type': EmbedTypes.imagesView,
      'images': [
        {
          'thumb': _thumb,
          'fullsize': _fullsize,
          'alt': _alt,
          'aspectRatio': {'width': 3, 'height': 2},
        },
      ],
    });
  }

  PostEmbed videoEmbed() {
    return PostEmbed.fromJson({
      r'$type': EmbedTypes.videoView,
      'video': _videoUrl,
      'thumbnail': _videoThumb,
    });
  }

  PostEmbed externalEmbed() {
    return PostEmbed.fromJson({
      r'$type': EmbedTypes.externalView,
      'uri': _linkUri,
      'domain': 'example.com',
      'title': 'Example Article',
      'thumb': _linkThumb,
      'sources': [
        {'uri': _sourceUri, 'title': 'Source One', 'domain': 'example.com'},
      ],
    });
  }

  PostEmbed blueskyEmbed() {
    return PostEmbed.fromJson({
      r'$type': EmbedTypes.postView,
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

  group('PostCard conceals a sensitive post', () {
    testWidgets('an images embed is replaced by the banner and placeholder', (
      tester,
    ) async {
      await pumpCard(tester, makePost(embed: imagesEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(
        find.text(_body),
        findsNothing,
        reason: 'body text is concealed along with the media',
      );
      expect(
        find.text(_title),
        findsOneWidget,
        reason: 'the title stays readable so the reader can judge the post',
      );
      expect(
        find.byType(PostCardActions),
        findsOneWidget,
        reason: 'voting and commenting stay available on a concealed post',
      );
      expect(
        imageUrls(tester),
        isNot(contains(_fullsize)),
        reason: 'the fullsize rendering must never be fetched while concealed',
      );
    });

    testWidgets('both reveal controls announce themselves, the alt text does '
        'not', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpCard(tester, makePost(embed: imagesEmbed()));

      expect(
        find.bySemanticsLabel('Show sensitive content'),
        findsNWidgets(2),
        reason: 'the banner and the placeholder are both reveal controls',
      );
      expect(
        find.bySemanticsLabel(_alt),
        findsNothing,
        reason: 'alt text describes the concealed image and must not leak',
      );

      semantics.dispose();
    });

    testWidgets('the banner sits between the title and the placeholder', (
      tester,
    ) async {
      await pumpCard(tester, makePost(embed: imagesEmbed()));

      final titleBottom = tester.getBottomLeft(find.text(_title)).dy;
      final bannerTop = tester.getTopLeft(find.byKey(_bannerKey)).dy;
      final bannerBottom = tester.getBottomLeft(find.byKey(_bannerKey)).dy;
      final placeholderTop = tester.getTopLeft(find.byKey(_placeholderKey)).dy;

      expect(bannerTop, greaterThanOrEqualTo(titleBottom));
      expect(bannerBottom, lessThanOrEqualTo(placeholderTop));
    });

    testWidgets('an external embed, its link bar and its sources are hidden', (
      tester,
    ) async {
      await pumpCard(
        tester,
        makePost(embed: externalEmbed()),
        config: megathreadConfig,
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
      expect(
        find.byKey(_placeholderKey),
        findsNothing,
        reason: 'only native image embeds get a blurred stand-in',
      );
    });

    testWidgets('a video embed is hidden', (tester) async {
      await pumpCard(tester, makePost(embed: videoEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byKey(_videoKey), findsNothing);
      expect(find.byKey(_placeholderKey), findsNothing);
    });

    testWidgets('a quoted Bluesky post is hidden', (tester) async {
      await pumpCard(tester, makePost(embed: blueskyEmbed()));

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byType(BlueskyPostCard), findsNothing);
    });

    testWidgets('a post with no nsfw label renders as it always has', (
      tester,
    ) async {
      await pumpCard(tester, makePost(embed: imagesEmbed(), sensitive: false));

      expect(find.byKey(_bannerKey), findsNothing);
      expect(find.byKey(_placeholderKey), findsNothing);
      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
    });

    testWidgets('a deleted post carries no banner and does not throw', (
      tester,
    ) async {
      await pumpCard(tester, deletedPost());

      expect(tester.takeException(), isNull);
      expect(find.byKey(_bannerKey), findsNothing);
      expect(find.byKey(_placeholderKey), findsNothing);
    });
  });

  group('PostCard reveal lifecycle', () {
    /// Reveals the post currently in the slot by tapping [control].
    Future<void> tapControl(WidgetTester tester, Key control) async {
      await tester.tap(find.byKey(control));
      await tester.pump();
    }

    void expectRevealed(WidgetTester tester) {
      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsNothing);
      expect(find.text('Hide'), findsOneWidget);
    }

    void expectConcealed(WidgetTester tester) {
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_imagesKey), findsNothing);
      expect(find.text(_body), findsNothing);
      expect(find.text('Show'), findsWidgets);
    }

    testWidgets('tapping the banner reveals the post', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpCard(tester, makePost(embed: imagesEmbed()));
      await tapControl(tester, _bannerKey);

      expectRevealed(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Hide sensitive content')),
        isSemantics(
          isButton: true,
          label: 'Hide sensitive content',
          hasTapAction: true,
        ),
        reason:
            'the node a screen reader announces must also be the node it '
            'can activate to conceal the post again',
      );

      semantics.dispose();
    });

    testWidgets('tapping the placeholder reveals the post', (tester) async {
      await pumpCard(tester, makePost(embed: imagesEmbed()));
      await tapControl(tester, _placeholderKey);

      expectRevealed(tester);
    });

    testWidgets('tapping the banner twice conceals the post again', (
      tester,
    ) async {
      await pumpCard(tester, makePost(embed: imagesEmbed()));
      await tapControl(tester, _bannerKey);
      await tapControl(tester, _bannerKey);

      expectConcealed(tester);
    });

    testWidgets('a vote on a revealed post leaves it revealed', (tester) async {
      final post = makePost(embed: imagesEmbed());
      final notifier = await pumpCard(tester, post);
      await tapControl(tester, _bannerKey);

      // What a vote does to the feed: the same post, restamped with new
      // stats. Re-concealing here would punish the reader for voting.
      notifier.value = post.copyWith(
        post: post.post.copyWith(stats: post.post.stats.copyWith(score: 7)),
      );
      await tester.pump();

      expectRevealed(tester);
    });

    testWidgets('a different post in the same slot arrives concealed', (
      tester,
    ) async {
      final notifier = await pumpCard(tester, makePost(embed: imagesEmbed()));
      await tapControl(tester, _bannerKey);

      notifier.value = makePost(uri: _uriB, embed: imagesEmbed());
      await tester.pump();

      expectConcealed(tester);
    });

    testWidgets('returning to a revealed post finds it concealed again', (
      tester,
    ) async {
      // A -> B -> A in one slot: the reveal must be keyed to the post that
      // is showing now, not merely differ from the last uri seen.
      final postA = makePost(embed: imagesEmbed());
      final notifier = await pumpCard(tester, postA);
      await tapControl(tester, _bannerKey);

      notifier.value = makePost(uri: _uriB, embed: imagesEmbed());
      await tester.pump();

      notifier.value = postA;
      await tester.pump();

      expectConcealed(tester);
    });

    testWidgets('the reply screen configuration conceals and reveals too', (
      tester,
    ) async {
      await pumpCard(
        tester,
        makePost(embed: imagesEmbed()),
        config: replyConfig,
      );

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.text(_body), findsNothing);

      await tapControl(tester, _bannerKey);

      expect(find.text(_body), findsOneWidget);
      expect(find.byKey(_imagesKey), findsOneWidget);
    });
  });
}
