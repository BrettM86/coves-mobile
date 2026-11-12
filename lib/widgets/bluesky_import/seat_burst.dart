import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/bluesky_import_motion.dart';

/// How long the burst overlay stays up.
const seatBurstDuration = Duration(milliseconds: 1300);

const _particleEase = Cubic(0.2, 0.7, 0.3, 1);

/// Outline confetti bursting from all four edges of [cardRect], in the
/// local coordinates of the overlay the burst fills. Decorative: it ignores
/// pointers and is hidden from assistive tech. Calls [onDone] once
/// [seatBurstDuration] has passed.
class SeatBurst extends StatefulWidget {
  const SeatBurst({required this.cardRect, required this.onDone, super.key});

  final Rect cardRect;
  final VoidCallback onDone;

  @override
  State<SeatBurst> createState() => _SeatBurstState();
}

class _SeatBurstState extends State<SeatBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: seatBurstDuration,
  );
  late final List<_Particle> _particles = _scatter(
    widget.cardRect,
    math.Random(),
  );

  @override
  void initState() {
    super.initState();
    _clock.forward().whenCompleteOrCancel(() {
      if (mounted && _clock.isCompleted) {
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BurstPainter(
            particles: _particles,
            clock: _clock,
            totalMilliseconds: seatBurstDuration.inMilliseconds,
          ),
        ),
      ),
    );
  }
}

enum _Kind { capsule, dash, diamond }

class _Particle {
  _Particle({
    required this.kind,
    required this.start,
    required this.end,
    required this.delay,
    required this.duration,
    required this.startAngle,
    required this.turn,
  });

  final _Kind kind;
  final Offset start;
  final Offset end;

  /// Milliseconds.
  final double delay;
  final double duration;

  /// Radians.
  final double startAngle;
  final double turn;
}

double _between(math.Random random, double low, double high) =>
    low + random.nextDouble() * (high - low);

double _radians(double degrees) => degrees * math.pi / 180;

List<_Particle> _scatter(Rect card, math.Random random) {
  final particles = <_Particle>[];

  void add(Offset start, Offset travel) {
    final index = particles.length;
    final kind = _Kind.values[index % 3];
    final double startAngle;
    final double turn;
    if (kind == _Kind.diamond) {
      startAngle = _radians(45);
      turn = _radians(_between(random, 90, 150));
    } else {
      startAngle = _radians(_between(random, -20, 20));
      turn = _radians(_between(random, -15, 15));
    }
    particles.add(
      _Particle(
        kind: kind,
        start: start,
        end: start + travel,
        delay: (index % 10) * 10 + _between(random, 0, 30),
        duration: _between(random, 650, 850),
        startAngle: startAngle,
        turn: turn,
      ),
    );
  }

  double along(int i, int count) =>
      0.2 + 0.6 * (i + 0.5 + _between(random, -0.3, 0.3)) / count;
  double fan(double position) =>
      (position - 0.5) * 120 + _between(random, -10, 10);

  const sideCount = 8;
  for (final direction in const [-1.0, 1.0]) {
    final x = direction < 0 ? card.left : card.right;
    for (var i = 0; i < sideCount; i++) {
      final position = along(i, sideCount);
      add(
        Offset(x, card.top + position * card.height),
        Offset(direction * _between(random, 36, 80), fan(position)),
      );
    }
  }
  for (final corner in [
    card.topLeft,
    card.topRight,
    card.bottomLeft,
    card.bottomRight,
  ]) {
    final dx = corner.dx == card.left ? -1.0 : 1.0;
    final dy = corner.dy == card.top ? -1.0 : 1.0;
    add(
      corner,
      Offset(dx * _between(random, 40, 70), dy * _between(random, 40, 70)),
    );
  }
  final edgeCount = seatBurstEdgeCount(card.size);
  for (final direction in const [-1.0, 1.0]) {
    final y = direction < 0 ? card.top : card.bottom;
    for (var i = 0; i < edgeCount; i++) {
      final position = along(i, edgeCount);
      add(
        Offset(card.left + position * card.width, y),
        Offset(fan(position), direction * _between(random, 36, 80)),
      );
    }
  }
  return particles;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.particles,
    required this.clock,
    required this.totalMilliseconds,
  }) : super(repaint: clock);

  final List<_Particle> particles;
  final Animation<double> clock;
  final int totalMilliseconds;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = clock.value * totalMilliseconds;
    for (final particle in particles) {
      final t = (elapsed - particle.delay) / particle.duration;
      if (t <= 0 || t >= 1) {
        continue;
      }
      _paintParticle(canvas, particle, t);
    }
  }

  /// Keyframes: at 30% the particle is 70% of the way at full scale, it
  /// holds full opacity to 65%, and ends at the end point at 0.75 scale,
  /// transparent. Each segment is eased.
  void _paintParticle(Canvas canvas, _Particle particle, double t) {
    final double travel;
    final double scale;
    if (t < 0.3) {
      final segment = _particleEase.transform(t / 0.3);
      travel = 0.7 * segment;
      scale = 0.8 + 0.2 * segment;
    } else {
      final segment = _particleEase.transform((t - 0.3) / 0.7);
      travel = 0.7 + 0.3 * segment;
      scale = 1 - 0.25 * segment;
    }
    final opacity = t < 0.65
        ? 1.0
        : 1 - _particleEase.transform((t - 0.65) / 0.35);
    final morph = _particleEase.transform(t);
    final centre = Offset.lerp(particle.start, particle.end, travel)!;

    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(particle.startAngle + particle.turn * morph)
      ..scale(scale);

    switch (particle.kind) {
      case _Kind.capsule:
        final width = 8 + (9 - 8) * morph;
        final height = 20 + (9 - 20) * morph;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: width, height: height),
            Radius.circular(width / 2),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.seatBurstRose.withValues(alpha: opacity),
        );
      case _Kind.dash:
        const width = 3.0;
        final height = 20 + (5 - 20) * morph;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: width, height: height),
            const Radius.circular(width / 2),
          ),
          Paint()..color = AppColors.seatBurstTeal.withValues(alpha: opacity),
        );
      case _Kind.diamond:
        final side = 11 + (8 - 11) * morph;
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: side, height: side),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.seatBurstAmber.withValues(alpha: opacity),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.particles != particles;
}
