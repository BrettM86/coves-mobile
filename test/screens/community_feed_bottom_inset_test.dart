import 'package:coves_flutter/models/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/community_feed_harness.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  testWidgets('the feed stops above the system navigation bar instead of '
      'scrolling under it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    final api = MockCovesApiService();
    when(api.getCommunity(community: anyNamed('community')))
        .thenAnswer((_) async => buildFeedTestCommunity());
    when(
      api.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [
          for (var i = 0; i < 10; i++)
            buildFeedTestPost(rkey: 'post-$i', title: 'Post $i'),
        ],
      ),
    );

    await pumpCommunityFeedScreen(tester, api);
    await tester.pumpAndSettle();

    final feed = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    expect(tester.getBottomLeft(feed.first).dy, 752);
  });
}
