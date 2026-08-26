import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/constants/app_typography.dart';
import 'package:coves_flutter/screens/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_helpers/font_identity.dart';

void main() {
  // `testWidgets`, never a plain `test`: this pumps a screen and resolves
  // fonts, which google_fonts only tolerates inside the fake-async zone.
  testWidgets('the wordmark keeps the display family, not the body font', (
    tester,
  ) async {
    // LoginScreen over LandingScreen: its display-family text renders
    // unconditionally, while the landing screen's only reaches the Text
    // fallback when the logo SVG fails to load - an error path that also
    // calls Sentry. A GoRouter is needed because the app bar asks whether it
    // can pop; no other provider is touched during build.
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    final wordmark = find.text('Welcome back');
    expect(wordmark, findsOneWidget);

    final spans = renderedSpans(tester, wordmark);
    expect(spans, hasLength(1));
    final style = spans.single.style;

    // Characterization: this already holds, and must survive the migration.
    // The risk is a lazy fix that collapses the wordmark into the body font
    // just to satisfy the no-GoogleFonts guard, quietly killing the brand
    // mark - so pin both halves, the family it must keep and the one it
    // must not become.
    expect(
      rendersInFamily(style, AppTypography.displayFamily),
      isTrue,
      reason:
          'the wordmark must render in ${AppTypography.displayFamily}, but '
          'resolved fontFamily=${style?.fontFamily} '
          'fallback=${style?.fontFamilyFallback}',
    );
    expect(
      rendersInFamily(style, AppTypography.fontFamily),
      isFalse,
      reason: 'the wordmark must not collapse into the body font',
    );

    // The accessor the migration needs. Once no screen may call GoogleFonts
    // directly, the display family has to be reachable from AppTypography -
    // `displayFamily` names it but nothing hands back a usable style.
    expect(
      rendersInFamily(AppTypography.display, AppTypography.displayFamily),
      isTrue,
      reason:
          'AppTypography.display must resolve '
          '${AppTypography.displayFamily}, so the wordmark can drop its '
          'GoogleFonts call without losing the family',
    );
    expect(
      rendersInFamily(AppTypography.display, AppTypography.fontFamily),
      isFalse,
      reason: 'AppTypography.display must not be the body font',
    );
  });
}
