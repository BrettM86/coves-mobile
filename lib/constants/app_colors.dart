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

  /// Placeholder text inside form fields - hint text on compose surfaces.
  ///
  /// NOT a duplicate of [textMuted]. The two differ only in the final byte
  /// (`…6B70` vs `…6B7F`) and read as the same gray at a glance, which makes
  /// them a standing trap: collapsing one into the other silently shifts
  /// every hint field's blue channel. They are kept apart deliberately - if
  /// they should ever become one color, change both values in a commit that
  /// says so, rather than "tidying" a reference from one to the other.
  static const textPlaceholder = Color(0xFF5A6B7F);

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

  /// Border on input fields and dividers across the compose surfaces
  /// (create-post form, community picker).
  static const inputBorder = Color(0xFF2A3441);

  /// Divider separating the tablet navigation rail from the page body.
  static const navDivider = Color(0xFF1A2433);

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

  /// The liked / upvoted vote state - the filled heart on a post or comment.
  ///
  /// A state color, not a severity one. Distinct from [error] on purpose:
  /// [error] is the muted salmon used for failures and validation messages,
  /// while this is the hot red that signals "you voted on this". Nothing
  /// destructive uses it, so do not rename it toward that meaning, and do not
  /// collapse the two - a liked heart is not an error.
  static const voteLiked = Color(0xFFFF0033);

  // ═══════════════════════════════════════════════════════════════════════════
  // AVATAR FALLBACKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Palette used to tint an avatar that has no image, picked by name hash.
  ///
  /// Deliberately one list rather than six individually named tokens: the
  /// entries carry no role on their own - only "some stable color for this
  /// name" - so naming them individually could only name their hue, which
  /// this palette does not do.
  ///
  /// Treat this list as frozen. `DisplayUtils.getFallbackColor` indexes it by
  /// `name.hashCode.abs() % length`, so BOTH the order and the length are
  /// load-bearing: appending is not the safe operation it looks like, because
  /// it changes the modulus and repartitions every existing name onto a
  /// different color. Reordering, inserting, removing and appending are all
  /// equally destructive - any edit repaints the avatar of every account that
  /// has no image.
  static const avatarFallbacks = [
    coral,
    teal,
    Color(0xFF9B59B6),
    Color(0xFF3498DB),
    Color(0xFF27AE60),
    Color(0xFFE74C3C),
  ];

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
