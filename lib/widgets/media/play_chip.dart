import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// The two play-chip treatments in the app. They are deliberately inverted
/// from one another — the feed sits a light glyph on a dark disc, the detail
/// view a dark glyph on a light one — and the glyph itself is part of the
/// style, not an independent knob.
enum PlayChipStyle { feed, detail }

/// Circular play affordance overlaying a video poster.
///
/// Shows a spinner in place of the glyph while [loading], which is how the
/// Streamable flow reports that it is resolving a playable URL.
class PlayChip extends StatelessWidget {
  const PlayChip({
    this.style = PlayChipStyle.feed,
    this.loading = false,
    super.key,
  });

  final PlayChipStyle style;
  final bool loading;

  Color get _background => switch (style) {
    PlayChipStyle.feed => AppColors.background.withValues(alpha: 0.7),
    PlayChipStyle.detail => AppColors.textPrimary.withValues(alpha: 0.9),
  };

  Color get _foreground => switch (style) {
    PlayChipStyle.feed => AppColors.textPrimary,
    PlayChipStyle.detail => AppColors.background,
  };

  IconData get _glyph => switch (style) {
    PlayChipStyle.feed => Icons.play_arrow,
    PlayChipStyle.detail => Icons.play_arrow_rounded,
  };

  double get _glyphSize => switch (style) {
    PlayChipStyle.feed => 48,
    PlayChipStyle.detail => 36,
  };

  Widget get _spinner => switch (style) {
    PlayChipStyle.feed => const CircularProgressIndicator(
      color: AppColors.loadingIndicator,
    ),
    PlayChipStyle.detail => const Padding(
      padding: EdgeInsets.all(18),
      child: CircularProgressIndicator(
        color: AppColors.background,
        strokeWidth: 2.5,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: _background, shape: BoxShape.circle),
      child:
          loading
              ? _spinner
              : Icon(_glyph, color: _foreground, size: _glyphSize),
    );
  }
}
