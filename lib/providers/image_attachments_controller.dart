// The composer's attached images and their uploads.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/image_upload_limits.dart';
import '../models/image_attachment.dart';
import '../models/picked_image.dart';
import '../models/post_embed_input.dart';
import '../models/upload_image_response.dart';
import '../services/api_exceptions.dart';
import '../utils/error_messages.dart';
import '../utils/image_format.dart';
import '../utils/image_picker_utils.dart';
import '../utils/image_preparation.dart';

/// Uploads one image's bytes as [contentType].
typedef ImageUploader = Future<UploadImageResponse> Function(
  Uint8List bytes,
  String contentType, {
  ProgressCallback? onSendProgress,
});

/// Thrown by [ImageAttachmentsController.uploadMissing] when any upload
/// failed; the failed attachments hold their errors.
class ImageUploadFailedException implements Exception {
  const ImageUploadFailedException();
}

/// The images attached to a post, in strip order, and their uploads.
///
/// The controller only calls [ImageUploader]; it owns no API service.
class ImageAttachmentsController extends ChangeNotifier {
  ImageAttachmentsController({required this._upload});

  /// Uploads in flight at once, across [uploadMissing] and [retry].
  static const _concurrentUploads = 2;

  final ImageUploader _upload;
  final List<ImageAttachment> _attachments = [];

  /// The upload in flight or waiting for a slot for each attachment id;
  /// completes with whether it succeeded.
  final Map<String, Future<bool>> _uploadsInFlight = {};

  /// Uploads holding one of the [_concurrentUploads] slots.
  int _activeUploads = 0;

  /// Uploads waiting for a slot, in the order they asked for one.
  final List<Completer<void>> _slotWaiters = [];

  /// Bumped by [forgetUploads] and [handOff]; an upload started under an
  /// older value is discarded.
  int _uploadGeneration = 0;
  int _nextId = 0;
  bool _disposed = false;

  List<ImageAttachment> get attachments => List.unmodifiable(_attachments);

  /// How many more images may be attached.
  int get remaining =>
      ImageUploadLimits.postImageMaxCount - _attachments.length;

  /// Attaches [picked]; returns a user notice when any were refused.
  ///
  /// Images past [ImageUploadLimits.postImageMaxCount] are refused, and so
  /// is any image `checkPostImage` refuses (format, bytes or pixels). The
  /// content type comes from the bytes, never from [PickedImage.mimeType].
  /// A refused image's file is deleted when the image owns it.
  String? add(List<PickedImage> picked) {
    final notices = <String>[];
    var added = false;
    var overLimit = false;
    for (final image in picked) {
      if (remaining < 1) {
        overLimit = true;
        _deleteIfOwned(image.file, ownsFile: image.ownsFile);
        continue;
      }
      final PostImageCheck check;
      try {
        check = checkPostImage(image.bytes);
      } on ImageValidationException catch (error) {
        if (!notices.contains(error.message)) {
          notices.add(error.message);
        }
        _deleteIfOwned(image.file, ownsFile: image.ownsFile);
        continue;
      }
      _attachments.add(
        ImageAttachment(
          id: _newId(),
          file: image.file,
          bytes: image.bytes,
          mimeType: check.mimeType,
          ownsFile: image.ownsFile,
        ),
      );
      added = true;
    }
    if (overLimit) {
      notices.add(
        'A post can have at most ${ImageUploadLimits.postImageMaxCount} '
        'images.',
      );
    }
    if (added) {
      _notify();
    }
    return notices.isEmpty ? null : notices.join(' ');
  }

  /// Removes the attachment with [id], dropping its blob and deleting its
  /// file when it owns it.
  void remove(String id) {
    final index = _attachments.indexWhere((attachment) => attachment.id == id);
    if (index < 0) {
      return;
    }
    final removed = _attachments.removeAt(index);
    _deleteIfOwned(removed.file, ownsFile: removed.ownsFile);
    _notify();
  }

