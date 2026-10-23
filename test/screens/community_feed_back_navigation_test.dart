// A community opened by deep link is the only route on the stack. Its back
// arrow and system Back must then land on the home feed instead of doing
// nothing (or exiting the app); when something is below, back still pops.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/icons/back_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String communityDid = 'did:plc:community';

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

enum _Back { arrow, system }

/// Pumps the community route, either deep-linked (sole route) or pushed on
/// top of `/origin`. With [loaded] the API answers immediately so the loaded
/// SliverAppBar renders; otherwise it never answers and the loading app bar
/// stays up without touching the network.
Future<GoRouter> pumpCommunityRoute(
  WidgetTester tester, {
  required String? start,
  required bool loaded,
}) async {
  final api = MockCovesApiService();
  when(api.getCommunity(community: anyNamed('community'))).thenAnswer(
    (_) => loaded
        ? Future.value(
            CommunityView(
              did: communityDid,
              name: 'testcove',
              displayName: 'Test Cove',
            ),
          )
        : Completer<CommunityView>().future,
  );
  when(
    api.getCommunityFeed(
      community: anyNamed('community'),
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      limit: anyNamed('limit'),
    ),
  ).thenAnswer(
    (_) => loaded
        ? Future.value(TimelineResponse(feed: const []))
        : Completer<TimelineResponse>().future,
  );

  final auth = FakeAuthProvider();
  final votes = FakeVoteProvider(auth);
  addTearDown(votes.dispose);
  final subscriptions = FakeSubscriptionProvider(
    authProvider: auth,
    apiService: api,
  );
  addTearDown(subscriptions.dispose);
  final blocks = BlockProvider(apiService: api, authProvider: auth);
  addTearDown(blocks.dispose);

  final router = GoRouter(
    initialLocation: start ?? '/community/$communityDid',
    routes: [
      GoRoute(
        path: '/feed',
        builder: (_, _) => const _Placeholder('FEED PLACEHOLDER'),
      ),
      GoRoute(
        path: '/origin',
        builder: (_, _) => const _Placeholder('ORIGIN PLACEHOLDER'),
      ),
      GoRoute(
        path: '/community/:identifier',
        builder: (_, state) => CommunityFeedScreen(
          identifier: state.pathParameters['identifier']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<CovesApiService>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<VoteProvider>.value(value: votes),
        ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
          value: subscriptions,
        ),
        ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        Provider<StreamableService>(create: (_) => StreamableService()),
        Provider<PostChangeBroadcast>(create: (_) => PostChangeBroadcast()),
        viewerAuthorityRegistration(auth: auth, apiService: api),
        unloadedMultiFeedProvider(auth: auth, apiService: api),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pump();

  if (start != null) {
    unawaited(router.push('/community/$communityDid'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  if (loaded) {
    await tester.pump();
    await tester.pump();
  }
  expect(find.byType(CommunityFeedScreen), findsOneWidget);
  return router;
}

void main() {
  for (final c in [
    (
      name: 'deep-linked, back arrow',
      start: null,
      loaded: false,
      back: _Back.arrow,
      expectedPath: '/feed',
      expectedText: 'FEED PLACEHOLDER',
    ),
    (
      name: 'deep-linked, system Back',
      start: null,
      loaded: false,
      back: _Back.system,
      expectedPath: '/feed',
      expectedText: 'FEED PLACEHOLDER',
    ),
    (
      name: 'pushed from /origin, back arrow',
      start: '/origin',
      loaded: false,
      back: _Back.arrow,
      expectedPath: '/origin',
      expectedText: 'ORIGIN PLACEHOLDER',
    ),
    (
      name: 'pushed from /origin, system Back',
      start: '/origin',
      loaded: false,
      back: _Back.system,
      expectedPath: '/origin',
      expectedText: 'ORIGIN PLACEHOLDER',
    ),
    (
      name: 'loaded, deep-linked, back arrow',
      start: null,
      loaded: true,
      back: _Back.arrow,
      expectedPath: '/feed',
      expectedText: 'FEED PLACEHOLDER',
    ),
    (
      name: 'loaded, pushed from /origin, back arrow',
      start: '/origin',
      loaded: true,
      back: _Back.arrow,
      expectedPath: '/origin',
      expectedText: 'ORIGIN PLACEHOLDER',
    ),
  ]) {
    testWidgets('community back navigation: ${c.name}', (tester) async {
      final router = await pumpCommunityRoute(
        tester,
        start: c.start,
        loaded: c.loaded,
      );

      if (c.back == _Back.arrow) {
        if (c.loaded) {
          expect(find.byType(SliverAppBar), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(SliverAppBar),
              matching: find.byType(BackIcon),
            ),
          );
        } else {
          await tester.tap(find.byType(BackIcon));
        }
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        c.expectedPath,
      );
      expect(find.text(c.expectedText), findsOneWidget);
      expect(find.byType(CommunityFeedScreen), findsNothing);
    });
  }

  testWidgets(
    'deep-linked community: system Back after a dialog closes still goes '
    'to /feed even if the screen rebuilt while the dialog was open',
    (tester) async {
      final router = await pumpCommunityRoute(
        tester,
        start: null,
        loaded: false,
      );

      final screenElement =
          tester.element(find.byType(CommunityFeedScreen)) as StatefulElement;
      unawaited(
        showDialog<void>(
          context: screenElement,
          builder: (_) => const AlertDialog(content: Text('DIALOG')),
        ),
      );
      // The loading spinner never settles, so pump past the route animation.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('DIALOG'), findsOneWidget);

      // Rebuild the screen while the dialog sits above it, as a feed load or
      // provider notification would.
      screenElement.markNeedsBuild();
      await tester.pump();

      // Close the dialog through its own context so this test does not
      // rebuild the screen itself.
      Navigator.of(tester.element(find.text('DIALOG'))).pop();
      // The loading spinner never settles, so pump past the route animation.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('DIALOG'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(router.routerDelegate.currentConfiguration.uri.path, '/feed');
      expect(find.text('FEED PLACEHOLDER'), findsOneWidget);
      expect(find.byType(CommunityFeedScreen), findsNothing);
    },
  );
}
