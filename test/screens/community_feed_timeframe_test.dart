// Top-sort time period on the community feed.
//
// With Top selected, a period chip sits right after the Top chip, labelled
// with the current period. Its popup menu picks the period, and every
// community-feed request made under Top carries it as `timeframe`. Hot and
// New send no timeframe and hide the chip.
//
// Request assertions spell out null timeframes and cursors on purpose.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:async';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/community_feed_harness.dart';
import '../test_helpers/test_mocks.dart';

const ValueKey<String> timeframeChipKey = ValueKey<String>(
  'community_feed_timeframe_chip',
);
const ValueKey<String> searchButtonKey = ValueKey<String>(
  'community_feed_search_button',
);
const ValueKey<String> searchFieldKey = ValueKey<String>(
  'community_feed_search_field',
);
const ValueKey<String> searchCloseKey = ValueKey<String>(
  'community_feed_search_close',
);

Finder get timeframeChip => find.byKey(timeframeChipKey);

/// The open menu's row for [label]; the chip's own label is not inside one.
Finder menuItem(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is MenuItemButton),
);

/// The title of the single post the stub serves for a first page.
String firstPageTitle(String sort, String? timeframe) =>
    '$sort ${timeframe ?? 'none'} post';

/// The title of the post the stub serves for the page after cursor 'c1'.
String secondPageTitle(String sort, String? timeframe) =>
    '$sort ${timeframe ?? 'none'} page 2';

