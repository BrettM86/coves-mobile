// Image format detection and post-image checks from the file's bytes.

import 'dart:convert';
import 'dart:typed_data';

import '../constants/image_upload_limits.dart';
import 'image_picker_utils.dart';

/// An image format recognised from its first bytes.
enum ImageFormat {
  jpeg('image/jpeg'),
  png('image/png'),
  webp('image/webp'),
  gif('image/gif'),
  heic('image/heic'),
  heif('image/heif'),
  avif('image/avif');

  const ImageFormat(this.mimeType);

  final String mimeType;
}

/// The MIME type and pixel dimensions read from a post image's header.
typedef PostImageCheck = ({String mimeType, int width, int height});

/// Shown for any format a post image cannot be uploaded as.
const unsupportedPostImageFormatMessage = 'Use a JPEG, PNG, WebP or GIF image.';

/// Shown for a post image over
/// [ImageUploadLimits.postImageMaxSizeBytes].
const postImageTooLargeMessage =
    'This image is larger than 10 MB. Choose a smaller image.';

/// Shown for an image over [ImageUploadLimits.postImageMaxPixels], over the
/// image preparer's decode ceiling, or refused by the server for its
/// dimensions. The text names no number because those limits differ.
const postImageTooManyPixelsMessage =
    'This image is too large. Choose a smaller image.';

/// Shown for a post image whose header cannot be read.
const unreadablePostImageMessage =
    'This image could not be read. Choose a different image.';

/// Shown when a converted or re-encoded post image cannot be saved to the
/// device's temporary storage.
const postImageNotSavedMessage =
    'This image could not be prepared on this device. Try again.';

/// The format of [bytes] from their first bytes, or null when unknown.
ImageFormat? sniffImageFormat(Uint8List bytes) {
  if (_startsWith(bytes, 0, const [0xff, 0xd8, 0xff])) {
    return ImageFormat.jpeg;
  }
  if (_startsWith(bytes, 0, const [137, 80, 78, 71, 13, 10, 26, 10])) {
    return ImageFormat.png;
  }
  if (_startsWithAscii(bytes, 0, 'GIF87a') ||
      _startsWithAscii(bytes, 0, 'GIF89a')) {
    return ImageFormat.gif;
  }
  if (_startsWithAscii(bytes, 0, 'RIFF') &&
      _startsWithAscii(bytes, 8, 'WEBP')) {
    return ImageFormat.webp;
  }
  if (_startsWithAscii(bytes, 4, 'ftyp')) {
    return _isoMediaFormat(bytes);
  }
  return null;
}

/// Checks [bytes] against the post-image format, byte and pixel limits.
///
/// Throws ImageValidationException when the image is refused.
PostImageCheck checkPostImage(Uint8List bytes) {
  final format = sniffImageFormat(bytes);
  // HEIC, HEIF and AVIF are recognised but not uploadable as they are.
  const unsupported = {ImageFormat.heic, ImageFormat.heif, ImageFormat.avif};
  if (format == null || unsupported.contains(format)) {
    throw const ImageValidationException(unsupportedPostImageFormatMessage);
  }

  if (bytes.length > ImageUploadLimits.postImageMaxSizeBytes) {
    throw const ImageValidationException(postImageTooLargeMessage);
  }

  final dimensions = imageHeaderDimensions(bytes, format);
  if (dimensions == null) {
    throw const ImageValidationException(unreadablePostImageMessage);
  }

  if (dimensions.width * dimensions.height >
      ImageUploadLimits.postImageMaxPixels) {
    throw const ImageValidationException(postImageTooManyPixelsMessage);
  }

  return (
    mimeType: format.mimeType,
    width: dimensions.width,
    height: dimensions.height,
  );
}

typedef _Dimensions = ({int width, int height});

/// The pixel dimensions in the header of [bytes], sniffed as [format], or
/// null when the header cannot be read, a dimension is zero, or the format
/// (HEIC, HEIF, AVIF) has no header this reads.
({int width, int height})? imageHeaderDimensions(
  Uint8List bytes,
  ImageFormat format,
) {
  final dimensions = switch (format) {
    ImageFormat.jpeg => _jpegDimensions(bytes),
    ImageFormat.png => _pngDimensions(bytes),
    ImageFormat.webp => _webpDimensions(bytes),
    ImageFormat.gif => _gifDimensions(bytes),
    ImageFormat.heic || ImageFormat.heif || ImageFormat.avif => null,
  };
  if (dimensions == null || dimensions.width < 1 || dimensions.height < 1) {
    return null;
  }
  return dimensions;
}

