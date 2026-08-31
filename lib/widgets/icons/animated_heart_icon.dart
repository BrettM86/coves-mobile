import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'lucide_icon_painter.dart';
import 'lucide_paths.dart';

/// Animated heart icon (Lucide `heart`) with outline and filled states
///
/// Features a dramatic animation sequence:
/// 1. Heart shrinks to nothing
/// 2. Red hollow circle expands outwards
/// 3. Small heart grows from center
/// 4. Heart pops to 1.3x with 7 particle dots
/// 5. Heart settles back to 1x filled
class AnimatedHeartIcon extends StatefulWidget {
  const AnimatedHeartIcon({
    required this.isLiked,
    this.size = 18,
    this.color,
    this.likedColor,
    super.key,
  });

  final bool isLiked;
  final double size;
  final Color? color;
  final Color? likedColor;

  @override
  State<AnimatedHeartIcon> createState() => _AnimatedHeartIconState();
}

class _AnimatedHeartIconState extends State<AnimatedHeartIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Heart scale animations
  late Animation<double> _heartShrinkAnimation;
  late Animation<double> _heartGrowAnimation;
  late Animation<double> _heartPopAnimation;

  // Hollow circle animation
  late Animation<double> _circleScaleAnimation;
  late Animation<double> _circleOpacityAnimation;

  // Particle burst animations
  late Animation<double> _particleScaleAnimation;
  late Animation<double> _particleOpacityAnimation;

  bool _hasBeenToggled = false;
  bool _previousIsLiked = false;

  @override
  void initState() {
    super.initState();
    _previousIsLiked = widget.isLiked;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Phase 1 (0-15%): Heart shrinks to nothing
    _heartShrinkAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.15, curve: Curves.easeIn),
      ),
    );

    // Phase 2 (15-40%): Hollow circle expands
    _circleScaleAnimation = Tween<double>(begin: 0, end: 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.4, curve: Curves.easeOut),
      ),
    );

    _circleOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.8), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 0), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.4)),
    );

    // Phase 3 (25-55%): Heart grows from small in center
    _heartGrowAnimation = Tween<double>(begin: 0.2, end: 1.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.55, curve: Curves.easeOut),
      ),
    );

    // Phase 4 (55-65%): Particle burst at peak
    _particleScaleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.65, curve: Curves.easeOut),
      ),
    );

    _particleOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 70),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.55, 0.75)),
    );

    // Phase 5 (65-100%): Heart settles to 1x
    _heartPopAnimation = Tween<double>(begin: 1.3, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 1, curve: Curves.elasticOut),
      ),
    );
  }

  @override
  void didUpdateWidget(AnimatedHeartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLiked != _previousIsLiked) {
      _hasBeenToggled = true;
      _previousIsLiked = widget.isLiked;

      if (widget.isLiked && mounted) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getHeartScale() {
    if (!widget.isLiked || !_hasBeenToggled) {
      return 1;
    }

    final progress = _controller.value;
    if (progress < 0.15) {
      // Phase 1: Shrinking
      return _heartShrinkAnimation.value;
    } else if (progress < 0.55) {
      // Phase 3: Growing from center
      return _heartGrowAnimation.value;
    } else {
      // Phase 5: Settling back
      return _heartPopAnimation.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.color ?? Theme.of(context).iconTheme.color ?? Colors.grey;
    // The palette's vote-liked red, not Material's `Colors.red` (0xFFF44336)
    // - a third red that matches neither this nor AppColors.error.
    final effectiveLikedColor = widget.likedColor ?? AppColors.voteLiked;

    // Use 2.5x size for animation overflow space (for 1.3x scale + particles)
    final containerSize = widget.size * 2.5;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: OverflowBox(
        maxWidth: containerSize,
        maxHeight: containerSize,
        child: SizedBox(
          width: containerSize,
          height: containerSize,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Phase 2: Expanding hollow circle
                  if (widget.isLiked &&
                      _hasBeenToggled &&
                      _controller.value >= 0.15 &&
                      _controller.value <= 0.4) ...[
                    Opacity(
                      opacity: _circleOpacityAnimation.value,
                      child: Transform.scale(
                        scale: _circleScaleAnimation.value,
                        child: Container(
                          width: widget.size,
                          height: widget.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: effectiveLikedColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Phase 4: Particle burst (7 dots)
                  if (widget.isLiked &&
                      _hasBeenToggled &&
                      _controller.value >= 0.55 &&
                      _controller.value <= 0.75)
                    ..._buildParticleBurst(effectiveLikedColor),

                  // Heart icon (all phases)
                  Transform.scale(
                    scale: _getHeartScale(),
                    child: CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: LucideIconPainter(
                        paths: LucidePaths.heart,
                        color:
                            widget.isLiked
                                ? effectiveLikedColor
                                : effectiveColor,
                        filled: widget.isLiked,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParticleBurst(Color color) {
    const particleCount = 7;
    final particles = <Widget>[];
    final containerSize = widget.size * 2.5;

    for (var i = 0; i < particleCount; i++) {
      final angle = (2 * math.pi * i) / particleCount;
      final distance = widget.size * 1 * _particleScaleAnimation.value;
      final dx = math.cos(angle) * distance;
      final dy = math.sin(angle) * distance;

      particles.add(
        Positioned(
          left: containerSize / 2 + dx - 2,
          top: containerSize / 2 + dy - 2,
          child: Opacity(
            opacity: _particleOpacityAnimation.value,
            child: Container(
              width: 2,
              height: 2,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      );
    }

    return particles;
  }
}
