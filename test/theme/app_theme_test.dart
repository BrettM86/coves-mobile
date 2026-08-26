import 'package:coves_flutter/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/font_identity.dart';
import '../test_helpers/theme_pump.dart';

/// The family Material resolves for this platform when no font is bundled.
///
/// The app names no body font, so the correct expectation is "whatever the
/// platform provides" - Roboto on Android, a San Francisco variant on Apple.
/// Comparing against Material's own default keeps this honest on both rather
/// than hardcoding one and lying on the other.
String? get _platformFamily =>
    ThemeData.dark().textTheme.bodyMedium?.fontFamily;

void main() {
  // Must be `testWidgets`, never a plain `test`: the google_fonts loader only
  // stays inert inside the fake-async zone testWidgets installs. In a real
  // zone it attempts an HTTP fetch and rethrows as an unhandled async error.
  testWidgets('AppTheme.dark themes text, color roles, and the page', (
    tester,
  ) async {
    late TextStyle defaultTextStyle;
    late ThemeData theme;

    await pumpUnderAppTheme(
      tester,
      Builder(
        builder: (context) {
          defaultTextStyle = DefaultTextStyle.of(context).style;
          theme = Theme.of(context);
          return const Text('x');
        },
      ),
    );

    // (a) Unstyled text is legible on the dark background.
    expect(
      defaultTextStyle.color,
      AppColors.textPrimary,
      reason: 'a bare Text() must inherit the primary text color',
    );
    expect(
      rendersInFamily(defaultTextStyle, _platformFamily),
      isTrue,
      reason:
          'a bare Text() must inherit $_platformFamily; got '
          'fontFamily=${defaultTextStyle.fontFamily} '
          'fallback=${defaultTextStyle.fontFamilyFallback}',
    );

    // (b) The color roles the app actually leans on resolve to AppColors
    // tokens. Deliberately a named subset: ColorScheme carries ~45 roles and
    // AppColors only has tokens for a handful, so an exhaustive assertion
    // would be either unsatisfiable or vacuous.
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.primary, AppColors.coral);
    expect(scheme.secondary, AppColors.teal);
    expect(scheme.surface, AppColors.backgroundSecondary);
    expect(scheme.onSurface, AppColors.textPrimary);
    expect(scheme.error, AppColors.error);
    expect(scheme.outline, AppColors.border);
    // Unpinned roles do NOT fall back to Material's dark baseline - they are
    // derived from the pinned ones, so leaving these two alone left
    // `outlineVariant` sitting at the near-white text color. Both are
    // live-reachable: MaterialBanner unconditionally draws a
    // `Divider(color: outlineVariant)`, which the reply screen and the
    // comment composer both put on screen.
    expect(scheme.outlineVariant, AppColors.border);
    expect(scheme.onSurfaceVariant, AppColors.textSecondary);

    // (c) The page sits a step below its surfaces. This reads like a bug but
    // is intentional: the scaffold background is the deep page color
    // (0xFF0B0F14) while cards, dialogs and sheets sit on
    // colorScheme.surface (0xFF1A1F26), which gives them their elevation.
    expect(theme.scaffoldBackgroundColor, AppColors.background);
  });
}
