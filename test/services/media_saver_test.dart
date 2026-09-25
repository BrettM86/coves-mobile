import 'dart:async';
import 'dart:io' as io;

import 'package:coves_flutter/services/media_saver.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const _imageUrl = 'https://cdn.example.test/img/feed_fullsize/plain/abc@jpeg';

// Method names gal sends that would write to the photo library.
const _putMethods = {'putImageBytes', 'putImage'};

// Event recorded in the shared log when the cache manager is asked for a file.
const _downloadEvent = 'download';

/// Answers the 'gal' method channel the way the native plugin would.
///
/// Gal.putImageBytes calls requestAccess on the channel itself before
/// 'putImageBytes', so requestAccess answers stay stable across calls.
class _FakeGalChannel {
  _FakeGalChannel(this.events);

  /// Shared with the cache manager so tests can check call order across both.
  final List<String> events;
  bool hasAccessResult = false;
  bool requestAccessResult = false;
  final Map<String, String> errorCodeByMethod = {};

  /// Thrown from the handler as-is rather than as a [PlatformException], the
  /// way a channel with no native implementation fails.
  final Map<String, Exception> exceptionByMethod = {};
  final List<MethodCall> calls = [];

  List<MethodCall> get putCalls =>
      calls.where((call) => _putMethods.contains(call.method)).toList();

  List<MethodCall> get accessCalls => calls
      .where(
        (call) => call.method == 'hasAccess' || call.method == 'requestAccess',
      )
      .toList();

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    events.add(call.method);
    final exception = exceptionByMethod[call.method];
    if (exception != null) {
      throw exception;
    }
    final errorCode = errorCodeByMethod[call.method];
    if (errorCode != null) {
      throw PlatformException(code: errorCode, message: 'native failure');
    }
    switch (call.method) {
      case 'hasAccess':
        return hasAccessResult;
      case 'requestAccess':
        return requestAccessResult;
      default:
        return null;
    }
  }
}

class _FakeCacheManager extends Fake implements BaseCacheManager {
  _FakeCacheManager(this.events);

  final List<String> events;
  File? file;
  Exception? error;

  /// When set, downloads wait on this instead of answering immediately.
  Completer<File>? pendingDownload;
  final List<String> requestedUrls = [];

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    requestedUrls.add(url);
    events.add(_downloadEvent);
    final download = pendingDownload;
    if (download != null) {
      return download.future;
    }
    final pendingError = error;
    if (pendingError != null) {
      throw pendingError;
    }
    return file!;
  }
}

