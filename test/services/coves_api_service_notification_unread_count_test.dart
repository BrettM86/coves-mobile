import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService.getUnreadCount', () {
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
      service = CovesApiService(
        sessionKeyOf: () => null,
        dio: dio,
        tokenGetter: () async => null,
      );
    });

    tearDown(() => service.dispose());

    test('B1 GET returns the integer unread count', () async {
      adapter.onGet(
        '/xrpc/social.coves.notification.getUnreadCount',
        (server) => server.reply(200, {'count': 7}),
      );

      expect(await service.getUnreadCount(), 7);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.path,
        '/xrpc/social.coves.notification.getUnreadCount',
      );
    });

    for (final (name, body) in [
      ('missing count', <String, Object>{}),
      ('string count', <String, Object>{'count': '7'}),
      ('floating-point count', <String, Object>{'count': 7.0}),
    ]) {
      test('B1 $name throws ApiException', () async {
        adapter.onGet(
          '/xrpc/social.coves.notification.getUnreadCount',
          (server) => server.reply(200, body),
        );

        await expectLater(
          service.getUnreadCount(),
          throwsA(isA<ApiException>()),
        );
      });
    }

    test('B1 503 maps to ServerException', () async {
      adapter.onGet(
        '/xrpc/social.coves.notification.getUnreadCount',
        (server) => server.reply(503, {
          'error': 'NotificationsUnavailable',
          'message': 'Notifications unavailable',
        }),
      );

      await expectLater(
        service.getUnreadCount(),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
