import 'package:flutter/material.dart';

import 'app_colors.dart';
import '../widgets/icons/back_icon.dart';
import 'app_typography.dart';

/// Application theme
///
/// Single source of truth for the [ThemeData] the app runs under, wiring the
/// design tokens in `app_colors.dart` and `app_typography.dart` into Material.
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  /// Color roles, mapped by hand onto the palette in `app_colors.dart`.
  ///
  /// Deliberately NOT `ColorScheme.fromSeed`: seeding derives a tonal palette
  /// whose colors are desaturated relatives of the seed and match nothing in
  /// the palette.
  ///
  /// An unpinned role does NOT fall back to some neutral Material default -
  /// [ColorScheme] derives it from the roles that *are* pinned. That is not a
  /// harmless gap: it is how `outlineVariant` arrived at a near-white, by
  /// deriving off `onSurface`, which the palette sets to its brightest text
  /// color. So a role left out here silently inherits a decision made
  /// somewhere else, and the failure mode is a hairline divider rendering as
  /// a bright white rule. Pin any role the app actually reads.
  static const ColorScheme _colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.coral,
    // Judgment call: coral, teal and error are all light, saturated
    // mid-tones, so black reads on them far better than the palette's
    // off-white does. AppColors has no token dark enough to serve as an
    // "on accent" color, so a neutral is the honest choice.
    onPrimary: Colors.black,
    secondary: AppColors.teal,
    onSecondary: Colors.black,
    error: AppColors.error,
    onError: Colors.black,
    // `surface` is an elevated color, not the page - see [dark]'s
    // `scaffoldBackgroundColor`. Note that Material 3 does not read `surface`
    // for cards and sheets (`surfaceContainerLow`) or dialogs
    // (`surfaceContainerHigh`); those land here only because they are
    // unpinned and derive from it. Pin them and this stops being true.
    surface: AppColors.backgroundSecondary,
    onSurface: AppColors.textPrimary,
    outline: AppColors.border,
    // Both derive off `onSurface` when unpinned, which put a near-white on
    // every hairline divider and every piece of secondary label text.
    outlineVariant: AppColors.border,
    onSurfaceVariant: AppColors.textSecondary,
  );

  /// The app's dark theme.
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: _colorScheme,
    // Named twice on purpose, because they feed different things:
    // `textTheme` carries the 15 body/display roles, while `fontFamily`
    // reaches the styles ThemeData derives for itself - `primaryTextTheme`
    // among them - so no widget can pick up a stray face by reading a slot
    // the supplied TextTheme does not cover.
    //
    // Passing it is redundant *today*, because the token is null and null is
    // the default. Keeping the wiring is the point: it is what makes setting
    // `AppTypography.fontFamily` to a family name actually change the app's
    // font. Delete this line and that one-line swap silently stops working.
    // ignore: avoid_redundant_argument_values
    fontFamily: AppTypography.fontFamily,
    textTheme: AppTypography.textTheme,
    // Must be explicit. Left unset, ThemeData resolves the icon color for a
    // dark brightness to plain `Colors.white` - NOT to `colorScheme.onSurface`
    // - so unstyled icons sit a notch cooler than body text. Pinning the
    // palette's warm off-white makes a post card's action row (reply, share,
    // heart) read at the same temperature as the text beside it.
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    // Implicit AppBar back buttons (post detail, any pushed route without an
    // explicit leading) render the Lucide arrow instead of Material's, so
    // navigation chrome matches the Lucide icon set used everywhere else.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const BackIcon(),
    ),
    // A step below `colorScheme.surface` on purpose: the page is the deep
    // 0xFF0B0F14 while the elevated containers sit above it on 0xFF1A1F26,
    // which is what gives them their elevation. Under Material 3 those
    // containers read `surfaceContainerLow` / `surfaceContainerHigh`, which
    // currently resolve to `surface` only because they are left unpinned.
    scaffoldBackgroundColor: AppColors.background,
  );
}
