import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app_colors.dart';

/// Application typography constants
///
/// Coves design system - type tokens shared by the app theme and by any
/// widget that needs to name the font family directly.
///
/// Body text renders in the **platform's own font** - [fontFamily] is null -
/// so the app looks native on each platform and honours the user's font
/// setting. Only the display face is bundled, because a wordmark has to be
/// itself.
///
/// If a body font is ever bundled here, bundle it as an asset rather than
/// fetching it at runtime. That is not an optimization, it is a correctness
/// requirement: a runtime font source that registers one family per weight
/// can only serve the weights it was asked to fetch, and every heavier weight
/// silently degrades to Regular with the rasterizer faking the bold. A single
/// **variable** file whose `wght` axis spans 100-900 lets one family name
/// serve every weight, so [TextStyle.fontWeight] selects a real cut.
class AppTypography {
  // Private constructor to prevent instantiation
  AppTypography._();

  /// Canonical body/UI font family, or null to use the platform's own.
  ///
  /// This is the ONLY place in the codebase that names a body/UI font family,
  /// and it is genuinely load-bearing: [textTheme] applies it through
  /// [TextTheme.apply], and `AppTheme.dark` hands it to
  /// `ThemeData.fontFamily`, so this value decides the app's font.
  ///
  /// **Null means "let the platform decide"**, which is the current choice:
  /// Roboto on stock Android, One UI Sans on Samsung, SF Pro on iOS. The app
  /// therefore looks native on each platform and inherits the user's own font
  /// setting, at the cost of not looking identical across them.
  ///
  /// To bundle a face instead, set this to a family name and declare that
  /// family in `pubspec.yaml` - the two must match. Prefer a single VARIABLE
  /// file with no `weight:` attributes, or heavier weights degrade to
  /// synthetic bold. That is the whole change; nothing else names a font.
  static const String? fontFamily = null;

  /// Display family, used for the Coves logo wordmark.
  ///
  /// Same rule as [fontFamily]: the single place this family is named, and it
  /// must match the `family:` key in `pubspec.yaml`.
  static const String displayFamily = 'Shrikhand';

  /// Text style for the Coves wordmark, in [displayFamily].
  ///
  /// Carries the family and nothing else: no size, weight or color. The two
  /// call sites want different sizes (48pt on the landing screen, 28pt with
  /// `height: 1.2` on login), so they layer their own on top -
  /// `AppTypography.display.copyWith(fontSize: 48, color: …)`. Keeping the
  /// getter bare is what lets one accessor serve both without inventing a
  /// per-site parameter list.
  ///
  /// This is the only way to reach the display family from outside this file,
  /// so the wordmark never has to name a font to keep the brand mark.
  static const TextStyle display = TextStyle(fontFamily: displayFamily);

  /// Declares the bundled font's OFL license to Flutter's license registry,
  /// so it appears in the standard "Licenses" page.
  ///
  /// Only [displayFamily] ships inside the binary - the body text uses the
  /// platform's own font, which carries its own licensing - and the SIL Open
  /// Font License requires the license text to travel with the file. Call
  /// once during startup. The collector is lazy, so the file is only read if
  /// a user opens the license page and this costs nothing at launch.
  static void registerLicenses() {
    LicenseRegistry.addLicense(() async* {
      for (final entry in const {
        displayFamily: 'assets/fonts/OFL-Shrikhand.txt',
      }.entries) {
        yield LicenseEntryWithLineBreaks(
          [entry.key],
          await rootBundle.loadString(entry.value),
        );
      }
    });
  }

  /// The app's [TextTheme]: Material's 2021 type scale, in [fontFamily], in
  /// the palette's text color.
  ///
  /// Built over a **dark** base, and both that choice and the explicit color
  /// application are load-bearing, for two different reasons:
  ///
  /// * `.apply(bodyColor:, displayColor:)` sets `color` on all 15 roles.
  ///   Without it the roles keep the base's own color, and [ThemeData] merges
  ///   a supplied `textTheme` *over* its typography defaults, so an explicit
  ///   color in the base wins over anything the theme would otherwise pick.
  ///   Under Material 3 that color is `colorScheme.onSurface` - for a light
  ///   base an opaque `0xFF1D1B20`, with no alpha to soften it - which would
  ///   render every unstyled `Text` near-black on the near-black page.
  /// * The dark base covers what `.apply` does *not* reach:
  ///   `decorationColor`, which `Typography.material2021` sets alongside the
  ///   text color and which `.apply` leaves untouched when passed null. Over
  ///   a light base, underlines and strikethrough would still come out
  ///   near-black even with the colors above corrected.
  static TextTheme get textTheme =>
      ThemeData.dark().textTheme.apply(
        // Redundant while [fontFamily] is null, and deliberately kept: this
        // is the wiring that makes the token load-bearing. See [fontFamily].
        // ignore: avoid_redundant_argument_values
        fontFamily: fontFamily,
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );
}
