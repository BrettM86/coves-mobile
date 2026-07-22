import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Tests for bearer token redaction in CovesApiService debug logs.
///
/// kDebugMode is true under `flutter test`, so the LogInterceptor added in
/// the CovesApiService constructor is active. debugPrint is swapped for a
/// capturing closure so every log line a real mocked request produces can
/// be asserted on (restored in tearDown).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Contains '!' — a character outside the old regex charset — to pin the
  // greedy non-whitespace match (the old pattern leaked the token tail).
  const token = 'abc!def.secret~token';

  group('CovesApiService - bearer token redaction', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;
    late List<String> logLines;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logLines = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logLines.add(message ?? '');
      };

      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      apiService = CovesApiService(
        dio: dio,
        tokenGetter: () async => token,
      );
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      apiService.dispose();
    });

    test('redacts the Authorization header in request logs', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, {'communities': [], 'cursor': null}),
        queryParameters: {'limit': 50, 'sort': 'popular'},
      );

      await apiService.listCommunities();

      final output = logLines.join('\n');
      expect(output, contains('Bearer [REDACTED]'));
      expect(output, isNot(contains(token)));
    });

    test('redacts bearer tokens echoed in error response data', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'debug echo: Bearer $token from upstream',
        }),
        queryParameters: {'limit': 50, 'sort': 'popular'},
      );

      await expectLater(
        apiService.listCommunities(),
        throwsA(isA<ServerException>()),
      );

      final output = logLines.join('\n');
      // The onError '   Data:' debugPrint and the LogInterceptor both log
      // the response body — neither may leak the raw token.
      expect(output, contains('Data:'));
      expect(output, contains('Bearer [REDACTED]'));
      expect(output, isNot(contains(token)));
    });
  });

  group('CovesApiService.redactBearerTokens', () {
    test('greedily redacts tokens with chars outside the old charset', () {
      expect(
        CovesApiService.redactBearerTokens('Authorization: Bearer $token'),
        'Authorization: Bearer [REDACTED]',
      );
    });

    test('is case-insensitive', () {
      expect(
        CovesApiService.redactBearerTokens('authorization: bearer $token'),
        'authorization: Bearer [REDACTED]',
      );
    });

    test('handles tab whitespace between scheme and token', () {
      expect(
        CovesApiService.redactBearerTokens('Bearer\t$token trailing'),
        'Bearer [REDACTED] trailing',
      );
    });

    test('redacts every occurrence in a line', () {
      expect(
        CovesApiService.redactBearerTokens('Bearer aaa!x and BEARER bbb!y'),
        'Bearer [REDACTED] and Bearer [REDACTED]',
      );
    });
  });
}
