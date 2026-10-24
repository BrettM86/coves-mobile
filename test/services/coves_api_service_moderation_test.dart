import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService.listModerationActions', () {
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

    test('Filters F1 sends only supplied moderation filters', () async {
      const postUri = 'at://did:plc:author/social.coves.community.postv2/p1';
      final cases =
          <
            ({
              String? cursor,
              String? action,
              String? community,
              String? subject,
              Map<String, Object> expected,
            })
          >[
            (
              cursor: 'c1',
              action: 'remove',
              community: 'did:plc:c',
              subject: null,
              expected: {
                'limit': 50,
                'cursor': 'c1',
                'action': 'remove',
                'community': 'did:plc:c',
              },
            ),
            (
              cursor: null,
              action: null,
              community: null,
              subject: postUri,
              expected: {'limit': 50, 'subject': postUri},
            ),
          ];

      for (final row in cases) {
        // Match both the pre-feature and intended requests so an incorrect
        // query reaches the assertion rather than failing adapter dispatch.
        adapter
          ..onGet(
            '/xrpc/social.coves.moderation.listActions',
            (server) => server.reply(200, {'actions': []}),
            queryParameters: {
              'limit': 50,
              if (row.cursor != null) 'cursor': row.cursor,
            },
          )
          ..onGet(
            '/xrpc/social.coves.moderation.listActions',
            (server) => server.reply(200, {'actions': []}),
            queryParameters: row.expected,
          );

        await service.listModerationActions(
          cursor: row.cursor,
          action: row.action,
          community: row.community,
          subject: row.subject,
        );
        expect(requests.single.queryParameters, row.expected);
        requests.clear();
      }
    });

    test(
      'B3 signed-out GET sends cursor and default limit and parses the page',
      () async {
        adapter.onGet(
          '/xrpc/social.coves.moderation.listActions',
          (server) => server.reply(200, {
            'actions': [
              {
                'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
                'action': 'remove',
                'createdAt': '2026-10-01T12:00:00.000Z',
                'authorityDid': 'did:web:coves.social',
                'scope': {'kind': 'instance'},
                'origin': 'local',
              },
            ],
            'cursor': 'c2',
          }),
          queryParameters: {'limit': 50, 'cursor': 'c1'},
        );

        final page = await service.listModerationActions(cursor: 'c1');
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/xrpc/social.coves.moderation.listActions',
        );
        expect(requests.single.queryParameters, {'limit': 50, 'cursor': 'c1'});
        expect(page, isA<ModerationActionPage>());
        expect(page.actions, hasLength(1));
        expect(page.actions.single.ref.actionId, 'a1');
        expect(page.cursor, 'c2');
      },
    );

    for (final (label, limit, expectedLimit) in [
      ('omitted cursor', null, 50),
      ('limit above maximum', 500, 100),
      ('limit below minimum', 0, 1),
    ]) {
      test('B3 $label sends only the clamped limit', () async {
        adapter.onGet(
          '/xrpc/social.coves.moderation.listActions',
          (server) => server.reply(200, {'actions': []}),
          queryParameters: {'limit': expectedLimit},
        );

        if (limit == null) {
          await service.listModerationActions();
        } else {
          await service.listModerationActions(limit: limit);
        }
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/xrpc/social.coves.moderation.listActions',
        );
        expect(requests.single.queryParameters, {'limit': expectedLimit});
      });
    }

    test(
      'B4 503 preserves the ModerationUnavailable XRPC error code',
      () async {
        adapter.onGet(
          '/xrpc/social.coves.moderation.listActions',
          (server) => server.reply(503, {
            'error': 'ModerationUnavailable',
            'message': 'Moderation log unavailable',
          }),
          queryParameters: {'limit': 50},
        );

        await expectLater(
          service.listModerationActions(),
          throwsA(
            isA<ServerException>().having(
              (error) => error.errorCode,
              'errorCode',
              'ModerationUnavailable',
            ),
          ),
        );
      },
    );

    test('B4 400 preserves InvalidCursor and its status code', () async {
      adapter.onGet(
        '/xrpc/social.coves.moderation.listActions',
        (server) => server.reply(400, {
          'error': 'InvalidCursor',
          'message': 'Invalid cursor',
        }),
        queryParameters: {'limit': 50},
      );

      await expectLater(
        service.listModerationActions(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.errorCode, 'errorCode', 'InvalidCursor'),
        ),
      );
    });
  });

  group('CovesApiService.listAdminModerationActions', () {
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

    test('B1 sends the admin filters and parses private fields, NSFW kinds '
        'and the cursor', () async {
      const subject = 'at://did:plc:a/social.coves.community.postv2/3kabc';
      Map<String, Object?> publicAction(String actionId, String kind) => {
        'ref': {'serviceDid': 'did:web:coves.social', 'actionId': actionId},
        'action': kind,
        'createdAt': '2026-10-01T12:00:00.000Z',
        'authorityDid': 'did:web:coves.social',
        'scope': {'kind': 'instance'},
        'origin': 'local',
      };
      adapter.onGet(
        '/xrpc/social.coves.moderation.listAdminActions',
        (server) => server.reply(200, {
          'actions': [
            {
              'action': publicAction('a1', 'restore'),
              'actorDid': 'did:plc:top',
              'privateNote': 'Spam ring.',
              'privateSubject': {'uri': subject, 'cid': 'bafyprivate'},
            },
            {
              'action': {'action': 'remove'},
              'actorDid': 'did:plc:top',
            },
            {'action': publicAction('a2', 'label')},
            {'action': publicAction('a3', 'retract-label')},
          ],
          'cursor': 'c2',
        }),
        queryParameters: {
          'limit': 25,
          'cursor': 'c1',
          'action': 'restore',
          'community': 'did:plc:c',
          'subject': subject,
        },
      );

      final page = await service.listAdminModerationActions(
        cursor: 'c1',
        limit: 25,
        action: 'restore',
        community: 'did:plc:c',
        subject: subject,
      );

      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.path,
        '/xrpc/social.coves.moderation.listAdminActions',
      );
      expect(requests.single.queryParameters, {
        'limit': 25,
        'cursor': 'c1',
        'action': 'restore',
        'community': 'did:plc:c',
        'subject': subject,
      });
      expect(page, isA<AdminModerationActionPage>());
      expect(page.cursor, 'c2');
      expect(
        [
          for (final entry in page.actions)
            (
              entry.action.ref.serviceDid,
              entry.action.ref.actionId,
              entry.action.action,
            ),
        ],
        [
          ('did:web:coves.social', 'a1', ModerationActionKind.restore),
          ('did:web:coves.social', 'a2', ModerationActionKind.label),
          ('did:web:coves.social', 'a3', ModerationActionKind.retractLabel),
        ],
      );
      final first = page.actions.first;
      expect(first.actorDid, 'did:plc:top');
      expect(first.privateNote, 'Spam ring.');
      expect(first.privateSubject?.uri, subject);
      expect(first.privateSubject?.cid, 'bafyprivate');
    });
  });
}
