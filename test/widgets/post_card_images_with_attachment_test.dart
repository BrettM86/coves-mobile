// B5: a feed PostCard renders an imagesWithAttachment#view post: the images
// as a swipeable gallery with page dots, the link bar for an external
// attachment, nothing for a quote attachment, and the sensitive stand-in
// when concealed.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/media/streamable_video_embed.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _imagesKey = Key('post-images-embed');
const _countBadgeKey = Key('post-images-count-badge');
const _pageIndicatorKey = Key('post-images-page-indicator');
const _placeholderKey = Key('sensitive-image-placeholder');

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';
const _thumb3 = 'https://cdn.test/t3.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';
const _full3 = 'https://cdn.test/f3.jpg';

const _linkUri = 'https://example.com/article';
const _linkThumb = 'https://cdn.test/link-thumb.jpg';
const _streamableUri = 'https://streamable.com/abc123';
const _quoteUri = 'at://did:plc:quoted/social.coves.community.post/q1';
const _quoteCid = 'bafyquotedcid';

const _images = [
  EmbedImage(thumb: _thumb1, fullsize: _full1),
  EmbedImage(thumb: _thumb2, fullsize: _full2),
  EmbedImage(thumb: _thumb3, fullsize: _full3),
];

const _rawImages = [
  {'thumb': _thumb1, 'fullsize': _full1},
  {'thumb': _thumb2, 'fullsize': _full2},
  {'thumb': _thumb3, 'fullsize': _full3},
];

/// Three images plus a link, built directly so a failure here is about
/// rendering, not parsing. The link carries a thumbnail so a second link
/// block under the images would be visible.
PostEmbed _withExternal() => ImagesWithAttachmentPostEmbed(
  type: 'social.coves.embed.imagesWithAttachment#view',
  images: _images,
  attachment: ExternalAttachment(
    ExternalEmbed(
      uri: _linkUri,
      title: 'An article worth reading',
      thumb: _linkThumb,
    ),
  ),
  data: {
    r'$type': 'social.coves.embed.imagesWithAttachment#view',
    'images': {
      r'$type': 'social.coves.embed.images#view',
      'images': _rawImages,
    },
    'attachment': {
      r'$type': 'social.coves.embed.external#viewExternal',
      'uri': _linkUri,
      'title': 'An article worth reading',
      'thumb': _linkThumb,
    },
  },
);

/// Three images plus a Streamable video link, which as a plain link post
/// would render an in-place video player.
PostEmbed _withStreamable() => ImagesWithAttachmentPostEmbed(
  type: 'social.coves.embed.imagesWithAttachment#view',
  images: _images,
  attachment: ExternalAttachment(
    ExternalEmbed(
      uri: _streamableUri,
      title: 'A clip',
      thumb: _linkThumb,
      embedType: 'video',
      provider: 'streamable',
    ),
  ),
  data: {
    r'$type': 'social.coves.embed.imagesWithAttachment#view',
    'images': {
      r'$type': 'social.coves.embed.images#view',
      'images': _rawImages,
    },
    'attachment': {
      r'$type': 'social.coves.embed.external#viewExternal',
      'uri': _streamableUri,
      'title': 'A clip',
      'thumb': _linkThumb,
      'embedType': 'video',
      'provider': 'streamable',
    },
  },
);

PostEmbed _withQuote() => ImagesWithAttachmentPostEmbed(
  type: 'social.coves.embed.imagesWithAttachment#view',
  images: _images,
  attachment: const QuoteAttachment(uri: _quoteUri, cid: _quoteCid),
  data: {
    r'$type': 'social.coves.embed.imagesWithAttachment#view',
    'images': {
      r'$type': 'social.coves.embed.images#view',
      'images': _rawImages,
    },
    'attachment': {
      r'$type': 'social.coves.embed.post#view',
      'post': {'uri': _quoteUri, 'cid': _quoteCid},
    },
  },
);

