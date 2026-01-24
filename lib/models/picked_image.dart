import 'dart:io';
import 'dart:typed_data';

/// Represents a picked and validated image ready for upload.
///
/// Contains the file, raw bytes, and detected MIME type
/// for convenient access during upload operations.
class PickedImage {
  const PickedImage({
    required this.file,
    required this.bytes,
    required this.mimeType,
  });

  /// The picked image file
  final File file;

  /// Image bytes ready for upload (base64 encoding, etc.)
  final Uint8List bytes;

  /// Detected MIME type (jpeg, png, webp, gif, or heic)
  final String mimeType;

  /// File path for display or debugging
  String get path => file.path;

  /// File size in bytes
  int get sizeBytes => bytes.length;
}