  /// Removes every attachment without deleting any file and returns them;
  /// their owner now owns their files.
  ///
  /// Uploads in flight are discarded, as in [forgetUploads], and an
  /// attachment they were uploading is handed off pending, so it uploads
  /// again wherever it is restored.
  List<ImageAttachment> handOff() {
    final handed = List.of(_attachments);
    _attachments.clear();
    _uploadGeneration++;
    _uploadsInFlight.clear();
    for (final attachment in handed) {
      if (attachment.status == ImageAttachmentStatus.uploading) {
        attachment
          ..status = ImageAttachmentStatus.pending
          ..progress = 0;
      }
    }
    if (handed.isNotEmpty) {
      _notify();
    }
    return handed;
  }

  /// Adopts [attachments] taken from a draft, keeping their blob, aspect
  /// ratio, alt and status; the controller owns their files from then on.
  void restore(List<ImageAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    _attachments.addAll(attachments);
    _notify();
  }

  /// An id no held attachment has, restored ones included.
  String _newId() {
    while (true) {
      final id = 'image-${_nextId++}';
      if (!_attachments.any((attachment) => attachment.id == id)) {
        return id;
      }
    }
  }

  /// Sets the alt text of the attachment with [id].
  void setAlt(String id, String alt) {
    final attachment = _attachments
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (attachment == null) {
      return;
    }
    attachment.alt = alt;
    _notify();
  }

  /// Moves the attachment at [from] so it ends up at index [to].
  void reorder(int from, int to) {
    if (from == to) {
      return;
    }
    _attachments.insert(to, _attachments.removeAt(from));
    _notify();
  }

  /// Uploads every attachment without a blob, two at a time in strip order,
  /// and waits for any upload already in flight (a Retry). Attachments added
  /// meanwhile are uploaded too, so every attachment has a blob on return.
  ///
  /// Throws [ImageUploadFailedException] when any upload fails, or when
  /// [forgetUploads] runs meanwhile, so no upload starts for the new account.
  Future<void> uploadMissing() async {
    final generation = _uploadGeneration;
    while (true) {
      final targets = _attachments
          .where((attachment) => attachment.blob == null)
          .toList();
      if (targets.isEmpty) {
        return;
      }
      final results = await Future.wait([
        for (final attachment in targets) _startUpload(attachment),
      ]);
      if (results.contains(false) || _isDiscarded(generation)) {
        throw const ImageUploadFailedException();
      }
    }
  }

  /// Uploads the failed attachment with [id] now.
  ///
  /// Does nothing when no failed attachment has [id]. A failure is left on
  /// the attachment rather than thrown.
  Future<void> retry(String id) async {
    final attachment = _attachments
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (attachment == null ||
        attachment.status != ImageAttachmentStatus.failed ||
        _uploadsInFlight.containsKey(id)) {
      return;
    }
    await _startUpload(attachment);
  }

  /// Drops every blob and upload state, for when the account the images
  /// were uploaded under is no longer the one posting.
  ///
  /// Uploads in flight finish but their results are discarded, and queued
  /// uploads never start; the next [uploadMissing] uploads every image again.
  void forgetUploads() {
    _uploadGeneration++;
    _uploadsInFlight.clear();
    for (final attachment in _attachments) {
      attachment
        ..blob = null
        ..aspectRatio = null
        ..status = ImageAttachmentStatus.pending
        ..progress = 0
        ..error = null
        ..errorCode = null;
    }
    _notify();
  }

  /// Upload error codes that a new sign-in for the same account can fix.
  static const _signInAgainErrorCodes = {
    'MissingBlobScope',
    'PermissionDenied',
  };

  /// Whether a failed upload was refused for a permission the session
  /// lacks, so signing in again may let it upload.
  bool get needsSignInAgain => _attachments.any(
    (attachment) =>
        attachment.status == ImageAttachmentStatus.failed &&
        _signInAgainErrorCodes.contains(attachment.errorCode),
  );

