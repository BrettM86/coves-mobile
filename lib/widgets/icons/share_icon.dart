import 'package:flutter/material.dart';

/// Share icon widget (arrow out of box)
///
/// Arrow-out-of-box icon from Bluesky's design system.
/// Uses the modified version with rounded corners for a friendlier look.
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
      painter: _ShareIconPainter(color: effectiveColor),
    );
  }
}

/// Custom painter for share icon
///
/// SVG path data from Bluesky's ArrowOutOfBoxModified icon component
class _ShareIconPainter extends CustomPainter {
  _ShareIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill; // Always fill - paths are pre-stroked

    // Scale factor to fit 24x24 viewBox into widget size
    final scale = size.width / 24.0;
    canvas.scale(scale);

    // ArrowOutOfBoxModified_Stroke2_Corner2_Rounded path from Bluesky
    // M20 13.75a1 1 0 0 1 1 1V18a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-3.25
    // a1 1 0 1 1 2 0V18 a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-3.25
    // a1 1 0 0 1 1-1ZM12 3a1 1 0 0 1 .707.293 l4.5 4.5
    // a1 1 0 1 1-1.414 1.414L13 6.414v8.836a1 1 0 1 1-2 0V6.414
    // L8.207 9.207a1 1 0 1 1-1.414-1.414l4.5-4.5A1 1 0 0 1 12 3Z

    // Box bottom part
    final path =
        Path()
          ..moveTo(20, 13.75)
          ..cubicTo(20.552, 13.75, 21, 14.198, 21, 14.75)
          ..lineTo(21, 18)
          ..cubicTo(21, 19.657, 19.657, 21, 18, 21)
          ..lineTo(6, 21)
          ..cubicTo(4.343, 21, 3, 19.657, 3, 18)
          ..lineTo(3, 14.75)
          ..cubicTo(3, 14.198, 3.448, 13.75, 4, 13.75)
          ..cubicTo(4.552, 13.75, 5, 14.198, 5, 14.75)
          ..lineTo(5, 18)
          ..cubicTo(5, 18.552, 5.448, 19, 6, 19)
          ..lineTo(18, 19)
          ..cubicTo(18.552, 19, 19, 18.552, 19, 18)
          ..lineTo(19, 14.75)
          ..cubicTo(19, 14.198, 19.448, 13.75, 20, 13.75)
          ..close()
          // Arrow
          ..moveTo(12, 3)
          ..cubicTo(12.265, 3, 12.52, 3.105, 12.707, 3.293)
          ..lineTo(17.207, 7.793)
          ..cubicTo(17.598, 8.184, 17.598, 8.817, 17.207, 9.207)
          ..cubicTo(16.816, 9.598, 16.183, 9.598, 15.793, 9.207)
          ..lineTo(13, 6.414)
          ..lineTo(13, 15.25)
          ..cubicTo(13, 15.802, 12.552, 16.25, 12, 16.25)
          ..cubicTo(11.448, 16.25, 11, 15.802, 11, 15.25)
          ..lineTo(11, 6.414)
          ..lineTo(8.207, 9.207)
          ..cubicTo(7.816, 9.598, 7.183, 9.598, 6.793, 9.207)
          ..cubicTo(6.402, 8.816, 6.402, 8.183, 6.793, 7.793)
          ..lineTo(11.293, 3.293)
          ..cubicTo(11.48, 3.105, 11.735, 3, 12, 3)
          ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShareIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
