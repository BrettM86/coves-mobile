import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService.getViewerAuthority', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService service;
    late List<RequestOptions> requests;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      requests = [];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.next(options);
          },
        ),
      );
      adapter = DioAdapter(dio: dio);
      service = CovesApiService(dio: dio, tokenGetter: () async => null);
    });

    tearDown(() => service.dispose());

    test(
      'B1 GET parses the boolean authority and ignores extra fields',
      () async {
        var responseBody = <String, Object>{};
        adapter.onGet(
          '/xrpc/social.coves.actor.getViewerAuthority',
          (server) => server.replyCallback(200, (_) => responseBody),
        );
        for (final (body, expected) in [
          (<String, Object>{'instanceAdmin': true, 'extra': 1}, true),
          (<String, Object>{'instanceAdmin': false}, false),
        ]) {
          responseBody = body;

          final answer = await service.getViewerAuthority();
          expect(answer, expected);
          expect(requests, hasLength(1));
          expect(requests.single.method, 'GET');
          expect(
            requests.single.path,
            '/xrpc/social.coves.actor.getViewerAuthority',
          );
          expect(requests.single.queryParameters, isEmpty);
          requests.clear();
        }
      },
    );

    test('B2 401 maps to AuthenticationException', () async {
      adapter.onGet(
        '/xrpc/social.coves.actor.getViewerAuthority',
        (server) => server.reply(401, {
          'error': 'AuthRequired',
          'message': 'Sign in required',
        }),
      );

      await expectLater(
        service.getViewerAuthority(),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('B2 503 retains the ModerationUnavailable error code', () async {
      adapter.onGet(
        '/xrpc/social.coves.actor.getViewerAuthority',
        (server) => server.reply(503, {
          'error': 'ModerationUnavailable',
          'message': 'Moderation unavailable',
        }),
      );

      await expectLater(
        service.getViewerAuthority(),
        throwsA(
          isA<ServerException>().having(
            (error) => error.errorCode,
            'errorCode',
            'ModerationUnavailable',
          ),
        ),
      );
    });

    test('B2 malformed authority responses throw ApiException', () async {
      var responseBody = <String, Object>{};
      adapter.onGet(
        '/xrpc/social.coves.actor.getViewerAuthority',
        (server) => server.replyCallback(200, (_) => responseBody),
      );
      for (final body in [
        <String, Object>{},
        <String, Object>{'instanceAdmin': 'true'},
      ]) {
        responseBody = body;

        await expectLater(
          service.getViewerAuthority(),
          throwsA(isA<ApiException>()),
        );
      }
    });
  });
}
