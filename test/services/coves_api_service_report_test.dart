import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
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
    DioAdapter(dio: dio).onPost(
      '/xrpc/social.coves.admin.submitReport',
      (server) => server.reply(200, {'reportId': 7}),
      data: Matchers.any,
    );
    service = CovesApiService(
      dio: dio,
      tokenGetter: () async => null,
      sessionKeyOf: () => null,
    );
  });

  tearDown(() => service.dispose());

  test('submitReport limits the explanation to 1000 runes, not UTF-16 '
      'code units', () async {
    // '😀' is one rune but two UTF-16 code units
    final rows = <(String, String, bool)>[
      ('900 runes / 1100 code units', '${'a' * 700}${'😀' * 200}', true),
      ('1000 runes / 1200 code units', '${'a' * 800}${'😀' * 200}', true),
      ('1001 runes / 1201 code units', '${'a' * 801}${'😀' * 200}', false),
    ];

    for (final (name, explanation, accepted) in rows) {
      requests.clear();
      final outcome = await service
          .submitReport(
            targetUri: 'at://did:plc:author/social.coves.community.post/p1',
            reason: 'spam',
            explanation: explanation,
          )
          .then<Object>((reportId) => reportId, onError: (Object e) => e);
      if (accepted) {
        expect(outcome, 7, reason: name);
        expect(requests, hasLength(1), reason: name);
        expect(
          (requests.single.data as Map)['explanation'],
          explanation,
          reason: name,
        );
      } else {
        expect(outcome, isA<ApiException>(), reason: name);
        expect(requests, isEmpty, reason: name);
      }
    }
  });
}
