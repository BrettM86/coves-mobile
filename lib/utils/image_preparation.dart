// Converts and re-encodes picked post images to an uploadable format and
// size.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/image_upload_limits.dart';
import '../models/picked_image.dart';
import 'image_format.dart';
import 'image_picker_utils.dart';

/// The formats the encoder writes.
enum EncodedImageFormat { jpeg, png }

/// Pixel dimensions.
typedef ImageSize = ({int width, int height});

/// Decodes an image, applies its EXIF orientation, scales it to
/// `targetSize` (no scaling when null) and encodes it without EXIF.
///
/// `inSampleSize`, a power of two, makes the decoder work at that fraction
/// of each dimension before scaling, when [supportsDecodeSampling] is true;
/// otherwise it is ignored and the image is decoded at full size.
abstract interface class ImageEncoder {
  /// Whether `inSampleSize` reduces the decode: true on Android, false on
  /// iOS, where flutter_image_compress builds a full-size UIImage first.
  bool get supportsDecodeSampling;

  Future<Uint8List> encode(
    Uint8List bytes, {
    required EncodedImageFormat format,
    required int quality,
    ImageSize? targetSize,
    int inSampleSize = 1,
  });
}

/// The subset of `FlutterImageCompress.compressWithList` the encoder uses.
typedef ImageCompressFunction = Future<Uint8List> Function(
  Uint8List image, {
  required int minWidth,
  required int minHeight,
  required int quality,
  required bool autoCorrectionAngle,
  required CompressFormat format,
  required bool keepExif,
  required int inSampleSize,
});

/// [ImageEncoder] over flutter_image_compress.
class FlutterImageCompressEncoder implements ImageEncoder {
  const FlutterImageCompressEncoder({
    required this.supportsDecodeSampling,
    this._compress = FlutterImageCompress.compressWithList,
  });

  final ImageCompressFunction _compress;

  @override
  final bool supportsDecodeSampling;

  /// Large enough that both platforms clamp the scale to 1; the plugin's
  /// 1920x1080 defaults would otherwise downscale.
  static const _uncappedEdge = 1 << 30;

  @override
  Future<Uint8List> encode(
    Uint8List bytes, {
    required EncodedImageFormat format,
    required int quality,
    ImageSize? targetSize,
    int inSampleSize = 1,
  }) {
    // The short edge on both platforms, whatever the EXIF orientation:
    // Android scales by max(1, min(w/minWidth, h/minHeight)), iOS fits the
    // orientation-applied image to the (minWidth, minHeight) box.
    final minimumEdge = switch (targetSize) {
      (:final width, :final height) => width < height ? width : height,
      null => _uncappedEdge,
    };
    return _compress(
      bytes,
      minWidth: minimumEdge,
      minHeight: minimumEdge,
      quality: quality,
      autoCorrectionAngle: true,
      format: switch (format) {
        EncodedImageFormat.jpeg => CompressFormat.jpeg,
        EncodedImageFormat.png => CompressFormat.png,
      },
      keepExif: false,
      inSampleSize: inSampleSize,
    );
  }
}

/// Deletes [file], a file [ImagePreparer.prepare] wrote, in the background;
/// a file already gone, or one that cannot be deleted, is left as it is.
void deletePreparedImageFile(File file) => unawaited(_deleteQuietly(file));

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Already gone, or not deletable; the OS clears the temp directory.
  }
}

/// The name prefix of every file [ImagePreparer.prepare] writes.
const _preparedImageFilePrefix = 'post-image-';

/// Matches the full names `_writeTemporaryFile` gives prepared images.
final _preparedImageFileName = RegExp(
  '^$_preparedImageFilePrefix\\d+-\\d+\\.(jpg|png)\$',
);

/// Deletes prepared image files in [directory] left by an earlier process:
/// those named like one and last modified before [processStart]. A file
/// that cannot be deleted, or a directory that cannot be listed, is left.
Future<void> sweepStalePreparedImageFiles({
  required Directory directory,
  required DateTime processStart,
}) async {
  var failures = 0;
  try {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !_preparedImageFileName.hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      try {
        if (entity.lastModifiedSync().isBefore(processStart)) {
          await entity.delete();
        }
      } on FileSystemException {
        failures++;
      }
    }
  } on FileSystemException {
    failures++;
  }
  if (failures > 0) {
    debugPrint('Prepared image sweep: $failures failures');
  }
}

/// Turns a picked image into one the server accepts, or refuses it.
class ImagePreparer {
  ImagePreparer({required this._encoder, required this._temporaryDirectory});

