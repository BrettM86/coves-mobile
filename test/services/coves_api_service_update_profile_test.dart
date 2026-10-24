import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('updateProfile sends the bio as "description", not "bio"', () async {
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
      '/xrpc/social.coves.actor.updateProfile',
      (server) => server.reply(200, {
        'uri': 'at://did:plc:abc123/social.coves.actor.profile/self',
        'cid': 'bafyreicid',
      }),
      data: Matchers.any,
    );

    await service.updateProfile(bio: 'New bio');

    final body = requests.single.data as Map<String, dynamic>;
    expect(body['description'], 'New bio');
    expect(body.containsKey('bio'), isFalse);
  });
}
