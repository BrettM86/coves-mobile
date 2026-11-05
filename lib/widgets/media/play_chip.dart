import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// The two play-chip treatments in the app. They are deliberately inverted
/// from one another — the feed sits a light glyph on a dark disc, the detail
/// view a dark glyph on a light one — and the glyph itself is part of the
/// style, not an independent knob.
enum PlayChipStyle { feed, detail }

/// What the chip offers: start playback, or pause it (a playing GIF).
enum PlayChipGlyph { play, pause }

/// Circular play affordance overlaying a video poster or a GIF still.
///
/// Shows a spinner in place of the glyph while [loading], which is how the
/// Streamable flow reports that it is resolving a playable URL. [compact]
/// shrinks the chip for a corner control that must not cover the media,
/// such as a playing GIF's pause control.
class PlayChip extends StatelessWidget {
  const PlayChip({
    this.style = PlayChipStyle.feed,
    this.glyph = PlayChipGlyph.play,
    this.loading = false,
    this.compact = false,
    super.key,
  });

  final PlayChipStyle style;
  final PlayChipGlyph glyph;
  final bool loading;
  final bool compact;

  static const double _diameter = 64;
  static const double _compactDiameter = 36;

  Color get _background => switch (style) {
    PlayChipStyle.feed => AppColors.background.withValues(alpha: 0.7),
    PlayChipStyle.detail => AppColors.textPrimary.withValues(alpha: 0.9),
  };

  Color get _foreground => switch (style) {
    PlayChipStyle.feed => AppColors.textPrimary,
    PlayChipStyle.detail => AppColors.background,
  };

  IconData get _glyph => switch ((style, glyph)) {
    (PlayChipStyle.feed, PlayChipGlyph.play) => Icons.play_arrow,
    (PlayChipStyle.detail, PlayChipGlyph.play) => Icons.play_arrow_rounded,
    (PlayChipStyle.feed, PlayChipGlyph.pause) => Icons.pause,
    (PlayChipStyle.detail, PlayChipGlyph.pause) => Icons.pause_rounded,
  };

  double get _glyphSize {
    final size = switch (style) {
      PlayChipStyle.feed => 48.0,
      PlayChipStyle.detail => 36.0,
    };
    return compact ? size * _compactDiameter / _diameter : size;
  }

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
    final diameter = compact ? _compactDiameter : _diameter;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: _background, shape: BoxShape.circle),
      child: loading
          ? _spinner
          : Icon(_glyph, color: _foreground, size: _glyphSize),
    );
  }
}
