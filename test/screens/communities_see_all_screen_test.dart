// Regression tests for the shared pagination wiring, driven through a real
// adopting screen.
//
// CommunitiesSeeAllScreen is the cheapest real surface that uses
// CursorPaginationController + PaginationScrollListener +
// PaginatedSliverList together: its only injected dependency is the API
// client.
//
// The behaviour under test is FIX 3 from the multi-model review: a first
// page too short to fill the viewport leaves nothing to scroll, so a
// scroll-event-driven trigger would stall there forever. The profile
// screen's old build-phase trigger covered this by accident; the shared
// listener has to be asked explicitly.

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/screens/home/communities_see_all_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

CommunityView community(String id) {
  return CommunityView(
    did: 'did:plc:$id',
    name: id,
    displayName: 'Community $id',
  );
}

CommunitiesResponse pageOf(List<String> ids, {String? cursor}) {
  return CommunitiesResponse(
    communities: ids.map(community).toList(),
    cursor: cursor,
  );
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  /// Answers listCommunities with [pages] in order, and records how many
  /// requests were made.
  List<int> stubPages(List<Object> pages) {
    final requests = <int>[0];
    when(
      mockApiService.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async {
      final index = requests[0];
      requests[0]++;
      final page = pages[index < pages.length ? index : pages.length - 1];
      if (page is Exception) {
        throw page;
      }
      return page as CommunitiesResponse;
    });
    return requests;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<CovesApiService>.value(
        value: mockApiService,
        child: const MaterialApp(
          home: CommunitiesSeeAllScreen(title: 'All', sort: 'popular'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a first page too short to scroll still loads the next one', (
    tester,
  ) async {
    final requests = stubPages(<Object>[
      pageOf(<String>['a', 'b', 'c'], cursor: 'c1'),
      pageOf(<String>['d', 'e', 'f']),
    ]);

    await pumpScreen(tester);

    expect(requests[0], 2);
    expect(find.text('Community a'), findsOneWidget);
    expect(find.text('Community f'), findsOneWidget);
  });

  testWidgets('it stops once the server stops handing back a cursor', (
    tester,
  ) async {
    final requests = stubPages(<Object>[pageOf(<String>['a'])]);

    await pumpScreen(tester);

    expect(requests[0], 1);
  });

  testWidgets('an empty page with a cursor does not poll forever', (
    tester,
  ) async {
    // The server keeps offering a cursor for a page it never fills.
    final requests = stubPages(<Object>[
      pageOf(<String>['a'], cursor: 'c1'),
      pageOf(const <String>[], cursor: 'c2'),
    ]);

    await pumpScreen(tester);

    expect(requests[0], 2);
  });

  testWidgets('a pull-to-refresh failure is visible with rows on screen', (
    tester,
  ) async {
    // The full-screen error is gated on an empty list, so before this the
    // user saw nothing at all: the list just sat there unchanged.
    stubPages(<Object>[
      pageOf(<String>['a']),
      NetworkException('the refresh exploded'),
    ]);

    await pumpScreen(tester);
    expect(find.text('Community a'), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('the refresh exploded'), findsOneWidget);
    // ...without blanking the rows that are still perfectly readable.
    expect(find.text('Community a'), findsOneWidget);
  });

  testWidgets('a failed page is not retried automatically', (tester) async {
    // The scroll/viewport trigger would otherwise re-fire on every tick.
    final requests = stubPages(<Object>[
      pageOf(<String>['a', 'b'], cursor: 'c1'),
      NetworkException('offline'),
    ]);

    await pumpScreen(tester);

    expect(requests[0], 2);
    // The screen's errorMapper passes a typed ApiException's message through.
    expect(find.text('offline'), findsOneWidget);

    // ...and the footer's Retry resumes it.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(requests[0], greaterThan(2));
  });
}
