import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
const _labelPath = '/xrpc/social.coves.moderation.labelContent';
const _retractPath = '/xrpc/social.coves.moderation.retractContentLabel';

Map<String, Object> _appliedResponse({
  required String version,
  required List<Map<String, String>> contentLabels,
}) => {
  'outcome': 'applied',
  'state': {
    'subject': _subjectUri,
    'version': version,
    'moderation': {'state': 'clear', 'contentLabels': contentLabels},
    'recordState': 'present',
  },
};

typedef _LabelRow = ({
  String name,
  Future<ModerationMutationResult> Function(CovesApiService service) send,
  String path,
  Map<String, Object> response,
  Map<String, Object> expectedBody,
  String expectedVersion,
  List<String> expectedContentLabels,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NSFW label service contract', () {
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

    final rows = <_LabelRow>[
      (
        name: 'labelContent with reason and private note',
        send: (service) => service.labelContent(
          subject: const StrongRef(uri: _subjectUri, cid: 'bafy-post'),
          expectedVersion: 'v3',
          idempotencyKey: 'label-p1-1',
          reason: ModerationReason.spam,
          privateNote: 'Graphic thumbnail',
        ),
        path: _labelPath,
        response: _appliedResponse(
          version: 'v4',
          contentLabels: [
            {'value': 'nsfw'},
          ],
        ),
        expectedBody: {
          'subject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
          },
          'labelValue': 'nsfw',
          'expectedVersion': 'v3',
          'idempotencyKey': 'label-p1-1',
          'reason': 'social.coves.moderation.defs#reasonSpam',
          'privateNote': 'Graphic thumbnail',
        },
        expectedVersion: 'v4',
        expectedContentLabels: ['nsfw'],
      ),
      (
        name: 'labelContent without reason or private note',
        send: (service) => service.labelContent(
          subject: const StrongRef(uri: _subjectUri, cid: 'bafy-post'),
          expectedVersion: 'v3',
          idempotencyKey: 'label-p1-2',
        ),
        path: _labelPath,
        response: _appliedResponse(
          version: 'v5',
          contentLabels: [
            {'value': 'nsfw'},
          ],
        ),
        expectedBody: {
          'subject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
          },
          'labelValue': 'nsfw',
          'expectedVersion': 'v3',
          'idempotencyKey': 'label-p1-2',
        },
        expectedVersion: 'v5',
        expectedContentLabels: ['nsfw'],
      ),
      (
        name:
            'retractContentLabel with reason, reviewed subject and private '
            'note',
        send: (service) => service.retractContentLabel(
          actionId: 'a1',
          expectedVersion: 'v6',
          idempotencyKey: 'retract-p1-1',
          reason: ModerationReason.moderatorDiscretion,
          reviewedSubject: const StrongRef(uri: _subjectUri, cid: 'bafy-edit'),
          privateNote: 'Label was a mistake',
        ),
        path: _retractPath,
        response: _appliedResponse(version: 'v7', contentLabels: []),
        expectedBody: {
          'actionId': 'a1',
          'expectedVersion': 'v6',
          'idempotencyKey': 'retract-p1-1',
          'reason': 'social.coves.moderation.defs#reasonModeratorDiscretion',
          'reviewedSubject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-edit',
          },
          'privateNote': 'Label was a mistake',
        },
        expectedVersion: 'v7',
        expectedContentLabels: [],
      ),
      (
        name:
            'retractContentLabel without reason, reviewed subject or private '
            'note',
        send: (service) => service.retractContentLabel(
          actionId: 'a1',
          expectedVersion: 'v6',
          idempotencyKey: 'retract-p1-2',
        ),
        path: _retractPath,
        response: _appliedResponse(version: 'v8', contentLabels: []),
        expectedBody: {
          'actionId': 'a1',
          'expectedVersion': 'v6',
          'idempotencyKey': 'retract-p1-2',
        },
        expectedVersion: 'v8',
        expectedContentLabels: [],
      ),
    ];

    for (final row in rows) {
      test('B1 ${row.name} posts the documented body '
          'and parses the result', () async {
        adapter.onPost(
          row.path,
          (server) => server.reply(200, row.response),
          data: Matchers.any,
        );

        final result = await row.send(service);

        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.path, row.path);
        expect(requests.single.data, row.expectedBody);
        expect(result.outcome, ModerationMutationOutcome.applied);
        expect(result.state.version, row.expectedVersion);
        expect(result.state.moderation.state, ModerationState.clear);
        expect(
          result.state.moderation.contentLabels.map((label) => label.value),
          row.expectedContentLabels,
        );
      });
    }
  });
}
