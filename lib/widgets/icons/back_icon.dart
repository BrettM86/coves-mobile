import 'package:flutter/material.dart';

import 'lucide_icon_painter.dart';
import 'lucide_paths.dart';

/// Back-navigation icon — Lucide `arrow-left`.
///
/// Used both directly in explicit leading buttons and as the app-wide
/// default via `actionIconTheme.backButtonIconBuilder` in AppTheme.
class BackIcon extends StatelessWidget {
  const BackIcon({this.size = 24, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.grey;

    return CustomPaint(
      size: Size(size, size),
      painter: LucideIconPainter(
        paths: LucidePaths.arrowLeft,
        color: effectiveColor,
      ),
    );
  }
}
