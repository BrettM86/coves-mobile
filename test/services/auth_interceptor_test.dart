import 'package:coves_flutter/services/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Direct tests for the shared 401-refresh interceptor.
///
/// The per-service token-refresh tests cover the happy retry paths through
/// real services; this file pins the branches those tests can't reach.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('createAuthInterceptor', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late int refreshCount;
    late int signOutCount;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      refreshCount = 0;
      signOutCount = 0;
    });

    void addInterceptor({Future<bool> Function()? refresher}) {
      dio.interceptors.add(
        createAuthInterceptor(
          tokenGetter: () async => 'token-1',
          tokenRefresher: refresher ??
              () async {
                refreshCount++;
                return false;
              },
          signOutHandler: () async {
            signOutCount++;
          },
          serviceName: 'TestService',
          dio: dio,
        ),
      );
    }

    test(
        '401 from the refresh endpoint signs out without attempting '
        'a refresh (no infinite loop)', () async {
      addInterceptor();
      dioAdapter.onPost(
        '/oauth/refresh',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      await expectLater(
        dio.post<Map<String, dynamic>>('/oauth/refresh'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCount, 0);
      expect(signOutCount, 1);
    });

    test(
        'an Error thrown by the refresher propagates the original 401 '
        'without signing out', () async {
      // The interceptor catches Object so a TypeError/StateError from the
      // auth provider cannot escape the async onError handler (which would
      // surface it as a misclassified network error). It must NOT sign out
      // either: the refresher owns that decision, and an internal error is
      // not evidence the session is dead.
      addInterceptor(
        refresher: () async => throw StateError('auth provider broken'),
      );
      dioAdapter.onGet(
        '/xrpc/test.endpoint',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/xrpc/test.endpoint'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      expect(signOutCount, 0);
    });
  });
}
