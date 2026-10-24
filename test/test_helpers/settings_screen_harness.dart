import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/screens/settings/settings_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_providers.dart';
import 'test_mocks.dart';
import 'unread_count_refresh_spy.dart';

/// Shared Settings dependencies, mirroring the app-level registrations.
///
/// Signed in as 'did:plc:alice' unless `signedInDid` says otherwise (pass
/// null to start signed out); [auth] switches accounts during a test.
class SettingsHarness {
  SettingsHarness({
    NotificationPreferencesChangeSignal? notificationPreferencesChangeSignal,
    String? signedInDid = 'did:plc:alice',
  }) : notificationPreferencesChangeSignal =
           notificationPreferencesChangeSignal ??
           NotificationPreferencesChangeSignal(),
       auth = FakeAuthProvider(signedInDid: signedInDid) {
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
  }

  final NotificationPreferencesChangeSignal notificationPreferencesChangeSignal;
  final FakeAuthProvider auth;
  final api = MockCovesApiService();
  final unreadCount = UnreadCountRefreshSpy();
  final sentPuts = <Map<String, bool>>[];
  final navigatorKey = GlobalKey<NavigatorState>();

  /// The signed-in DID when each `getNotificationPreferences` was sent, and
  /// the pending response of each, in request order. Filled once
  /// [stubPendingPreferenceRequests] is called.
  final loadRequestDids = <String?>[];
  final loadResponses = <Completer<NotificationPreferences>>[];

  /// The signed-in DID when each `putNotificationPreferences` was sent, and
  /// the pending response of each, in request order ([sentPuts] holds the
  /// sent values). Filled once [stubPendingPreferenceRequests] is called.
  final putRequestDids = <String?>[];
  final putResponses = <Completer<NotificationPreferences>>[];

  GoRouter? _router;

  /// The router of [pumpRouter].
  GoRouter get router => _router!;

  /// Answers every preference load and update with a pending [Completer]
  /// the test completes, recording who was signed in when it was sent.
  void stubPendingPreferenceRequests() {
    when(api.getNotificationPreferences()).thenAnswer((_) {
      loadRequestDids.add(auth.did);
      final response = Completer<NotificationPreferences>();
      loadResponses.add(response);
      return response.future;
    });
    when(
      api.putNotificationPreferences(
        postReply: anyNamed('postReply'),
        commentReply: anyNamed('commentReply'),
        mention: anyNamed('mention'),
        upvote: anyNamed('upvote'),
      ),
    ).thenAnswer((invocation) {
      putRequestDids.add(auth.did);
      final named = invocation.namedArguments;
      final postReply = named[#postReply] as bool?;
      final commentReply = named[#commentReply] as bool?;
      final mention = named[#mention] as bool?;
      final upvote = named[#upvote] as bool?;
      sentPuts.add({
        'postReply': ?postReply,
        'commentReply': ?commentReply,
        'mention': ?mention,
        'upvote': ?upvote,
      });
      final response = Completer<NotificationPreferences>();
      putResponses.add(response);
      return response.future;
    });
  }

  List<SingleChildWidget> get _providers => [
    Provider<CovesApiService>.value(value: api),
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ChangeNotifierProvider<UnreadNotificationCountProvider>.value(
      value: unreadCount,
    ),
    ChangeNotifierProvider<NotificationPreferencesChangeSignal>.value(
      value: notificationPreferencesChangeSignal,
    ),
    viewerAuthorityRegistration(auth: auth, apiService: api),
    notificationPreferencesRegistration(auth: auth, apiService: api),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Widget home = const SettingsScreen(),
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: _providers,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.dark,
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps a router at '/' ('Home') with '/settings' (the real screen) and
  /// '/login' ('Login destination') routes; see [openSettings].
  Future<void> pumpRouter(WidgetTester tester) async {
    _router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login destination')),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: _providers,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await settleRouterFrames(tester);
  }

  /// Pushes '/settings' on the router of [pumpRouter].
  Future<void> openSettings(WidgetTester tester) async {
    unawaited(router.push('/settings'));
    await settleRouterFrames(tester);
    expect(router.state.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  /// Pops Settings back to 'Home' on the router of [pumpRouter].
  Future<void> closeSettings(WidgetTester tester) async {
    router.pop();
    await settleRouterFrames(tester);
    expect(router.state.uri.path, '/');
    expect(find.byType(SettingsScreen), findsNothing);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    _router?.dispose();
    unreadCount.dispose();
    notificationPreferencesChangeSignal.dispose();
    auth.dispose();
  }
}

/// Bounded frames that finish a route transition even over a spinner, where
/// `pumpAndSettle` never settles.
Future<void> settleRouterFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// The Notifications switch labels, top to bottom.
const settingsSwitchLabels = [
  'Replies to your posts',
  'Replies to your comments',
  'Mentions',
  'Likes',
];

void expectNoSwitchLabels() {
  for (final label in settingsSwitchLabels) {
    expect(find.text(label), findsNothing, reason: label);
  }
}

/// Expects each switch of [settingsSwitchLabels] on screen with the toggled
/// state at the same index of [expected]. Needs semantics enabled.
void expectSwitchStates(WidgetTester tester, List<bool> expected) {
  for (var index = 0; index < settingsSwitchLabels.length; index++) {
    final label = settingsSwitchLabels[index];
    expect(find.text(label), findsOneWidget, reason: label);
    expect(
      tester
          .getSemantics(find.text(label))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      expected[index] ? Tristate.isTrue : Tristate.isFalse,
      reason: label,
    );
  }
}
