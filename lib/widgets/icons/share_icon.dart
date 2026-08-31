import 'package:flutter/material.dart';

import 'lucide_icon_painter.dart';
import 'lucide_paths.dart';

/// Share icon widget (curved arrow pointing right) — Lucide `forward`.
class ShareIcon extends StatelessWidget {
  const ShareIcon({this.size = 18, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).iconTheme.color ?? Colors.grey;

    return CustomPaint(
      size: Size(size, size),
      painter: LucideIconPainter(
        paths: LucidePaths.forward,
        color: effectiveColor,
      ),
    );
  }
}
