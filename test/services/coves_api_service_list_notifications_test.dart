import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService.listNotifications', () {
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

    for (final (name, cursor) in [
      ('without cursor', null),
      ('with cursor', 'abc'),
    ]) {
      test('B7 GET $name omits limit', () async {
        adapter.onGet(
          '/xrpc/social.coves.notification.listNotifications',
          (server) => server.reply(200, {'notifications': []}),
          queryParameters: cursor == null ? {} : {'cursor': 'abc'},
        );

        await service.listNotifications(cursor: cursor);

        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/xrpc/social.coves.notification.listNotifications',
        );
        expect(
          requests.single.queryParameters,
          cursor == null ? <String, dynamic>{} : {'cursor': 'abc'},
        );
        expect(requests.single.queryParameters, isNot(contains('limit')));
      });
    }

    test('B7 parses a notification row and page cursor', () async {
      adapter.onGet(
        '/xrpc/social.coves.notification.listNotifications',
        (server) => server.reply(200, {
          'notifications': [
            {
              'reason': 'postReply',
              'sortAt': '2026-10-08T12:00:00Z',
              'isRead': false,
              'rootPost': {
                'uri':
                    'at://did:plc:alice/social.coves.community.postv2/3kpost',
                'cid': 'bafy-post',
              },
              'record': {
                'uri':
                    'at://did:plc:bob/social.coves.community.comment/3kcomment',
                'cid': 'bafy-comment',
              },
              'author': {'did': 'did:plc:bob'},
            },
          ],
          'cursor': 'next-page',
        }),
      );

      final page = await service.listNotifications();

      expect(page, isA<NotificationPage>());
      expect(page.notifications, hasLength(1));
      expect(page.notifications.single.reason, NotificationReason.postReply);
      expect(
        page.notifications.single.rootPost.uri,
        'at://did:plc:alice/social.coves.community.postv2/3kpost',
      );
      expect(page.cursor, 'next-page');
    });

    for (final (name, body) in [
      ('missing notifications', <String, Object>{}),
      (
        'object notifications',
        <String, Object>{'notifications': <String, Object>{}},
      ),
    ]) {
      test('B7 $name throws ApiException', () async {
        adapter.onGet(
          '/xrpc/social.coves.notification.listNotifications',
          (server) => server.reply(200, body),
        );

        await expectLater(
          service.listNotifications(),
          throwsA(isA<ApiException>()),
        );
      });
    }
  });

  group('CovesApiService.listNotifications 401 refresh', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService service;
    late String token;
    late bool refreshSucceeds;
    late List<Map<String, dynamic>> requestHeaders;
    late List<String> signOuts;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      adapter = DioAdapter(dio: dio);
      token = 'expired-token';
      refreshSucceeds = true;
      requestHeaders = [];
      signOuts = [];
      service = CovesApiService(
        sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
        dio: dio,
        tokenGetter: () async => token,
        tokenRefresher: () async {
          if (refreshSucceeds) {
            token = 'refreshed-token';
          }
          return refreshSucceeds;
        },
        signOutHandler: () async => signOuts.add('signed out'),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestHeaders.add(Map<String, dynamic>.of(options.headers));
            handler.next(options);
          },
        ),
      );
    });

    tearDown(() => service.dispose());

    test(
      'B8 retries a 401 with refreshed Authorization and returns page',
      () async {
        adapter
          ..onGet(
            '/xrpc/social.coves.notification.listNotifications',
            (server) => server.reply(401, {'error': 'Unauthorized'}),
            headers: {'Authorization': 'Bearer expired-token'},
          )
          ..onGet(
            '/xrpc/social.coves.notification.listNotifications',
            (server) => server.reply(200, {
              'notifications': [],
              'cursor': 'after-refresh',
            }),
            headers: {'Authorization': 'Bearer refreshed-token'},
          );

        final page = await service.listNotifications();

        expect(requestHeaders.map((headers) => headers['Authorization']), [
          'Bearer expired-token',
          'Bearer refreshed-token',
        ]);
        expect(page.notifications, isEmpty);
        expect(page.cursor, 'after-refresh');
      },
    );

    test(
      'B8 failed refresh throws AuthenticationException without sign-out',
      () async {
        refreshSucceeds = false;
        adapter.onGet(
          '/xrpc/social.coves.notification.listNotifications',
          (server) => server.reply(401, {'error': 'Unauthorized'}),
          headers: {'Authorization': 'Bearer expired-token'},
        );

        await expectLater(
          service.listNotifications(),
          throwsA(isA<AuthenticationException>()),
        );
        expect(signOuts, isEmpty);
      },
    );
  });
}
