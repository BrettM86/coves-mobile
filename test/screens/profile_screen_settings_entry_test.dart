import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/screens/settings/settings_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/unread_count_refresh_spy.dart';

class _AcceptedEula extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class _AcceptedGuidelines extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

/// Pumps the signed-in viewer's own profile at '/profile', with a
/// '/settings' route ('Settings destination'), and returns the router.
Future<GoRouter> _pumpOwnProfile(WidgetTester tester) async {
  const viewerDid = 'did:plc:viewer';
  final auth = FakeAuthProvider(signedInDid: viewerDid);
  final api = MockCovesApiService();
  when(api.getViewerAuthority()).thenAnswer((_) async => false);
  when(api.getProfile(actor: viewerDid)).thenAnswer(
    (_) async => UserProfile(did: viewerDid, handle: 'viewer.coves.social'),
  );
  when(
    api.getAuthorPosts(
      actor: viewerDid,
      filter: anyNamed('filter'),
      community: anyNamed('community'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
    ),
  ).thenAnswer((_) async => TimelineResponse(feed: const []));
  when(api.getUnreadCount()).thenAnswer((_) async => 0);

  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const ProfileScreen(actor: viewerDid),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('Settings destination')),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    auth.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: profileScreenProviders(
        auth: auth,
        apiService: api,
        commentService: MockCommentService(),
      ),
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byTooltip('Menu'), findsOneWidget);
  return router;
}

void main() {
  const viewerDid = 'did:plc:viewer';

  testWidgets(
    'B3 own profile Settings entry pushes route and dismisses sheet',
    (tester) async {
      final router = await _pumpOwnProfile(tester);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/settings');
      expect(find.text('Settings destination'), findsOneWidget);
      expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);

      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    },
  );

  testWidgets('B6d own profile menu tiles show Lucide glyphs', (tester) async {
    await _pumpOwnProfile(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    const tileGlyphs = {
      'Settings': LucidePaths.settings,
      'End User License Agreement': LucidePaths.fileText,
      'Community Guidelines': LucidePaths.users,
      'Sign Out': LucidePaths.logOut,
    };
    for (final MapEntry(key: title, value: paths) in tileGlyphs.entries) {
      expectLucideGlyph(
        tester,
        within: find.widgetWithText(ListTile, title),
        paths: paths,
        reason: title,
      );
    }
    for (final icon in [
      Icons.settings_outlined,
      Icons.description_outlined,
      Icons.groups_outlined,
      Icons.logout,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: '$icon');
    }
  });

  testWidgets('B3 production router resolves /settings to SettingsScreen', (
    tester,
  ) async {
    final auth = FakeAuthProvider(signedInDid: viewerDid);
    final eula = _AcceptedEula();
    final guidelines = _AcceptedGuidelines();
    final api = MockCovesApiService();
    final unreadCount = UnreadCountRefreshSpy();
    final signal = NotificationPreferencesChangeSignal();
    final pending = Completer<NotificationPreferences>();
    when(api.getNotificationPreferences()).thenAnswer((_) => pending.future);
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    final router = createRouter(auth, eula, guidelines);
    addTearDown(() {
      router.dispose();
      auth.dispose();
      eula.dispose();
      guidelines.dispose();
      unreadCount.dispose();
      signal.dispose();
    });

    router.go('/settings');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<NotificationPreferencesChangeSignal>.value(
            value: signal,
          ),
          ChangeNotifierProvider<UnreadNotificationCountProvider>.value(
            value: unreadCount,
          ),
          viewerAuthorityRegistration(auth: auth, apiService: api),
          notificationPreferencesRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
