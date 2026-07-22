import 'dart:async';

import 'package:coves_flutter/models/feed_state.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fake AuthProvider for testing (see test/widgets/feed_screen_test.dart).
// Unauthenticated: FeedScreen shows the Discover empty state and
// ProfileScreen shows the sign-in prompt, so no network is touched.
class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => false;

  @override
  bool get isLoading => false;
}

// Fake VoteProvider for testing
class FakeVoteProvider extends VoteProvider {
  FakeVoteProvider()
    : super(
        voteService: VoteService(
          sessionGetter: () async => null,
          didGetter: () => null,
        ),
        authProvider: FakeAuthProvider(),
      );

  @override
  bool isLiked(String postUri) => false;
}

// Fake CommunitySubscriptionProvider that never touches the network
class FakeCommunitySubscriptionProvider extends CommunitySubscriptionProvider {
  FakeCommunitySubscriptionProvider({required super.authProvider});

  @override
  Future<void> loadSubscribedCommunities() async {
    // No-op for testing - avoids network calls and pending timers
  }
}

// Fake MultiFeedProvider that never touches the network
class FakeMultiFeedProvider extends MultiFeedProvider {
  FakeMultiFeedProvider() : super(FakeAuthProvider());

  @override
  FeedState getState(FeedType type) => FeedState.initial();

  @override
  Future<void> loadFeed(FeedType type, {bool refresh = false}) async {}

  @override
  Future<void> retry(FeedType type) async {}

  @override
  Future<void> loadMore(FeedType type) async {}

  @override
  void saveScrollPosition(FeedType type, double position) {}
}

void main() {
  group('MainShellScreen system back matrix', () {
    late FakeAuthProvider fakeAuthProvider;
    late FakeMultiFeedProvider fakeFeedProvider;
    late FakeVoteProvider fakeVoteProvider;
    late CommunitySubscriptionProvider subscriptionProvider;
    late BlockProvider blockProvider;
    late UserProfileProvider profileProvider;
    late GlobalKey<NavigatorState> navigatorKey;

    setUp(() {
      fakeAuthProvider = FakeAuthProvider();
      fakeFeedProvider = FakeMultiFeedProvider();
      fakeVoteProvider = FakeVoteProvider();
      subscriptionProvider = FakeCommunitySubscriptionProvider(
        authProvider: fakeAuthProvider,
      );
      blockProvider = BlockProvider(
        apiService: CovesApiService(),
        authProvider: fakeAuthProvider,
      );
      profileProvider = UserProfileProvider(fakeAuthProvider);
      navigatorKey = GlobalKey<NavigatorState>();
    });

    tearDown(() {
      subscriptionProvider.dispose();
      blockProvider.dispose();
      profileProvider.dispose();
      fakeVoteProvider.dispose();
      fakeFeedProvider.dispose();
      fakeAuthProvider.dispose();
    });

    /// Pumps a base route and pushes MainShellScreen on top of it, so a
    /// successful system back visibly pops (back to the base route) while a
    /// blocked back leaves the shell in place.
    Future<void> pumpShell(WidgetTester tester) async {
      // Force the phone layout (bottom navigation bar): shortestSide < 600
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
            ChangeNotifierProvider<MultiFeedProvider>.value(
              value: fakeFeedProvider,
            ),
            ChangeNotifierProvider<VoteProvider>.value(value: fakeVoteProvider),
            ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
              value: subscriptionProvider,
            ),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            ChangeNotifierProvider<UserProfileProvider>.value(
              value: profileProvider,
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('base route')),
          ),
        ),
      );

      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const MainShellScreen()),
        ),
      );
      await tester.pump();
      // Let post-frame loads (communities/profile) resolve to error/empty
      // states against the test HTTP client
      await tester.pump(const Duration(seconds: 1));
    }

    /// Taps a bottom-nav item by its Semantics label ('Home', 'Create', ...)
    Future<void> tapNavItem(WidgetTester tester, String label) async {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        ),
      );
      await tester.pump();
    }

    /// Simulates the Android system back button (same path as a real
    /// hardware/gesture back: WidgetsApp -> root navigator maybePop).
    Future<void> systemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      // Let a potential route pop transition run to completion (the zoom
      // page transition takes 500ms)
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump();
    }

    /// The shell's tab IndexedStack (the first one under MainShellScreen -
    /// DropdownButton in the composer owns a nested IndexedStack of its own)
    int stackIndex(WidgetTester tester) {
      final stack = tester.widget<IndexedStack>(
        find
            .descendant(
              of: find.byType(MainShellScreen),
              matching: find.byType(IndexedStack),
            )
            .first,
      );
      return stack.index!;
    }

    Future<void> dirtyComposer(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Unsaved draft',
      );
      await tester.pump();
    }

    testWidgets('Create tab + dirty composer: back is intercepted and '
        'lands on Feed tab', (tester) async {
      await pumpShell(tester);

      await tapNavItem(tester, 'Create');
      expect(stackIndex(tester), 2);
      await dirtyComposer(tester);

      await systemBack(tester);

      // Not popped - shell still on screen, draft alive in the IndexedStack
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(find.text('base route'), findsNothing);
      // ...and the user landed on the Feed tab
      expect(stackIndex(tester), 0);
    });

    testWidgets('Create tab + clean composer: back pops normally', (
      tester,
    ) async {
      await pumpShell(tester);

      await tapNavItem(tester, 'Create');
      expect(stackIndex(tester), 2);

      await systemBack(tester);

      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.text('base route'), findsOneWidget);
    });

    testWidgets('other tab + dirty composer: back pops normally '
        '(draft protection must not fire off the Create tab)', (tester) async {
      await pumpShell(tester);

      // Dirty the composer, then switch away from the Create tab
      await tapNavItem(tester, 'Create');
      await dirtyComposer(tester);
      await tapNavItem(tester, 'Home');
      expect(stackIndex(tester), 0);

      await systemBack(tester);

      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.text('base route'), findsOneWidget);
    });

    testWidgets('after an intercepted back, a second back (now on Feed, '
        'clean) pops', (tester) async {
      await pumpShell(tester);

      await tapNavItem(tester, 'Create');
      await dirtyComposer(tester);

      // First back: intercepted, lands on Feed
      await systemBack(tester);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(stackIndex(tester), 0);

      // Second back: nothing to protect anymore, pops
      await systemBack(tester);
      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.text('base route'), findsOneWidget);
    });
  });
}
