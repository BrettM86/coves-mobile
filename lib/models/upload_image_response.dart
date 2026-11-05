// Response from POST /xrpc/social.coves.media.uploadImage

import 'post.dart';

/// The uploaded blob ref (copied unchanged into `embed.images[]`), the
/// server-detected MIME type, the stored size and the post-orientation
/// aspect ratio.
class UploadImageResponse {
  const UploadImageResponse({
    required this.blob,
    required this.mimeType,
    required this.size,
    this.aspectRatio,
  });

  /// Throws [FormatException] when `blob`, `mimeType` or `size` is missing
  /// or of the wrong type. An `aspectRatio` without two positive integer
  /// dimensions is treated as absent, since it is optional.
  factory UploadImageResponse.fromJson(Map<String, dynamic> json) {
    final blob = json['blob'];
    final mimeType = json['mimeType'];
    final size = json['size'];
    if (blob is! Map<String, dynamic>) {
      throw FormatException('Expected blob map but got ${blob.runtimeType}');
    }
    if (mimeType is! String) {
      throw FormatException(
        'Expected mimeType string but got ${mimeType.runtimeType}',
      );
    }
    if (size is! int) {
      throw FormatException('Expected size int but got ${size.runtimeType}');
    }
    return UploadImageResponse(
      blob: blob,
      mimeType: mimeType,
      size: size,
      aspectRatio: _parseAspectRatio(json['aspectRatio']),
    );
  }

  static EmbedAspectRatio? _parseAspectRatio(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final width = value['width'];
    final height = value['height'];
    if (width is! int || height is! int || width < 1 || height < 1) {
      return null;
    }
    return EmbedAspectRatio(width: width, height: height);
  }

  final Map<String, dynamic> blob;
  final String mimeType;
  final int size;
  final EmbedAspectRatio? aspectRatio;
}
