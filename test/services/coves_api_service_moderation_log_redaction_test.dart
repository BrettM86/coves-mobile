import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('moderation endpoint debug log redaction', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService service;
    late List<String> logLines;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logLines = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logLines.add(message ?? '');
      };

      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      adapter = DioAdapter(dio: dio);
      service = CovesApiService(
        sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
        dio: dio,
        tokenGetter: () async => 'SECRET-TOKEN-MARKER',
      );
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      service.dispose();
    });

    test('B7 mutation and other moderation paths log metadata only', () async {
      adapter.onGet(
        '/xrpc/social.coves.moderation.listAdminActions',
        (server) => server.reply(200, {'message': 'ADMIN-LIST-MARKER'}),
      );
      await dio.get('/xrpc/social.coves.moderation.listAdminActions');

      var output = logLines.join('\n');
      expect(output, contains('GET'));
      expect(output, contains('social.coves.moderation.listAdminActions'));
      expect(output, contains('200'));
      expect(output, isNot(contains('ADMIN-LIST-MARKER')));

      logLines.clear();
      const subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
      adapter.onPost(
        '/xrpc/social.coves.moderation.removeContent',
        (server) => server.reply(200, {
          'outcome': 'applied',
          'state': {
            'subject': subjectUri,
            'version': 'BODY-VERSION-MARKER',
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
            'privateNote': 'SECRET-NOTE-RESP',
            'privateSubject': {
              'uri': 'at://did:plc:author/social.coves.community.post/SECRET-SUBJECT',
              'cid': 'bafy-post',
            },
          },
        }),
        data: Matchers.any,
      );

      await service.removeContent(
        subject: const StrongRef(uri: subjectUri, cid: 'bafy-post'),
        expectedVersion: 'v3',
        idempotencyKey: 'BODY-KEY-MARKER',
        reason: ModerationReason.harassment,
        privateNote: 'SECRET-NOTE-REQ',
      );

      output = logLines.join('\n');
      expect(output, contains('POST'));
      expect(output, contains('social.coves.moderation.removeContent'));
      expect(output, contains('200'));
      for (final marker in [
        'SECRET-NOTE-REQ',
        'SECRET-NOTE-RESP',
        'SECRET-SUBJECT',
        'BODY-KEY-MARKER',
        'BODY-VERSION-MARKER',
        'SECRET-TOKEN-MARKER',
      ]) {
        expect(output, isNot(contains(marker)), reason: marker);
      }
    });

    test('B8 errors omit bodies and query values except listActions', () async {
      adapter.onGet(
        '/xrpc/social.coves.moderation.listActions',
        (server) =>
            server.reply(200, {'actions': [], 'message': 'PUBLIC-LIST-MARKER'}),
        queryParameters: {'limit': 50},
      );
      await service.listModerationActions();
      expect(logLines.join('\n'), contains('PUBLIC-LIST-MARKER'));

      logLines.clear();
      final request = RequestOptions(
        path: '/xrpc/social.coves.moderation.listAdminActions',
        method: 'GET',
      );
      mapDioException(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 500,
            data: {'message': 'MAP-ERROR-MARKER'},
          ),
          type: DioExceptionType.badResponse,
        ),
        operation: 'list admin actions',
      );
      expect(logLines.join('\n'), isNot(contains('MAP-ERROR-MARKER')));

      logLines.clear();
      const subjectUri =
          'at://did:plc:author/social.coves.community.post/QUERY-MARKER';
      adapter.onGet(
        '/xrpc/social.coves.moderation.getSubjectState',
        (server) => server.reply(403, {
          'error': 'Forbidden',
          'message': 'SECRET-ERROR-BODY',
        }),
        queryParameters: {'subject': subjectUri},
      );
      await expectLater(
        service.getModerationSubjectState(subjectUri),
        throwsA(isA<ApiException>()),
      );

      final output = logLines.join('\n');
      expect(output, contains('GET'));
      expect(output, contains('social.coves.moderation.getSubjectState'));
      expect(output, contains('403'));
      expect(output, isNot(contains('QUERY-MARKER')));
      expect(output, isNot(contains('SECRET-ERROR-BODY')));
    });

    test('B8 successful subject state fetch omits the subject query', () async {
      const subjectUri =
          'at://did:plc:author/social.coves.community.post/QUERY-MARKER';
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

      await service.getModerationSubjectState(subjectUri);

      final output = logLines.join('\n');
      expect(output, contains('GET'));
      expect(output, contains('social.coves.moderation.getSubjectState'));
      expect(output, contains('200'));
      expect(output, isNot(contains('QUERY-MARKER')));
      expect(output, isNot(contains('SECRET-TOKEN-MARKER')));
    });
  });
}
