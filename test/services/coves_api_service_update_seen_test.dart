import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B1 updateSeen posts the exact original seenAt JSON body', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.next(options);
        },
      ),
    );
    final adapter = DioAdapter(dio: dio);
    final service = CovesApiService(
      sessionKeyOf: () => null,
      dio: dio,
      tokenGetter: () async => null,
    );
    addTearDown(service.dispose);
    adapter.onPost(
      '/xrpc/social.coves.notification.updateSeen',
      (server) => server.reply(200, {}),
      data: Matchers.any,
    );

    await service.updateNotificationsSeen(
      seenAt: '2026-10-08T12:00:00.123456789Z',
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/xrpc/social.coves.notification.updateSeen');
    expect(requests.single.data, {'seenAt': '2026-10-08T12:00:00.123456789Z'});
  });
}
