import 'package:flutter/material.dart';

/// Application color constants
///
/// Coves design system - warm beach-inspired palette adapted for dark mode.
/// Uses coral and teal as primary accents with warm undertones.
class AppColors {
  // Private constructor to prevent instantiation
  AppColors._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUNDS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary background - deep ocean navy
  static const background = Color(0xFF0B0F14);

  /// Secondary background - elevated surfaces, cards
  static const backgroundSecondary = Color(0xFF1A1F26);

  /// Tertiary background - input fields, subtle elevation
  static const backgroundTertiary = Color(0xFF1A2028);

  // ═══════════════════════════════════════════════════════════════════════════
  // BRAND COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary coral - energized warm orange (main accent)
  static const coral = Color(0xFFFF8040);

  /// Coral light - hover/glow states
  static const coralLight = Color(0xFFFFB468);

  /// Coral dark - pressed states
  static const coralDark = Color(0xFFDF7E40);

  /// Teal - secondary brand color (ocean-inspired)
  static const teal = Color(0xFF63B5B1);

  /// Teal dark - secondary pressed states
  static const tealDark = Color(0xFF4A9994);

  /// Legacy primary (alias to coral for compatibility)
  static const primary = coral;

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary text - warm off-white
  static const textPrimary = Color(0xFFFFF8F0);

  /// Secondary text - muted cool gray (blue undertone)
  static const textSecondary = Color(0xFFB6C2D2);

  /// Muted text - subtle hints, placeholders
  static const textMuted = Color(0xFF5A6B70);

  /// Link text - teal accent
  static const textLink = teal;

  // ═══════════════════════════════════════════════════════════════════════════
  // UI ELEMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Border color - subtle dark gray
  static const border = Color(0xFF2A2F36);

  /// Border warm - subtle coral-tinted gray for cards
  static const borderWarm = Color(0xFF2D2A28);

  /// Border focused - coral accent
  static const borderFocused = coral;

  /// Loading indicator
  static const loadingIndicator = Color(0xFF484F58);

  /// Community name - teal accent (matches brand)
  static const communityName = teal;

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMANTIC COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Success green
  static const success = Color(0xFF22C55E);

  /// Warning orange (uses coral)
  static const warning = coralDark;

  /// Error red
  static const error = Color(0xFFEC7558);

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATIVE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Floating bubble gradient start
  static const bubbleGradientStart = Color(0x26F08C59); // coral @ ~15%

  /// Floating bubble gradient end
  static const bubbleGradientEnd = Color(0x2663B5B1); // teal @ ~15%

  /// Ocean gradient overlay
  static const oceanGradient = Color(0x4063B5B1); // teal @ ~25%
}
