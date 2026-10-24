import 'dart:typed_data';

import 'package:coves_flutter/utils/image_picker_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageConstraints presets', () {
    test('avatar and banner byte limits match the backend blob limits '
        '(avatar 1,000,000 bytes, banner 2,000,000 bytes)', () {
      final rows = <(String, ImageConstraints, int, bool)>[
        ('avatar at limit', ImageConstraints.avatar, 1000000, true),
        ('avatar over limit', ImageConstraints.avatar, 1000500, false),
        ('banner at limit', ImageConstraints.banner, 2000000, true),
        ('banner over limit', ImageConstraints.banner, 2000500, false),
      ];

      for (final (name, constraints, size, accepted) in rows) {
        void validate() => ImagePickerUtils.validateImage(
          bytes: Uint8List(size),
          mimeType: 'image/jpeg',
          constraints: constraints,
        );
        if (accepted) {
          expect(validate, returnsNormally, reason: name);
        } else {
          expect(
            validate,
            throwsA(isA<ImageValidationException>()),
            reason: name,
          );
        }
      }
    });

    test('banner preset requests images at least 2048 px tall', () {
      expect(ImageConstraints.banner.maxHeight, greaterThanOrEqualTo(2048));
    });
  });
}
