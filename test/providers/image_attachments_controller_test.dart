import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coves_flutter/models/image_attachment.dart';
import 'package:coves_flutter/models/picked_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/models/upload_image_response.dart';
import 'package:coves_flutter/providers/image_attachments_controller.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/image_fixtures.dart';

/// One call into the fake uploader, completed by the test.
class _UploadCall {
  _UploadCall(this.bytes, this.contentType, this.onSendProgress);

  final Uint8List bytes;
  final String contentType;
  final ProgressCallback? onSendProgress;
  final Completer<UploadImageResponse> completer = Completer();
}

/// Records every upload and leaves it in flight until the test completes it.
class _FakeUploader {
  final List<_UploadCall> calls = [];
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<UploadImageResponse> upload(
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) {
    final call = _UploadCall(bytes, contentType, onSendProgress);
    calls.add(call);
    _inFlight++;
    if (_inFlight > maxInFlight) {
      maxInFlight = _inFlight;
    }
    return call.completer.future.whenComplete(() => _inFlight--);
  }

  /// Completes call [index] with the blob `{'ref': 'blob-<tag>'}`.
  void succeed(int index, String tag) {
    calls[index].completer.complete(
      UploadImageResponse(
        blob: {'ref': 'blob-$tag'},
        mimeType: calls[index].contentType,
        size: calls[index].bytes.length,
        aspectRatio: EmbedAspectRatio(width: 4, height: 3),
      ),
    );
  }

  void fail(int index) {
    calls[index].completer.completeError(
      ServerException('PDS upload failed', statusCode: 502),
    );
  }
}

/// A picked image whose declared MIME type is deliberately wrong, so only
/// sniffing the bytes gives the right content type. The file need not exist.
PickedImage _picked(String name, List<int> header) => PickedImage(
  file: File('/picked/$name'),
  bytes: headerBytes(header),
  mimeType: 'image/heic',
);

/// Lets every pending microtask and zero-delay timer run.
Future<void> _settle() => pumpEventQueue();

/// [future]'s error, or null when it completes; registered up front so a
/// rejection is never unhandled.
Future<Object?> _outcome(Future<void> future) =>
    future.then<Object?>((_) => null, onError: (Object error) => error);

