// Acceptance tests for the Communities discovery search when the query
// changes while the first full-list fetch (listCommunities(limit: 100)) is
// still in flight: the results shown after the fetch completes must follow
// what the search field says now, not the query that started the fetch.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/screens/home/communities_discovery_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/error_copy_rows.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const Duration pastDebounce = Duration(milliseconds: 350);

// Section fixtures deliberately contain neither "ga" nor "gam" in any
// field that CommunitySearchUtils.filterByQuery inspects.
final List<CommunityView> popularFixtures = [
  CommunityView(did: 'did:plc:popular1', name: 'photos', displayName: 'Photos'),
];
final List<CommunityView> newFixtures = [
  CommunityView(did: 'did:plc:new1', name: 'hiking', displayName: 'Hiking'),
];

// Full-list-only fixtures. "Gaming" matches both "ga" and "gam";
// "Garden" matches "ga" but not "gam" (name, displayName and description).
final CommunityView gamingCommunity = CommunityView(
  did: 'did:plc:gaming',
  name: 'gaming',
  displayName: 'Gaming',
);
final CommunityView gardenCommunity = CommunityView(
  did: 'did:plc:garden',
  name: 'garden',
  displayName: 'Garden',
);

void main() {
  late MockCovesApiService mockApiService;
  late Completer<CommunitiesResponse> fullListCompleter;

  setUp(() {
    mockApiService = MockCovesApiService();

    when(
      mockApiService.listCommunities(
        limit: 8,
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer(
      (_) async => CommunitiesResponse(communities: popularFixtures),
    );
    when(
      mockApiService.listCommunities(
        limit: 5,
        cursor: anyNamed('cursor'),
        sort: 'new',
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: newFixtures));
    when(
      mockApiService.listCommunities(
        limit: 100,
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) => fullListCompleter.future);
  });

  Future<void> pumpDiscovery(WidgetTester tester) async {
    // Created inside the test body so its completion is scheduled on the
    // testWidgets fake-async zone that tester.pump drives; a Completer made
    // in setUp completes on the real zone and never reaches the screen.
    fullListCompleter = Completer<CommunitiesResponse>();

    final auth = FakeAuthProvider();
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: mockApiService,
    );
    addTearDown(subscriptions.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: mockApiService),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
            value: subscriptions,
          ),
        ],
        // The screen is normally embedded in MainShellScreen, which owns
        // the Scaffold its Material widgets need.
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: CommunitiesDiscoveryScreen()),
        ),
      ),
    );
    // Post-frame section loads resolve immediately.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Recently Created'), findsOneWidget);
  }

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(pastDebounce);
    await tester.pump();
  }

  void verifyFullListRequestedOnce() {
    verify(
      mockApiService.listCommunities(
        limit: 100,
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).called(1);
  }

  Future<void> completeFullList(
    WidgetTester tester,
    List<CommunityView> communities,
  ) async {
    fullListCompleter.complete(CommunitiesResponse(communities: communities));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('A1 results follow the query typed while the first full-list '
      'fetch was in flight', (tester) async {
    await pumpDiscovery(tester);

    await typeSearch(tester, 'ga');
    verifyFullListRequestedOnce();

    await typeSearch(tester, 'gam');

    await completeFullList(tester, [gamingCommunity, gardenCommunity]);
    expect(find.text('Gaming'), findsOneWidget);
    expect(
      find.text('Garden'),
      findsNothing,
      reason: '"Garden" matches the stale query "ga" but not "gam"',
    );
    expect(find.text('1 result'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('A2 clearing the search while the first full-list fetch was in '
      'flight leaves the browse sections showing', (tester) async {
    await pumpDiscovery(tester);

    await typeSearch(tester, 'ga');
    verifyFullListRequestedOnce();

    await typeSearch(tester, '');
    expect(find.text('Popular'), findsOneWidget);

    await completeFullList(tester, [gamingCommunity, gardenCommunity]);

    expect(
      find.text('Popular'),
      findsOneWidget,
      reason: 'the search field is empty, so the browse sections must show',
    );
    expect(find.text('Recently Created'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ results?$')), findsNothing);
    expect(find.textContaining('No communities match'), findsNothing);
    expect(find.text('Gaming'), findsNothing);
    expect(find.text('Garden'), findsNothing);

    await unmount(tester);
  });

  // The B tests complete the fetch BEFORE the debounce for the new text
  // fires: 50ms after entering text plus completeFullList's 100ms is 150ms,
  // under the 300ms debounce. So the completion itself must read the field;
  // reusing the last debounced query would still apply "ga".
  Future<void> enterTextWithinDebounce(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('B1 a fetch completing before the next debounce applies the '
      'normalized text currently in the field', (tester) async {
    await pumpDiscovery(tester);

    await typeSearch(tester, 'ga');
    verifyFullListRequestedOnce();

    await enterTextWithinDebounce(tester, ' GAM ');

    await completeFullList(tester, [gamingCommunity, gardenCommunity]);

    expect(find.text('Gaming'), findsOneWidget);
    expect(
      find.text('Garden'),
      findsNothing,
      reason:
          '"Garden" matches the stale query "ga" but not the field text '
          '" GAM " normalized to "gam"',
    );
    expect(find.text('1 result'), findsOneWidget);

    await unmount(tester);
  });

  for (final (label, clearedText) in [
    ('empty text', ''),
    ('whitespace-only text', '   '),
  ]) {
    testWidgets('B2 a fetch completing before the next debounce after the '
        'field was cleared ($label) leaves the browse sections showing', (
      tester,
    ) async {
      await pumpDiscovery(tester);

      await typeSearch(tester, 'ga');
      verifyFullListRequestedOnce();

      await enterTextWithinDebounce(tester, clearedText);

      await completeFullList(tester, [gamingCommunity, gardenCommunity]);

      expect(
        find.text('Popular'),
        findsOneWidget,
        reason: 'the search field is blank, so the browse sections must show',
      );
      expect(find.text('Recently Created'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d+ results?$')), findsNothing);
      expect(find.textContaining('No communities match'), findsNothing);
      expect(find.text('Gaming'), findsNothing);
      expect(find.text('Garden'), findsNothing);

      await unmount(tester);
    });
  }

  group('when the full-list fetch fails', () {
    // Section fixtures for the failure fallback, which filters the
    // deduplicated section data. "Gamers" matches both "ga" and "gam" and
    // appears in popular AND new under one DID, so it must be listed once;
    // "Gardeners" matches "ga" but not "gam".
    final gamersCommunity = CommunityView(
      did: 'did:plc:section-gamers',
      name: 'gamers',
      displayName: 'Gamers',
    );
    final gardenersCommunity = CommunityView(
      did: 'did:plc:section-gardeners',
      name: 'gardeners',
      displayName: 'Gardeners',
    );

    // Runs after the outer setUp; mockito answers with the latest matching
    // stub, so only this group sees these sections.
    setUp(() {
      when(
        mockApiService.listCommunities(
          limit: 8,
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer(
        (_) async => CommunitiesResponse(
          communities: [gamersCommunity, gardenersCommunity],
        ),
      );
      when(
        mockApiService.listCommunities(
          limit: 5,
          cursor: anyNamed('cursor'),
          sort: 'new',
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer(
        (_) async => CommunitiesResponse(communities: [gamersCommunity]),
      );
    });

    Future<void> failFullList(WidgetTester tester) async {
      fullListCompleter.completeError(Exception('full list unavailable'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('B3a the fallback filters the deduplicated sections by the '
        'query typed while the fetch was in flight', (tester) async {
      await pumpDiscovery(tester);

      await typeSearch(tester, 'ga');
      verifyFullListRequestedOnce();

      await typeSearch(tester, 'gam');

      await failFullList(tester);

      expect(find.text('Gamers'), findsOneWidget);
      expect(
        find.text('Gardeners'),
        findsNothing,
        reason: '"Gardeners" matches the stale query "ga" but not "gam"',
      );
      expect(find.text('1 result'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('B3b the fallback leaves the browse sections showing when the '
        'field was cleared while the fetch was in flight', (tester) async {
      await pumpDiscovery(tester);

      await typeSearch(tester, 'ga');
      verifyFullListRequestedOnce();

      await typeSearch(tester, '');
      expect(find.text('Popular'), findsOneWidget);

      await failFullList(tester);

      expect(
        find.text('Popular'),
        findsOneWidget,
        reason: 'the search field is empty, so the browse sections must show',
      );
      expect(find.text('Recently Created'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d+ results?$')), findsNothing);
      expect(find.textContaining('No communities match'), findsNothing);

      await unmount(tester);
    });

    // Leaves the retry fetch pending: the first fetch failed while the field
    // said "gam", then the user tapped "· tap to load more".
    Future<void> tapRetryAfterFailedGamSearch(WidgetTester tester) async {
      await pumpDiscovery(tester);

      await typeSearch(tester, 'gam');
      verifyFullListRequestedOnce();
      await failFullList(tester);

      expect(find.text('Gamers'), findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
      expect(find.text('· tap to load more'), findsOneWidget);

      // The full-list stub answers with whichever completer is current, so
      // the retry gets its own.
      fullListCompleter = Completer<CommunitiesResponse>();
      await tester.tap(find.text('· tap to load more'));
      await tester.pump();

      // The first request was verified above, so this counts the retry alone.
      verifyFullListRequestedOnce();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('· tap to load more'), findsNothing);
    }

    // The retry's full list. "gard" matches Garden and Gardeners; "gam", the
    // query in the field when the retry started, matches only Gaming.
    final retryFullList = [
      gamingCommunity,
      gardenCommunity,
      gardenersCommunity,
    ];

    testWidgets('B4a a retry completing after the query changed applies the '
        'query now in the field', (tester) async {
      await tapRetryAfterFailedGamSearch(tester);

      await typeSearch(tester, 'gard');
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'the "gard" debounce must fire while the retry is pending',
      );

      await completeFullList(tester, retryFullList);

      expect(
        find.text('2 results'),
        findsOneWidget,
        reason:
            '"gard" matches Garden and Gardeners; "gam" matches only Gaming',
      );
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('Gardeners'), findsOneWidget);
      expect(
        find.text('Gaming'),
        findsNothing,
        reason: '"Gaming" matches the stale query "gam" but not "gard"',
      );
      expect(find.text('· tap to load more'), findsNothing);

      await unmount(tester);
    });

    testWidgets('B4b a retry completing after the field was cleared leaves '
        'the browse sections showing', (tester) async {
      await tapRetryAfterFailedGamSearch(tester);

      await typeSearch(tester, '');
      expect(find.text('Popular'), findsOneWidget);

      await completeFullList(tester, retryFullList);

      expect(
        find.text('Popular'),
        findsOneWidget,
        reason: 'the search field is empty, so the browse sections must show',
      );
      expect(find.text('Recently Created'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d+ results?$')), findsNothing);
      expect(find.textContaining('No communities match'), findsNothing);
      expect(find.text('Gaming'), findsNothing);
      expect(find.text('Garden'), findsNothing);

      await unmount(tester);
    });
  });

  group('section load failure copy', () {
    for (final row in errorCopyRows(
      'Could not load communities. Please try again.',
    )) {
      testWidgets('a ${row.name} Popular load failure shows '
          '"${row.expected}"', (tester) async {
        when(
          mockApiService.listCommunities(
            limit: 8,
            cursor: anyNamed('cursor'),
            sort: anyNamed('sort'),
            subscribed: anyNamed('subscribed'),
          ),
        ).thenThrow(row.error);

        await pumpDiscovery(tester);

        expect(find.text(row.expected), findsOneWidget);
        if (row.rawText case final rawText?) {
          expect(find.textContaining(rawText), findsNothing);
        }

        await unmount(tester);
      });
    }
  });
}
