import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
const _restorePath = '/xrpc/social.coves.moderation.restoreContent';

const _appliedResponse = <String, Object>{
  'outcome': 'applied',
  'state': {
    'subject': _subjectUri,
    'version': 'v8',
    'moderation': {'state': 'clear', 'contentLabels': <Object>[]},
    'recordState': 'present',
  },
};

typedef _RestoreRow = ({
  String name,
  StrongRef? reviewedSubject,
  String? privateNote,
  Map<String, Object> expectedBody,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restoreContent service contract', () {
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
      service = CovesApiService(dio: dio, tokenGetter: () async => null);
    });

    tearDown(() => service.dispose());

    final rows = <_RestoreRow>[
      (
        name: 'with reviewed subject and private note',
        reviewedSubject: const StrongRef(uri: _subjectUri, cid: 'bafy-edit'),
        privateNote: 'Removal was a mistake',
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'restore-p1-1',
          'reason': 'social.coves.moderation.defs#reasonRuleViolation',
          'reviewedSubject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-edit',
          },
          'privateNote': 'Removal was a mistake',
        },
      ),
      (
        name: 'with reviewed subject only',
        reviewedSubject: const StrongRef(uri: _subjectUri, cid: 'bafy-edit'),
        privateNote: null,
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'restore-p1-1',
          'reason': 'social.coves.moderation.defs#reasonRuleViolation',
          'reviewedSubject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-edit',
          },
        },
      ),
      (
        name: 'with private note only',
        reviewedSubject: null,
        privateNote: 'Removal was a mistake',
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'restore-p1-1',
          'reason': 'social.coves.moderation.defs#reasonRuleViolation',
          'privateNote': 'Removal was a mistake',
        },
      ),
      (
        name: 'without reviewed subject or private note',
        reviewedSubject: null,
        privateNote: null,
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'restore-p1-1',
          'reason': 'social.coves.moderation.defs#reasonRuleViolation',
        },
      ),
    ];

    for (final row in rows) {
      test('B2 restoreContent ${row.name} posts the documented body '
          'and parses the result', () async {
        adapter.onPost(
          _restorePath,
          (server) => server.reply(200, _appliedResponse),
          data: Matchers.any,
        );

        final result = await service.restoreContent(
          actionId: 'R1',
          expectedVersion: 'v7',
          idempotencyKey: 'restore-p1-1',
          reason: ModerationReason.ruleViolation,
          reviewedSubject: row.reviewedSubject,
          privateNote: row.privateNote,
        );

        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.path, _restorePath);
        expect(requests.single.data, row.expectedBody);
        expect(result.outcome, ModerationMutationOutcome.applied);
        expect(result.state.version, 'v8');
        expect(result.state.moderation.state, ModerationState.clear);
        expect(result.state.recordState, ModerationRecordState.present);
      });
    }
  });
}
