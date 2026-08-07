// Characterization tests for FeedPage's anti-jitter invariants.
//
// These PASS against the current lib/widgets/feed_page.dart and exist as
// guard rails for the pagination de-duplication work: if FeedPage adopts
// PaginatedSliverList, these four properties must survive the swap.
//
//   1. the footer slot is always reserved while posts are non-empty, so the
//      child count never fluctuates during pagination (feed_page.dart:62-65,
//      :243)
//   2. the footer carries the stable ValueKey('feed_footer') (:203-208)
//   3. the idle footer reserves exactly 80px (:343-346)
//   4. findChildIndexCallback maps post URIs and the footer (:244-261)

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

FeedViewPost buildPost(String id) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:test/social.coves.community.post/$id',
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      community: CommunityRef(
        did: 'did:plc:community',
        name: 'test-community',
        handle: 'test-community.community.coves.social',
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(content: 'Body $id', title: 'Post $id', facets: []),
      stats: PostStats(score: 1, upvotes: 1, downvotes: 0, commentCount: 0),
    ),
  );
}

void main() {
  late FakeAuthProvider auth;
  late ScrollController scrollController;

  setUp(() {
    auth = FakeAuthProvider();
    scrollController = ScrollController();
  });

  tearDown(() {
    scrollController.dispose();
    auth.dispose();
  });

  Widget host({
    required List<FeedViewPost> posts,
    bool isLoadingMore = false,
    bool hasMore = true,
    String? error,
  }) {
    return MultiProvider(
      providers: postCardProviders(auth: auth),
      child: MaterialApp(
        home: Scaffold(
          body: FeedPage(
            feedType: FeedType.discover,
            posts: posts,
            isLoading: false,
            isLoadingMore: isLoadingMore,
            hasMore: hasMore,
            error: error,
            scrollController: scrollController,
            onRefresh: () async {},
            onRetry: () {},
            onClearErrorAndLoadMore: () {},
            isAuthenticated: false,
            currentTime: DateTime.parse('2025-01-01T13:00:00Z'),
          ),
        ),
      ),
    );
  }

  SliverChildBuilderDelegate delegateOf(WidgetTester tester) {
    final adaptor = tester.widget<SliverMultiBoxAdaptorWidget>(
      find.byWidgetPredicate((w) => w is SliverMultiBoxAdaptorWidget),
    );
    return adaptor.delegate as SliverChildBuilderDelegate;
  }

  const footerKey = ValueKey<String>('feed_footer');

  testWidgets('reserves a footer slot while posts are non-empty', (
    tester,
  ) async {
    final posts = <FeedViewPost>[buildPost('a'), buildPost('b')];

    await tester.pumpWidget(host(posts: posts));

    expect(delegateOf(tester).estimatedChildCount, posts.length + 1);
    expect(find.byKey(footerKey), findsOneWidget);
  });

  testWidgets('child count is stable across isLoadingMore toggles', (
    tester,
  ) async {
    final posts = <FeedViewPost>[buildPost('a'), buildPost('b')];

    await tester.pumpWidget(host(posts: posts));
    final idle = delegateOf(tester).estimatedChildCount;

    await tester.pumpWidget(host(posts: posts, isLoadingMore: true));
    final loading = delegateOf(tester).estimatedChildCount;

    await tester.pumpWidget(host(posts: posts));

    expect(loading, idle);
    expect(delegateOf(tester).estimatedChildCount, idle);
  });

  testWidgets('the idle footer reserves exactly 80px', (tester) async {
    await tester.pumpWidget(host(posts: <FeedViewPost>[buildPost('a')]));

    expect(tester.getSize(find.byKey(footerKey)).height, 80.0);
  });

  testWidgets('the footer becomes a spinner while loading more, without '
      'changing the child count', (tester) async {
    final posts = <FeedViewPost>[buildPost('a')];

    await tester.pumpWidget(host(posts: posts, isLoadingMore: true));

    expect(delegateOf(tester).estimatedChildCount, 2);
    expect(
      find.descendant(
        of: find.byKey(footerKey),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('findChildIndexCallback maps post URIs and the footer', (
    tester,
  ) async {
    final posts = <FeedViewPost>[
      buildPost('a'),
      buildPost('b'),
      buildPost('c'),
    ];

    await tester.pumpWidget(host(posts: posts));

    final indexOfKey = delegateOf(tester).findChildIndexCallback!;

    expect(indexOfKey(ValueKey<String>(posts[0].post.uri)), 0);
    expect(indexOfKey(ValueKey<String>(posts[2].post.uri)), 2);
    expect(indexOfKey(footerKey), posts.length);
    expect(indexOfKey(const ValueKey<String>('at://unknown')), isNull);
    expect(indexOfKey(const ValueKey<int>(0)), isNull);
  });

  testWidgets('each post is keyed by its URI', (tester) async {
    final posts = <FeedViewPost>[buildPost('a')];

    await tester.pumpWidget(host(posts: posts));

    expect(find.byKey(ValueKey<String>(posts[0].post.uri)), findsOneWidget);
  });
}
