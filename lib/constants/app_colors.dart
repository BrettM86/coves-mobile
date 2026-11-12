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

  /// Metadata text - timestamps, kind labels and other small secondary copy.
  ///
  /// Unlike [textMuted], this passes 4.5:1 contrast on [background], so it is
  /// safe for text a reader needs.
  static const textMeta = Color(0xFF8494A3);

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

  /// Surface of an inset box quoting other content, such as a moderation log
  /// row's subject.
  static const insetSurface = Color(0xFF131920);

  /// Border of an [insetSurface] box.
  static const insetBorder = Color(0xFF1E252E);

  /// Loading indicator
  static const loadingIndicator = Color(0xFF484F58);

  /// Gallery page-dot pill: a translucent dark grey that reads against both
  /// the page background and an image.
  static const mediaPill = Color(0xE6262626);

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

  /// NSFW label amber - marking or unmarking content as NSFW.
  static const nsfwLabel = Color(0xFFE8B84A);

  /// The liked / upvoted vote state - the filled heart on a post or comment.
  ///
  /// A state color, not a severity one. Distinct from [error] on purpose:
  /// [error] is the muted salmon used for failures and validation messages,
  /// while this is the hot red that signals "you voted on this". Nothing
  /// destructive uses it, so do not rename it toward that meaning, and do not
  /// collapse the two - a liked heart is not an error.
  static const voteLiked = Color(0xFFFF0033);

  // ═══════════════════════════════════════════════════════════════════════════
  // BLUESKY
  // ═══════════════════════════════════════════════════════════════════════════

  // The Bluesky profile card in the import dialog copies the Bluesky app's
  // "dim" theme whatever the app theme is.

  /// Bluesky profile card surface (Bluesky dim background).
  static const blueskyCardBackground = Color(0xFF151D28);

  /// Bluesky profile card outline and its empty banner and avatar.
  static const blueskyCardBorder = Color(0xFF2C3A4E);

  /// Secondary text on the Bluesky profile card, such as the handle.
  static const blueskyCardMutedText = Color(0xFFABB8C9);

  /// Bluesky profile card placeholders and hover surface (Bluesky dim).
  static const blueskyCardHover = Color(0xFF1C2939);

  // ═══════════════════════════════════════════════════════════════════════════
  // BLUESKY IMPORT: COVES TARGET CARD
  // ═══════════════════════════════════════════════════════════════════════════

  // The hollow Coves card the Bluesky card is dragged onto, and the colours
  // the Bluesky card blends into on its way there. Tailwind slate (light
  // theme) and zinc (dark theme), matching the web client.

  /// Coves card surface, light theme (slate-50).
  static const covesImportSurfaceLight = Color(0xFFF8FAFC);

  /// Coves card dashed outline at rest, light theme (slate-300).
  static const covesImportOutlineLight = Color(0xFFCBD5E1);

  /// Coves card ink, and its outline while the card is over it, light theme
  /// (slate-900).
  static const covesImportInkLight = Color(0xFF0F172A);

  /// Coves card muted text, light theme (slate-600).
  static const covesImportMutedLight = Color(0xFF475569);

  /// Coves card placeholders, light theme (slate-200).
  static const covesImportPlaceholderLight = Color(0xFFE2E8F0);

  /// Coves card surface, dark theme (zinc-900).
  static const covesImportSurfaceDark = Color(0xFF18181B);

  /// Coves card dashed outline at rest, dark theme (zinc-700).
  static const covesImportOutlineDark = Color(0xFF3F3F46);

  /// Coves card ink, and its outline while the card is over it, dark theme
  /// (zinc-100).
  static const covesImportInkDark = Color(0xFFF4F4F5);

  /// Coves card muted text, dark theme (zinc-400).
  static const covesImportMutedDark = Color(0xFFA1A1AA);

  /// Coves card placeholders, dark theme (zinc-800).
  static const covesImportPlaceholderDark = Color(0xFF27272A);

  /// Seat burst capsule outline (rose-500).
  static const seatBurstRose = Color(0xFFF43F5E);

  /// Seat burst dash fill (teal-500).
  static const seatBurstTeal = Color(0xFF14B8A6);

  /// Seat burst diamond outline (amber-500).
  static const seatBurstAmber = Color(0xFFF59E0B);

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
