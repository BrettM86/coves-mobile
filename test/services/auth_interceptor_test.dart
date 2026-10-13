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
          tokenRefresher:
              refresher ??
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

    test('401 from the refresh endpoint signs out without attempting '
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

    test('an Error thrown by the refresher propagates the original 401 '
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

    test('a non-401 failure on the post-refresh retry reaches the caller '
        'instead of the original 401', () async {
      final adapter = _SequencedAdapter([
        (401, '{"error":"Unauthorized"}'),
        (500, '{"error":"InternalServerError"}'),
      ]);
      dio.httpClientAdapter = adapter;
      var token = 'token-old';
      var signOutCount = 0;
      dio.interceptors.add(
        createAuthInterceptor(
          tokenGetter: () async => token,
          tokenRefresher: () async {
            token = 'token-new';
            return true;
          },
          signOutHandler: () async {
            signOutCount++;
          },
          serviceName: 'TestService',
          dio: dio,
        ),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/xrpc/test.endpoint'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
      expect(signOutCount, 0);
    });

    test('a re-sent request made while signed out carries no Authorization '
        'header from the previous account', () async {
      final adapter = _SequencedAdapter([(200, '{}'), (200, '{}')]);
      dio.httpClientAdapter = adapter;
      String? token = 'token-A';
      dio.interceptors.add(
        createAuthInterceptor(
          tokenGetter: () async => token,
          tokenRefresher: () async => false,
          signOutHandler: () async {},
          serviceName: 'TestService',
          dio: dio,
        ),
      );

      // First send as account A; its RequestOptions now carry token-A, as
      // the options RetryInterceptor re-sends via dio.fetch would.
      final first = await dio.get<Map<String, dynamic>>('/xrpc/test.endpoint');
      expect(adapter.sentHeaders[0]['Authorization'], 'Bearer token-A');

      // Sign out, then re-send the same options.
      token = null;
      expect(first.requestOptions.headers['Authorization'], 'Bearer token-A');
      await dio.fetch<Map<String, dynamic>>(first.requestOptions);

      expect(adapter.sentHeaders[1], isNot(contains('Authorization')));
    });
  });
}

/// Replies with the given (status, body) pairs in order, one per request,
/// and records each request's outgoing headers as they reach the wire.
class _SequencedAdapter implements HttpClientAdapter {
  _SequencedAdapter(this._replies);

  final List<(int, String)> _replies;
  final List<Map<String, dynamic>> sentHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sentHeaders.add(Map<String, dynamic>.of(options.headers));
    if (sentHeaders.length > _replies.length) {
      throw StateError(
        'unexpected request #${sentHeaders.length} to ${options.path}',
      );
    }
    final (status, body) = _replies[sentHeaders.length - 1];
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
