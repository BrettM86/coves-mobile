import 'package:coves_flutter/utils/alt_text_limits.dart';
import 'package:flutter_test/flutter_test.dart';

/// One family emoji: four emoji joined by three zero-width joiners, one
/// grapheme cluster of 25 UTF-8 bytes.
const _family = '👨‍👩‍👧‍👦';

void main() {
  group('AltTextMeasure.of', () {
    // remaining and showCounter are null where the row does not assert them.
    final rows =
        <
          ({
            String name,
            String text,
            int graphemes,
            int bytes,
            AltTextLimit? exceeded,
            bool isValid,
            int? remaining,
            bool? showCounter,
          })
        >[
          (
            name: 'empty',
            text: '',
            graphemes: 0,
            bytes: 0,
            exceeded: null,
            isValid: true,
            remaining: 1000,
            showCounter: false,
          ),
          (
            name: '899 x "a": counter hidden',
            text: 'a' * 899,
            graphemes: 899,
            bytes: 899,
            exceeded: null,
            isValid: true,
            remaining: 101,
            showCounter: false,
          ),
          (
            name: '900 x "a": counter shown at 100 remaining',
            text: 'a' * 900,
            graphemes: 900,
            bytes: 900,
            exceeded: null,
            isValid: true,
            remaining: 100,
            showCounter: true,
          ),
          (
            name: '1000 x "a": at the grapheme limit',
            text: 'a' * 1000,
            graphemes: 1000,
            bytes: 1000,
            exceeded: null,
            isValid: true,
            remaining: 0,
            showCounter: true,
          ),
          (
            name: '1001 x "a": over the grapheme limit',
            text: 'a' * 1001,
            graphemes: 1001,
            bytes: 1001,
            exceeded: AltTextLimit.graphemes,
            isValid: false,
            remaining: null,
            showCounter: null,
          ),
          (
            name: '380 family emoji (9,500 bytes): counter hidden',
            text: _family * 380,
            graphemes: 380,
            bytes: 9500,
            exceeded: null,
            isValid: true,
            remaining: 500,
            showCounter: false,
          ),
          (
            name:
                '396 family emoji (9,900 bytes): counter shown at 100 '
                'remaining',
            text: _family * 396,
            graphemes: 396,
            bytes: 9900,
            exceeded: null,
            isValid: true,
            remaining: 100,
            showCounter: true,
          ),
          (
            name: '400 family emoji (10,000 bytes): at the byte limit',
            text: _family * 400,
            graphemes: 400,
            bytes: 10000,
            exceeded: null,
            isValid: true,
            remaining: 0,
            showCounter: true,
          ),
          (
            name: '1000 family emoji (25,000 bytes): over the byte limit only',
            text: _family * 1000,
            graphemes: 1000,
            bytes: 25000,
            exceeded: AltTextLimit.bytes,
            isValid: false,
            remaining: null,
            showCounter: null,
          ),
          (
            name: '1001 family emoji: over both, graphemes reported first',
            text: _family * 1001,
            graphemes: 1001,
            bytes: 25025,
            exceeded: AltTextLimit.graphemes,
            isValid: false,
            remaining: null,
            showCounter: null,
          ),
        ];

    for (final row in rows) {
      test(row.name, () {
        final measure = AltTextMeasure.of(row.text);

        expect(
          (
            graphemes: measure.graphemes,
            bytes: measure.bytes,
            exceeded: measure.exceeded,
            isValid: measure.isValid,
          ),
          (
            graphemes: row.graphemes,
            bytes: row.bytes,
            exceeded: row.exceeded,
            isValid: row.isValid,
          ),
        );
        if (row.remaining case final remaining?) {
          expect(measure.remaining, remaining);
        }
        if (row.showCounter case final showCounter?) {
          expect(measure.showCounter, showCounter);
        }
      });
    }
  });
}
