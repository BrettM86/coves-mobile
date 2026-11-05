// An image attached to a post in the composer, before and after upload.

import 'dart:io';
import 'dart:typed_data';

import 'post.dart';

/// Where an attachment is in its upload.
enum ImageAttachmentStatus { pending, uploading, uploaded, failed }

/// One composer image: the picked file and bytes, the MIME type sniffed from
/// the bytes, and once uploaded the blob ref and aspect ratio the upload
/// returned.
class ImageAttachment {
  ImageAttachment({
    required this.id,
    required this.file,
    required this.bytes,
    required this.mimeType,
    this.blob,
    this.aspectRatio,
    this.status = ImageAttachmentStatus.pending,
    this.progress = 0,
    this.error,
    this.errorCode,
    this.alt = '',
    this.ownsFile = false,
  });

  /// Stable for the attachment's life in the strip.
  final String id;
  final File file;
  final Uint8List bytes;
  final String mimeType;

  /// Whether the app created [file] and must delete it when done.
  final bool ownsFile;
  Map<String, dynamic>? blob;
  EmbedAspectRatio? aspectRatio;
  ImageAttachmentStatus status;

  /// Upload progress from 0 to 1.
  double progress;

  /// The user-facing message of the last failed upload.
  String? error;

  /// The server's error code for the last failed upload, when it sent one.
  String? errorCode;

  /// The alt text as the user typed it; empty when none.
  String alt;

  /// [alt] trimmed, or null when it is blank.
  String? get trimmedAlt {
    final trimmed = alt.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
