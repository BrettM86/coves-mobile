import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lucide_icon_painter.dart';
import 'lucide_paths.dart';

/// Outlined downvote with the frontend's short thumb-tap feedback.
class DownvoteIcon extends StatefulWidget {
  const DownvoteIcon({
    this.size = 18,
    this.color,
    this.isDownvoted = false,
    super.key,
  });

  final double size;
  final Color? color;
  final bool isDownvoted;

  @override
  State<DownvoteIcon> createState() => _DownvoteIconState();
}

class _DownvoteIconState extends State<DownvoteIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );

  @override
  void didUpdateWidget(DownvoteIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDownvoted &&
        !oldWidget.isDownvoted &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else if (!widget.isDownvoted) {
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // CSS ease-out applies separately between the frontend's keyframes.
  double _keyframe(double first, double second, double third) {
    final progress = _controller.value;
    const easeOut = Cubic(0, 0, 0.58, 1);
    if (progress < 0.4) {
      return first * easeOut.transform(progress / 0.4);
    }
    if (progress < 0.72) {
      return first +
          (second - first) * easeOut.transform((progress - 0.4) / 0.32);
    }
    return second +
        (third - second) * easeOut.transform((progress - 0.72) / 0.28);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.color ?? IconTheme.of(context).color ?? Colors.grey;
    return AnimatedBuilder(
      animation: _controller,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: LucideIconPainter(
          paths: LucidePaths.thumbsDown,
          color: effectiveColor,
          strokeWidth: widget.isDownvoted ? 2.5 : 2,
        ),
      ),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _keyframe(3, -1, 0)),
        child: Transform.rotate(
          angle: _keyframe(-8, 3, 0) * math.pi / 180,
          alignment: const Alignment(0.2, -0.3),
          child: child,
        ),
      ),
    );
  }
}
