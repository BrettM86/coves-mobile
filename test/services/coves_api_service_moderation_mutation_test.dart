import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('moderation mutation service contract', () {
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

    test(
      'B5 GET subject state sends subject and retains XRPC errors',
      () async {
        const subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
        adapter.onGet(
          '/xrpc/social.coves.moderation.getSubjectState',
          (server) => server.reply(200, {
            'state': {
              'subject': subjectUri,
              'version': 'v3',
              'moderation': {'state': 'clear', 'contentLabels': []},
              'recordState': 'present',
            },
          }),
          queryParameters: {'subject': subjectUri},
        );

        final state = await service.getModerationSubjectState(subjectUri);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/xrpc/social.coves.moderation.getSubjectState',
        );
        expect(requests.single.queryParameters, {
          'subject': 'at://did:plc:author/social.coves.community.post/p1',
        });
        expect(
          state.subject,
          'at://did:plc:author/social.coves.community.post/p1',
        );
        expect(state.version, 'v3');

        for (final (status, errorCode, matcher) in [
          (
            403,
            'Forbidden',
            isA<ApiException>()
                .having((error) => error.statusCode, 'statusCode', 403)
                .having((error) => error.errorCode, 'errorCode', 'Forbidden'),
          ),
          (
            404,
            'SubjectNotFound',
            isA<NotFoundException>().having(
              (error) => error.errorCode,
              'errorCode',
              'SubjectNotFound',
            ),
          ),
          (
            503,
            'ModerationUnavailable',
            isA<ServerException>().having(
              (error) => error.errorCode,
              'errorCode',
              'ModerationUnavailable',
            ),
          ),
        ]) {
          adapter.onGet(
            '/xrpc/social.coves.moderation.getSubjectState',
            (server) => server.reply(status, {
              'error': errorCode,
              'message': 'Request failed',
            }),
            queryParameters: {'subject': subjectUri},
          );
          await expectLater(
            service.getModerationSubjectState(subjectUri),
            throwsA(matcher),
            reason: '$status $errorCode',
          );
        }
      },
    );

    test(
      'B6 removeContent posts exact body and parses result or conflict',
      () async {
        const subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
        final responseBody = <String, dynamic>{
          'outcome': 'applied',
          'state': {
            'subject': subjectUri,
            'version': 'v4',
            'moderation': {'state': 'removed', 'contentLabels': []},
            'recordState': 'present',
            'localRemoval': {
              'serviceDid': 'did:web:coves.social',
              'actionId': 'a1',
            },
          },
          'action': {
            'action': {
              'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
              'action': 'remove',
              'createdAt': '2026-10-01T12:00:00.000Z',
              'authorityDid': 'did:web:coves.social',
              'scope': {'kind': 'instance'},
              'origin': 'local',
            },
            'actorDid': 'did:plc:admin',
          },
        };
        adapter.onPost(
          '/xrpc/social.coves.moderation.removeContent',
          (server) => server.reply(200, responseBody),
          data: Matchers.any,
        );

        final applied = await service.removeContent(
          subject: const StrongRef(uri: subjectUri, cid: 'bafy-post'),
          expectedVersion: 'v3',
          idempotencyKey: 'remove-p1-1',
          reason: ModerationReason.harassment,
          privateNote: 'Review note',
        );
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(
          requests.single.path,
          '/xrpc/social.coves.moderation.removeContent',
        );
        expect(requests.single.data, {
          'subject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
          },
          'expectedVersion': 'v3',
          'idempotencyKey': 'remove-p1-1',
          'reason': 'social.coves.moderation.defs#reasonHarassment',
          'privateNote': 'Review note',
        });
        expect(applied.outcome, ModerationMutationOutcome.applied);
        expect(applied.state.version, 'v4');
        expect(
          applied.action?.action.ref,
          const ModerationActionRef(
            serviceDid: 'did:web:coves.social',
            actionId: 'a1',
          ),
        );

        requests.clear();
        adapter.onPost(
          '/xrpc/social.coves.moderation.removeContent',
          (server) => server.reply(200, {
            'outcome': 'unchanged',
            'state': {
              'subject': subjectUri,
              'version': 'v4',
              'moderation': {'state': 'removed', 'contentLabels': []},
              'recordState': 'present',
            },
          }),
          data: Matchers.any,
        );
        final unchanged = await service.removeContent(
          subject: const StrongRef(uri: subjectUri, cid: 'bafy-post'),
          expectedVersion: 'v4',
          idempotencyKey: 'remove-p1-2',
          reason: ModerationReason.moderatorDiscretion,
        );
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(
          requests.single.path,
          '/xrpc/social.coves.moderation.removeContent',
        );
        expect(requests.single.data, {
          'subject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
          },
          'expectedVersion': 'v4',
          'idempotencyKey': 'remove-p1-2',
          'reason': 'social.coves.moderation.defs#reasonModeratorDiscretion',
        });
        expect(unchanged.outcome, ModerationMutationOutcome.unchanged);

        adapter.onPost(
          '/xrpc/social.coves.moderation.removeContent',
          (server) => server.reply(400, {'error': 'StateConflict'}),
          data: Matchers.any,
        );
        await expectLater(
          service.removeContent(
            subject: const StrongRef(uri: subjectUri, cid: 'bafy-post'),
            expectedVersion: 'v3',
            idempotencyKey: 'remove-p1-3',
            reason: ModerationReason.harassment,
          ),
          throwsA(
            isA<ApiException>()
                .having((error) => error.statusCode, 'statusCode', 400)
                .having(
                  (error) => error.errorCode,
                  'errorCode',
                  'StateConflict',
                ),
          ),
        );
      },
    );

    test(
      'B6 removeContent rejects an unknown reason without sending a request',
      () async {
        await expectLater(
          service.removeContent(
            subject: const StrongRef(
              uri: 'at://did:plc:author/social.coves.community.post/p1',
              cid: 'bafy-post',
            ),
            expectedVersion: 'v3',
            idempotencyKey: 'remove-p1-unknown',
            reason: ModerationReason.unknown,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(requests, isEmpty);
      },
    );
  });
}
