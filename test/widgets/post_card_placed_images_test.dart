// B8: a feed PostCard lays its media out from the unplaced images only: no
// media block when every image is placed, a swipeable gallery of the
// unplaced ones with page dots otherwise, and the sensitive stand-in still
// covering a concealed post whose images are all placed.
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _imagesKey = Key('post-images-embed');
const _countBadgeKey = Key('post-images-count-badge');
const _pageIndicatorKey = Key('post-images-page-indicator');
const _viewerKey = Key('image-viewer');
const _viewerIndicatorKey = Key('image-viewer-page-indicator');
const _placeholderKey = Key('sensitive-image-placeholder');

const _text =
    'Trip notes\n\n[image 1]\n\n[image 2]\n\n[image 3]\n\n[image 4]\n\nEnd';

const _images = [
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
  EmbedImage(
    thumb: 'https://cdn.test/t3.jpg',
    fullsize: 'https://cdn.test/f3.jpg',
  ),
];

/// `#image` facet placing image [index] over [span] in [_text].
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

final _allPlaced = [
  _place('[image 1]', 0),
  _place('[image 2]', 1),
  _place('[image 3]', 2),
  _place('[image 4]', 3),
];

PostEmbed _imagesEmbed() => ImagesPostEmbed(
  type: 'social.coves.embed.images#view',
  images: _images,
  data: const {},
);

PostEmbed _withExternal() => ImagesWithAttachmentPostEmbed(
  type: 'social.coves.embed.imagesWithAttachment#view',
  images: _images,
  attachment: ExternalAttachment(
    ExternalEmbed(
      uri: 'https://example.com/article',
      title: 'An article worth reading',
    ),
  ),
  data: const {},
);

FeedViewPost _post(
  PostEmbed embed,
  List<RichTextFacet> facets, {
  bool sensitive = false,
  String text = _text,
}) => FeedViewPost(
  post: PostView(
    uri: 'at://did:plc:author/social.coves.community.post/p1',
    cid: 'cid-p1',
    rkey: 'p1',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
    createdAt: DateTime(2024),
    indexedAt: DateTime(2024),
    record: PostRecord(
      title: 'Photos from the coast',
      content: text,
      facets: facets,
      labels: sensitive ? const ['nsfw'] : const [],
    ),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    embed: embed,
  ),
);

Future<void> _pumpCard(WidgetTester tester, FeedViewPost post) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              // A fresh state per post, so a second pump re-lays out
              key: ObjectKey(post),
              post: post,
              sessionStamp: null,
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: postCardProviders(auth: FakeAuthProvider()),
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pump();
}

/// The dots inside the indicator keyed [indicatorKey].
MediaPageDots _dots(WidgetTester tester, Key indicatorKey) {
  final finder = find.descendant(
    of: find.byKey(indicatorKey),
    matching: find.byType(MediaPageDots),
    matchRoot: true,
  );
  expect(finder, findsOneWidget, reason: '$indicatorKey should hold dots');
  return tester.widget<MediaPageDots>(finder);
}

/// The url of the image under the centre of the feed media block: the page
/// the user is looking at.
String _visibleImageUrl(WidgetTester tester) {
  final centre = tester.getRect(find.byKey(_imagesKey)).center;
  final visible = find
      .descendant(
        of: find.byKey(_imagesKey),
        matching: find.byType(CachedNetworkImage),
      )
      .evaluate()
      .where((element) {
        final box = element.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        return rect.contains(centre);
      })
      .toList();
  expect(visible, hasLength(1), reason: 'one page fills the media block');
  return (visible.single.widget as CachedNetworkImage).imageUrl;
}

String _previewText(WidgetTester tester) => tester
    .widget<RichText>(
      find.descendant(
        of: find.byType(RichTextRenderer),
        matching: find.byType(RichText),
      ),
    )
    .text
    .toPlainText();

