import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fakes mirror test/widget_test.dart: the gates report accepted so the router
// doesn't redirect to /eula before MaterialApp settles.
class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => false;

  @override
  bool get isLoading => false;
}

class FakeEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class FakeGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

void main() {
  // `testWidgets`, never a plain `test`: AppTheme.dark pulls fonts through
  // google_fonts, whose loader only stays inert inside the fake-async zone.
  testWidgets('CovesApp themes its MaterialApp from the palette', (
    tester,
  ) async {
    final authProvider = FakeAuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<EulaProvider>(
            create: (_) => FakeEulaProvider(),
          ),
          ChangeNotifierProvider<CommunityGuidelinesProvider>(
            create: (_) => FakeGuidelinesProvider(),
          ),
          Provider<CovesApiService>(
            create: (_) => CovesApiService(tokenGetter: () async => null),
            dispose: (_, service) => service.dispose(),
          ),
          ChangeNotifierProvider(
            create: (context) => MultiFeedProvider(
              authProvider,
              apiService: context.read<CovesApiService>(),
            ),
          ),
        ],
        child: const CovesApp(),
      ),
    );

    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = app.theme;
    expect(theme, isNotNull, reason: 'CovesApp must supply a theme');

    // Asserted on observable roles rather than on identity with
    // `AppTheme.dark`, so the contract is "the running app is themed from the
    // palette" rather than "one particular object was passed".
    //
    // These roles discriminate: seeding from the same coral does NOT
    // reproduce the palette. `ColorScheme.fromSeed(seedColor:
    // AppColors.primary, brightness: Brightness.dark)` yields a desaturated
    // tonal derivative for `primary`, and a warm near-black for the derived
    // scaffold background - neither matches the token it was seeded from.
    expect(theme!.colorScheme.primary, AppColors.coral);
    expect(theme.scaffoldBackgroundColor, AppColors.background);

    // The app is dark-only by design. `theme` alone would already win with
    // `darkTheme` null, so these two lines are what stop a future light
    // theme from silently taking over on a device set to light mode.
    expect(app.darkTheme?.colorScheme.primary, AppColors.coral);
    expect(app.themeMode, ThemeMode.dark);
  });
}
