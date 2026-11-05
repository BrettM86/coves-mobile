import 'dart:io';
import 'dart:typed_data';

import 'package:coves_flutter/utils/image_picker_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../test_helpers/image_fixtures.dart';

/// Image picker platform whose multi-image pick returns [files].
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.files);

  final List<XFile> files;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => files;
}

void main() {
  group('pickPostImages', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('pick_post_images');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('returns the readable files in order and counts the unreadable '
        'ones', () async {
      final first = File('${directory.path}/first.png')
        ..writeAsBytesSync(tinyPng4x3);
      final last = File('${directory.path}/last.jpg')
        ..writeAsBytesSync(tinyJpeg4x3);
      final originalPicker = ImagePickerPlatform.instance;
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);
      ImagePickerPlatform.instance = _FakeImagePicker([
        XFile(first.path),
        XFile('${directory.path}/missing.png'),
        XFile(last.path),
      ]);

      final picked = await ImagePickerUtils.pickPostImages(
        ImageSource.gallery,
        remaining: 8,
      );

      expect(picked.images.map((image) => image.path).toList(), [
        first.path,
        last.path,
      ]);
      expect(picked.images.map((image) => image.mimeType).toList(), [
        'image/png',
        'image/jpeg',
      ]);
      expect(picked.unreadableCount, 1);
    });
  });

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
