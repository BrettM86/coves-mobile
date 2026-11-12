import 'dart:ui' show Offset, Size;

import 'package:coves_flutter/utils/bluesky_import_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dragProgress', () {
    test('projects the drag onto the start-to-target vector, 0 at the start '
        'and 1 over the target centre', () {
      const start = Offset(100, 100);
      const target = Offset(100, 500);
      double progress(Offset delta) =>
          dragProgress(start: start, target: target, delta: delta);

      expect(progress(Offset.zero), 0);
      expect(progress(const Offset(0, 400)), 1);
      expect(progress(const Offset(0, 200)), 0.5);
      // Sideways movement does not count.
      expect(progress(const Offset(50, 200)), 0.5);
      // Dragged away from the target.
      expect(progress(const Offset(0, -100)), -0.25);
    });

    test('works horizontally and diagonally', () {
      expect(
        dragProgress(
          start: const Offset(100, 100),
          target: const Offset(500, 100),
          delta: const Offset(300, 0),
        ),
        0.75,
      );
      expect(
        dragProgress(
          start: Offset.zero,
          target: const Offset(300, 400),
          delta: const Offset(150, 200),
        ),
        0.5,
      );
    });
  });

  group('colour blend', () {
    test('blendAmount is smoothstep of the clamped progress', () {
      expect(blendAmount(-0.5), 0);
      expect(blendAmount(0), 0);
      expect(blendAmount(0.25), 0.15625);
      expect(blendAmount(0.5), 0.5);
      expect(blendAmount(0.75), 0.84375);
      expect(blendAmount(1), 1);
      expect(blendAmount(1.5), 1);
    });

    test('blendStep switches at the midpoint', () {
      expect(blendStep(0), 0);
      expect(blendStep(0.25), 0);
      expect(blendStep(0.49), 0);
      expect(blendStep(0.5), 1);
      expect(blendStep(0.75), 1);
      expect(blendStep(1), 1);
    });

    test('surfaceShare is 1 - 0.4p - 0.6 step, jumping at the midpoint', () {
      expect(surfaceShare(0), closeTo(1, 1e-9));
      expect(surfaceShare(0.25), closeTo(0.9, 1e-9));
      expect(surfaceShare(0.49), closeTo(0.804, 1e-9));
      expect(surfaceShare(0.5), closeTo(0.2, 1e-9));
      expect(surfaceShare(0.75), closeTo(0.1, 1e-9));
      expect(surfaceShare(1), closeTo(0, 1e-9));
    });
  });

  group('shouldDrop', () {
    test('drops when released over the target or at half way or more, and '
        'only with a field selected', () {
      expect(
        shouldDrop(releaseOverTarget: true, progress: 0.1, anySelected: true),
        isTrue,
      );
      expect(
        shouldDrop(releaseOverTarget: false, progress: 0.5, anySelected: true),
        isTrue,
      );
      expect(
        shouldDrop(releaseOverTarget: false, progress: 0.49, anySelected: true),
        isFalse,
      );
      expect(
        shouldDrop(releaseOverTarget: false, progress: -1, anySelected: true),
        isFalse,
      );
      expect(
        shouldDrop(releaseOverTarget: true, progress: 1, anySelected: false),
        isFalse,
      );
      expect(
        shouldDrop(releaseOverTarget: false, progress: 0.8, anySelected: false),
        isFalse,
      );
    });
  });

  group('bioPreview', () {
    test('normalises CRLF line endings to LF', () {
      expect(bioPreview('Line one\r\nLine two'), 'Line one\nLine two');
    });

    test('collapses runs of blank lines to a single line break', () {
      expect(bioPreview('First\n\nSecond'), 'First\nSecond');
      expect(bioPreview('First\n\n\n\nSecond'), 'First\nSecond');
      expect(bioPreview('First\r\n\r\n\r\nSecond'), 'First\nSecond');
    });

    test('trims leading and trailing blank lines', () {
      expect(bioPreview('\n\nHello\n\n'), 'Hello');
    });

    test('leaves a single-line bio unchanged', () {
      expect(bioPreview('Hi  there'), 'Hi  there');
    });
  });

  group('seatBurstParticleCount', () {
    test('is 42 at both measured card sizes', () {
      expect(seatBurstParticleCount(const Size(316, 220)), 42);
      expect(seatBurstParticleCount(const Size(471, 328)), 42);
    });

    test('clamps the top and bottom counts to 4..24 each', () {
      // 16 side + 4 corner particles, plus 24 on each long edge.
      expect(seatBurstParticleCount(const Size(1000, 100)), 68);
      // 16 side + 4 corner particles, plus 4 on each short edge.
      expect(seatBurstParticleCount(const Size(100, 1000)), 28);
    });
  });
}