/// HEIC, HEIF or AVIF from an ISO-BMFF `ftyp` box's major and compatible
/// brands, or null for any other brand (MP4 video, for example).
ImageFormat? _isoMediaFormat(Uint8List bytes) {
  final boxSize = _bigEndian32(bytes, 0);
  if (boxSize == null) {
    return null;
  }
  final end = boxSize < bytes.length ? boxSize : bytes.length;
  final brands = <String>[
    if (end >= 12) ascii.decode(bytes.sublist(8, 12), allowInvalid: true),
    // Compatible brands follow the 4-byte minor version.
    for (var offset = 16; offset + 4 <= end; offset += 4)
      ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true),
  ];
  const avifBrands = {'avif', 'avis'};
  const heicBrands = {'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis'};
  const heifBrands = {'mif1', 'msf1', 'heif'};
  if (brands.any(avifBrands.contains)) {
    return ImageFormat.avif;
  }
  if (brands.any(heicBrands.contains)) {
    return ImageFormat.heic;
  }
  if (brands.any(heifBrands.contains)) {
    return ImageFormat.heif;
  }
  return null;
}

/// PNG: width and height are the first fields of the IHDR chunk.
_Dimensions? _pngDimensions(Uint8List bytes) {
  if (!_startsWithAscii(bytes, 12, 'IHDR')) {
    return null;
  }
  final width = _bigEndian32(bytes, 16);
  final height = _bigEndian32(bytes, 20);
  if (width == null || height == null) {
    return null;
  }
  return (width: width, height: height);
}

/// GIF: the logical screen size follows the 6-byte signature.
_Dimensions? _gifDimensions(Uint8List bytes) {
  final width = _littleEndian16(bytes, 6);
  final height = _littleEndian16(bytes, 8);
  if (width == null || height == null) {
    return null;
  }
  return (width: width, height: height);
}

/// WebP: the first chunk is VP8X (extended), VP8L (lossless) or VP8 (lossy).
_Dimensions? _webpDimensions(Uint8List bytes) {
  const payload = 20;
  if (_startsWithAscii(bytes, 12, 'VP8X')) {
    final widthMinusOne = _littleEndian24(bytes, payload + 4);
    final heightMinusOne = _littleEndian24(bytes, payload + 7);
    if (widthMinusOne == null || heightMinusOne == null) {
      return null;
    }
    return (width: widthMinusOne + 1, height: heightMinusOne + 1);
  }
  if (_startsWithAscii(bytes, 12, 'VP8L')) {
    if (bytes.length <= payload || bytes[payload] != 0x2f) {
      return null;
    }
    final bits = _littleEndian32(bytes, payload + 1);
    if (bits == null) {
      return null;
    }
    return (width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1);
  }
  if (_startsWithAscii(bytes, 12, 'VP8 ')) {
    if (!_startsWith(bytes, payload + 3, const [0x9d, 0x01, 0x2a])) {
      return null;
    }
    final width = _littleEndian16(bytes, payload + 6);
    final height = _littleEndian16(bytes, payload + 8);
    if (width == null || height == null) {
      return null;
    }
    return (width: width & 0x3fff, height: height & 0x3fff);
  }
  return null;
}

/// JPEG: walks the marker segments to the first start-of-frame header.
_Dimensions? _jpegDimensions(Uint8List bytes) {
  var offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset] != 0xff) {
      return null;
    }
    // Fill bytes: any number of 0xff may precede a marker.
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) {
      return null;
    }
    final marker = bytes[offset];
    offset++;
    // Standalone markers carry no length.
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      continue;
    }
    // End of image or start of scan before any frame header.
    if (marker == 0xd9 || marker == 0xda) {
      return null;
    }
    final length = _bigEndian16(bytes, offset);
    if (length == null || length < 2) {
      return null;
    }
    if (_isStartOfFrame(marker)) {
      // Length, precision, then height and width.
      final height = _bigEndian16(bytes, offset + 3);
      final width = _bigEndian16(bytes, offset + 5);
      if (width == null || height == null) {
        return null;
      }
      return (width: width, height: height);
    }
    offset += length;
  }
  return null;
}

/// SOF0–SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
bool _isStartOfFrame(int marker) =>
    marker >= 0xc0 &&
    marker <= 0xcf &&
    marker != 0xc4 &&
    marker != 0xc8 &&
    marker != 0xcc;

bool _startsWith(Uint8List bytes, int offset, List<int> prefix) {
  if (bytes.length < offset + prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[offset + index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

bool _startsWithAscii(Uint8List bytes, int offset, String prefix) =>
    _startsWith(bytes, offset, ascii.encode(prefix));

int? _bigEndian16(Uint8List bytes, int offset) {
  if (bytes.length < offset + 2) {
    return null;
  }
  return (bytes[offset] << 8) | bytes[offset + 1];
}

int? _bigEndian32(Uint8List bytes, int offset) {
  if (bytes.length < offset + 4) {
    return null;
  }
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int? _littleEndian16(Uint8List bytes, int offset) {
  if (bytes.length < offset + 2) {
    return null;
  }
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int? _littleEndian24(Uint8List bytes, int offset) {
  if (bytes.length < offset + 3) {
    return null;
  }
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

int? _littleEndian32(Uint8List bytes, int offset) {
  if (bytes.length < offset + 4) {
    return null;
  }
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
