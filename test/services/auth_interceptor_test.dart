import 'dart:async';

import 'package:coves_flutter/services/auth_interceptor.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/retry_interceptor.dart';
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
          sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
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
          sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
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
          sessionKeyOf: () => token == null
              ? null
              : (did: 'did:plc:test', sessionId: 'session-1'),
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
  group('P-C3 I1 automatic request session ownership', () {
    for (final phase in [
      'late401',
      'refresh',
      'token',
      'initial',
      'retry401',
    ]) {
      test('$phase cannot replay or sign out a replacement session', () async {
        if (phase == 'late401') {
          final control = _MutationTransport();
          addTearDown(control.service.dispose);
          control.adapter.answer = (index, _) async =>
              _preferencesReply(index == 0 ? 401 : 200);
          await control.service.putNotificationPreferences(mention: false);
          expect(control.adapter.sent.map((row) => row.authorization), [
            'Bearer token-A',
            'Bearer token-A-rotated',
          ]);
          expect(control.adapter.sent.last.body, {'mention': false});
          expect(control.key, (did: 'did:plc:A', sessionId: 'session-A'));
        }

        final transport = _MutationTransport();
        addTearDown(transport.service.dispose);
        final reachedBoundary = Completer<void>();
        final response = Completer<ResponseBody>();
        final refresh = Completer<bool>();
        final token = Completer<String?>();
        if (phase == 'initial' || phase == 'token') {
          var reads = 0;
          transport.readToken = () {
            reads++;
            if (reads == (phase == 'initial' ? 1 : 2)) {
              reachedBoundary.complete();
              return token.future;
            }
            return Future.value(transport.token);
          };
        }
        if (phase == 'refresh') {
          transport.refresh = () {
            reachedBoundary.complete();
            return refresh.future;
          };
        }
        transport.adapter.answer = (index, _) {
          if ((phase == 'late401' && index == 0) ||
              (phase == 'retry401' && index == 1)) {
            reachedBoundary.complete();
            return response.future;
          }
          return Future.value(
            _preferencesReply(index == 0 && phase != 'initial' ? 401 : 200),
          );
        };

        final outcome = transport.service
            .putNotificationPreferences(mention: false)
            .then<Object?>((_) => null, onError: (Object error) => error);
        await reachedBoundary.future;
        if (phase != 'initial') {
          expect(transport.adapter.sent.first.authorization, 'Bearer token-A');
          expect(transport.adapter.sent.first.body, {'mention': false});
        }
        // Initial-token coverage uses a NEW login by the SAME DID; a DID
        // guard alone would accept its replacement credentials.
        transport.key = (
          did: phase == 'initial' ? 'did:plc:A' : 'did:plc:B',
          sessionId: 'session-B',
        );
        final replacementKey = transport.key;
        transport.token = 'token-B';
        if (phase == 'initial' || phase == 'token') {
          token.complete('token-B');
        } else if (phase == 'refresh') {
          refresh.complete(true);
        } else {
          response.complete(_preferencesReply(401));
        }
        final failure = await outcome;

        expect(
          transport.adapter.sent.where(
            (row) => row.authorization == 'Bearer token-B',
          ),
          isEmpty,
          reason: 'A body must never reach the adapter with B credentials',
        );
        expect(
          transport.refreshedSessions,
          isNot(contains(replacementKey)),
          reason: 'old work must not refresh the replacement session',
        );
        expect(
          transport.signedOutSessions,
          isNot(contains(replacementKey)),
          reason: 'old retry401 must not sign out the replacement session',
        );
        expect(transport.key, replacementKey);
        expect(
          failure,
          isNotNull,
          reason: 'the obsolete operation must settle',
        );
      });
    }

    test('sendTimeout automatic retry cannot retokenize A body as B', () async {
      final control = _MutationTransport();
      addTearDown(control.service.dispose);
      final positiveBackoff = control.observeBackoff();
      control.adapter.answer = (index, options) async {
        if (index == 0) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.sendTimeout,
          );
        }
        return _preferencesReply(200);
      };
      final positive = control.service.putNotificationPreferences(
        mention: false,
      );
      await positiveBackoff.future;
      expect(control.adapter.sent.single.authorization, 'Bearer token-A');
      await positive;
      expect(control.adapter.sent, hasLength(2));
      expect(control.adapter.sent.last.authorization, 'Bearer token-A');
      expect(control.adapter.sent.last.body, {'mention': false});

      final transport = _MutationTransport();
      addTearDown(transport.service.dispose);
      final negativeBackoff = transport.observeBackoff();
      transport.adapter.answer = control.adapter.answer;
      var completed = false;
      final pending = transport.service
          .putNotificationPreferences(mention: false)
          .then<Object?>(
            (_) {
              completed = true;
              return null;
            },
            onError: (Object error) {
              completed = true;
              return error;
            },
          );
      await negativeBackoff.future;
      expect(transport.adapter.sent.single.authorization, 'Bearer token-A');
      expect(transport.adapter.sent.single.body, {'mention': false});
      expect(completed, isFalse);
      transport
        ..key = (did: 'did:plc:B', sessionId: 'session-B')
        ..token = 'token-B';
      final failure = await pending;
      expect(completed, isTrue, reason: 'automatic retry must finish');
      expect(
        transport.adapter.sent.where(
          (row) => row.authorization == 'Bearer token-B',
        ),
        isEmpty,
        reason: 'actual RetryInterceptor delay must retain A session ownership',
      );
      expect(failure, isNotNull);
      expect(transport.refreshedSessions, isEmpty);
      expect(transport.signedOutSessions, isEmpty);
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

ResponseBody _preferencesReply(int status) => ResponseBody.fromString(
  status == 200
      ? '{"postReply":true,"commentReply":true,"mention":false,"upvote":true}'
      : '{"error":"Unauthorized"}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _MutationTransport {
  _MutationTransport() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
    adapter = _MutationAdapter();
    dio.httpClientAdapter = adapter;
    service = CovesApiService(
      dio: dio,
      sessionKeyOf: () => key,
      tokenGetter: () => readToken?.call() ?? Future.value(token),
      tokenRefresher: () {
        refreshedSessions.add(key);
        if (refresh != null) {
          return refresh!();
        }
        if (key == (did: 'did:plc:A', sessionId: 'session-A')) {
          token = 'token-A-rotated';
        }
        return Future.value(true);
      },
      signOutHandler: () async {
        signedOutSessions.add(key);
        key = null;
        token = null;
      },
    );
  }

  Object? key = (did: 'did:plc:A', sessionId: 'session-A');
  String? token = 'token-A';
  Future<String?> Function()? readToken;
  Future<bool> Function()? refresh;
  final List<Object?> refreshedSessions = [];
  final List<Object?> signedOutSessions = [];
  late final Dio dio;
  late final CovesApiService service;
  late final _MutationAdapter adapter;

  Completer<void> observeBackoff() {
    final index = dio.interceptors.indexWhere(
      (item) => item is RetryInterceptor,
    );
    final original = dio.interceptors[index] as RetryInterceptor;
    final boundary = Completer<void>();
    dio.interceptors[index] = _ObservedRetryInterceptor(
      dio: original.dio,
      maxRetries: original.maxRetries,
      initialDelay: original.initialDelay,
      serviceName: original.serviceName,
      boundary: boundary,
    );
    return boundary;
  }
}

class _ObservedRetryInterceptor extends RetryInterceptor {
  _ObservedRetryInterceptor({
    required super.dio,
    required super.maxRetries,
    required super.initialDelay,
    required super.serviceName,
    required this.boundary,
  });

  final Completer<void> boundary;

  @override
  Future<void> onError(DioException error, ErrorInterceptorHandler handler) {
    // The real implementation runs synchronously through its first await:
    // the initial sendTimeout is now waiting in its unmodified backoff.
    final pending = super.onError(error, handler);
    if (!boundary.isCompleted) {
      boundary.complete();
    }
    return pending;
  }
}

class _MutationAdapter implements HttpClientAdapter {
  final sent = <({Object? authorization, Map<String, dynamic> body})>[];
  late Future<ResponseBody> Function(int index, RequestOptions options) answer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    expect(options.method, 'POST');
    expect(options.path, '/xrpc/social.coves.notification.putPreferences');
    final index = sent.length;
    sent.add((
      authorization: options.headers['Authorization'],
      body: Map<String, dynamic>.of(options.data as Map<String, dynamic>),
    ));
    return answer(index, options);
  }

  @override
  void close({bool force = false}) {}
}
