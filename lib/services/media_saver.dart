import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';

/// Saves remote media to the device's photo library.
abstract interface class MediaSaver {
  /// Saves the image at [url].
  ///
  /// Operational failures (any [Exception]) are normalized to a
  /// [MediaSaveException], so callers can map [MediaSaveException.failure] to
  /// a message. [Error]s are programming bugs and propagate unchanged.
  Future<void> saveImage(String url);
}

/// Why a save to the photo library failed.
enum MediaSaveFailure {
  /// The user refused or revoked add access to the photo library.
  accessDenied,

  /// The image bytes couldn't be fetched or read, including a timeout.
  downloadFailed,

  /// The photo-library write or the plugin failed for any other reason.
  saveFailed,
}

class MediaSaveException implements Exception {
  const MediaSaveException(this.failure);

  final MediaSaveFailure failure;

  @override
  String toString() => 'MediaSaveException(${failure.name})';
}

/// Saves images to the camera roll through gal, reading bytes from the image
/// cache so an image the viewer already shows is not downloaded again.
///
/// Saves never name an album: on iOS an album save needs full photo-library
/// read/write permission, while a plain camera-roll save needs only add-only
/// access.
class GalMediaSaver implements MediaSaver {
  GalMediaSaver({BaseCacheManager? cacheManager})
    : _cacheManager = cacheManager ?? DefaultCacheManager();

  // Bounds only the download: the permission request can legitimately wait
  // while the user reads the OS dialog.
  static const _downloadTimeout = Duration(seconds: 30);

  final BaseCacheManager _cacheManager;

  @override
  Future<void> saveImage(String url) async {
    try {
      final granted = await Gal.hasAccess() || await Gal.requestAccess();
      if (!granted) {
        throw const MediaSaveException(MediaSaveFailure.accessDenied);
      }

      final Uint8List bytes;
      try {
        bytes = await _readImageBytes(url).timeout(_downloadTimeout);
      } on Exception {
        throw const MediaSaveException(MediaSaveFailure.downloadFailed);
      }

      await Gal.putImageBytes(bytes);
    } on MediaSaveException {
      rethrow;
    } on GalException catch (error) {
      throw MediaSaveException(
        error.type == GalExceptionType.accessDenied
            ? MediaSaveFailure.accessDenied
            : MediaSaveFailure.saveFailed,
      );
    } on Exception {
      // gal converts only PlatformException; anything else from the channel,
      // such as MissingPluginException, would otherwise escape the contract.
      throw const MediaSaveException(MediaSaveFailure.saveFailed);
    }
  }

  Future<Uint8List> _readImageBytes(String url) async {
    final file = await _cacheManager.getSingleFile(url);
    return file.readAsBytes();
  }
}
