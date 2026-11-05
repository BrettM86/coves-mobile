// B5/B6: the feed card's swipeable gallery owns horizontal drags that start
// on it, even inside a horizontal feed pager and at its first or last page,
// while vertical drags on it still scroll the feed.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _imagesKey = Key('post-images-embed');
const _title = 'Photos from the coast';

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
];

FeedViewPost _post() => FeedViewPost(
  post: PostView(
    uri: 'at://did:plc:author/social.coves.community.post/p1',
    cid: 'cid-p1',
    rkey: 'p1',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
    createdAt: DateTime(2024),
    indexedAt: DateTime(2024),
    record: const PostRecord(title: _title, content: 'Three photos'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    embed: ImagesPostEmbed(
      type: 'social.coves.embed.images#view',
      images: _images,
      data: const {},
    ),
  ),
);

/// Pumps [body] as the home route on a fixed 400 x 900 surface.
Future<void> _pumpHome(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: body),
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

/// The page the feed card's gallery is on.
double? _galleryPage(WidgetTester tester) => tester
    .widget<PageView>(
      find.descendant(
        of: find.byKey(_imagesKey),
        matching: find.byType(PageView),
      ),
    )
    .controller!
    .page;

/// One drag inside a two-page horizontal feed pager.
typedef _PagerCase = ({
  String name,

  /// The outer page the card sits on, and the pager starts at.
  int cardPage,

  /// Leftward gallery swipes made before the drag under test.
  int galleryPreSwipes,

  /// Whether the drag starts on the gallery or on the card's title.
  bool onGallery,
  Offset drag,
  double expectedOuterPage,

  /// The gallery page after the drag; null when the drag is not on it.
  double? expectedGalleryPage,
});

const List<_PagerCase> _pagerCases = [
  (
    name: '(a) a left drag on gallery page 0 pages the gallery, not the feed',
    cardPage: 0,
    galleryPreSwipes: 0,
    onGallery: true,
    drag: Offset(-300, 0),
    expectedOuterPage: 0,
    expectedGalleryPage: 1,
  ),
  (
    name: '(b) a left drag on the last gallery page leaves the feed in place',
    cardPage: 0,
    galleryPreSwipes: 2,
    onGallery: true,
    drag: Offset(-300, 0),
    expectedOuterPage: 0,
    expectedGalleryPage: 2,
  ),
  (
    name: '(c) a right drag on gallery page 0 leaves the feed on its page',
    cardPage: 1,
    galleryPreSwipes: 0,
    onGallery: true,
    drag: Offset(300, 0),
    expectedOuterPage: 1,
    expectedGalleryPage: 0,
  ),
  (
    name: 'control: a left drag on the card title pages the feed',
    cardPage: 0,
    galleryPreSwipes: 0,
    onGallery: false,
    drag: Offset(-300, 0),
    expectedOuterPage: 1,
    expectedGalleryPage: null,
  ),
];

void main() {
  group('B5 feed gallery inside a horizontal feed pager', () {
    for (final row in _pagerCases) {
      testWidgets(row.name, (tester) async {
        final outer = PageController(initialPage: row.cardPage);
        addTearDown(outer.dispose);

        Widget page(int index) => index == row.cardPage
            ? SingleChildScrollView(
                child: PostCard(post: _post(), sessionStamp: null),
              )
            : const SizedBox.expand();

        await _pumpHome(
          tester,
          PageView(controller: outer, children: [page(0), page(1)]),
        );

        for (var swipe = 0; swipe < row.galleryPreSwipes; swipe++) {
          await tester.drag(find.byKey(_imagesKey), const Offset(-300, 0));
          await tester.pumpAndSettle();
          expect(
            outer.page,
            row.cardPage.toDouble(),
            reason: 'a gallery swipe must not page the feed',
          );
        }

        final target = row.onGallery
            ? find.byKey(_imagesKey)
            : find.text(_title);
        await tester.drag(target, row.drag);
        await tester.pumpAndSettle();

        expect(outer.page, row.expectedOuterPage);
        if (row.expectedGalleryPage != null) {
          expect(_galleryPage(tester), row.expectedGalleryPage);
        }
      });
    }
  });

  testWidgets('B6 a vertical drag starting on the feed gallery scrolls the '
      'feed', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await _pumpHome(
      tester,
      ListView(
        controller: scroll,
        children: [
          PostCard(post: _post(), sessionStamp: null),
          const SizedBox(height: 2000),
        ],
      ),
    );

    await tester.drag(find.byKey(_imagesKey), const Offset(0, -300));
    await tester.pumpAndSettle();

    // The 300px drag less the 20px slop the drag spends before it starts.
    expect(scroll.offset, greaterThanOrEqualTo(280));
  });
}
