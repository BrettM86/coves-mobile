import 'dart:ui' show Tristate;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/screens/auth/login_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notifications_shell_harness.dart';
import '../test_helpers/sign_in_flow_fakes.dart';
import '../test_helpers/test_mocks.dart';

class _RouterHarness {
  _RouterHarness() {
    feeds = IdleFeedProvider(auth, apiService: api);
    router = createRouter(auth, eula, guidelines);
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(api.getUnreadCount()).thenAnswer((_) async => 1);
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer(
      (_) async => NotificationPage.fromJson({
        'notifications': <Map<String, dynamic>>[],
        'cursor': null,
      }),
    );
  }

  final auth = GatedSignInAuthProvider();
  final eula = AcceptedEulaProvider();
  final guidelines = AcceptedGuidelinesProvider();
  final api = MockCovesApiService();
  late final MultiFeedProvider feeds;
  late final GoRouter router;

  Widget app() => MultiProvider(
    providers: routerShellProviders(auth: auth, api: api, feeds: feeds),
    child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    feeds.dispose();
    router.dispose();
    guidelines.dispose();
    eula.dispose();
    auth.dispose();
  }
}

void main() {
  testWidgets('B8 signed-out Notifications sign-in pushes login and returns to '
      'the same selected shell with one unread request', (tester) async {
    tester.view.physicalSize = const Size(590, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _RouterHarness();
    try {
      await tester.pumpWidget(harness.app());
      harness.router.go('/feed');
      await tester.pumpAndSettle();
      final shellState = tester.state<State<MainShellScreen>>(
        find.byType(MainShellScreen),
      );

      await tester.tap(phoneNavItem('Notifications'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(NotificationsScreen),
          matching: find.text('Sign in'),
        ),
        findsOneWidget,
      );
      verifyNever(harness.api.getUnreadCount());

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(harness.router.canPop(), isTrue);

      await tester.enterText(find.byType(TextFormField), 'alice.test');
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(harness.auth.isAwaitingOAuth, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      harness.auth.completeOAuth('did:plc:alice');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(
        harness.router.routerDelegate.currentConfiguration.uri.path,
        '/feed',
      );
      expect(
        tester.state<State<MainShellScreen>>(find.byType(MainShellScreen)),
        same(shellState),
      );
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester
              .getSemantics(phoneNavItem('Notifications'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(
          tester.getSemantics(phoneNavItem('Home')).flagsCollection.isSelected,
          Tristate.isFalse,
        );
      } finally {
        semantics.dispose();
      }
      verify(harness.api.getUnreadCount()).called(1);
      expect(
        find.descendant(
          of: find.byType(NotificationsScreen, skipOffstage: false),
          matching: find.text('Sign in', skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
    } finally {
      await harness.dispose(tester);
    }
  });
}
