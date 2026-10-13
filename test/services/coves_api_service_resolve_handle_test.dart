import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService - resolveHandle', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      apiService = CovesApiService(
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    test('asks the AppView resolveHandle endpoint for the bare handle and '
        'returns its did', () async {
      // The route only matches this exact path and query, so a wrong path or
      // a sigil-prefixed handle surfaces as an unmatched-request error
      dioAdapter.onGet(
        '/xrpc/com.atproto.identity.resolveHandle',
        (server) => server.reply(200, {'did': 'did:plc:alice'}),
        queryParameters: {'handle': 'alice.coves.social'},
      );

      // An error is captured as the outcome so a failure reports what came
      // back (including an unmatched-route error) next to the expected did
      final outcome = await apiService
          .resolveHandle(handle: 'alice.coves.social')
          .then<Object>((did) => did, onError: (Object error) => error);
      expect(outcome, 'did:plc:alice');
    });

    test('a 200 whose did is missing or not a string throws an '
        'ApiException', () async {
      final malformedBodies = <String, Map<String, dynamic>>{
        'missing did': {},
        'numeric did': {'did': 42},
      };

      for (final MapEntry(key: label, value: body) in malformedBodies.entries) {
        dioAdapter.onGet(
          '/xrpc/com.atproto.identity.resolveHandle',
          (server) => server.reply(200, body),
          queryParameters: {'handle': 'alice.coves.social'},
        );

        await expectLater(
          apiService.resolveHandle(handle: 'alice.coves.social'),
          throwsA(isA<ApiException>()),
          reason: label,
        );
      }
    });
  });
}
