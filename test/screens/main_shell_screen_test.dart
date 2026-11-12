import 'dart:async';

import 'package:coves_flutter/models/feed_state.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/bluesky_import_test_helpers.dart';
import '../test_helpers/fake_providers.dart'
    show
        notificationPreferencesRegistration,
        notificationsListRegistration,
        unchangingSessionKey,
        unreadNotificationCountRegistration,
        viewerAuthorityRegistration;

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
          sessionKeyOf: () => null,
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
  FakeCommunitySubscriptionProvider({required super.authProvider})
    : super(apiService: CovesApiService(sessionKeyOf: () => null));

  @override
  Future<void> loadSubscribedCommunities() async {
    // No-op for testing - avoids network calls and pending timers
  }
}

// Fake MultiFeedProvider that never touches the network
class FakeMultiFeedProvider extends MultiFeedProvider {
  FakeMultiFeedProvider()
    : super(
        FakeAuthProvider(),
        apiService: CovesApiService(sessionKeyOf: () => null),
        postChangeBroadcast: PostChangeBroadcast(),
        sessionKeyOf: unchangingSessionKey,
      );

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
    late ProfileCache profileCache;
    late GlobalKey<NavigatorState> navigatorKey;

    setUp(() {
      fakeAuthProvider = FakeAuthProvider();
      fakeFeedProvider = FakeMultiFeedProvider();
      fakeVoteProvider = FakeVoteProvider();
      subscriptionProvider = FakeCommunitySubscriptionProvider(
        authProvider: fakeAuthProvider,
      );
      blockProvider = BlockProvider(
        apiService: CovesApiService(sessionKeyOf: () => null),
        authProvider: fakeAuthProvider,
      );
      profileCache = ProfileCache(fakeAuthProvider);
      navigatorKey = GlobalKey<NavigatorState>();
    });

    tearDown(() {
      subscriptionProvider.dispose();
      blockProvider.dispose();
      profileCache.dispose();
      fakeVoteProvider.dispose();
      fakeFeedProvider.dispose();
      fakeAuthProvider.dispose();
    });

    /// Pumps a base route and pushes MainShellScreen on top of it, so a
    /// successful system back visibly pops (back to the base route) while a
    /// blocked back leaves the shell in place.
    Future<void> pumpShell(WidgetTester tester) async {
      final apiService = CovesApiService(sessionKeyOf: () => null);
      // Force the phone layout (bottom navigation bar): shortestSide < 600
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CovesApiService>(
              create: (_) => apiService,
              dispose: (_, service) => service.dispose(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
            // App-level dependencies of the Notifications and Profile tabs
            ChangeNotifierProvider<NotificationPreferencesChangeSignal>(
              create: (_) => NotificationPreferencesChangeSignal(),
            ),
            viewerAuthorityRegistration(
              auth: fakeAuthProvider,
              apiService: apiService,
            ),
            unreadNotificationCountRegistration(
              auth: fakeAuthProvider,
              apiService: apiService,
            ),
            notificationsListRegistration(
              auth: fakeAuthProvider,
              apiService: apiService,
            ),
            notificationPreferencesRegistration(
              auth: fakeAuthProvider,
              apiService: apiService,
            ),
            ChangeNotifierProvider<MultiFeedProvider>.value(
              value: fakeFeedProvider,
            ),
            ChangeNotifierProvider<VoteProvider>.value(value: fakeVoteProvider),
            ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
              value: subscriptionProvider,
            ),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            // App-level dependencies the Profile tab builds its own
            // UserProfileProvider from
            Provider<CommentService>(
              create: (_) => CommentService(sessionKeyOf: () => null),
            ),
            Provider<ViewerStateHydrator>(
              create: (_) => ViewerStateHydrator(
                authProvider: fakeAuthProvider,
                voteProvider: fakeVoteProvider,
              ),
            ),
            Provider<ProfileCache>.value(value: profileCache),
            Provider<PostChangeBroadcast>(create: (_) => PostChangeBroadcast()),
            blueskyImportOfferRegistration(
              auth: fakeAuthProvider,
              apiService: apiService,
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

    testWidgets('Home tab: back pops normally (exits the shell)', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(stackIndex(tester), 0);

      await systemBack(tester);

      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.text('base route'), findsOneWidget);
    });

    for (final (label, index) in [
      ('Communities', 1),
      ('Create', 2),
      ('Notifications', 3),
      ('Me', 4),
    ]) {
      testWidgets('$label tab: back switches to the Home tab, and a second '
          'back pops', (tester) async {
        await pumpShell(tester);

        await tapNavItem(tester, label);
        expect(stackIndex(tester), index);

        await systemBack(tester);

        expect(find.byType(MainShellScreen), findsOneWidget);
        expect(find.text('base route'), findsNothing);
        expect(stackIndex(tester), 0);

        await systemBack(tester);

        expect(find.byType(MainShellScreen), findsNothing);
        expect(find.text('base route'), findsOneWidget);
      });
    }

    testWidgets('Create tab + dirty composer: back switches to Home and the '
        'draft stays alive', (tester) async {
      await pumpShell(tester);

      await tapNavItem(tester, 'Create');
      await dirtyComposer(tester);

      await systemBack(tester);

      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(stackIndex(tester), 0);

      await tapNavItem(tester, 'Create');
      expect(find.text('Unsaved draft'), findsOneWidget);
    });

    testWidgets('route pushed over a non-Home tab: back pops that route '
        'first and keeps the tab', (tester) async {
      await pumpShell(tester);

      await tapNavItem(tester, 'Communities');
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('pushed route')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('pushed route'), findsOneWidget);

      await systemBack(tester);

      expect(find.text('pushed route'), findsNothing);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(stackIndex(tester), 1);

      await systemBack(tester);

      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(stackIndex(tester), 0);
    });
  });
}
