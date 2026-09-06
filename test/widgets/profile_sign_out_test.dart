import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

class _RetryableSignOutProvider extends AuthProvider {
  int signOutCalls = 0;
  bool _authenticated = true;

  @override
  bool get isAuthenticated => _authenticated;

  @override
  bool get isLoading => false;

  @override
  String? get error =>
      signOutCalls == 1 ? "Couldn't sign out. Please try again." : null;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    // The first server revocation fails; the second is confirmed.
    _authenticated = signOutCalls == 1;
    notifyListeners();
  }
}

void main() {
  testWidgets('failed sign out stays on profile and Retry can sign out', (
    tester,
  ) async {
    final authProvider = _RetryableSignOutProvider();
    final profileProvider = UserProfileProvider(
      authProvider,
      apiService: MockCovesApiService(),
      commentService: MockCommentService(),
    );
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Text('Login screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(authProvider.dispose);
    addTearDown(profileProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<UserProfileProvider>.value(
            value: profileProvider,
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Missing profile data must never prevent the user from signing out.
    expect(find.text('Failed to load profile'), findsOneWidget);
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(authProvider.signOutCalls, 1);
    expect(authProvider.isAuthenticated, isTrue);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Login screen'), findsNothing);
    expect(find.text("Couldn't sign out. Please try again."), findsOneWidget);
    final retryAction = find.descendant(
      of: find.byType(SnackBar),
      matching: find.text('Retry'),
    );
    expect(retryAction, findsOneWidget);
    await tester.tap(retryAction);
    await tester.pumpAndSettle();

    expect(authProvider.signOutCalls, 2);
    expect(authProvider.isAuthenticated, isFalse);
    expect(find.text('Login screen'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
  });
}
