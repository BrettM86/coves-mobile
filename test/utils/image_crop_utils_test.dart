import 'dart:io';

import 'package:coves_flutter/models/picked_image.dart';
import 'package:coves_flutter/utils/image_crop_utils.dart';
import 'package:coves_flutter/utils/image_picker_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.pickedPath);

  final String pickedPath;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(pickedPath);
}

class _FakeImageCropper extends ImageCropperPlatform {
  _FakeImageCropper(this.croppedPath);

  final String croppedPath;
  final List<String> sourcePaths = [];

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async {
    sourcePaths.add(sourcePath);
    return CroppedFile(croppedPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pickAndCropImage crops an oversized picked PNG and validates only '
      'the cropped JPEG', () async {
    final directory = Directory.systemTemp.createTempSync('image_crop_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final pickedPath = '${directory.path}/picked.png';
    final croppedPath = '${directory.path}/cropped.jpg';
    File(pickedPath).writeAsBytesSync(List<int>.filled(1500000, 0));
    File(croppedPath).writeAsBytesSync(List<int>.filled(1000, 0));

    final originalPicker = ImagePickerPlatform.instance;
    final originalCropper = ImageCropperPlatform.instance;
    addTearDown(() {
      ImagePickerPlatform.instance = originalPicker;
      ImageCropperPlatform.instance = originalCropper;
    });
    ImagePickerPlatform.instance = _FakeImagePicker(pickedPath);
    final cropper = _FakeImageCropper(croppedPath);
    ImageCropperPlatform.instance = cropper;

    final outcome = await ImageCropUtils.pickAndCropImage(
      // Default constraints are the avatar preset
      source: ImageSource.gallery,
    ).then<Object?>((image) => image, onError: (Object error) => error);

    expect(
      outcome,
      isA<PickedImage>()
          .having((image) => image.mimeType, 'mimeType', 'image/jpeg')
          .having((image) => image.sizeBytes, 'sizeBytes', 1000),
    );
    expect(cropper.sourcePaths, [pickedPath]);
  });

  test('pickAndCropImage rejects a cropped file just above the avatar '
      'size limit', () async {
    final directory = Directory.systemTemp.createTempSync('image_crop_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final pickedPath = '${directory.path}/picked.png';
    final croppedPath = '${directory.path}/cropped.jpg';
    File(pickedPath).writeAsBytesSync(List<int>.filled(1000, 0));
    // Above the 1,000,000-byte avatar limit, below the 2,000,000-byte banner
    // limit, so comparing against the wrong preset also fails this test.
    File(croppedPath).writeAsBytesSync(List<int>.filled(1000500, 0));

    final originalPicker = ImagePickerPlatform.instance;
    final originalCropper = ImageCropperPlatform.instance;
    addTearDown(() {
      ImagePickerPlatform.instance = originalPicker;
      ImageCropperPlatform.instance = originalCropper;
    });
    ImagePickerPlatform.instance = _FakeImagePicker(pickedPath);
    ImageCropperPlatform.instance = _FakeImageCropper(croppedPath);

    await expectLater(
      // Default constraints are the avatar preset
      ImageCropUtils.pickAndCropImage(source: ImageSource.gallery),
      throwsA(isA<ImageValidationException>()),
    );
  });
}
