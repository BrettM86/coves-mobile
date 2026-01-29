import 'package:flutter/material.dart';

/// Share icon widget (arrow pointing right)
///
/// ArrowShareRight icon from Bluesky's design system.
/// Uses the Stroke2_Corner2_Rounded variant for a consistent look.
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
/// SVG path data from Bluesky's ArrowShareRight_Stroke2_Corner2_Rounded
class _ShareIconPainter extends CustomPainter {
  _ShareIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    // Scale factor to fit 24x24 viewBox into widget size
    final scale = size.width / 24.0;
    canvas.scale(scale);

    // ArrowShareRight_Stroke2_Corner2_Rounded path from Bluesky
    // M11.839 4.744c0-1.488 1.724-2.277 2.846-1.364l.107.094 7.66 7.256.128.134
    // c.558.652.558 1.62 0 2.272l-.128.135-7.66 7.255c-1.115 1.057-2.953.267-2.953-1.27
    // v-2.748c-3.503.055-5.417.41-6.592.97-.997.474-1.525 1.122-2.084 2.14l-.243.46
    // c-.558 1.088-2.09.583-2.08-.515l.015-.748c.111-3.68.777-6.5 2.546-8.415
    // 1.83-1.98 4.63-2.771 8.438-2.884V4.744Zm2 3.256c0 .79-.604 1.41-1.341 1.494
    // l-.149.01c-3.9.057-6.147.813-7.48 2.254-.963 1.043-1.562 2.566-1.842 4.79
    // .38-.327.826-.622 1.361-.877 1.656-.788 4.08-1.14 7.938-1.169l.153.007
    // c.754.071 1.36.704 1.36 1.491v2.675L20.884 12l-7.045-6.676V8Z

    final path =
        Path()
          // Main shape
          ..moveTo(11.839, 4.744)
          ..cubicTo(11.839, 3.256, 13.563, 2.467, 14.685, 3.38)
          ..lineTo(14.792, 3.474)
          ..lineTo(22.452, 10.73)
          ..lineTo(22.58, 10.864)
          ..cubicTo(23.138, 11.516, 23.138, 12.484, 22.58, 13.136)
          ..lineTo(22.452, 13.271)
          ..lineTo(14.792, 20.526)
          ..cubicTo(13.677, 21.583, 11.839, 20.793, 11.839, 19.256)
          ..lineTo(11.839, 16.508)
          ..cubicTo(8.336, 16.563, 6.422, 16.918, 5.247, 17.478)
          ..cubicTo(4.25, 17.952, 3.722, 18.6, 3.163, 19.618)
          ..lineTo(2.92, 20.078)
          ..cubicTo(2.362, 21.166, 0.83, 20.661, 0.84, 19.563)
          ..lineTo(0.855, 18.815)
          ..cubicTo(0.966, 15.135, 1.632, 12.315, 3.401, 10.4)
          ..cubicTo(5.231, 8.42, 8.031, 7.629, 11.839, 7.516)
          ..lineTo(11.839, 4.744)
          ..close()
          // Inner cutout
          ..moveTo(13.839, 8)
          ..cubicTo(13.839, 8.79, 13.235, 9.41, 12.498, 9.494)
          ..lineTo(12.349, 9.504)
          ..cubicTo(8.449, 9.561, 6.202, 10.317, 4.869, 11.758)
          ..cubicTo(3.906, 12.801, 3.307, 14.324, 3.027, 16.548)
          ..cubicTo(3.407, 16.221, 3.853, 15.926, 4.388, 15.671)
          ..cubicTo(6.044, 14.883, 8.468, 14.531, 12.326, 14.502)
          ..lineTo(12.479, 14.509)
          ..cubicTo(13.233, 14.58, 13.839, 15.213, 13.839, 16)
          ..lineTo(13.839, 18.675)
          ..lineTo(20.884, 12)
          ..lineTo(13.839, 5.324)
          ..lineTo(13.839, 8)
          ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShareIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
