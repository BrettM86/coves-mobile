// RED-phase spec for the shared paginated sliver.
//
// Compile-red until lib/widgets/paginated_sliver_list.dart exists. Kept
// self-contained so the rest of the suite still compiles.
//
// PaginatedSliverList carries FeedPage's four anti-jitter fixes generically
// (source: lib/widgets/feed_page.dart):
//   1. an always-reserved footer slot while items are non-empty, so the
//      child count never fluctuates during pagination
//   2. a fixed 80px idle footer, matching the loading spinner's height
//   3. a stable KeyedSubtree key on the footer
//   4. a findChildIndexCallback that maps item keys and the footer
//
// The characterization of the FeedPage behaviour these are extracted from
// lives in test/widgets/feed_page_test.dart.

import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:coves_flutter/widgets/paginated_sliver_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  const _Item(this.id);

  final String id;
}

/// A stateful tile whose counter survives a rebuild only if the element is
/// reused, which is what the item ValueKeys buy us.
class _CounterTile extends StatefulWidget {
  const _CounterTile({required this.label, super.key});

  final String label;

  @override
  State<_CounterTile> createState() => _CounterTileState();
}

class _CounterTileState extends State<_CounterTile> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: GestureDetector(
        onTap: () => setState(() => taps++),
        child: Text('${widget.label}:$taps'),
      ),
    );
  }
}

