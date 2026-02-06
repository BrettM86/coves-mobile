import 'package:flutter/material.dart';

/// Utility class for responsive layout detection and sizing.
///
/// Provides tablet detection and content width constraints for
/// adapting layouts between phone and tablet form factors.
class ResponsiveUtils {
  /// Tablets have shortestSide >= 600dp (Material Design guidelines)
  static const double tabletBreakpoint = 600;

  /// Maximum content width for readability on large screens.
  ///
  /// 640px provides an optimal line length of ~70-80 characters for body text,
  /// which research shows maximizes reading comprehension and comfort.
  /// This value also aligns with common content-width patterns in web design.
  static const double maxContentWidth = 640;

  /// Returns true if device is a tablet (based on shortest side).
  ///
  /// Uses shortestSide to handle both portrait and landscape orientations
  /// consistently - a tablet is still a tablet regardless of rotation.
  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= tabletBreakpoint;
  }

  /// Wraps [child] with centered max-width constraints on tablets.
  ///
  /// On phones, returns the child unchanged.
  /// On tablets, centers the child within [maxContentWidth] constraints.
  static Widget wrapForTablet(BuildContext context, Widget child) {
    if (!isTablet(context)) {
      return child;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}