void main() {
  late _FakeUploader uploader;
  late ImageAttachmentsController controller;

  setUp(() {
    uploader = _FakeUploader();
    controller = ImageAttachmentsController(upload: uploader.upload);
  });

  tearDown(() => controller.dispose());

  test('uploadMissing runs at most two uploads at a time, in strip order, '
      'each with the content type sniffed from its bytes', () async {
    final picked = [
      _picked('1.jpg', png(11, 11)),
      _picked('2.png', jpeg(12, 12)),
      _picked('3.png', gif('GIF89a', 13, 13)),
      _picked('4.gif', webpVp8x(14, 14)),
      _picked('5.webp', png(15, 15)),
    ];
    controller.add(picked);

    final run = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(2));

    uploader.succeed(1, '2');
    await _settle();
    expect(uploader.calls, hasLength(3));

    uploader.succeed(0, '1');
    await _settle();
    expect(uploader.calls, hasLength(4));

    uploader
      ..succeed(2, '3')
      ..succeed(3, '4');
    await _settle();
    expect(uploader.calls, hasLength(5));

    uploader.succeed(4, '5');
    expect(await run, isNull);

    expect(uploader.maxInFlight, 2);
    expect(uploader.calls.map((call) => call.contentType).toList(), [
      'image/png',
      'image/jpeg',
      'image/gif',
      'image/webp',
      'image/png',
    ]);
    for (var i = 0; i < picked.length; i++) {
      expect(uploader.calls[i].bytes, picked[i].bytes, reason: 'upload $i');
    }
    expect(controller.attachments.map((a) => a.status).toList(), [
      for (var i = 0; i < 5; i++) ImageAttachmentStatus.uploaded,
    ]);
    expect(controller.embedImages.map((image) => image.blob).toList(), [
      {'ref': 'blob-1'},
      {'ref': 'blob-2'},
      {'ref': 'blob-3'},
      {'ref': 'blob-4'},
      {'ref': 'blob-5'},
    ]);
    expect(
      controller.embedImages
          .map((image) => (image.aspectRatio?.width, image.aspectRatio?.height))
          .toList(),
      [for (var i = 0; i < 5; i++) (4, 3)],
    );
  });

  test('upload progress lands on the matching attachment', () async {
    controller.add([
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
    ]);
    var notified = 0;
    controller.addListener(() => notified++);

    final run = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(2));

    notified = 0;
    uploader.calls[0].onSendProgress!(25, 100);
    uploader.calls[1].onSendProgress!(30, 40);

    expect(controller.attachments.map((a) => a.progress).toList(), [
      0.25,
      0.75,
    ]);
    expect(notified, greaterThan(0));

    uploader
      ..succeed(0, '1')
      ..succeed(1, '2');
    await run;
  });

  test('a failed upload rejects uploadMissing, keeps its error, and the next '
      'uploadMissing uploads only that attachment', () async {
    final picked = [
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
      _picked('3.png', png(13, 13)),
    ];
    controller.add(picked);

    final first = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(2));
    uploader
      ..succeed(0, '1')
      ..succeed(1, '2');
    await _settle();
    expect(uploader.calls, hasLength(3));
    uploader.fail(2);

    expect(await first, isA<ImageUploadFailedException>());
    expect(controller.attachments.map((a) => a.status).toList(), [
      ImageAttachmentStatus.uploaded,
      ImageAttachmentStatus.uploaded,
      ImageAttachmentStatus.failed,
    ]);
    expect(controller.attachments[2].error, isNotNull);
    expect(controller.attachments[2].error, isNotEmpty);

    final second = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(4));
    expect(uploader.calls[3].bytes, picked[2].bytes);
    uploader.succeed(3, '3');

    expect(await second, isNull);
    expect(controller.attachments[2].status, ImageAttachmentStatus.uploaded);
    expect(controller.attachments[2].error, isNull);
    expect(controller.embedImages.map((image) => image.blob).toList(), [
      {'ref': 'blob-1'},
      {'ref': 'blob-2'},
      {'ref': 'blob-3'},
    ]);
  });

  test('retry uploads only that failed attachment', () async {
    final picked = [
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
    ];
    controller.add(picked);

    final first = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(2));
    uploader
      ..succeed(0, '1')
      ..fail(1);
    expect(await first, isA<ImageUploadFailedException>());

    // A pending attachment added after the failure is not part of the retry
    final later = _picked('3.png', png(13, 13));
    controller.add([later]);

    final retried = _outcome(controller.retry(controller.attachments[1].id));
    await _settle();
    expect(uploader.calls, hasLength(3));
    expect(uploader.calls[2].bytes, picked[1].bytes);
    uploader.succeed(2, '2');

    expect(await retried, isNull);
    expect(controller.attachments.map((a) => a.status).toList(), [
      ImageAttachmentStatus.uploaded,
      ImageAttachmentStatus.uploaded,
      ImageAttachmentStatus.pending,
    ]);
  });

  test('a Retry tapped while uploadMissing runs shares its two upload slots '
      'and uploads that attachment once', () async {
    final picked = [
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
      _picked('3.png', png(13, 13)),
    ];
    controller.add(picked);
    final first = _outcome(controller.uploadMissing());
    await _settle();
    uploader
      ..fail(0)
      ..fail(1);
    await _settle();
    uploader.fail(2);
    expect(await first, isA<ImageUploadFailedException>());
    uploader.maxInFlight = 0;

    final second = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(5));
    final retried = _outcome(controller.retry(controller.attachments[2].id));
    await _settle();
    expect(uploader.calls, hasLength(5), reason: 'Retry waits for a slot');

    uploader
      ..succeed(3, '1')
      ..succeed(4, '2');
    await _settle();
    expect(uploader.calls, hasLength(6));
    expect(uploader.calls[5].bytes, picked[2].bytes);
    uploader.succeed(5, '3');

    expect(await retried, isNull);
    expect(await second, isNull);
    expect(uploader.calls, hasLength(6));
    expect(uploader.maxInFlight, 2);
    expect(controller.embedImages.map((image) => image.blob).toList(), [
      {'ref': 'blob-1'},
      {'ref': 'blob-2'},
      {'ref': 'blob-3'},
    ]);
  });

  test('a Retry in flight before uploadMissing is reused, and the batch '
      'waits for it within the two upload slots', () async {
    final picked = [
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
      _picked('3.png', png(13, 13)),
    ];
    controller.add([picked[0]]);
    final first = _outcome(controller.uploadMissing());
    await _settle();
    uploader.fail(0);
    expect(await first, isA<ImageUploadFailedException>());
    uploader.maxInFlight = 0;

    final retried = _outcome(controller.retry(controller.attachments[0].id));
    await _settle();
    expect(uploader.calls, hasLength(2));
    controller.add([picked[1], picked[2]]);

    final batch = _outcome(controller.uploadMissing());
    var batchDone = false;
    unawaited(batch.then((_) => batchDone = true));
    await _settle();
    expect(uploader.calls, hasLength(3), reason: 'the Retry holds one slot');
    expect(uploader.calls[2].bytes, picked[1].bytes);

    uploader.succeed(2, '2');
    await _settle();
    expect(uploader.calls, hasLength(4));
    expect(uploader.calls[3].bytes, picked[2].bytes);
    uploader.succeed(3, '3');
    await _settle();
    expect(batchDone, isFalse, reason: 'the batch waits for the Retry');

    uploader.succeed(1, '1');
    expect(await retried, isNull);
    expect(await batch, isNull);
    expect(uploader.calls, hasLength(4), reason: 'the retried image once');
    expect(uploader.maxInFlight, 2);
    expect(controller.embedImages.map((image) => image.blob).toList(), [
      {'ref': 'blob-1'},
      {'ref': 'blob-2'},
      {'ref': 'blob-3'},
    ]);
  });

  test('forgetUploads as the final upload completes rejects uploadMissing '
      'and starts no further upload', () async {
    controller.add([
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
    ]);
    var forgot = false;
    controller.addListener(() {
      if (!forgot &&
          controller.attachments.every(
            (attachment) => attachment.status == ImageAttachmentStatus.uploaded,
          )) {
        forgot = true;
        controller.forgetUploads();
      }
    });
    final run = _outcome(controller.uploadMissing());
    await _settle();
    uploader.succeed(0, '1');
    await _settle();
    uploader.succeed(1, '2');
    await _settle();

    expect(forgot, isTrue);
    expect(uploader.calls, hasLength(2), reason: 'no upload after forgetting');
    expect(await run, isA<ImageUploadFailedException>());

    final next = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(4));
    uploader
      ..succeed(2, 'b1')
      ..succeed(3, 'b2');
    expect(await next, isNull);
  });

  test('forgetUploads clears every blob and status, drops the results of '
      'uploads in flight, starts no queued upload, and the next uploadMissing '
      'uploads every image again', () async {
    final picked = [
      _picked('1.png', png(11, 11)),
      _picked('2.png', png(12, 12)),
      _picked('3.png', png(13, 13)),
      _picked('4.png', png(14, 14)),
    ];
    controller.add(picked);
    final first = _outcome(controller.uploadMissing());
    await _settle();
    uploader.succeed(0, '1');
    await _settle();
    expect(uploader.calls, hasLength(3));

    controller.forgetUploads();

    expect(controller.attachments.map((a) => a.blob).toList(), [
      null,
      null,
      null,
      null,
    ]);
    expect(controller.attachments.map((a) => a.aspectRatio).toList(), [
      null,
      null,
      null,
      null,
    ]);
    expect(controller.attachments.map((a) => a.status).toList(), [
      for (var i = 0; i < 4; i++) ImageAttachmentStatus.pending,
    ]);

    uploader
      ..succeed(1, '2')
      ..succeed(2, '3');
    await _settle();
    expect(uploader.calls, hasLength(3), reason: 'no queued upload starts');
    expect(controller.attachments.map((a) => a.blob).toList(), [
      null,
      null,
      null,
      null,
    ]);
    expect(await first, isA<ImageUploadFailedException>());

    final second = _outcome(controller.uploadMissing());
    await _settle();
    expect(uploader.calls, hasLength(5));
    expect(uploader.calls[3].bytes, picked[0].bytes);
    expect(uploader.calls[4].bytes, picked[1].bytes);
    uploader
      ..succeed(3, 'b1')
      ..succeed(4, 'b2');
    await _settle();
    uploader
      ..succeed(5, 'b3')
      ..succeed(6, 'b4');
    expect(await second, isNull);
    expect(controller.embedImages.map((image) => image.blob).toList(), [
      {'ref': 'blob-b1'},
      {'ref': 'blob-b2'},
      {'ref': 'blob-b3'},
      {'ref': 'blob-b4'},
    ]);
  });

  test('dispose starts no queued upload', () async {
    final disposedUploader = _FakeUploader();
    final disposed = ImageAttachmentsController(upload: disposedUploader.upload)
      ..add([
        _picked('1.png', png(11, 11)),
        _picked('2.png', png(12, 12)),
        _picked('3.png', png(13, 13)),
      ]);
    final run = _outcome(disposed.uploadMissing());
    await _settle();
    expect(disposedUploader.calls, hasLength(2));

    disposed.dispose();
    disposedUploader
      ..succeed(0, '1')
      ..succeed(1, '2');
    await _settle();

    expect(disposedUploader.calls, hasLength(2));
    await run;
  });

  test(
    'removing an uploaded attachment drops its blob from the embed',
    () async {
      controller.add([
        _picked('1.png', png(11, 11)),
        _picked('2.png', png(12, 12)),
      ]);

      final run = _outcome(controller.uploadMissing());
      await _settle();
      expect(uploader.calls, hasLength(2));
      uploader
        ..succeed(0, '1')
        ..succeed(1, '2');
      expect(await run, isNull);

      controller.remove(controller.attachments[0].id);

      expect(controller.attachments.map((a) => a.file.path).toList(), [
        '/picked/2.png',
      ]);
      expect(controller.embedImages.map((image) => image.blob).toList(), [
        {'ref': 'blob-2'},
      ]);
    },
  );

  test('with 7 attached, picking 3 adds only the first and the notice '
      'gives the limit of 8', () {
    final notice = controller.add([
      for (var i = 1; i <= 7; i++) _picked('$i.png', png(10 + i, 10 + i)),
    ]);
    expect(notice, isNull);
    expect(controller.remaining, 1);

    final overflowNotice = controller.add([
      _picked('8.png', png(18, 18)),
      _picked('9.png', png(19, 19)),
      _picked('10.png', png(20, 20)),
    ]);

    expect(controller.attachments, hasLength(8));
    expect(controller.attachments.last.file.path, '/picked/8.png');
    expect(controller.remaining, 0);
    expect(overflowNotice, contains('8'));
  });

  group('owned files', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('attachment_ownership');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    /// A picked PNG backed by a real file called [name] in [directory].
    PickedImage pickedFile(String name, {required bool ownsFile}) {
      final bytes = headerBytes(png(11, 11));
      final file = File('${directory.path}/$name')..writeAsBytesSync(bytes);
      return PickedImage(
        file: file,
        bytes: bytes,
        mimeType: 'image/png',
        ownsFile: ownsFile,
      );
    }

    /// Gives a file deletion started by the controller time to finish.
    Future<void> settleDeletes() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    final removeRows = <({String name, bool ownsFile, bool existsAfter})>[
      (
        name: 'an owned (converted) attachment removed: its file is deleted',
        ownsFile: true,
        existsAfter: false,
      ),
      (
        name: 'an unowned (picked as is) attachment removed: its file is kept',
        ownsFile: false,
        existsAfter: true,
      ),
    ];

    for (final row in removeRows) {
      test(row.name, () async {
        final picked = pickedFile('image.png', ownsFile: row.ownsFile);
        controller.add([picked]);

        controller.remove(controller.attachments.single.id);
        await settleDeletes();

        expect(
          File('${directory.path}/image.png').existsSync(),
          row.existsAfter,
        );
      });
    }

    test('dispose deletes the owned file of an attachment still held and '
        'keeps the unowned one', () async {
      ImageAttachmentsController(upload: uploader.upload)
        ..add([
          pickedFile('owned.png', ownsFile: true),
          pickedFile('unowned.png', ownsFile: false),
        ])
        ..dispose();
      await settleDeletes();

      expect(File('${directory.path}/owned.png').existsSync(), isFalse);
      expect(File('${directory.path}/unowned.png').existsSync(), isTrue);
    });

    test('handOff returns the held attachments in order and deletes nothing, '
        'and a later dispose deletes nothing', () async {
      final handing = ImageAttachmentsController(upload: uploader.upload)
        ..add([
          pickedFile('owned.png', ownsFile: true),
          pickedFile('unowned.png', ownsFile: false),
        ]);

      final handed = handing.handOff();
      await settleDeletes();

      expect(handed.map((attachment) => attachment.id).toList(), [
        'image-0',
        'image-1',
      ]);
      expect(handing.attachments, isEmpty);
      expect(File('${directory.path}/owned.png').existsSync(), isTrue);
      expect(File('${directory.path}/unowned.png').existsSync(), isTrue);

      handing.dispose();
      await settleDeletes();

      expect(File('${directory.path}/owned.png').existsSync(), isTrue);
      expect(File('${directory.path}/unowned.png').existsSync(), isTrue);
    });

    test('an owned picked image refused for the count limit (the 9th) has '
        'its file deleted', () async {
      controller.add([
        for (var i = 1; i <= 8; i++) _picked('$i.png', png(10 + i, 10 + i)),
        pickedFile('ninth.png', ownsFile: true),
      ]);
      await settleDeletes();

      expect(controller.attachments, hasLength(8));
      expect(File('${directory.path}/ninth.png').existsSync(), isFalse);
    });
  });

  group('alt text and order', () {
    /// Attaches images a, b and c and uploads them as blob-a, blob-b and
    /// blob-c.
    Future<void> attachAndUploadThree() async {
      controller.add([
        _picked('a.png', png(11, 11)),
        _picked('b.jpg', jpeg(12, 12)),
        _picked('c.gif', gif('GIF89a', 13, 13)),
      ]);
      final run = _outcome(controller.uploadMissing());
      await _settle();
      uploader
        ..succeed(0, 'a')
        ..succeed(1, 'b');
      await _settle();
      uploader.succeed(2, 'c');
      expect(await run, isNull);
    }

    test('the embed carries each trimmed alt and omits a blank one', () async {
      await attachAndUploadThree();
      final ids = [
        for (final attachment in controller.attachments) attachment.id,
      ];

      controller
        ..setAlt(ids[0], '  a cat  ')
        ..setAlt(ids[1], '')
        ..setAlt(ids[2], '   ');

      final images =
          ImagesEmbedInput(images: controller.embedImages).toJson()['images']
              as List<Object?>;
      final first = images[0]! as Map<String, Object?>;
      final second = images[1]! as Map<String, Object?>;
      final third = images[2]! as Map<String, Object?>;
      expect(first['alt'], 'a cat');
      expect(second.containsKey('alt'), isFalse);
      expect(third.containsKey('alt'), isFalse);
    });

    final reorderRows = <({String name, int from, int to, List<String> order})>[
      (
        name: 'reorder(0, 2) moves the first to the end',
        from: 0,
        to: 2,
        order: ['b', 'c', 'a'],
      ),
      (
        name: 'reorder(2, 0) moves the last to the front',
        from: 2,
        to: 0,
        order: ['c', 'a', 'b'],
      ),
    ];
    final filesByTag = {
      'a': '/picked/a.png',
      'b': '/picked/b.jpg',
      'c': '/picked/c.gif',
    };

    for (final row in reorderRows) {
      test(
        '${row.name}: attachments, embed blobs and listeners follow',
        () async {
          await attachAndUploadThree();
          var notified = false;
          controller
            ..addListener(() => notified = true)
            ..reorder(row.from, row.to);

          expect(
            controller.attachments
                .map((attachment) => attachment.file.path)
                .toList(),
            [for (final tag in row.order) filesByTag[tag]],
          );
          expect(controller.embedImages.map((image) => image.blob).toList(), [
            for (final tag in row.order) {'ref': 'blob-$tag'},
          ]);
          expect(notified, isTrue);
        },
      );
    }
  });

  group('B11 restore', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('attachment_restore');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    /// An uploaded attachment from a draft, backed by a real owned file
    /// called [name] in [directory].
    ImageAttachment draftAttachment(String id, String name) {
      final bytes = headerBytes(png(11, 11));
      return ImageAttachment(
        id: id,
        file: File('${directory.path}/$name')..writeAsBytesSync(bytes),
        bytes: bytes,
        mimeType: 'image/png',
        ownsFile: true,
        blob: {'ref': 'blob-$name'},
        aspectRatio: EmbedAspectRatio(width: 4, height: 3),
        status: ImageAttachmentStatus.uploaded,
        progress: 1,
        alt: 'alt for $name',
      );
    }

    test('B11 restored attachments keep blob, aspect ratio, alt and status, '
        'a later add gets a distinct id, and setAlt and remove act on each '
        'alone', () {
      controller.restore([
        draftAttachment('image-0', 'a.png'),
        draftAttachment('image-1', 'b.png'),
      ]);

      expect(controller.attachments, hasLength(2));
      final restored = controller.attachments.first;
      expect(restored.blob, {'ref': 'blob-a.png'});
      expect(restored.aspectRatio?.width, 4);
      expect(restored.aspectRatio?.height, 3);
      expect(restored.alt, 'alt for a.png');
      expect(restored.status, ImageAttachmentStatus.uploaded);

      controller.add([_picked('c.png', png(12, 12))]);
      final addedId = controller.attachments.last.id;
      expect(addedId, isNot(anyOf('image-0', 'image-1')));

      controller
        ..setAlt(addedId, 'new alt')
        ..setAlt('image-0', 'restored alt')
        ..remove('image-1');

      expect(
        [for (final attachment in controller.attachments) attachment.alt],
        ['restored alt', 'new alt'],
      );
    });

    test('B11 uploadMissing uploads only the image added after a restore and '
        'the embed keeps the restored blob first', () async {
      controller
        ..restore([draftAttachment('image-0', 'a.png')])
        ..add([_picked('c.png', png(12, 12))]);

      final run = _outcome(controller.uploadMissing());
      await _settle();
      expect(uploader.calls, hasLength(1));
      uploader.succeed(0, 'c');
      expect(await run, isNull);

      expect(controller.embedImages.map((image) => image.blob).toList(), [
        {'ref': 'blob-a.png'},
        {'ref': 'blob-c'},
      ]);
    });

    test('B11 attachments handed off mid-upload (a Retry and a first upload) '
        'come back not uploaded, ignore the late results, and upload in the '
        'new controller', () async {
      final previous = ImageAttachmentsController(upload: uploader.upload)
        ..add([_picked('1.png', png(11, 11)), _picked('2.png', png(12, 12))]);
      final firstRun = _outcome(previous.uploadMissing());
      await _settle();
      expect(uploader.calls, hasLength(2));
      uploader.fail(0);
      await _settle();
      // Attachment 1 is retried while attachment 2's first upload runs
      final retried = _outcome(previous.retry(previous.attachments[0].id));
      await _settle();
      expect(uploader.calls, hasLength(3));
      expect(previous.attachments.map((a) => a.status).toList(), [
        ImageAttachmentStatus.uploading,
        ImageAttachmentStatus.uploading,
      ]);

      final handed = previous.handOff();
      previous.dispose();
      uploader
        ..succeed(1, 'late-2')
        ..succeed(2, 'late-1');
      await _settle();
      expect(await retried, isNull);
      expect(await firstRun, isA<ImageUploadFailedException>());

      controller.restore(handed);
      for (final attachment in controller.attachments) {
        expect(attachment.status, ImageAttachmentStatus.pending);
        expect(attachment.progress, 0);
        expect(attachment.blob, isNull);
        expect(attachment.error, isNull);
      }

      final run = _outcome(controller.uploadMissing());
      await _settle();
      expect(uploader.calls, hasLength(5));
      uploader
        ..succeed(3, '1')
        ..succeed(4, '2');
      expect(await run, isNull);
      expect(controller.embedImages.map((image) => image.blob).toList(), [
        {'ref': 'blob-1'},
        {'ref': 'blob-2'},
      ]);
    });

    test(
      'B11 dispose deletes the owned file of a restored attachment',
      () async {
        ImageAttachmentsController(upload: uploader.upload)
          ..restore([draftAttachment('image-0', 'a.png')])
          ..dispose();

        final file = File('${directory.path}/a.png');
        for (var i = 0; i < 100 && file.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(file.existsSync(), isFalse);
      },
    );
  });
}
