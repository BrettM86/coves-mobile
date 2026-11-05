import 'package:flutter/widgets.dart';

import '../../constants/app_colors.dart';

/// A gallery's page indicator: one small dot per page in a dark translucent
/// pill, the current page's dot drawn solid.
///
/// A single page has nothing to indicate, so [count] below two renders
/// nothing, semantics included.
class MediaPageDots extends StatelessWidget {
  const MediaPageDots({required this.count, required this.index, super.key});

  final int count;
  final int index;

  static const _dotSize = 5.0;
  static const _dotGap = 6.0;
  static const _verticalPadding = 6.0;

  /// Half the pill's height, so its ends are full semicircles.
  static const _pillRadius = _verticalPadding + _dotSize / 2;

  static const Color _pillColor = AppColors.mediaPill;
  static final Color _inactiveDotColor = AppColors.textPrimary.withValues(
    alpha: 0.6,
  );

  @override
  Widget build(BuildContext context) {
    if (count < 2) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      label: 'Image ${index + 1} of $count',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _pillColor,
          borderRadius: BorderRadius.circular(_pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: _verticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var dot = 0; dot < count; dot++) ...[
                if (dot > 0) const SizedBox(width: _dotGap),
                DecoratedBox(
                  key: Key('media-page-dot-$dot'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot == index
                        ? AppColors.textPrimary
                        : _inactiveDotColor,
                  ),
                  child: const SizedBox.square(dimension: _dotSize),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
