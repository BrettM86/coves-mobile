// B6: DetailedPostView renders an imagesWithAttachment#view post: the
// gallery above the body and the link card below the images, a single image
// with its link card, nothing for a quote attachment, and the sensitive
// stand-in when concealed.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _imagesKey = Key('detail-images-embed');
const _pageIndicatorKey = Key('detail-images-page-indicator');
const _placeholderKey = Key('sensitive-image-placeholder');

const _body = 'Body of the post under the photos';

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';
const _thumb3 = 'https://cdn.test/t3.jpg';
const _full1 = 'https://cdn.test/f1.jpg';
const _full2 = 'https://cdn.test/f2.jpg';
const _full3 = 'https://cdn.test/f3.jpg';

const _linkUri = 'https://example.com/article';
const _quoteUri = 'at://did:plc:quoted/social.coves.community.post/q1';
const _quoteCid = 'bafyquotedcid';

const _threeImages = [
  EmbedImage(thumb: _thumb1, fullsize: _full1),
  EmbedImage(thumb: _thumb2, fullsize: _full2),
  EmbedImage(thumb: _thumb3, fullsize: _full3),
];

List<Map<String, dynamic>> _raw(List<EmbedImage> images) => [
  for (final image in images)
    {'thumb': image.thumb, 'fullsize': image.fullsize},
];

/// Built directly so a failure here is about rendering, not parsing.
PostEmbed _withExternal(List<EmbedImage> images) =>
    ImagesWithAttachmentPostEmbed(
      type: 'social.coves.embed.imagesWithAttachment#view',
      images: images,
      attachment: ExternalAttachment(
        ExternalEmbed(uri: _linkUri, title: 'An article worth reading'),
      ),
      data: {
        r'$type': 'social.coves.embed.imagesWithAttachment#view',
        'images': {
          r'$type': 'social.coves.embed.images#view',
          'images': _raw(images),
        },
        'attachment': {
          r'$type': 'social.coves.embed.external#viewExternal',
          'uri': _linkUri,
          'title': 'An article worth reading',
        },
      },
    );

PostEmbed _withQuote() => ImagesWithAttachmentPostEmbed(
  type: 'social.coves.embed.imagesWithAttachment#view',
  images: _threeImages,
  attachment: const QuoteAttachment(uri: _quoteUri, cid: _quoteCid),
  data: {
    r'$type': 'social.coves.embed.imagesWithAttachment#view',
    'images': {
      r'$type': 'social.coves.embed.images#view',
      'images': _raw(_threeImages),
    },
    'attachment': {
      r'$type': 'social.coves.embed.post#view',
      'post': {'uri': _quoteUri, 'cid': _quoteCid},
    },
  },
);

void main() {
  /// A tall phone surface; the harness scrolls like the real SliverList.
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
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(child: DetailedPostView(post: post)),
        ),
      ),
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
          content: _body,
          labels: sensitive ? const ['nsfw'] : const [],
        ),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        embed: embed,
      ),
    );
  }

  Future<void> pumpDetail(WidgetTester tester, FeedViewPost post) async {
    useDetailSurface(tester);
    await tester.pumpWidget(harness(post));
    await tester.pump();
  }

  group('DetailedPostView imagesWithAttachment embed', () {
    testWidgets(
      'B6 three images and a link put the gallery above the body and the '
      'link card below the images',
      (tester) async {
        await pumpDetail(tester, makePost(_withExternal(_threeImages)));

        expect(find.byKey(_imagesKey), findsOneWidget);
        final dots = find.descendant(
          of: find.byKey(_pageIndicatorKey),
          matching: find.byType(MediaPageDots),
          matchRoot: true,
        );
        expect(dots, findsOneWidget);
        expect(tester.widget<MediaPageDots>(dots).count, 3);
        expect(tester.widget<MediaPageDots>(dots).index, 0);
        expect(find.text(_body), findsOneWidget);
        expect(find.byType(ExternalLinkBar), findsOneWidget);
        expect(
          tester
              .widget<ExternalLinkBar>(find.byType(ExternalLinkBar))
              .embed
              .uri,
          _linkUri,
        );

        final galleryBottom = tester.getBottomLeft(find.byKey(_imagesKey)).dy;
        expect(
          tester.getTopLeft(find.text(_body)).dy,
          greaterThanOrEqualTo(galleryBottom),
          reason: 'the gallery sits above the body text',
        );
        expect(
          tester.getTopLeft(find.byType(ExternalLinkBar)).dy,
          greaterThanOrEqualTo(galleryBottom),
          reason: 'the link card sits below the images',
        );
      },
    );

    testWidgets('B6 a single image and a link render the image and the link '
        'card', (tester) async {
      await pumpDetail(tester, makePost(_withExternal([_threeImages.first])));

      expect(tester.takeException(), isNull);
      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byKey(_pageIndicatorKey), findsNothing);
      expect(find.byType(ExternalLinkBar), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(ExternalLinkBar)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(_imagesKey)).dy),
      );
    });

    testWidgets(
      'B6 a quote attachment renders the images and nothing for the quote',
      (tester) async {
        await pumpDetail(tester, makePost(_withQuote()));

        expect(find.byKey(_imagesKey), findsOneWidget);
        expect(find.byType(BlueskyPostCard), findsNothing);
        expect(find.byType(ExternalLinkBar), findsNothing);
      },
    );

    testWidgets(
      'B6 an NSFW-concealed post shows the sensitive placeholder instead of '
      'the images',
      (tester) async {
        await pumpDetail(
          tester,
          makePost(_withExternal(_threeImages), sensitive: true),
        );

        expect(find.byKey(_placeholderKey), findsOneWidget);
        expect(find.byKey(_imagesKey), findsNothing);
        expect(find.byType(ExternalLinkBar), findsNothing);
      },
    );
  });
}