  /// The embed images, in strip order, with each alt trimmed and left out
  /// when blank; StateError if any lacks a blob.
  List<EmbedImageInput> get embedImages => [
    for (final attachment in _attachments)
      EmbedImageInput(
        blob:
            attachment.blob ??
            (throw StateError('Attachment ${attachment.id} has no blob')),
        alt: attachment.trimmedAlt,
        aspectRatio: attachment.aspectRatio,
      ),
  ];

  /// The upload of [attachment] already in flight, or a new one that waits
  /// for a free slot.
  Future<bool> _startUpload(ImageAttachment attachment) {
    final existing = _uploadsInFlight[attachment.id];
    if (existing != null) {
      return existing;
    }
    late final Future<bool> upload;
    // A block body: returning the removed future from whenComplete would
    // make the upload wait on itself.
    upload = _uploadInSlot(attachment).whenComplete(() {
      if (identical(_uploadsInFlight[attachment.id], upload)) {
        _uploadsInFlight.remove(attachment.id);
      }
    });
    _uploadsInFlight[attachment.id] = upload;
    return upload;
  }

  Future<bool> _uploadInSlot(ImageAttachment attachment) async {
    final generation = _uploadGeneration;
    await _acquireSlot();
    try {
      // Disposed or forgotten while waiting its turn.
      if (_isDiscarded(generation)) {
        return false;
      }
      // Removed from the strip, or uploaded, while waiting its turn.
      if (!_attachments.contains(attachment) || attachment.blob != null) {
        return true;
      }
      return await _uploadAttachment(attachment, generation);
    } finally {
      _releaseSlot();
    }
  }

  Future<void> _acquireSlot() {
    if (_activeUploads < _concurrentUploads) {
      _activeUploads++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _slotWaiters.add(waiter);
    return waiter.future;
  }

  /// Hands the slot to the longest waiting upload, or frees it.
  void _releaseSlot() {
    if (_slotWaiters.isNotEmpty) {
      _slotWaiters.removeAt(0).complete();
    } else {
      _activeUploads--;
    }
  }

  bool _isDiscarded(int generation) =>
      _disposed || generation != _uploadGeneration;

  /// Uploads [attachment]; returns whether it now has a blob. The result of
  /// an attachment removed meanwhile is dropped and counts as success; the
  /// result of an upload discarded meanwhile is dropped and counts as failure.
  Future<bool> _uploadAttachment(
    ImageAttachment attachment,
    int generation,
  ) async {
    attachment
      ..status = ImageAttachmentStatus.uploading
      ..progress = 0
      ..error = null
      ..errorCode = null;
    _notify();
    try {
      final response = await _upload(
        attachment.bytes,
        attachment.mimeType,
        onSendProgress: (sent, total) {
          if (total <= 0 || _isDiscarded(generation)) {
            return;
          }
          attachment.progress = sent / total;
          _notify();
        },
      );
      if (_isDiscarded(generation)) {
        return false;
      }
      attachment
        ..blob = response.blob
        ..aspectRatio = response.aspectRatio
        ..status = ImageAttachmentStatus.uploaded
        ..progress = 1;
      _notify();
      return true;
    } on Exception catch (error) {
      if (_isDiscarded(generation)) {
        return false;
      }
      attachment
        ..status = ImageAttachmentStatus.failed
        ..error = ErrorMessage.uploadImage(error)
        ..errorCode = error is ApiException ? error.errorCode : null;
      _notify();
      return !_attachments.contains(attachment);
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _deleteIfOwned(File file, {required bool ownsFile}) {
    if (ownsFile) {
      deletePreparedImageFile(file);
    }
  }

  /// Deletes the owned files of the attachments still held.
  @override
  void dispose() {
    _disposed = true;
    for (final attachment in _attachments) {
      _deleteIfOwned(attachment.file, ownsFile: attachment.ownsFile);
    }
    super.dispose();
  }
}
