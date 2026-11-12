import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/bluesky_colors.dart';
import '../../utils/bluesky_import_motion.dart';

/// Wide layouts (side-by-side cards) start at this dialog width.
const double importWideBreakpoint = 768;

/// The fixed row heights the Bluesky card and the Coves card share, so the
/// two always match whatever their content.
enum ImportCardGeometry {
  /// Phone layout, under [importWideBreakpoint].
  phone._(
    labelStrip: 28,
    banner: 80,
    avatar: 56,
    avatarOverlap: 20,
    nameRow: 30,
    nameFontSize: 20,
    handleRow: 20,
    bioRow: 48,
    bioTopPadding: 8,
    bioLines: 2,
    bottomPadding: 10,
  ),

  /// Wide layout, at [importWideBreakpoint] and up.
  wide._(
    labelStrip: 36,
    banner: 144,
    avatar: 80,
    avatarOverlap: 28,
    nameRow: 34,
    nameFontSize: 24,
    handleRow: 22,
    bioRow: 72,
    bioTopPadding: 12,
    bioLines: 3,
    bottomPadding: 16,
  );

  const ImportCardGeometry._({
    required this.labelStrip,
    required this.banner,
    required this.avatar,
    required this.avatarOverlap,
    required this.nameRow,
    required this.nameFontSize,
    required this.handleRow,
    required this.bioRow,
    required this.bioTopPadding,
    required this.bioLines,
    required this.bottomPadding,
  });

  static const double border = 2;
  static const double radius = 12;
  static const double avatarRing = 3;
  static const double horizontalPadding = 16;
  static const double avatarTextGap = 12;
  static const double bioFontSize = 14;
  static const double bioLineHeight = 20;

  final double labelStrip;
  final double banner;

  /// The avatar's outer diameter, ring included.
  final double avatar;
  final double avatarOverlap;
  final double nameRow;
  final double nameFontSize;
  final double handleRow;
  final double bioRow;
  final double bioTopPadding;
  final int bioLines;
  final double bottomPadding;

  /// The card's whole height, border included.
  double get height =>
      labelStrip +
      banner +
      nameRow +
      handleRow +
      bioRow +
      bottomPadding +
      2 * border;

  /// Where the name and handle rows start, beside the avatar.
  double get textLeft => horizontalPadding + avatar + avatarTextGap;
}

/// The colours one card is drawn in.
@immutable
class ImportCardPalette {
  const ImportCardPalette({
    required this.surface,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.placeholder,
  });

  /// The Bluesky card's colours at blend amount [p] towards [coves]: the
  /// surface jumps at the midpoint, the border blends smoothly and the text
  /// and accent switch at the midpoint. All blends run in oklab.
  factory ImportCardPalette.blend(CovesTargetPalette coves, double p) {
    if (p <= 0) {
      return bluesky;
    }
    final covesShare = 1 - surfaceShare(p);
    final step = blendStep(p) == 1;
    return ImportCardPalette(
      surface: lerpOklab(bluesky.surface, coves.surface, covesShare),
      border: lerpOklab(bluesky.border, coves.ink, p),
      ink: step ? coves.ink : bluesky.ink,
      muted: step ? coves.muted : bluesky.muted,
      accent: step ? coves.muted : bluesky.accent,
      placeholder: lerpOklab(
        bluesky.placeholder,
        coves.placeholder,
        covesShare,
      ),
    );
  }

  /// Bluesky's "dim" palette, used in every Coves theme.
  static const bluesky = ImportCardPalette(
    surface: AppColors.blueskyCardBackground,
    border: AppColors.blueskyCardBorder,
    ink: BlueskyColors.textPrimary,
    muted: AppColors.blueskyCardMutedText,
    accent: BlueskyColors.blueskyBlue,
    placeholder: AppColors.blueskyCardHover,
  );

  final Color surface;
  final Color border;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color placeholder;
}

/// The Coves card's colours for the current theme.
enum CovesTargetPalette {
  light._(
    surface: AppColors.covesImportSurfaceLight,
    outline: AppColors.covesImportOutlineLight,
    ink: AppColors.covesImportInkLight,
    muted: AppColors.covesImportMutedLight,
    placeholder: AppColors.covesImportPlaceholderLight,
  ),
  dark._(
    surface: AppColors.covesImportSurfaceDark,
    outline: AppColors.covesImportOutlineDark,
    ink: AppColors.covesImportInkDark,
    muted: AppColors.covesImportMutedDark,
    placeholder: AppColors.covesImportPlaceholderDark,
  );

  const CovesTargetPalette._({
    required this.surface,
    required this.outline,
    required this.ink,
    required this.muted,
    required this.placeholder,
  });

  static CovesTargetPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;

  final Color surface;

  /// The dashed outline at rest.
  final Color outline;

  /// Text, and the outline while the Bluesky card is over the target.
  final Color ink;
  final Color muted;
  final Color placeholder;
}
