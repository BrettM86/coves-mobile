import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('notification endpoint debug log redaction', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService service;
    late List<String> logLines;
    late DebugPrintCallback originalDebugPrint;
    String? refreshError;

    setUp(() {
      logLines = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logLines.add(message ?? '');
      };
      refreshError = null;
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      adapter = DioAdapter(dio: dio);
      service = CovesApiService(
        sessionKeyOf: () => null,
        dio: dio,
        tokenGetter: () async => null,
        tokenRefresher: () async {
          if (refreshError != null) {
            throw StateError(refreshError!);
          }
          return false;
        },
      );
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      service.dispose();
    });

    for (final (name, method, path, status, markers) in [
      (
        'list success',
        'GET',
        '/xrpc/social.coves.notification.listNotifications',
        '200',
        [
          'HANDLE-RESPONSE-MARKER',
          'DID-RESPONSE-MARKER',
          'EXCERPT-RESPONSE-MARKER',
          'CURSOR-RESPONSE-MARKER',
          'CURSOR-QUERY-MARKER',
        ],
      ),
      (
        'list error',
        'GET',
        '/xrpc/social.coves.notification.listNotifications',
        '400',
        [
          'HANDLE-ERROR-MARKER',
          'DID-ERROR-MARKER',
          'EXCERPT-ERROR-MARKER',
          'CURSOR-ERROR-MARKER',
          'CURSOR-ERROR-QUERY-MARKER',
        ],
      ),
      (
        'unread count',
        'GET',
        '/xrpc/social.coves.notification.getUnreadCount',
        '200',
        ['UNREAD-RESPONSE-MARKER'],
      ),
      (
        'update seen',
        'POST',
        '/xrpc/social.coves.notification.updateSeen',
        '200',
        ['SEEN-REQUEST-MARKER', 'SEEN-RESPONSE-MARKER'],
      ),
      // A user's like history is private to them, like their notifications.
      (
        'likes success',
        'GET',
        '/xrpc/social.coves.actor.getLikes',
        '200',
        [
          'LIKED-TITLE-RESPONSE-MARKER',
          'LIKED-URI-RESPONSE-MARKER',
          'LIKES-CURSOR-RESPONSE-MARKER',
          'LIKES-CURSOR-QUERY-MARKER',
        ],
      ),
      (
        'likes error',
        'GET',
        '/xrpc/social.coves.actor.getLikes',
        '400',
        ['LIKES-ERROR-MARKER', 'LIKES-CURSOR-ERROR-QUERY-MARKER'],
      ),
    ]) {
      test('B9 $name logs method, path and status without markers', () async {
        switch (name) {
          case 'list success':
            adapter.onGet(
              path,
              (server) => server.reply(200, {
                'notifications': [
                  {
                    'reason': 'mention',
                    'sortAt': '2026-10-08T12:00:00Z',
                    'isRead': false,
                    'rootPost': {
                      'uri': 'at://did:plc:alice/social.coves.community.postv2/3kpost',
                      'cid': 'bafy-post',
                    },
                    'record': {
                      'uri': 'at://did:plc:bob/social.coves.community.comment/3kcomment',
                      'cid': 'bafy-comment',
                      'excerpt': 'EXCERPT-RESPONSE-MARKER',
                    },
                    'author': {
                      'did': 'did:plc:DID-RESPONSE-MARKER',
                      'handle': 'HANDLE-RESPONSE-MARKER',
                    },
                  },
                ],
                'cursor': 'CURSOR-RESPONSE-MARKER',
              }),
              queryParameters: {'cursor': 'CURSOR-QUERY-MARKER'},
            );
            await service.listNotifications(cursor: 'CURSOR-QUERY-MARKER');
          case 'list error':
            adapter.onGet(
              path,
              (server) => server.reply(400, {
                'error': 'InvalidCursor',
                'message': 'CURSOR-ERROR-MARKER',
                'handle': 'HANDLE-ERROR-MARKER',
                'did': 'did:plc:DID-ERROR-MARKER',
                'excerpt': 'EXCERPT-ERROR-MARKER',
              }),
              queryParameters: {'cursor': 'CURSOR-ERROR-QUERY-MARKER'},
            );
            await expectLater(
              service.listNotifications(cursor: 'CURSOR-ERROR-QUERY-MARKER'),
              throwsA(isA<ApiException>()),
            );
          case 'unread count':
            adapter.onGet(
              path,
              (server) => server.reply(200, {
                'count': 7,
                'privateValue': 'UNREAD-RESPONSE-MARKER',
              }),
            );
            expect(await service.getUnreadCount(), 7);
          case 'update seen':
            adapter.onPost(
              path,
              (server) =>
                  server.reply(200, {'privateValue': 'SEEN-RESPONSE-MARKER'}),
              data: Matchers.any,
            );
            await dio.post(path, data: {'privateValue': 'SEEN-REQUEST-MARKER'});
          case 'likes success':
            adapter.onGet(
              path,
              (server) => server.reply(200, {
                'feed': [
                  {
                    r'$type': 'social.coves.actor.getLikes#likedPost',
                    'post': {
                      'uri': 'at://did:plc:community1/social.coves.community.post/LIKED-URI-RESPONSE-MARKER',
                      'cid': 'cid-liked',
                      'rkey': 'LIKED-URI-RESPONSE-MARKER',
                      'author': {
                        'did': 'did:plc:author1',
                        'handle': 'author.test',
                      },
                      'community': {
                        'did': 'did:plc:community1',
                        'name': 'testcommunity',
                      },
                      'record': {
                        'title': 'LIKED-TITLE-RESPONSE-MARKER',
                        'content': 'body',
                      },
                      'createdAt': '2025-06-01T12:00:00Z',
                      'indexedAt': '2025-06-01T12:00:01Z',
                      'stats': {
                        'upvotes': 1,
                        'downvotes': 0,
                        'score': 1,
                        'commentCount': 0,
                      },
                    },
                  },
                ],
                'cursor': 'LIKES-CURSOR-RESPONSE-MARKER',
              }),
              queryParameters: {
                'actor': 'did:plc:liker',
                'limit': 15,
                'cursor': 'LIKES-CURSOR-QUERY-MARKER',
              },
            );
            final likes = await service.getActorLikes(
              actor: 'did:plc:liker',
              cursor: 'LIKES-CURSOR-QUERY-MARKER',
            );
            expect(likes.feed, hasLength(1));
          case 'likes error':
            adapter.onGet(
              path,
              (server) => server.reply(400, {
                'error': 'InvalidCursor',
                'message': 'LIKES-ERROR-MARKER',
              }),
              queryParameters: {
                'actor': 'did:plc:liker',
                'limit': 15,
                'cursor': 'LIKES-CURSOR-ERROR-QUERY-MARKER',
              },
            );
            await expectLater(
              service.getActorLikes(
                actor: 'did:plc:liker',
                cursor: 'LIKES-CURSOR-ERROR-QUERY-MARKER',
              ),
              throwsA(isA<ApiException>()),
            );
        }

        final output = logLines.join('\n');
        for (final marker in markers) {
          expect(output, isNot(contains(marker)), reason: marker);
        }
        expect(output, contains(method));
        expect(output, contains(path));
        expect(output, contains(status));
      });
    }

    test(
      'B9 public discover GET still logs response body — regression guard',
      () async {
        adapter.onGet(
          '/xrpc/social.coves.feed.getDiscover',
          (server) => server.reply(200, {
            'feed': [],
            'message': 'PUBLIC-RESPONSE-MARKER',
          }),
          queryParameters: {'sort': 'hot', 'limit': 15},
        );

        await service.getDiscover();

        expect(logLines.join('\n'), contains('PUBLIC-RESPONSE-MARKER'));
      },
    );

    for (final (name, path, operation, marker) in [
      (
        'list connection error',
        '/xrpc/social.coves.notification.listNotifications',
        'notification',
        'M1-CONNECTION-MARKER',
      ),
      (
        'list refresher error',
        '/xrpc/social.coves.notification.listNotifications',
        'notification',
        'M2-REFRESH-MARKER',
      ),
      (
        'list parse error',
        '/xrpc/social.coves.notification.listNotifications',
        'notification',
        'Expected Map but got String',
      ),
      (
        'unread parse error',
        '/xrpc/social.coves.notification.getUnreadCount',
        'fetch unread notification count',
        'Expected Map but got String',
      ),
      (
        'likes parse error',
        '/xrpc/social.coves.actor.getLikes',
        'fetch actor likes',
        'Expected Map but got String',
      ),
      (
        'likes connection error',
        '/xrpc/social.coves.actor.getLikes',
        'fetch actor likes',
        'L1-CONNECTION-MARKER',
      ),
      (
        'likes refresher error',
        '/xrpc/social.coves.actor.getLikes',
        'fetch actor likes',
        'L2-REFRESH-MARKER',
      ),
    ]) {
      test('B10 $name omits diagnostic details', () async {
        switch (name) {
          case 'list connection error':
            dio.httpClientAdapter = _ConnectionErrorAdapter(marker);
            await expectLater(
              service.listNotifications(),
              throwsA(isA<NetworkException>()),
            );
          case 'list refresher error':
            refreshError = marker;
            adapter.onGet(
              path,
              (server) => server.reply(401, {'error': 'Unauthorized'}),
            );
            await expectLater(
              service.listNotifications(),
              throwsA(isA<AuthenticationException>()),
            );
          case 'list parse error':
            adapter.onGet(path, (server) => server.reply(200, 'not an object'));
            await expectLater(
              service.listNotifications(),
              throwsA(isA<ApiException>()),
            );
          case 'unread parse error':
            adapter.onGet(path, (server) => server.reply(200, 'not an object'));
            await expectLater(
              service.getUnreadCount(),
              throwsA(isA<ApiException>()),
            );
          case 'likes parse error':
            adapter.onGet(
              path,
              (server) => server.reply(200, 'not an object'),
              queryParameters: {'actor': 'did:plc:liker', 'limit': 15},
            );
            await expectLater(
              service.getActorLikes(actor: 'did:plc:liker'),
              throwsA(isA<ApiException>()),
            );
          case 'likes connection error':
            dio.httpClientAdapter = _ConnectionErrorAdapter(marker);
            await expectLater(
              service.getActorLikes(actor: 'did:plc:liker'),
              throwsA(isA<NetworkException>()),
            );
          case 'likes refresher error':
            refreshError = marker;
            adapter.onGet(
              path,
              (server) => server.reply(401, {'error': 'Unauthorized'}),
              queryParameters: {'actor': 'did:plc:liker', 'limit': 15},
            );
            await expectLater(
              service.getActorLikes(actor: 'did:plc:liker'),
              throwsA(isA<AuthenticationException>()),
            );
        }

        final output = logLines.join('\n');
        expect(output, contains('GET'));
        expect(output, contains(path));
        expect(output, contains(RegExp('Starting: [^\\n]*$operation')));
        if (name.endsWith('parse error')) {
          expect(
            logLines.any(
              (line) =>
                  line.contains(operation) && line.contains('FormatException'),
            ),
            isTrue,
          );
        }
        expect(output, isNot(contains(marker)));
      });
    }

    for (final (name, marker) in [
      ('connection error', 'M1-CONNECTION-MARKER'),
      ('refresher error', 'M2-REFRESH-MARKER'),
      ('parse error', 'Expected Map but got String'),
    ]) {
      test(
        'B10 public discover $name still logs details — regression guard',
        () async {
          const path = '/xrpc/social.coves.feed.getDiscover';
          switch (name) {
            case 'connection error':
              dio.httpClientAdapter = _ConnectionErrorAdapter(marker);
            case 'refresher error':
              refreshError = marker;
              adapter.onGet(
                path,
                (server) => server.reply(401, {'error': 'Unauthorized'}),
                queryParameters: {'sort': 'hot', 'limit': 15},
              );
            case 'parse error':
              adapter.onGet(
                path,
                (server) => server.reply(200, 'not an object'),
                queryParameters: {'sort': 'hot', 'limit': 15},
              );
          }

          await expectLater(
            service.getDiscover(),
            throwsA(isA<ApiException>()),
          );

          expect(logLines.join('\n'), contains(marker));
        },
      );
    }
  });
}

class _ConnectionErrorAdapter implements HttpClientAdapter {
  _ConnectionErrorAdapter(this.message);

  final String message;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
    message: message,
  );

  @override
  void close({bool force = false}) {}
}
