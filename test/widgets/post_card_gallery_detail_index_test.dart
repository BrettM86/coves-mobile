// Swiping a feed card's gallery and then opening the post carries the page
// into the detail view, which opens its gallery on the same image.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _title = 'Photos from the coast';

FeedViewPost _post({String rkey = 'p1'}) => FeedViewPost(
  post: PostView(
    uri: 'at://did:plc:author/social.coves.community.post/$rkey',
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
      images: [
        for (var i = 0; i < 3; i++)
          EmbedImage(
            thumb: 'https://cdn.test/t$i.jpg',
            fullsize: 'https://cdn.test/f$i.jpg',
          ),
      ],
      data: const {},
    ),
  ),
);

void main() {
  testWidgets('opening the post after a swipe opens the detail gallery on '
      'the same page', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PostDetailRouteExtra? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: _post(), sessionStamp: null),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) {
            final extra = opened = state.extra as PostDetailRouteExtra?;
            return Scaffold(
              body: SingleChildScrollView(
                child: DetailedPostView(
                  post: extra!.post,
                  initialImageIndex: extra.initialImageIndex,
                ),
              ),
            );
          },
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

    await tester.drag(
      find.byKey(const Key('post-images-embed')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();

    expect(opened?.initialImageIndex, 1);
    final dots = tester.widget<MediaPageDots>(
      find.descendant(
        of: find.byKey(const Key('detail-images-page-indicator')),
        matching: find.byType(MediaPageDots),
        matchRoot: true,
      ),
    );
    expect(dots.index, 1);
    final page = tester
        .widget<PageView>(
          find.descendant(
            of: find.byKey(const Key('detail-images-embed')),
            matching: find.byType(PageView),
          ),
        )
        .controller!
        .page;
    expect(page, 1);
  });

  testWidgets('a post opened without a swipe starts on the first page', (
    tester,
  ) async {
    PostDetailRouteExtra? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: _post(), sessionStamp: null),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) {
            opened = state.extra as PostDetailRouteExtra?;
            return const SizedBox();
          },
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
    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();

    expect(opened?.initialImageIndex, 0);
  });

  testWidgets('the comment button also opens the post on the swiped page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PostDetailRouteExtra? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: _post(), sessionStamp: null),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) {
            opened = state.extra as PostDetailRouteExtra?;
            return const SizedBox();
          },
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
    await tester.drag(
      find.byKey(const Key('post-images-embed')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('post-images-embed')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.endsWith(' comments') ?? false),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened?.initialImageIndex, 2);
  });

  testWidgets('a card reused for another post with the same images starts '
      'over on the first page, in the feed and in the post', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shown = ValueNotifier(_post());
    addTearDown(shown.dispose);
    PostDetailRouteExtra? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: shown,
                builder: (context, post, _) =>
                    PostCard(post: post, sessionStamp: null),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) {
            opened = state.extra as PostDetailRouteExtra?;
            return const SizedBox();
          },
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
    await tester.drag(
      find.byKey(const Key('post-images-embed')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    // Same element, a different post whose images are identical (a
    // crosspost, say).
    shown.value = _post(rkey: 'p2');
    await tester.pumpAndSettle();

    final dots = tester.widget<MediaPageDots>(
      find.descendant(
        of: find.byKey(const Key('post-images-page-indicator')),
        matching: find.byType(MediaPageDots),
        matchRoot: true,
      ),
    );
    expect(dots.index, 0);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(opened?.post.post.uri, endsWith('/p2'));
    expect(opened?.initialImageIndex, 0);
  });
}
