import 'dart:convert';

import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/coves_http.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Tests for CovesApiService.uploadImage (PRD_IMAGES_MOBILE §3.1).
///
/// The Dio is the production one from [createCovesDio], so the shared 30 s
/// receive timeout and the JSON default content type are real. Requests go
/// through [_RecordingAdapter], which records every request's options and
/// the bytes actually streamed, then answers from a [DioAdapter].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uploadPath = '/xrpc/social.coves.media.uploadImage';

  // A PNG signature, distinctive bytes no log line would contain by
  // accident, and an ASCII marker that would show up in any string form of
  // the body.
  const markerText = 'UPLOADBODYMARKER';
  final bodyBytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, //
    201, 202, 203, 204, 205, 206, 207, 208,
    ...ascii.encode(markerText),
    ...List<int>.filled(1234 - 8 - 8 - markerText.length, 0),
  ]);

  const blobLiteral = <String, dynamic>{
    r'$type': 'blob',
    'ref': {
      r'$link': 'bafkreigh2akiscaildcqabsyg3dfr6chu3fgpregiymsck7e7aqa4s52zy',
    },
    'mimeType': 'image/png',
    'size': 987,
  };

  Map<String, dynamic> uploadResponseJson() => <String, dynamic>{
    'blob': <String, dynamic>{
      r'$type': 'blob',
      'ref': <String, dynamic>{
        r'$link': 'bafkreigh2akiscaildcqabsyg3dfr6chu3fgpregiymsck7e7aqa4s52zy',
      },
      'mimeType': 'image/png',
      'size': 987,
    },
    'mimeType': 'image/png',
    'size': 987,
    'aspectRatio': <String, dynamic>{'width': 1200, 'height': 800},
  };

  late Dio dio;
  late DioAdapter dioAdapter;
  late _RecordingAdapter recorder;
  late CovesApiService apiService;
  late List<String> logLines;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logLines = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      logLines.add(message ?? '');
    };

    dio = createCovesDio(headers: {'Content-Type': 'application/json'});
    dioAdapter = DioAdapter(dio: dio);
    recorder = _RecordingAdapter(dioAdapter);
    dio.httpClientAdapter = recorder;
    apiService = CovesApiService(
      sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
      dio: dio,
      tokenGetter: () async => 'test-token',
    );
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    apiService.dispose();
  });

  group('CovesApiService.uploadImage', () {
    test('sends the raw bytes as image/png with 120 s send and receive '
        'timeouts, leaves other requests on the 30 s receive timeout, and '
        'parses the response with the blob unchanged', () async {
      dioAdapter
        ..onPost(
          uploadPath,
          (server) => server.reply(200, uploadResponseJson()),
          data: Matchers.any,
        )
        ..onGet(
          '/xrpc/social.coves.community.list',
          (server) => server.reply(200, {'communities': [], 'cursor': null}),
          queryParameters: {'limit': 50, 'sort': 'popular'},
        );

      final response = await apiService.uploadImage(bodyBytes, 'image/png');
      await apiService.listCommunities();

      final upload = recorder.requests.singleWhere(
        (request) => request.options.path == uploadPath,
      );
      expect(upload.options.method, 'POST');
      expect(upload.options.data, isA<Uint8List>());
      expect(upload.options.data, orderedEquals(bodyBytes));
      expect(upload.sentBytes, orderedEquals(bodyBytes));
      expect(upload.options.contentType, 'image/png');
      expect(upload.options.sendTimeout, const Duration(seconds: 120));
      expect(upload.options.receiveTimeout, const Duration(seconds: 120));

      final other = recorder.requests.singleWhere(
        (request) =>
            request.options.path == '/xrpc/social.coves.community.list',
      );
      expect(other.options.receiveTimeout, const Duration(seconds: 30));

      expect(response.blob, blobLiteral);
      expect(response.mimeType, 'image/png');
      expect(response.size, 987);
      expect(response.aspectRatio?.width, 1200);
      expect(response.aspectRatio?.height, 800);
    });

    test('a send timeout on the first attempt is retried with the same '
        'bytes and the call returns the parsed response', () async {
      recorder.failFirstAttemptWith = DioExceptionType.sendTimeout;
      dioAdapter.onPost(
        uploadPath,
        (server) => server.reply(200, uploadResponseJson()),
        data: Matchers.any,
      );

      final response = await apiService.uploadImage(bodyBytes, 'image/png');

      final uploads = recorder.requests
          .where((request) => request.options.path == uploadPath)
          .toList();
      expect(uploads, hasLength(2));
      expect(uploads[1].options.data, isA<Uint8List>());
      expect(uploads[1].options.data, orderedEquals(bodyBytes));
      expect(uploads[1].sentBytes, orderedEquals(bodyBytes));
      expect(response.blob, blobLiteral);
    });

    test('the debug log names the content type and length but none of the '
        'body bytes', () async {
      dioAdapter.onPost(
        uploadPath,
        (server) => server.reply(200, uploadResponseJson()),
        data: Matchers.any,
      );

      await apiService.uploadImage(bodyBytes, 'image/png');

      final output = logLines.join('\n');
      expect(output, contains('image/png'));
      expect(output, contains('1234'));
      // List form of the body (what Dio's LogInterceptor prints).
      expect(output, isNot(contains('137, 80, 78')));
      expect(output, isNot(contains('201, 202, 203')));
      // String forms of the body.
      expect(output, isNot(contains(markerText)));
      expect(output, isNot(contains(base64Encode(bodyBytes.sublist(0, 24)))));
    });
  });
}

class _RecordedRequest {
  _RecordedRequest(this.options, this.sentBytes);

  final RequestOptions options;
  final List<int>? sentBytes;
}

/// Records each request's options and streamed body, optionally failing the
/// first attempt with a transport error, then answers from [_inner].
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._inner);

  final DioAdapter _inner;
  final List<_RecordedRequest> requests = [];
  DioExceptionType? failFirstAttemptWith;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    List<int>? sentBytes;
    if (requestStream != null) {
      sentBytes = [];
      await requestStream.forEach(sentBytes.addAll);
    }
    requests.add(_RecordedRequest(options, sentBytes));

    final failure = failFirstAttemptWith;
    if (failure != null && requests.length == 1) {
      throw DioException(requestOptions: options, type: failure);
    }
    return _inner.fetch(options, null, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
