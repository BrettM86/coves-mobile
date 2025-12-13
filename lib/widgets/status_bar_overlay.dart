import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A solid color overlay for the status bar area
///
/// Prevents content from showing through the transparent status bar when
/// scrolling. Use with a Stack widget, positioned at the top.
///
/// Example:
/// ```dart
/// Stack(
///   children: [
///     // Your scrollable content
///     CustomScrollView(...),
///     // Status bar overlay
///     const StatusBarOverlay(),
///   ],
/// )
/// ```
class StatusBarOverlay extends StatelessWidget {
  const StatusBarOverlay({
    this.color = AppColors.background,
    super.key,
  });

  /// The color to fill the status bar area with
  final Color color;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: statusBarHeight,
      child: Container(color: color),
    );
  }
}
