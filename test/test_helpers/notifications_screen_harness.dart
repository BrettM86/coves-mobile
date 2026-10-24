import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'fake_providers.dart';
import 'test_mocks.dart';

/// Runs the signed-in notifications screen with one response per cursor call.
/// Calls not covered by [immediatePages] wait on [responses] in call order.
class NotificationsScreenHarness {
  NotificationsScreenHarness({
    this.viewportSize = const Size(540, 1800),
    this.immediatePages = const [],
  }) {
    responses.first.future.ignore();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const NotificationsScreen(isSelected: true),
        ),
        GoRoute(
          path: '/post/:postUri',
          builder: (_, _) => const Scaffold(body: Text('Post destination')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login destination')),
        ),
      ],
    );
    when(api.getUnreadCount()).thenAnswer((_) async => 0);
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(api.updateNotificationsSeen(seenAt: anyNamed('seenAt')))
        .thenAnswer((_) async {});
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      cursors.add(call.namedArguments[#cursor] as String?);
      requestDids.add(auth.did);
      final index = cursors.length - 1;
      if (responses.length <= index) {
        final response = Completer<NotificationPage>();
        response.future.ignore();
        responses.add(response);
      }
      if (index < immediatePages.length) {
        return Future.value(immediatePages[index]);
      }
      return responses[index].future;
    });
  }

  final Size viewportSize;
  final List<NotificationPage> immediatePages;
  final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
  final api = MockCovesApiService();
  final cursors = <String?>[];
  final requestDids = <String?>[];
  final responses = <Completer<NotificationPage>>[
    Completer<NotificationPage>(),
  ];
  late final GoRouter router;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<NotificationPreferencesChangeSignal>(
            create: (_) => NotificationPreferencesChangeSignal(),
          ),
          Provider<CovesApiService>.value(value: api),
          viewerAuthorityRegistration(auth: auth, apiService: api),
          unreadNotificationCountRegistration(auth: auth, apiService: api),
          notificationsListRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    auth.dispose();
  }
}
