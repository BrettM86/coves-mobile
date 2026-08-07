// Spec for `formatVideoDuration` in its new home.
//
// The function is currently declared in lib/widgets/post_card.dart and
// imported from there by detailed_post_view.dart — a feed widget is the wrong
// home for a pure formatter that both surfaces use. This file pins the
// behaviour against the new import path; the copy in
// test/widgets/post_card_media_test.dart (group 'formatVideoDuration', B5)
// moves to this import once the function does.
//
// COMPILE-RED until lib/widgets/media/media_format.dart exists.

import 'package:coves_flutter/widgets/media/media_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatVideoDuration', () {
    test('formats sub-minute durations as m:ss', () {
      expect(formatVideoDuration(0), '0:00');
      expect(formatVideoDuration(5), '0:05');
      expect(formatVideoDuration(42), '0:42');
      expect(formatVideoDuration(59), '0:59');
    });

    test('formats minute durations as m:ss zero-padded', () {
      expect(formatVideoDuration(60), '1:00');
      expect(formatVideoDuration(61), '1:01');
      expect(formatVideoDuration(754), '12:34');
      expect(formatVideoDuration(3599), '59:59');
    });

    test('switches to h:mm:ss at one hour', () {
      expect(formatVideoDuration(3600), '1:00:00');
      expect(formatVideoDuration(3723), '1:02:03');
      expect(formatVideoDuration(7325), '2:02:05');
    });

    test('treats negative input as zero rather than throwing', () {
      // The value comes from an untrusted record, so the function is total.
      expect(formatVideoDuration(-1), '0:00');
      expect(formatVideoDuration(-3600), '0:00');
    });
  });
}