  factory ImagePreparer.platform() => ImagePreparer(
    encoder: FlutterImageCompressEncoder(
      supportsDecodeSampling: Platform.isAndroid,
    ),
    temporaryDirectory: getTemporaryDirectory,
  );

  final ImageEncoder _encoder;
  final Future<Directory> Function() _temporaryDirectory;

  /// The long edge a re-encoded image is scaled down to.
  static const _maximumLongEdge = 4096;

  /// Images with more pixels are refused before they reach a decoder that
  /// samples at decode time.
  static const _maximumDecodePixels = 400000000;

  /// Images with more pixels are refused before they reach a decoder that
  /// decodes at full size: 64 MP is 256 MB of RGBA, under iPhone app memory
  /// limits, and above every current iPhone camera (48 MP).
  static const _maximumFullDecodePixels = 64000000;
  static const _jpegQuality = 90;
  static const _pngQuality = 100;

  /// Makes file names unique among the files this process writes.
  static int _fileCounter = 0;

  /// Prepares [images] in order, passing each refused image's message to
  /// [onRefused].
  ///
  /// Returns null when [isDropped] holds after any image; the files
  /// prepared so far are deleted then, and on an unexpected error, which is
  /// rethrown.
  Future<List<PickedImage>?> prepareAll(
    List<PickedImage> images, {
    required bool Function() isDropped,
    required void Function(String message) onRefused,
  }) async {
    final prepared = <PickedImage>[];
    var complete = false;
    try {
      for (final image in images) {
        try {
          prepared.add(await prepare(image));
        } on ImageValidationException catch (error) {
          onRefused(error.message);
        }
        if (isDropped()) {
          return null;
        }
      }
      complete = true;
      return prepared;
    } finally {
      if (!complete) {
        for (final image in prepared) {
          if (image.ownsFile) {
            deletePreparedImageFile(image.file);
          }
        }
      }
    }
  }

  /// Returns [picked] itself when it is uploadable as it is, otherwise an
  /// owned file in the temporary directory holding the converted or
  /// re-encoded image.
  ///
  /// Throws ImageValidationException when the image is refused or the
  /// output cannot be saved; nothing is left written then.
  Future<PickedImage> prepare(PickedImage picked) async {
    final format = sniffImageFormat(picked.bytes);
    if (format == null) {
      throw const ImageValidationException(unsupportedPostImageFormatMessage);
    }

    final _Header prepared;
    if (_isConvertedFormat(format)) {
      // Without image extents the conversion decodes at full size.
      final extents = _heifImageExtents(picked.bytes);
      final converted = await _encode(
        picked.bytes,
        EncodedImageFormat.jpeg,
        null,
        extents == null
            ? 1
            : _decodeSampleSize(extents, _encoder.supportsDecodeSampling),
      );
      prepared = _limitMessage(converted) == null
          ? converted
          : await _reencode(converted);
    } else {
      final size = imageHeaderDimensions(picked.bytes, format);
      if (size == null) {
        throw const ImageValidationException(unreadablePostImageMessage);
      }
      final header = (bytes: picked.bytes, format: format, size: size);
      final message = _limitMessage(header);
      if (message == null) {
        return picked;
      }
      if (format == ImageFormat.gif) {
        throw ImageValidationException(message);
      }
      prepared = await _reencode(header);
    }

    final File file;
    try {
      file = await _writeTemporaryFile(prepared);
    } on Exception {
      // No temp directory (MissingPlatformDirectoryException,
      // PlatformException) or a failed write (FileSystemException).
      throw const ImageValidationException(postImageNotSavedMessage);
    }
    return PickedImage(
      file: file,
      bytes: prepared.bytes,
      mimeType: prepared.format.mimeType,
      ownsFile: true,
    );
  }

  /// Encodes [header] capped at [_maximumLongEdge], as PNG when it has
  /// transparency and JPEG otherwise, and refuses an output still over a
  /// limit.
  Future<_Header> _reencode(_Header header) async {
    final output = await _encode(
      header.bytes,
      _hasTransparency(header)
          ? EncodedImageFormat.png
          : EncodedImageFormat.jpeg,
      _cappedSize(header.size),
      _decodeSampleSize(header.size, _encoder.supportsDecodeSampling),
    );
    final message = _limitMessage(output);
    if (message != null) {
      throw ImageValidationException(message);
    }
    return output;
  }