void main() {
  testWidgets('every image placed reads as a text post; labelled nsfw it is '
      'still concealed', (tester) async {
    await _pumpCard(tester, _post(_imagesEmbed(), _allPlaced));

    expect(find.byKey(_imagesKey), findsNothing);
    expect(find.byKey(_placeholderKey), findsNothing);
    expect(_previewText(tester), 'Trip notes\n\nEnd');

    await _pumpCard(tester, _post(_imagesEmbed(), _allPlaced, sensitive: true));

    expect(find.byKey(_placeholderKey), findsOneWidget);
    expect(find.textContaining('Trip notes', findRichText: true), findsNothing);
  });

  testWidgets('a body of only placed images draws no preview box', (
    tester,
  ) async {
    const text = '[image 1]\n\n[image 2]';
    await _pumpCard(
      tester,
      _post(_imagesEmbed(), [
        _place('[image 1]', 0, text: text),
        _place('[image 2]', 1, text: text),
      ], text: text),
    );

    expect(find.byType(RichTextRenderer), findsNothing);
    // The two unplaced images still show as media
    expect(find.byKey(_imagesKey), findsOneWidget);
  });

  testWidgets('two of four placed shows a gallery of the two unplaced '
      'images with page dots', (tester) async {
    await _pumpCard(
      tester,
      _post(_imagesEmbed(), [_place('[image 1]', 0), _place('[image 2]', 1)]),
    );

    expect(_visibleImageUrl(tester), 'https://cdn.test/t2.jpg');
    expect(_dots(tester, _pageIndicatorKey).count, 2);
    expect(_dots(tester, _pageIndicatorKey).index, 0);
    expect(find.byKey(_countBadgeKey), findsNothing);
  });

  testWidgets('B2 acceptance: the feed media block is a swipeable gallery of '
      'the unplaced images that opens the viewer on the current page', (
    tester,
  ) async {
    final images = [
      _images[0],
      EmbedImage(
        thumb: 'https://cdn.test/t1.jpg',
        fullsize: 'https://cdn.test/f1.jpg',
        aspectRatio: EmbedAspectRatio(width: 9, height: 16),
      ),
      _images[2],
      _images[3],
    ];
    final embed = ImagesPostEmbed(
      type: 'social.coves.embed.images#view',
      images: images,
      data: const {},
    );
    await _pumpCard(tester, _post(embed, [_place('[image 1]', 0)]));

    // The frame follows the first unplaced image, clamped to the feed's 3:4.
    expect(
      tester
          .widget<AspectRatio>(
            find
                .descendant(
                  of: find.byKey(_imagesKey),
                  matching: find.byType(AspectRatio),
                )
                .first,
          )
          .aspectRatio,
      closeTo(3 / 4, 0.001),
    );
    expect(find.byKey(_countBadgeKey), findsNothing);
    expect(_visibleImageUrl(tester), 'https://cdn.test/t1.jpg');
    expect(_dots(tester, _pageIndicatorKey).count, 3);
    expect(_dots(tester, _pageIndicatorKey).index, 0);

    await tester.drag(find.byKey(_imagesKey), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(_dots(tester, _pageIndicatorKey).index, 1);
    expect(_visibleImageUrl(tester), 'https://cdn.test/t2.jpg');

    await tester.tap(find.byKey(_imagesKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_viewerKey), findsOneWidget);
    expect(_dots(tester, _viewerIndicatorKey).count, 3);
    expect(_dots(tester, _viewerIndicatorKey).index, 1);
    expect(
      tester
          .widgetList<CachedNetworkImage>(
            find.descendant(
              of: find.byKey(_viewerKey),
              matching: find.byType(CachedNetworkImage),
            ),
          )
          .map((image) => image.imageUrl),
      contains('https://cdn.test/f2.jpg'),
    );
  });

  testWidgets('every image placed with a link attachment keeps only the link '
      'bar', (tester) async {
    await _pumpCard(tester, _post(_withExternal(), _allPlaced));

    expect(find.byKey(_imagesKey), findsNothing);
    expect(find.byType(ExternalLinkBar), findsOneWidget);
  });
}