void main() {
  List<_Item> items(int count) {
    return List<_Item>.generate(count, (i) => _Item('id-$i'));
  }

  Widget host(PaginatedSliverList<_Item> sliver) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: <Widget>[sliver]),
      ),
    );
  }

  PaginatedSliverList<_Item> buildList({
    required List<_Item> data,
    bool isLoadingMore = false,
    bool hasMore = true,
    String? loadMoreError,
    String? refreshError,
    VoidCallback? onRetryLoadMore,
    VoidCallback? onRetryRefresh,
    Widget? endOfFeedWidget,
    Widget? emptyWidget,
    Key? footerKey,
    Widget Function(BuildContext, _Item, int)? itemBuilder,
  }) {
    return PaginatedSliverList<_Item>(
      items: data,
      isLoadingMore: isLoadingMore,
      hasMore: hasMore,
      loadMoreError: loadMoreError,
      refreshError: refreshError,
      onRetryLoadMore: onRetryLoadMore ?? () {},
      onRetryRefresh: onRetryRefresh ?? (refreshError == null ? null : () {}),
      idOf: (item) => item.id,
      footerKey: footerKey,
      endOfFeedWidget: endOfFeedWidget,
      emptyWidget: emptyWidget,
      itemBuilder:
          itemBuilder ??
          (context, item, index) =>
              SizedBox(height: 120, child: Text(item.id)),
    );
  }

  SliverChildDelegate delegateOf(WidgetTester tester) {
    final adaptor = tester.widget<SliverMultiBoxAdaptorWidget>(
      find.byWidgetPredicate((w) => w is SliverMultiBoxAdaptorWidget),
    );
    return adaptor.delegate;
  }

  int childCountOf(WidgetTester tester) {
    return delegateOf(tester).estimatedChildCount!;
  }

  Finder footerFinder() {
    return find.byWidgetPredicate(
      (w) =>
          w is KeyedSubtree &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.endsWith('_footer'),
    );
  }

  group('stable child count', () {
    testWidgets('the footer slot is reserved while items are non-empty', (
      tester,
    ) async {
      await tester.pumpWidget(host(buildList(data: items(3))));

      expect(childCountOf(tester), 4);
      expect(footerFinder(), findsOneWidget);
    });

    testWidgets('child count does not change when isLoadingMore toggles', (
      tester,
    ) async {
      await tester.pumpWidget(host(buildList(data: items(3))));
      final idle = childCountOf(tester);

      await tester.pumpWidget(
        host(buildList(data: items(3), isLoadingMore: true)),
      );
      final loading = childCountOf(tester);

      await tester.pumpWidget(host(buildList(data: items(3))));

      expect(loading, idle);
      expect(childCountOf(tester), idle);
    });

    testWidgets('child count does not change when a load-more error '
        'appears', (tester) async {
      await tester.pumpWidget(host(buildList(data: items(3))));
      final idle = childCountOf(tester);

      await tester.pumpWidget(
        host(buildList(data: items(3), loadMoreError: 'nope')),
      );

      expect(childCountOf(tester), idle);
    });

    testWidgets('no footer slot is reserved when there are no items', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: const <_Item>[],
            emptyWidget: const Text('nothing here'),
          ),
        ),
      );

      expect(footerFinder(), findsNothing);
      expect(find.text('nothing here'), findsOneWidget);
    });
  });

  group('footer states', () {
    testWidgets('the idle footer reserves exactly 80px', (tester) async {
      await tester.pumpWidget(host(buildList(data: items(1))));

      expect(tester.getSize(footerFinder()).height, 80.0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the idle and loading footers are exactly the same height', (
      tester,
    ) async {
      // The invariant behind the reserved footer slot: swapping the spacer
      // for the spinner must not move the scroll offset. This is
      // structural — both sides are sized from kInlineLoadingHeight — not
      // a coincidence of the spinner's intrinsic size (which is 68px).
      await tester.pumpWidget(host(buildList(data: items(1))));
      final idleHeight = tester.getSize(footerFinder()).height;

      await tester.pumpWidget(
        host(buildList(data: items(1), isLoadingMore: true)),
      );
      final loadingHeight = tester.getSize(footerFinder()).height;

      expect(idleHeight, kInlineLoadingHeight);
      expect(loadingHeight, kInlineLoadingHeight);
    });

    testWidgets('the footer key ends in _footer by default', (tester) async {
      await tester.pumpWidget(host(buildList(data: items(1))));

      expect(footerFinder(), findsOneWidget);
    });

    testWidgets('a footerKey of the wrong shape is rejected', (tester) async {
      // The app-wide convention: ValueKey<String> ending in "_footer".
      // findChildIndexCallback and every footer finder rely on it.
      //
      // Built directly rather than pumped: mounting a widget whose build
      // throws buries the assertion under a "RenderViewport expected a
      // RenderSliver" cascade.
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(
        () => buildList(
          data: items(1),
          footerKey: const ValueKey<String>('community_feed'),
        ).build(context),
        throwsAssertionError,
      );

      expect(
        () => buildList(
          data: items(1),
          footerKey: const ValueKey<int>(7),
        ).build(context),
        throwsAssertionError,
      );

      expect(
        () => buildList(
          data: items(1),
          footerKey: const ValueKey<String>('community_feed_footer'),
        ).build(context),
        returnsNormally,
      );
    });

    testWidgets('an explicit footerKey is used', (tester) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            footerKey: const ValueKey<String>('community_feed_footer'),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('community_feed_footer')),
        findsOneWidget,
      );
    });

    testWidgets('a spinner shows while loading more', (tester) async {
      await tester.pumpWidget(
        host(buildList(data: items(1), isLoadingMore: true)),
      );

      expect(
        find.descendant(
          of: footerFinder(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a load-more error shows a retry that fires the callback', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            loadMoreError: 'Network error. Check your connection.',
            onRetryLoadMore: () => retries++,
          ),
        ),
      );

      expect(
        find.text('Network error. Check your connection.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('the error footer wins over the end-of-feed footer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            hasMore: false,
            loadMoreError: 'boom',
            endOfFeedWidget: const Text("You're all caught up!"),
          ),
        ),
      );

      expect(find.text('boom'), findsOneWidget);
      expect(find.text("You're all caught up!"), findsNothing);
    });

    testWidgets('the spinner wins over the error footer', (tester) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            isLoadingMore: true,
            loadMoreError: 'boom',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('boom'), findsNothing);
    });

    testWidgets('the end-of-feed widget shows when hasMore is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            hasMore: false,
            endOfFeedWidget: const Text("You're all caught up!"),
          ),
        ),
      );

      expect(find.text("You're all caught up!"), findsOneWidget);
    });

    testWidgets('the idle 80px footer is used when no endOfFeedWidget is '
        'supplied', (tester) async {
      await tester.pumpWidget(
        host(buildList(data: items(1), hasMore: false)),
      );

      expect(tester.getSize(footerFinder()).height, 80.0);
    });
  });

  group('failed refresh with items on screen', () {
    // Every screen gates its full-screen error on items.isEmpty, so a
    // pull-to-refresh that fails with content already on screen used to
    // show the user nothing at all. The footer is the one slot that is
    // always reserved, so it carries the message.
    testWidgets('the refresh error shows in the footer', (tester) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(3),
            refreshError: 'Network error. Check your connection.',
          ),
        ),
      );

      expect(
        find.descendant(
          of: footerFinder(),
          matching: find.text('Network error. Check your connection.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('its retry fires onRetryRefresh, not onRetryLoadMore', (
      tester,
    ) async {
      var refreshRetries = 0;
      var loadMoreRetries = 0;

      await tester.pumpWidget(
        host(
          buildList(
            data: items(3),
            refreshError: 'boom',
            onRetryRefresh: () => refreshRetries++,
            onRetryLoadMore: () => loadMoreRetries++,
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(refreshRetries, 1);
      expect(loadMoreRetries, 0);
    });

    testWidgets('a refresh error does not change the child count', (
      tester,
    ) async {
      await tester.pumpWidget(host(buildList(data: items(3))));
      final idle = childCountOf(tester);

      await tester.pumpWidget(
        host(buildList(data: items(3), refreshError: 'boom')),
      );

      expect(childCountOf(tester), idle);
    });

    testWidgets('the load-more error wins over the refresh error', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            loadMoreError: 'pagination boom',
            refreshError: 'refresh boom',
          ),
        ),
      );

      expect(find.text('pagination boom'), findsOneWidget);
      expect(find.text('refresh boom'), findsNothing);
    });

    testWidgets('the refresh error wins over the end-of-feed footer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          buildList(
            data: items(1),
            hasMore: false,
            refreshError: 'refresh boom',
            endOfFeedWidget: const Text("You're all caught up!"),
          ),
        ),
      );

      expect(find.text('refresh boom'), findsOneWidget);
      expect(find.text("You're all caught up!"), findsNothing);
    });
  });

  group('item identity', () {
    testWidgets('each item is keyed by idOf and wrapped in a '
        'RepaintBoundary', (tester) async {
      await tester.pumpWidget(host(buildList(data: items(2))));

      expect(
        find.byKey(const ValueKey<String>('id-0')),
        findsOneWidget,
      );
      expect(
        tester.widget(find.byKey(const ValueKey<String>('id-1'))),
        isA<RepaintBoundary>(),
      );
    });

    testWidgets('findChildIndexCallback maps items, the footer and '
        'unknown keys', (tester) async {
      await tester.pumpWidget(host(buildList(data: items(3))));

      final delegate = delegateOf(tester) as SliverChildBuilderDelegate;
      final indexOfKey = delegate.findChildIndexCallback!;

      expect(indexOfKey(const ValueKey<String>('id-0')), 0);
      expect(indexOfKey(const ValueKey<String>('id-2')), 2);
      expect(indexOfKey(const ValueKey<String>('nope')), isNull);
      expect(indexOfKey(const ValueKey<int>(1)), isNull);

      final footer = tester.widget<KeyedSubtree>(footerFinder());
      expect(indexOfKey(footer.key!), 3);
    });

    testWidgets('prepending an item preserves the existing items state', (
      tester,
    ) async {
      Widget tile(BuildContext context, _Item item, int index) => _CounterTile(
        key: ValueKey<String>('tile-${item.id}'),
        label: item.id,
      );

      await tester.pumpWidget(
        host(buildList(data: items(3), itemBuilder: tile)),
      );

      await tester.tap(find.text('id-1:0'));
      await tester.pump();
      expect(find.text('id-1:1'), findsOneWidget);

      await tester.pumpWidget(
        host(
          buildList(
            data: <_Item>[const _Item('id-new'), ...items(3)],
            itemBuilder: tile,
          ),
        ),
      );

      // The tapped tile kept its state because it kept its key/element.
      expect(find.text('id-1:1'), findsOneWidget);
    });
  });
}
