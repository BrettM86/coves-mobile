import 'package:flutter/material.dart';

/// Reply/comment icon widget
///
/// Speech bubble icon from Bluesky's design system.
/// Supports both outline and filled states.
class ReplyIcon extends StatelessWidget {
  const ReplyIcon({this.size = 18, this.color, this.filled = false, super.key});

  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).iconTheme.color ?? Colors.grey;

    return CustomPaint(
      size: Size(size, size),
      painter: _ReplyIconPainter(color: effectiveColor, filled: filled),
    );
  }
}

/// Custom painter for reply/comment icon
///
/// SVG path data from Bluesky's Reply icon component
class _ReplyIconPainter extends CustomPainter {
  _ReplyIconPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill; // Always fill - paths are pre-stroked

    // Scale factor to fit 24x24 viewBox into widget size
    final scale = size.width / 24.0;
    canvas.scale(scale);

    final path = Path();

    if (filled) {
      // Filled reply icon path from Bluesky
      // M22.002 15a4 4 0 0 1-4 4h-4.648l-4.727 3.781A1.001 1.001 0 0 1 7.002 22
      // v-3h-1a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4h12a4 4 0 0 1 4 4v8Z
      path
        ..moveTo(22.002, 15)
        ..cubicTo(22.002, 17.209, 20.211, 19, 18.002, 19)
        ..lineTo(13.354, 19)
        ..lineTo(8.627, 22.781)
        ..cubicTo(8.243, 23.074, 7.683, 22.808, 7.627, 22.318)
        ..lineTo(7.002, 22)
        ..lineTo(7.002, 19)
        ..lineTo(6.002, 19)
        ..cubicTo(3.793, 19, 2.002, 17.209, 2.002, 15)
        ..lineTo(2.002, 7)
        ..cubicTo(2.002, 4.791, 3.793, 3, 6.002, 3)
        ..lineTo(18.002, 3)
        ..cubicTo(20.211, 3, 22.002, 4.791, 22.002, 7)
        ..lineTo(22.002, 15)
        ..close();
    } else {
      // Outline reply icon path from Bluesky
      // M20.002 7a2 2 0 0 0-2-2h-12a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2
      // a1 1 0 0 1 1 1 v1.918l3.375-2.7a1 1 0 0 1 .625-.218h5
      // a2 2 0 0 0 2-2V7Zm2 8a4 4 0 0 1-4 4 h-4.648l-4.727 3.781
      // A1.001 1.001 0 0 1 7.002 22v-3h-1a4 4 0 0 1-4-4V7
      // a4 4 0 0 1 4-4h12a4 4 0 0 1 4 4v8Z

      // Inner shape
      path
        ..moveTo(20.002, 7)
        ..cubicTo(20.002, 5.895, 19.107, 5, 18.002, 5)
        ..lineTo(6.002, 5)
        ..cubicTo(4.897, 5, 4.002, 5.895, 4.002, 7)
        ..lineTo(4.002, 15)
        ..cubicTo(4.002, 16.105, 4.897, 17, 6.002, 17)
        ..lineTo(8.002, 17)
        ..cubicTo(8.554, 17, 9.002, 17.448, 9.002, 18)
        ..lineTo(9.002, 19.918)
        ..lineTo(12.377, 17.218)
        ..cubicTo(12.574, 17.073, 12.813, 17, 13.002, 17)
        ..lineTo(18.002, 17)
        ..cubicTo(19.107, 17, 20.002, 16.105, 20.002, 15)
        ..lineTo(20.002, 7)
        ..close()
        // Outer shape
        ..moveTo(22.002, 15)
        ..cubicTo(22.002, 17.209, 20.211, 19, 18.002, 19)
        ..lineTo(13.354, 19)
        ..lineTo(8.627, 22.781)
        ..cubicTo(8.243, 23.074, 7.683, 22.808, 7.627, 22.318)
        ..lineTo(7.002, 22)
        ..lineTo(7.002, 19)
        ..lineTo(6.002, 19)
        ..cubicTo(3.793, 19, 2.002, 17.209, 2.002, 15)
        ..lineTo(2.002, 7)
        ..cubicTo(2.002, 4.791, 3.793, 3, 6.002, 3)
        ..lineTo(18.002, 3)
        ..cubicTo(20.211, 3, 22.002, 4.791, 22.002, 7)
        ..lineTo(22.002, 15)
        ..close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ReplyIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.filled != filled;
  }
}
