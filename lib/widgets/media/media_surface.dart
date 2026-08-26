import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Icon treatment for a [MediaFill]. The feed card and the detail view use
/// different weights because they render media at different sizes.
typedef MediaFillStyle = ({Color iconColor, double iconSize});

/// The feed card's fill treatment.
const MediaFillStyle kFeedMediaFill = (
  iconColor: AppColors.textSecondary,
  iconSize: 32,
);

/// The detail view's fill treatment.
const MediaFillStyle kDetailMediaFill = (
  iconColor: AppColors.textMuted,
  iconSize: 40,
);

/// Neutral fill behind media: shown while a thumbnail loads, when it fails,
/// and for videos the AppView gave us no poster for.
class MediaFill extends StatelessWidget {
  const MediaFill({
    this.icon,
    this.iconColor = AppColors.textSecondary,
    this.iconSize = 32,
    super.key,
  });

  /// Optional glyph centred in the fill. A bare fill (no icon) is what a
  /// still-loading thumbnail shows, so it reads as space rather than error.
  final IconData? icon;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundSecondary,
      child:
          icon == null
              ? null
              : Center(child: Icon(icon, color: iconColor, size: iconSize)),
    );
  }
}

/// Small translucent pill overlaying media — the image count, the gallery
/// page indicator and the video duration all use it.
class MediaBadge extends StatelessWidget {
  const MediaBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
