import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../models/picked_image.dart';
import 'image_picker_utils.dart';

/// Configuration for image cropping behavior.
class CropConfig {
  const CropConfig({
    this.title = 'Crop Image',
    this.cropStyle = CropStyle.circle,
    this.aspectRatio = const CropAspectRatio(ratioX: 1, ratioY: 1),
    this.lockAspectRatio = true,
    this.compressQuality = 90,
  }) : assert(
          compressQuality >= 0 && compressQuality <= 100,
          'compressQuality must be between 0 and 100',
        );

  /// Title shown in the cropper UI
  final String title;

  /// Crop style (circle for avatars, rectangle for banners)
  final CropStyle cropStyle;

  /// Aspect ratio for the crop area
  final CropAspectRatio aspectRatio;

  /// Whether to lock the aspect ratio
  final bool lockAspectRatio;

  /// JPEG compression quality (0-100)
  final int compressQuality;

  /// Creates a copy with the given fields replaced.
  CropConfig copyWith({
    String? title,
    CropStyle? cropStyle,
    CropAspectRatio? aspectRatio,
    bool? lockAspectRatio,
    int? compressQuality,
  }) {
    return CropConfig(
      title: title ?? this.title,
      cropStyle: cropStyle ?? this.cropStyle,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      lockAspectRatio: lockAspectRatio ?? this.lockAspectRatio,
      compressQuality: compressQuality ?? this.compressQuality,
    );
  }

  /// Default configuration for circular avatar cropping
  static const avatar = CropConfig();

  /// Configuration for rectangular banner images
  static const banner = CropConfig(
    title: 'Crop Banner',
    cropStyle: CropStyle.rectangle,
    aspectRatio: CropAspectRatio(ratioX: 3, ratioY: 1),
  );
}

/// Utility for cropping images using native platform croppers.
///
/// Uses [image_cropper] which provides native UI on both iOS (TOCropViewController)
/// and Android (uCrop) for a polished, platform-consistent experience.
abstract final class ImageCropUtils {
  /// Crops an image file using the native platform cropper.
  ///
  /// Returns a [CroppedFile] containing the cropped image, or null if cancelled.
  ///
  /// [sourcePath] - Path to the source image file
  /// [config] - Optional crop configuration (defaults to avatar)
  ///
  /// Throws [PlatformException] if the native cropper fails.
  static Future<CroppedFile?> cropImage({
    required String sourcePath,
    CropConfig config = CropConfig.avatar,
  }) async {
    try {
      return await ImageCropper().cropImage(
        sourcePath: sourcePath,
        aspectRatio: config.aspectRatio,
        compressQuality: config.compressQuality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: config.title,
            toolbarColor: AppColors.background,
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            navBarLight: false,
            backgroundColor: AppColors.background,
            activeControlsWidgetColor: AppColors.primary,
            cropFrameColor: AppColors.primary,
            cropGridColor: Colors.white.withValues(alpha: 0.3),
            dimmedLayerColor: AppColors.background.withValues(alpha: 0.7),
            cropStyle: config.cropStyle,
            lockAspectRatio: config.lockAspectRatio,
            hideBottomControls: true,
            showCropGrid: true,
            cropGridRowCount: 2,
            cropGridColumnCount: 2,
          ),
          IOSUiSettings(
            title: config.title,
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: config.lockAspectRatio,
            resetAspectRatioEnabled: !config.lockAspectRatio,
            aspectRatioPickerButtonHidden: config.lockAspectRatio,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
      );
    } on PlatformException catch (e, stackTrace) {
      developer.log(
        'Native image cropper failed',
        name: 'ImageCropUtils',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Picks an image and opens the native cropper.
  ///
  /// Combines [ImagePickerUtils.pickImage] with [cropImage] for a
  /// complete pick-and-crop flow using native platform UI.
  ///
  /// Returns [PickedImage] with cropped image data, or null if cancelled
  /// at any step (image picking or cropping).
  ///
  /// Throws [ImageValidationException] if the picked image fails validation.
  ///
  /// Example:
  /// ```dart
  /// final source = await ImageSourcePicker.show(context);
  /// if (source != null) {
  ///   final result = await ImageCropUtils.pickAndCropImage(
  ///     source: source,
  ///   );
  ///   if (result != null) {
  ///     // Upload result.bytes
  ///   }
  /// }
  /// ```
  static Future<PickedImage?> pickAndCropImage({
    required ImageSource source,
    ImageConstraints constraints = ImageConstraints.avatar,
    CropConfig cropConfig = CropConfig.avatar,
  }) async {
    final picked = await ImagePickerUtils.pickImage(
      source,
      constraints: constraints,
    );

    if (picked == null) {
      developer.log(
        'Image picking cancelled or failed',
        name: 'ImageCropUtils',
      );
      return null;
    }

    final croppedFile = await cropImage(
      sourcePath: picked.file.path,
      config: cropConfig,
    );

    if (croppedFile == null) {
      developer.log(
        'Image cropping cancelled by user',
        name: 'ImageCropUtils',
      );
      return null;
    }

    final croppedFileObj = File(croppedFile.path);

    final Uint8List croppedBytes;
    try {
      croppedBytes = await croppedFileObj.readAsBytes();
    } on FileSystemException catch (e, stackTrace) {
      developer.log(
        'Failed to read cropped file',
        name: 'ImageCropUtils',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    // Validate cropped file size against constraints
    if (croppedBytes.length > constraints.maxSizeBytes) {
      throw ImageValidationException(
        'Cropped image is too large '
        '(${(croppedBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Maximum size is ${(constraints.maxSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB.',
      );
    }

    final mimeType = ImagePickerUtils.inferMimeTypeFromExtension(
      croppedFile.path,
    );

    return PickedImage(
      file: croppedFileObj,
      bytes: croppedBytes,
      mimeType: mimeType,
    );
  }
}