void main() {
  /// Phone-sized surface so the full-width media block does not overflow.
  void useMediaSizedSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(FeedViewPost post) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              Scaffold(body: PostCard(post: post, sessionStamp: null)),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) =>
              const Scaffold(body: Text('DETAIL SCREEN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MultiProvider(
      providers: postCardProviders(auth: FakeAuthProvider()),
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  FeedViewPost makePost(PostEmbed embed, {bool sensitive = false}) {
    return FeedViewPost(
      post: PostView(
        uri: 'at://did:plc:author/social.coves.community.post/p1',
        cid: 'cid-p1',
        rkey: 'p1',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: PostRecord(
          title: 'Photos from the trip',
          content: 'Body of the post',
          labels: sensitive ? const ['nsfw'] : const [],
        ),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        embed: embed,
      ),
    );
  }

  Finder inBlock(Key blockKey, Finder matching) => find.descendant(
    of: find.byKey(blockKey),
    matching: matching,
    matchRoot: true,
  );

  /// The feed gallery's page dots.
  MediaPageDots feedDots(WidgetTester tester) {
    final finder = inBlock(_pageIndicatorKey, find.byType(MediaPageDots));
    expect(finder, findsOneWidget, reason: 'the gallery shows page dots');
    return tester.widget<MediaPageDots>(finder);
  }

  group('PostCard imagesWithAttachment embed', () {
    testWidgets(
      'B5 three images and a link show a gallery on its first image with '
      'page dots, and the link bar',
      (tester) async {
        useMediaSizedSurface(tester);
        await tester.pumpWidget(harness(makePost(_withExternal())));
        await tester.pump();

        expect(find.byKey(_imagesKey), findsOneWidget);
        final imageFinder = inBlock(
          _imagesKey,
          find.byType(CachedNetworkImage),
        );
        expect(imageFinder, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
          _thumb1,
        );
        expect(feedDots(tester).count, 3);
        expect(feedDots(tester).index, 0);
        expect(find.byKey(_countBadgeKey), findsNothing);

        expect(find.byType(ExternalLinkBar), findsOneWidget);
        expect(
          tester
              .widget<ExternalLinkBar>(find.byType(ExternalLinkBar))
              .embed
              .uri,
          _linkUri,
        );
        // The images are the media; the link must not add its own
        // thumbnail block under them.
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is CachedNetworkImage && widget.imageUrl == _linkThumb,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'B5 a Streamable link attachment shows the link bar and no video player',
      (tester) async {
        useMediaSizedSurface(tester);
        await tester.pumpWidget(harness(makePost(_withStreamable())));
        await tester.pump();

        expect(find.byKey(_imagesKey), findsOneWidget);
        expect(find.byType(ExternalLinkBar), findsOneWidget);
        expect(find.byType(StreamableVideoEmbed), findsNothing);
      },
    );

    testWidgets(
      'B5 a quote attachment shows the images with no quote card and no link '
      'bar',
      (tester) async {
        useMediaSizedSurface(tester);
        await tester.pumpWidget(harness(makePost(_withQuote())));
        await tester.pump();

        expect(find.byKey(_imagesKey), findsOneWidget);
        expect(feedDots(tester).count, 3);
        expect(find.byKey(_countBadgeKey), findsNothing);
        expect(find.byType(BlueskyPostCard), findsNothing);
        expect(find.byType(ExternalLinkBar), findsNothing);
      },
    );

    testWidgets(
      'B5 an NSFW-concealed post shows the sensitive placeholder instead of '
      'the images',
      (tester) async {
        useMediaSizedSurface(tester);
        await tester.pumpWidget(
          harness(makePost(_withExternal(), sensitive: true)),
        );
        await tester.pump();

        expect(find.byKey(_placeholderKey), findsOneWidget);
        expect(find.byKey(_imagesKey), findsNothing);
        expect(find.byType(ExternalLinkBar), findsNothing);
      },
    );
  });
}
