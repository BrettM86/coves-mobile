import 'package:flutter/material.dart';

/// Bluesky color constants
///
/// Color palette matching Bluesky's "dim" theme (dark blue-gray).
/// These values are taken from the bskyembed component in social-app.
class BlueskyColors {
  // Private constructor to prevent instantiation
  BlueskyColors._();

  /// Bluesky brand blue - outer container background
  /// From tailwind.config.cjs: brand = rgb(10,122,255)
  static const blueskyBlue = Color(0xFF0A7AFF);

  /// Inner card background - dim theme: dimmedBg = rgb(22,30,39)
  static const cardBackground = Color(0xFF161E27);

  /// Card border color - dim theme border
  static const cardBorder = Color(0xFF2E3D4F);

  /// Primary text color - white
  static const textPrimary = Color(0xFFFFFFFF);

  /// Secondary text color - gray-blue for handles
  static const textSecondary = Color(0xFF8B98A5);

  /// Muted text color - for timestamps
  static const textMuted = Color(0xFF8B98A5);

  /// Action icon/text color - same gray-blue
  static const actionColor = Color(0xFF8B98A5);

  /// Link color - Bluesky blue
  static const linkBlue = Color(0xFF1185FE);

  /// Link color lightened - for press states
  static const linkBlueLight = Color(0xFF4AABFF);

  /// Avatar fallback background
  static const avatarFallback = Color(0xFF2E3D4F);

  /// Outer container border radius
  static const double outerBorderRadius = 20;

  /// Inner card border radius
  static const double innerBorderRadius = 14;
}