  /// Encodes [bytes], decoded at 1/[inSampleSize], and reads the output's
  /// header; an encoder failure or an output that is not a readable JPEG or
  /// PNG is refused as unreadable.
  Future<_Header> _encode(
    Uint8List bytes,
    EncodedImageFormat format,
    ImageSize? targetSize,
    int inSampleSize,
  ) async {
    final Uint8List output;
    try {
      output = await _encoder.encode(
        bytes,
        format: format,
        quality: switch (format) {
          EncodedImageFormat.jpeg => _jpegQuality,
          EncodedImageFormat.png => _pngQuality,
        },
        targetSize: targetSize,
        inSampleSize: inSampleSize,
      );
    } on Exception {
      throw const ImageValidationException(unreadablePostImageMessage);
      // flutter_image_compress reports every native failure, and a null or
      // empty result, as CompressError, which extends Error.
      // ignore: avoid_catching_errors
    } on CompressError {
      throw const ImageValidationException(unreadablePostImageMessage);
      // The plugin throws UnsupportedError on a platform it does not
      // support.
      // ignore: avoid_catching_errors
    } on UnsupportedError {
      throw const ImageValidationException(unreadablePostImageMessage);
    }
    final outputFormat = sniffImageFormat(output);
    if (outputFormat != ImageFormat.jpeg && outputFormat != ImageFormat.png) {
      throw const ImageValidationException(unreadablePostImageMessage);
    }
    final size = imageHeaderDimensions(output, outputFormat!);
    if (size == null) {
      throw const ImageValidationException(unreadablePostImageMessage);
    }
    return (bytes: output, format: outputFormat, size: size);
  }

  Future<File> _writeTemporaryFile(_Header image) async {
    final directory = await _temporaryDirectory();
    final extension = image.format == ImageFormat.png ? 'png' : 'jpg';
    final name =
        '$_preparedImageFilePrefix${DateTime.now().microsecondsSinceEpoch}-'
        '${_fileCounter++}.$extension';
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    var created = false;
    var written = false;
    try {
      await file.create(exclusive: true);
      created = true;
      await file.writeAsBytes(image.bytes);
      written = true;
    } finally {
      if (created && !written) {
        deletePreparedImageFile(file);
      }
    }
    return file;
  }
}

/// Bytes with the format and dimensions read from their header.
typedef _Header = ({Uint8List bytes, ImageFormat format, ImageSize size});

bool _isConvertedFormat(ImageFormat format) =>
    format == ImageFormat.heic ||
    format == ImageFormat.heif ||
    format == ImageFormat.avif;

/// The message for the first limit [header] is over, or null within limits.
String? _limitMessage(_Header header) {
  if (header.bytes.length > ImageUploadLimits.postImageMaxSizeBytes) {
    return postImageTooLargeMessage;
  }
  if (header.size.width * header.size.height >
      ImageUploadLimits.postImageMaxPixels) {
    return postImageTooManyPixelsMessage;
  }
  return null;
}

/// The largest power of two that keeps the decoded long edge of [size] at
/// or above [ImagePreparer._maximumLongEdge], so the encoder can still reach
/// its target; refuses [size] above [ImagePreparer._maximumDecodePixels].
///
/// Without [decodeSampling] the decode is at full size, so the sample is 1
/// and [size] above [ImagePreparer._maximumFullDecodePixels] is refused.
int _decodeSampleSize(ImageSize size, bool decodeSampling) {
  final ceiling = decodeSampling
      ? ImagePreparer._maximumDecodePixels
      : ImagePreparer._maximumFullDecodePixels;
  if (size.width * size.height > ceiling) {
    throw const ImageValidationException(postImageTooManyPixelsMessage);
  }
  if (!decodeSampling) {
    return 1;
  }
  final long = size.width >= size.height ? size.width : size.height;
  var sample = 1;
  while (long ~/ (sample * 2) >= ImagePreparer._maximumLongEdge) {
    sample *= 2;
  }
  return sample;
}

/// The largest image spatial extents (ispe) property in a HEIF or AVIF
/// file's meta box, or null when there is none. Thumbnails and grid tiles
/// are smaller than the image they belong to, so the largest bounds the
/// decode.
ImageSize? _heifImageExtents(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final meta = _findBox(bytes, data, 'meta', 0, bytes.length);
  // meta is a full box: version and flags precede its children.
  if (meta == null || meta.start + 4 > meta.end) {
    return null;
  }
  final iprp = _findBox(bytes, data, 'iprp', meta.start + 4, meta.end);
  if (iprp == null) {
    return null;
  }
  final ipco = _findBox(bytes, data, 'ipco', iprp.start, iprp.end);
  if (ipco == null) {
    return null;
  }
  ImageSize? largest;
  var offset = ipco.start;
  while (true) {
    final ispe = _findBox(bytes, data, 'ispe', offset, ipco.end);
    if (ispe == null) {
      return largest;
    }
    offset = ispe.end;
    // Version and flags, then 32-bit width and height.
    if (ispe.start + 12 > ispe.end) {
      continue;
    }
    final width = data.getUint32(ispe.start + 4);
    final height = data.getUint32(ispe.start + 8);
    if (width == 0 || height == 0) {
      continue;
    }
    if (largest == null || width * height > largest.width * largest.height) {
      largest = (width: width, height: height);
    }
  }
}

