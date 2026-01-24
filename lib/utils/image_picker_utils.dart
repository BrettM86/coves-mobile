import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/picked_image.dart';

/// Configuration for image picking constraints
class ImageConstraints {
  const ImageConstraints({
    this.maxWidth = 1024,
    this.maxHeight = 1024,
    this.imageQuality = 85,
    this.maxSizeBytes = 1024 * 1024, // 1 MB
    this.allowedMimeTypes = const {'image/jpeg', 'image/png', 'image/webp'},
  })  : assert(maxWidth > 0, 'maxWidth must be positive'),
        assert(maxHeight > 0, 'maxHeight must be positive'),
        assert(
          imageQuality >= 0 && imageQuality <= 100,
          'imageQuality must be 0-100',
        ),
        assert(maxSizeBytes > 0, 'maxSizeBytes must be positive');

  /// Maximum width in pixels (image will be resized if larger)
  final double maxWidth;

  /// Maximum height in pixels (image will be resized if larger)
  final double maxHeight;

  /// JPEG compression quality (0-100)
  final int imageQuality;

  /// Maximum file size in bytes after picking
  final int maxSizeBytes;

  /// Set of allowed MIME types
  final Set<String> allowedMimeTypes;

  /// Preset for avatar images (profile pics, community avatars)
  static const avatar = ImageConstraints();

  /// Preset for larger images (banners, post images)
  static const banner = ImageConstraints(
    maxWidth: 2048,
    maxSizeBytes: 2 * 1024 * 1024, // 2 MB
  );
}

/// Thrown when image validation fails
class ImageValidationException implements Exception {
  const ImageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Image picker utility functions
///
/// Provides reusable image picking, validation, and MIME type detection.
/// All methods are static and stateless for easy testing.
class ImagePickerUtils {
  // Private constructor to prevent instantiation
  ImagePickerUtils._();

  static final ImagePicker _picker = ImagePicker();

  /// Pick an image from the specified source with optional constraints.
  ///
  /// Returns [PickedImage] with file, bytes, and MIME type,
  /// or null if cancelled.
  /// Throws [ImageValidationException] if image fails validation.
  ///
  /// [source] - ImageSource.gallery or ImageSource.camera
  /// [constraints] - Optional constraints (defaults to avatar preset)
  static Future<PickedImage?> pickImage(
    ImageSource source, {
    ImageConstraints constraints = ImageConstraints.avatar,
  }) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
      imageQuality: constraints.imageQuality,
    );

    if (pickedFile == null) {
      return null;
    }

    final file = File(pickedFile.path);
    final bytes = await file.readAsBytes();
    final mimeType = inferMimeTypeFromExtension(pickedFile.path);

    validateImage(
      bytes: bytes,
      mimeType: mimeType,
      constraints: constraints,
    );

    return PickedImage(
      file: file,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  /// Infer MIME type from file path extension.
  ///
  /// Returns the MIME type string based on file extension.
  /// Logs a warning and defaults to 'image/jpeg' for unknown extensions.
  static String inferMimeTypeFromExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        developer.log(
          'Unknown image extension ".$extension", defaulting to image/jpeg',
          name: 'ImagePickerUtils',
          level: 900, // Warning level
        );
        return 'image/jpeg';
    }
  }

  /// Validate image bytes and MIME type against constraints.
  ///
  /// Throws [ImageValidationException] if validation fails.
  static void validateImage({
    required Uint8List bytes,
    required String mimeType,
    required ImageConstraints constraints,
  }) {
    // Check file size
    if (bytes.length > constraints.maxSizeBytes) {
      final maxSizeMB = constraints.maxSizeBytes / (1024 * 1024);
      throw ImageValidationException(
        'Image size exceeds maximum of ${maxSizeMB.toStringAsFixed(0)} MB. '
        'Please choose a smaller image.',
      );
    }

    // Check MIME type
    if (!constraints.allowedMimeTypes.contains(mimeType)) {
      final allowed = constraints.allowedMimeTypes
          .map((t) => t.split('/').last.toUpperCase())
          .join(', ');
      throw ImageValidationException(
        'Unsupported image type. Please use $allowed.',
      );
    }
  }
}