Matcher _throwsSaveFailure(MediaSaveFailure failure) => throwsA(
  isA<MediaSaveException>().having(
    (exception) => exception.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('gal');
  const fileSystem = LocalFileSystem();

  late List<String> events;
  late _FakeGalChannel gal;
  late _FakeCacheManager cacheManager;
  late io.Directory temporaryDirectory;
  late Uint8List imageBytes;
  late GalMediaSaver saver;

  setUp(() {
    events = [];
    gal = _FakeGalChannel(events);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, gal.handle);

    temporaryDirectory = io.Directory.systemTemp.createTempSync(
      'media_saver_test',
    );
    imageBytes = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, //
      0x49, 0x46, 0x00, 0x01, 0x7F, 0x80, 0x00, 0xFF, 0xD9,
    ]);
    final cachedFile = fileSystem.file(
      '${temporaryDirectory.path}/cached_image.jpg',
    )..writeAsBytesSync(imageBytes);

    cacheManager = _FakeCacheManager(events)..file = cachedFile;
    saver = GalMediaSaver(cacheManager: cacheManager);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('GalMediaSaver access', () {
    test('denied access request throws accessDenied without saving', () async {
      gal
        ..hasAccessResult = false
        ..requestAccessResult = false;

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.accessDenied),
      );
      expect(gal.putCalls, isEmpty);
      expect(
        cacheManager.requestedUrls,
        isEmpty,
        reason: 'permission is settled before anything is downloaded',
      );
    });

    // Gal.putImageBytes sends its own requestAccess after the download, so
    // only the calls before the download show what the saver itself asked.
    List<String> eventsBeforeDownload() =>
        events.takeWhile((event) => event != _downloadEvent).toList();

    test('granted access request saves the image', () async {
      gal
        ..hasAccessResult = false
        ..requestAccessResult = true;

      await saver.saveImage(_imageUrl);

      expect(eventsBeforeDownload(), [
        'hasAccess',
        'requestAccess',
      ], reason: 'the saver checks access, then asks for it, then downloads');
      expect(events, contains(_downloadEvent));
      expect(gal.putCalls, hasLength(1));
      expect(
        events.indexOf('putImageBytes'),
        greaterThan(events.indexOf(_downloadEvent)),
      );
    });

    test('existing access saves the image', () async {
      gal
        ..hasAccessResult = true
        ..requestAccessResult = true;

      await saver.saveImage(_imageUrl);

      expect(eventsBeforeDownload(), [
        'hasAccess',
      ], reason: 'existing access must not prompt with requestAccess');
      expect(events, contains(_downloadEvent));
      expect(gal.putCalls, hasLength(1));
    });
  });

  group('GalMediaSaver add-only camera roll save', () {
    test('puts exactly the cached bytes with no album', () async {
      gal
        ..hasAccessResult = false
        ..requestAccessResult = true;

      await saver.saveImage(_imageUrl);

      expect(cacheManager.requestedUrls, [_imageUrl]);
      expect(gal.putCalls, hasLength(1));
      final putCall = gal.putCalls.single;
      expect(putCall.method, 'putImageBytes');
      final arguments = putCall.arguments as Map<Object?, Object?>;
      expect(arguments['bytes'], orderedEquals(imageBytes));
      expect(arguments.containsKey('album'), isTrue);
      expect(arguments['album'], isNull);
    });

    test('asks for camera-roll access, never album access', () async {
      gal
        ..hasAccessResult = false
        ..requestAccessResult = true;

      await saver.saveImage(_imageUrl);

      expect(gal.accessCalls, isNotEmpty);
      for (final call in gal.accessCalls) {
        expect(call.arguments, {
          'toAlbum': false,
        }, reason: '${call.method} must request add-only access');
      }
      expect(gal.putCalls, hasLength(1));
    });
  });

  group('GalMediaSaver download failures', () {
    setUp(() {
      gal
        ..hasAccessResult = true
        ..requestAccessResult = true;
    });

    test('HTTP error from the cache manager throws downloadFailed', () async {
      cacheManager.error = HttpExceptionWithStatus(
        404,
        'Invalid statusCode: 404',
        uri: Uri.parse(_imageUrl),
      );

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.downloadFailed),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('offline cache manager throws downloadFailed', () async {
      cacheManager.error = const io.SocketException('Failed host lookup');

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.downloadFailed),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('unreadable cached file throws downloadFailed', () async {
      cacheManager.file = fileSystem.file(
        '${temporaryDirectory.path}/missing_image.jpg',
      );

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.downloadFailed),
      );
      expect(gal.putCalls, isEmpty);
    });

    testWidgets(
      'download that never finishes throws downloadFailed after 30 seconds',
      (tester) async {
        cacheManager.pendingDownload = Completer<File>();
        Object? outcome;
        var finished = false;
        unawaited(
          saver
              .saveImage(_imageUrl)
              .then<void>(
                (_) => outcome = 'completed without error',
                onError: (Object error) => outcome = error,
              )
              .whenComplete(() => finished = true),
        );

        await tester.pump(const Duration(seconds: 29));
        expect(cacheManager.requestedUrls, [_imageUrl]);
        expect(
          finished,
          isFalse,
          reason: 'a slow download is given the full 30 seconds',
        );

        await tester.pump(const Duration(seconds: 2));
        expect(
          finished,
          isTrue,
          reason: 'a download stuck past 30 seconds must end the save',
        );
        expect(
          outcome,
          isA<MediaSaveException>().having(
            (exception) => exception.failure,
            'failure',
            MediaSaveFailure.downloadFailed,
          ),
        );
        expect(gal.putCalls, isEmpty);
      },
    );
  });

  group('GalMediaSaver non-platform channel exceptions', () {
    setUp(() {
      gal
        ..hasAccessResult = true
        ..requestAccessResult = true;
    });

    test('missing plugin checking access throws saveFailed', () async {
      gal.exceptionByMethod['hasAccess'] = MissingPluginException(
        'No implementation found for method hasAccess on channel gal',
      );

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.saveFailed),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('missing plugin while saving throws saveFailed', () async {
      gal.exceptionByMethod['putImageBytes'] = MissingPluginException(
        'No implementation found for method putImageBytes on channel gal',
      );

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.saveFailed),
      );
      expect(gal.putCalls, hasLength(1));
    });
  });

  group('GalMediaSaver permission-stage plugin errors', () {
    test('ACCESS_DENIED checking access throws accessDenied', () async {
      gal.errorCodeByMethod['hasAccess'] = 'ACCESS_DENIED';

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.accessDenied),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('ACCESS_DENIED requesting access throws accessDenied', () async {
      gal.hasAccessResult = false;
      gal.errorCodeByMethod['requestAccess'] = 'ACCESS_DENIED';

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.accessDenied),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('UNEXPECTED checking access throws saveFailed', () async {
      gal.errorCodeByMethod['hasAccess'] = 'UNEXPECTED';

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.saveFailed),
      );
      expect(gal.putCalls, isEmpty);
    });

    test('unknown code requesting access throws saveFailed', () async {
      gal.hasAccessResult = false;
      gal.errorCodeByMethod['requestAccess'] = 'SOMETHING_NEW';

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.saveFailed),
      );
      expect(gal.putCalls, isEmpty);
    });
  });

  group('GalMediaSaver put errors', () {
    setUp(() {
      gal
        ..hasAccessResult = true
        ..requestAccessResult = true;
    });

    test('ACCESS_DENIED while saving throws accessDenied', () async {
      gal.errorCodeByMethod['putImageBytes'] = 'ACCESS_DENIED';

      await expectLater(
        saver.saveImage(_imageUrl),
        _throwsSaveFailure(MediaSaveFailure.accessDenied),
      );
      expect(gal.putCalls, hasLength(1));
    });

    for (final code in [
      'NOT_ENOUGH_SPACE',
      'NOT_SUPPORTED_FORMAT',
      'UNEXPECTED',
    ]) {
      test('$code while saving throws saveFailed', () async {
        gal.errorCodeByMethod['putImageBytes'] = code;

        await expectLater(
          saver.saveImage(_imageUrl),
          _throwsSaveFailure(MediaSaveFailure.saveFailed),
        );
        expect(gal.putCalls, hasLength(1));
      });
    }
  });
}