void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Bounded frames for while a spinner keeps pumpAndSettle from returning.
Future<void> pumpFrames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  /// Answers every community-feed request with one post named after its
  /// sort and timeframe. A first page whose 'sort/timeframe' key is in
  /// [held] waits on that completer; the first page for [pagedKey] carries
  /// cursor 'c1', and the page after it ends the feed. [filler] extra
  /// posts follow the named post on every unheld first page.
  void stubFeed({
    Map<String, Completer<TimelineResponse>> held = const {},
    String? pagedKey,
    int filler = 0,
  }) {
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer((_) async => buildFeedTestCommunity());

    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) {
      final sort = invocation.namedArguments[#sort] as String;
      final timeframe = invocation.namedArguments[#timeframe] as String?;
      final cursor = invocation.namedArguments[#cursor] as String?;
      final key = '$sort/$timeframe';
      if (cursor == 'c1') {
        final title = secondPageTitle(sort, timeframe);
        return Future.value(
          TimelineResponse(
            feed: [
              buildFeedTestPost(rkey: title.replaceAll(' ', '-'), title: title),
            ],
          ),
        );
      }
      final completer = held[key];
      if (completer != null) {
        return completer.future;
      }
      final title = firstPageTitle(sort, timeframe);
      return Future.value(
        TimelineResponse(
          feed: [
            buildFeedTestPost(rkey: title.replaceAll(' ', '-'), title: title),
            for (var i = 0; i < filler; i++)
              buildFeedTestPost(
                rkey: '${title.replaceAll(' ', '-')}-filler-$i',
                title: '$title filler $i',
              ),
          ],
          cursor: key == pagedKey ? 'c1' : null,
        ),
      );
    });
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await pumpCommunityFeedScreen(tester, mockApiService);
    await tester.pumpAndSettle();
  }

  Future<void> tapSort(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> openTimeframeMenu(WidgetTester tester) async {
    expect(timeframeChip, findsOneWidget);
    await tester.ensureVisible(timeframeChip);
    await tester.pumpAndSettle();
    await tester.tap(timeframeChip);
    await tester.pumpAndSettle();
  }

  Future<void> selectTimeframe(WidgetTester tester, String label) async {
    await openTimeframeMenu(tester);
    await tester.tap(menuItem(label));
    await tester.pumpAndSettle();
  }

  testWidgets('at 320x640, choosing Top asks for the top feed of all time '
      'and shows an All time period chip right after Top that scrolls into '
      'view and opens its menu', (tester) async {
    useSurface(tester, const Size(320, 640));
    stubFeed();
    await pumpScreen(tester);

    await tapSort(tester, 'Top');

    verify(
      mockApiService.getCommunityFeed(
        community: communityFeedTestDid,
        sort: 'top',
        timeframe: 'all',
        limit: anyNamed('limit'),
        // Omitted: the mock's null default is the only cursor that matches.
      ),
    );

    expect(timeframeChip, findsOneWidget);
    expect(
      find.descendant(of: timeframeChip, matching: find.text('All time')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: timeframeChip,
        matching: find.byWidgetPredicate(
          (widget) =>
              (widget is Icon &&
                  <IconData>{
                    Icons.schedule,
                    Icons.schedule_outlined,
                    Icons.access_time,
                    Icons.access_time_outlined,
                    Icons.access_time_filled,
                  }.contains(widget.icon)) ||
              (widget is AppIcon && widget.iconName.contains('clock')),
        ),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(timeframeChip);
    await tester.pumpAndSettle();

    // Right after the Top chip, in the same row.
    final topRight = tester.getTopRight(find.text('Top'));
    final chipLeft = tester.getTopLeft(timeframeChip);
    expect(chipLeft.dx, greaterThan(topRight.dx));
    expect(chipLeft.dx - topRight.dx, lessThan(32));
    expect(
      (tester.getCenter(timeframeChip).dy -
              tester.getCenter(find.text('Top')).dy)
          .abs(),
      lessThan(4),
    );

    await tester.tap(timeframeChip);
    await tester.pumpAndSettle();

    expect(menuItem('Past week'), findsOneWidget);
    expect(menuItem('All time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the period menu lists every period in order with a check on '
      'the current one, and each choice reloads Top with its timeframe', (
    tester,
  ) async {
    useSurface(tester, const Size(400, 1600));
    stubFeed();
    await pumpScreen(tester);
    await tapSort(tester, 'Top');

    const labels = [
      'Past hour',
      'Past day',
      'Past week',
      'Past month',
      'Past year',
      'All time',
    ];
    // (label to choose, timeframe it must send). All time comes last so it
    // is never the current period when chosen.
    const rows = [
      ('Past hour', 'hour'),
      ('Past day', 'day'),
      ('Past week', 'week'),
      ('Past month', 'month'),
      ('Past year', 'year'),
      ('All time', 'all'),
    ];

    var current = 'All time';
    for (final (label, timeframe) in rows) {
      await openTimeframeMenu(tester);

      final tops = [
        for (final item in labels) tester.getTopLeft(menuItem(item)).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: '${labels[i]} below ${labels[i - 1]}',
        );
      }
      for (final item in labels) {
        expect(
          find.descendant(
            of: menuItem(item),
            matching: find.byIcon(Icons.check),
          ),
          item == current ? findsOneWidget : findsNothing,
          reason: 'check on $item while $current is current',
        );
      }

      clearInteractions(mockApiService);
      await tester.tap(menuItem(label));
      await tester.pumpAndSettle();

      verify(
        mockApiService.getCommunityFeed(
          community: communityFeedTestDid,
          sort: 'top',
          timeframe: timeframe,
          limit: anyNamed('limit'),
        ),
      );
      expect(find.text(firstPageTitle('top', timeframe)), findsOneWidget);
      expect(
        find.descendant(of: timeframeChip, matching: find.text(label)),
        findsOneWidget,
      );
      current = label;
    }

    await openTimeframeMenu(tester);
    expect(
      find.descendant(
        of: menuItem('All time'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: menuItem('Past year'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('leaving Top for Hot or New sends no timeframe and hides the '
      'period chip', (tester) async {
    useSurface(tester, const Size(400, 1600));
    stubFeed();
    await pumpScreen(tester);

    for (final (label, sort) in const [('Hot', 'hot'), ('New', 'new')]) {
      await tapSort(tester, 'Top');
      await selectTimeframe(tester, 'Past week');

      clearInteractions(mockApiService);
      await tapSort(tester, label);

      verify(
        mockApiService.getCommunityFeed(
          community: communityFeedTestDid,
          sort: sort,
          timeframe: null,
          limit: anyNamed('limit'),
          cursor: null,
        ),
      );
      expect(timeframeChip, findsNothing, reason: 'after switching to $label');
    }
  });

  testWidgets('returning to Top keeps the period chosen before leaving it', (
    tester,
  ) async {
    useSurface(tester, const Size(400, 1600));
    stubFeed();
    await pumpScreen(tester);

    await tapSort(tester, 'Top');
    await selectTimeframe(tester, 'Past week');
    await tapSort(tester, 'Hot');

    clearInteractions(mockApiService);
    await tapSort(tester, 'Top');

    verify(
      mockApiService.getCommunityFeed(
        community: communityFeedTestDid,
        sort: 'top',
        timeframe: 'week',
        limit: anyNamed('limit'),
      ),
    );
    expect(
      find.descendant(of: timeframeChip, matching: find.text('Past week')),
      findsOneWidget,
    );
  });

  testWidgets('a page for the previous period that lands after the new '
      'period is discarded', (tester) async {
    useSurface(tester, const Size(400, 1600));
    final allTime = Completer<TimelineResponse>();
    final pastWeek = Completer<TimelineResponse>();
    stubFeed(held: {'top/all': allTime, 'top/week': pastWeek});
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Top'));
    await pumpFrames(tester);
    await tester.tap(find.text('Top'));
    await pumpFrames(tester);

    expect(timeframeChip, findsOneWidget);
    await tester.ensureVisible(timeframeChip);
    await pumpFrames(tester);
    await tester.tap(timeframeChip);
    await pumpFrames(tester);
    await tester.tap(menuItem('Past week'));
    await pumpFrames(tester);

    pastWeek.complete(
      TimelineResponse(
        feed: [buildFeedTestPost(rkey: 'week-1', title: 'Week winner')],
      ),
    );
    await pumpFrames(tester);
    expect(find.text('Week winner'), findsOneWidget);

    allTime.complete(
      TimelineResponse(
        feed: [buildFeedTestPost(rkey: 'all-1', title: 'All time winner')],
      ),
    );
    await pumpFrames(tester);

    expect(find.text('All time winner'), findsNothing);
    expect(find.text('Week winner'), findsOneWidget);
  });

  testWidgets('load-more, pull-to-refresh and closing a search all keep the '
      'chosen period, and search requests are unchanged', (tester) async {
    useSurface(tester, const Size(400, 1600));
    stubFeed(pagedKey: 'top/week');
    when(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedTestPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );
    await pumpScreen(tester);

    await tapSort(tester, 'Top');
    await selectTimeframe(tester, 'Past week');

    // Load-more: the next page keeps the period.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    verify(
      mockApiService.getCommunityFeed(
        community: communityFeedTestDid,
        sort: 'top',
        timeframe: 'week',
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    );
    expect(find.text(secondPageTitle('top', 'week')), findsOneWidget);

    // Pull-to-refresh reloads the first page at the same period.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    clearInteractions(mockApiService);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    verify(
      mockApiService.getCommunityFeed(
        community: communityFeedTestDid,
        sort: 'top',
        timeframe: 'week',
        limit: anyNamed('limit'),
      ),
    );

    // A submitted search is a plain relevance search with no period.
    clearInteractions(mockApiService);
    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(searchFieldKey), 'linux');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityFeedTestDid,
        // Pinned against the API default so search stays a relevance search.
        sort: 'relevance',
        timeframe: null,
        limit: anyNamed('limit'),
        cursor: null,
      ),
    );
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    // Closing the search restores Top at the chosen period, from the top.
    clearInteractions(mockApiService);
    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();
    verify(
      mockApiService.getCommunityFeed(
        community: communityFeedTestDid,
        sort: 'top',
        timeframe: 'week',
        limit: anyNamed('limit'),
      ),
    );
    expect(
      find.descendant(of: timeframeChip, matching: find.text('Past week')),
      findsOneWidget,
    );
  });

  testWidgets('changing the period or the sort drops the previous posts and '
      'next-page cursor at once, even when the new first page fails', (
    tester,
  ) async {
    useSurface(tester, const Size(400, 1600));
    final pastWeek = Completer<TimelineResponse>();
    final newest = Completer<TimelineResponse>();
    stubFeed(
      held: {'top/week': pastWeek, 'new/null': newest},
      pagedKey: 'top/all',
      // Enough posts that the first page overfills the viewport, so 'c1' is
      // only requested by scrolling.
      filler: 30,
    );
    await pumpScreen(tester);
    final chipRow = find.ancestor(
      of: find.text('Hot'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );

    // Period: Top/All time has a first page with a next cursor. The sort
    // chips sit on screen at this width; ensureVisible would scroll the
    // feed itself and trigger load-more.
    await tester.tap(find.text('Top'));
    await pumpFrames(tester);
    expect(find.text('top all post'), findsOneWidget);
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    );

    // Scroll only the chip row to bring the period chip clear of the
    // search button.
    await tester.drag(chipRow, const Offset(-200, 0));
    await pumpFrames(tester);
    await tester.tap(timeframeChip);
    await pumpFrames(tester);
    await tester.tap(menuItem('Past week'));
    await pumpFrames(tester);
    expect(
      find.text('top all post'),
      findsNothing,
      reason: 'All time posts are dropped while Past week loads',
    );

    pastWeek.completeError(Exception('week failed'));
    await pumpFrames(tester);
    expect(
      find.text('top all post'),
      findsNothing,
      reason: 'All time posts stay dropped after Past week fails',
    );

    final feedScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    expect(feedScrollable, findsOneWidget);
    await tester.drag(feedScrollable, const Offset(0, -2000));
    await pumpFrames(tester);
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    );

    // Sort: Hot to New, with New's first page held.
    await tester.drag(chipRow, const Offset(200, 0));
    await pumpFrames(tester);
    await tester.tap(find.text('Hot'));
    await pumpFrames(tester);
    expect(find.text('hot none post'), findsOneWidget);

    await tester.tap(find.text('New'));
    await pumpFrames(tester);
    expect(
      find.text('hot none post'),
      findsNothing,
      reason: 'Hot posts are dropped while New loads',
    );

    newest.completeError(Exception('new failed'));
    await pumpFrames(tester);
    expect(
      find.text('hot none post'),
      findsNothing,
      reason: 'Hot posts stay dropped after New fails',
    );
  });

  testWidgets('dragging the feed while the period menu is open closes the '
      'menu and scrolls the feed', (tester) async {
    useSurface(tester, const Size(400, 800));
    stubFeed(filler: 10);
    await pumpScreen(tester);
    await tapSort(tester, 'Top');
    await openTimeframeMenu(tester);
    expect(menuItem('Past week'), findsOneWidget);

    ScrollPosition feedPosition() => tester
        .state<ScrollableState>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        )
        .position;
    final offsetBefore = feedPosition().pixels;
    expect(
      offsetBefore,
      greaterThan(0),
      reason: 'opening the menu scrolled the feed, leaving room to drag back',
    );

    // Start the drag on the feed's left side, clear of the menu.
    await tester.dragFrom(const Offset(40, 400), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(
      menuItem('Past week'),
      findsNothing,
      reason: 'a drag outside the menu closes it',
    );
    expect(
      feedPosition().pixels,
      lessThan(offsetBefore),
      reason: 'the same drag scrolls the feed',
    );
  });
}
