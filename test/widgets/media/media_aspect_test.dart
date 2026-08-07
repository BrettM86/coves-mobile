// Spec for the shared media aspect-ratio clamp.
//
// The feed card and the detail view clamp a record's declared aspect ratio to
// DIFFERENT bounds, on purpose: the feed keeps a scannable card shape, the
// detail view preserves nearly the true proportions and clamps only as a
// safety rail (the backend never validates `aspectRatio`, so a hostile record
// can declare 1:1000000). One function, two bound sets.
//
// Target API — lib/widgets/media/media_aspect.dart:
//
//   typedef MediaRatioBounds = ({double min, double max});
//   const MediaRatioBounds kFeedRatioBounds = (min: 3 / 4, max: 16 / 9);
//   const MediaRatioBounds kDetailRatioBounds = (min: 1 / 3, max: 3);
//   double clampMediaRatio(
//     EmbedAspectRatio? ratio, {
//     required double min,
//     required double max,
//     double fallback = 16 / 9,
//   });
//
// All ratios are width/height.
//
// COMPILE-RED until lib/widgets/media/media_aspect.dart exists.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/media/media_aspect.dart';
import 'package:flutter_test/flutter_test.dart';

/// Calls the clamp with the feed's bounds, the way post_card.dart will.
double feedRatio(EmbedAspectRatio? ratio) => clampMediaRatio(
  ratio,
  min: kFeedRatioBounds.min,
  max: kFeedRatioBounds.max,
);

/// Calls the clamp with the detail view's bounds.
double detailRatio(EmbedAspectRatio? ratio) => clampMediaRatio(
  ratio,
  min: kDetailRatioBounds.min,
  max: kDetailRatioBounds.max,
);

void main() {
  group('bound constants', () {
    test('the feed clamps to 3:4 .. 16:9', () {
      expect(kFeedRatioBounds.min, 3 / 4);
      expect(kFeedRatioBounds.max, 16 / 9);
    });

    test('the detail view clamps to 1:3 .. 3:1', () {
      expect(kDetailRatioBounds.min, 1 / 3);
      expect(kDetailRatioBounds.max, 3);
    });
  });

  group('clampMediaRatio with no declared ratio', () {
    test('falls back to 16:9 by default', () {
      expect(feedRatio(null), 16 / 9);
      expect(detailRatio(null), 16 / 9);
    });

    test('honours an explicit fallback', () {
      expect(clampMediaRatio(null, min: 1 / 3, max: 3, fallback: 1), 1.0);
    });

    test('does not clamp the fallback into the bounds', () {
      // The fallback is a deliberate display choice, not record data; it is
      // returned as given so a caller can pick a shape outside its own rails.
      expect(clampMediaRatio(null, min: 1, max: 1.2, fallback: 16 / 9), 16 / 9);
    });
  });

  group('clampMediaRatio with feed bounds', () {
    test('passes an in-range ratio through untouched', () {
      expect(feedRatio(EmbedAspectRatio(width: 4, height: 3)), 4 / 3);
      expect(feedRatio(EmbedAspectRatio(width: 1, height: 1)), 1.0);
    });

    test('keeps the exact bound values', () {
      expect(feedRatio(EmbedAspectRatio(width: 16, height: 9)), 16 / 9);
      expect(feedRatio(EmbedAspectRatio(width: 3, height: 4)), 3 / 4);
    });

    test('clamps a panorama down to 16:9', () {
      expect(feedRatio(EmbedAspectRatio(width: 21, height: 9)), 16 / 9);
      expect(feedRatio(EmbedAspectRatio(width: 4000, height: 1)), 16 / 9);
    });

    test('clamps a tall portrait up to 3:4', () {
      // A 9:16 story screenshot gets center-cropped rather than swallowing
      // the viewport.
      expect(feedRatio(EmbedAspectRatio(width: 9, height: 16)), 3 / 4);
      expect(feedRatio(EmbedAspectRatio(width: 1, height: 1000000)), 3 / 4);
    });
  });

  group('clampMediaRatio with detail bounds', () {
    test('lets a 9:16 portrait through uncropped', () {
      expect(detailRatio(EmbedAspectRatio(width: 9, height: 16)), 9 / 16);
    });

    test('lets a 3:1 panorama through uncropped', () {
      expect(detailRatio(EmbedAspectRatio(width: 3, height: 1)), 3.0);
    });

    test('clamps a hostile ratio to the safety rails', () {
      expect(detailRatio(EmbedAspectRatio(width: 1, height: 1000000)), 1 / 3);
      expect(detailRatio(EmbedAspectRatio(width: 1000000, height: 1)), 3.0);
    });

    test('always returns a finite, positive ratio', () {
      final extremes = <EmbedAspectRatio>[
        EmbedAspectRatio(width: 1, height: 1000000),
        EmbedAspectRatio(width: 1000000, height: 1),
        EmbedAspectRatio(width: 1, height: 1),
      ];
      for (final ratio in extremes) {
        final value = detailRatio(ratio);
        expect(value.isFinite, isTrue, reason: 'AspectRatio would assert');
        expect(value, greaterThan(0));
      }
    });
  });
}
