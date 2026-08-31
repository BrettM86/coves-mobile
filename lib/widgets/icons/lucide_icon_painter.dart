import 'package:flutter/material.dart';

import 'lucide_paths.dart';

/// Paints a Lucide icon (24x24 viewBox, 2px round stroke) scaled to the
/// widget size. When [filled] the same shapes are also filled with [color],
/// giving the solid variant used for "active" states.
class LucideIconPainter extends CustomPainter {
  LucideIconPainter({
    required this.paths,
    required this.color,
    this.filled = false,
  });

  final List<String> paths;
  final Color color;
  final bool filled;

  static const double _viewBox = 24;
  static const double _strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _viewBox, size.height / _viewBox);

    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final fill =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    for (final d in paths) {
      final path = lucidePath(d);
      if (filled) {
        canvas.drawPath(path, fill);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(LucideIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.filled != filled ||
      oldDelegate.paths != paths;
}

/// Renders a set of Lucide paths as a plain icon widget, colored explicitly
/// or by the ambient [IconTheme]. For one-off glyphs that don't warrant a
/// dedicated widget class.
class LucideGlyph extends StatelessWidget {
  const LucideGlyph(this.paths, {this.size = 24, this.color, super.key});

  final List<String> paths;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.grey;

    return CustomPaint(
      size: Size(size, size),
      painter: LucideIconPainter(paths: paths, color: effectiveColor),
    );
  }
}