/// The payload bounds of the first [type] box among the sibling boxes in
/// [start]..[end], or null when there is none or a box size is malformed.
({int start, int end})? _findBox(
  Uint8List bytes,
  ByteData data,
  String type,
  int start,
  int end,
) {
  var offset = start;
  while (offset + 8 <= end) {
    final declared = data.getUint32(offset);
    // 0 runs to the end; 1 (a 64-bit size) does not occur in a header.
    final size = declared == 0 ? end - offset : declared;
    if (size < 8 || offset + size > end) {
      return null;
    }
    if (ascii.decode(
          bytes.sublist(offset + 4, offset + 8),
          allowInvalid: true,
        ) ==
        type) {
      return (start: offset + 8, end: offset + size);
    }
    offset += size;
  }
  return null;
}

/// [size] scaled so its long edge is [ImagePreparer._maximumLongEdge], or
/// null when it is already no longer.
///
/// The encoder scales by the short edge (minWidth = minHeight = short) and
/// both platforms truncate `long * short' / short` in float32, so the exact
/// floor of the short edge lands the long edge just under the cap (9000x6000
/// → 2730 → 4095.0, truncated to 4094). The short edge is instead the
/// smallest one that puts the exact long edge in 4096.01..4096.99, clear of
/// float32 error on either side of the truncation; when no integer short edge
/// lands there (an exact ratio, or a very long image), the floor is used.
ImageSize? _cappedSize(ImageSize size) {
  const maximum = ImagePreparer._maximumLongEdge;
  // Hundredths of a pixel of margin.
  const margin = 1;
  final landscape = size.width >= size.height;
  final long = landscape ? size.width : size.height;
  final short = landscape ? size.height : size.width;
  if (long <= maximum) {
    return null;
  }
  // The smallest s with long * s / short >= maximum + 0.01.
  final lowest =
      ((maximum * 100 + margin) * short + long * 100 - 1) ~/ (long * 100);
  var cappedShort =
      long * lowest * 100 <= (maximum * 100 + 100 - margin) * short
      ? lowest
      : short * maximum ~/ long;
  if (cappedShort < 1) {
    cappedShort = 1;
  }
  return landscape
      ? (width: maximum, height: cappedShort)
      : (width: cappedShort, height: maximum);
}

/// Whether the header of [header] declares transparency: PNG colour type 4
/// or 6 or a tRNS chunk before IDAT; WebP's VP8X alpha flag or VP8L
/// alpha_is_used bit. JPEG and lossy VP8 WebP are opaque.
bool _hasTransparency(_Header header) {
  final bytes = header.bytes;
  final data = ByteData.sublistView(bytes);
  switch (header.format) {
    case ImageFormat.png:
      // Signature (8), IHDR length and type (8), width, height, bit depth.
      const colorTypeOffset = 25;
      if (bytes.length <= colorTypeOffset) {
        return false;
      }
      final colorType = bytes[colorTypeOffset];
      if (colorType == 4 || colorType == 6) {
        return true;
      }
      // The chunk after IHDR: signature (8) + IHDR (4 + 4 + 13 + 4).
      var offset = 33;
      while (offset + 8 <= bytes.length) {
        final length = data.getUint32(offset);
        final type = ascii.decode(
          bytes.sublist(offset + 4, offset + 8),
          allowInvalid: true,
        );
        if (type == 'IDAT') {
          return false;
        }
        if (type == 'tRNS') {
          return true;
        }
        offset += 12 + length;
      }
      return false;
    case ImageFormat.webp:
      const chunkTypeOffset = 12;
      const payloadOffset = 20;
      final chunkType = ascii.decode(
        bytes.sublist(chunkTypeOffset, chunkTypeOffset + 4),
        allowInvalid: true,
      );
      if (chunkType == 'VP8X') {
        return bytes[payloadOffset] & 0x10 != 0;
      }
      if (chunkType == 'VP8L') {
        final bits = data.getUint32(payloadOffset + 1, Endian.little);
        return (bits >> 28) & 1 == 1;
      }
      return false;
    case ImageFormat.jpeg ||
        ImageFormat.gif ||
        ImageFormat.heic ||
        ImageFormat.heif ||
        ImageFormat.avif:
      return false;
  }
}
