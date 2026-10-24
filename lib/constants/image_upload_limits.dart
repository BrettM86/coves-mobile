/// Image upload size limits enforced by the Coves backend.
///
/// Mirrors the AppView's blob limits (decimal megabytes).
abstract final class ImageUploadLimits {
  /// Maximum size of a user or community avatar (1 MB).
  static const avatarMaxSizeBytes = 1000000;

  /// Maximum size of a banner (2 MB).
  static const bannerMaxSizeBytes = 2000000;

  /// Formats [bytes] as decimal megabytes, e.g. 1500000 -> "1.50 MB".
  static String formatMegabytes(int bytes, {int fractionDigits = 2}) =>
      '${(bytes / 1000000).toStringAsFixed(fractionDigits)} MB';
}
