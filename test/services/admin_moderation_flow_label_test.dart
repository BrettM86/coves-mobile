import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/admin_moderation_flow.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/moderation_errors.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
const _subject = StrongRef(uri: _subjectUri, cid: 'bafy-post');
const _statePath = '/xrpc/social.coves.moderation.getSubjectState';
const _labelPath = '/xrpc/social.coves.moderation.labelContent';
const _retractPath = '/xrpc/social.coves.moderation.retractContentLabel';

const _graphicMediaLabel = {
  'value': 'graphic-media',
  'action': {'serviceDid': 'did:web:s0.coves.social', 'actionId': 'A0'},
};
const _nsfwLabel = {
  'value': 'nsfw',
  'action': {'serviceDid': 'did:web:s1.coves.social', 'actionId': 'A1'},
};

Map<String, Object> _state(
  String version, {
  String recordState = 'present',
  Map<String, String>? currentSubject,
  List<Map<String, Object>> localLabels = const [],
  List<String> contentLabels = const [],
}) => {
  'subject': _subjectUri,
  'version': version,
  'moderation': {
    'state': 'clear',
    'contentLabels': [
      for (final value in contentLabels) {'value': value},
    ],
  },
  'recordState': recordState,
  'currentSubject': ?currentSubject,
  'localLabels': localLabels,
};

/// The labeled post with an edited current version (cid bafy-edit).
Map<String, Object> _labeledState(
  String version, {
  String recordState = 'present',
}) => _state(
  version,
  recordState: recordState,
  currentSubject: recordState == 'present'
      ? const {'uri': _subjectUri, 'cid': 'bafy-edit'}
      : null,
  localLabels: [_graphicMediaLabel, _nsfwLabel],
  contentLabels: ['graphic-media', 'nsfw'],
);

Map<String, Object> _applied(String version, List<String> contentLabels) => {
  'outcome': 'applied',
  'state': _state(version, contentLabels: contentLabels),
};

DioException _lostResponse(String path) => DioException(
  requestOptions: RequestOptions(path: path, method: 'POST'),
  type: DioExceptionType.connectionError,
  message: 'Connection closed after send',
);

typedef _SubmissionRow = ({
  String name,
  Map<String, Object> state,
  Future<ModerationFlowResult> Function(AdminModerationFlow flow) submit,
  String path,
  Map<String, Object> response,
  Map<String, Object> expectedBody,
});

final _labelWithoutReason = (
  name: 'label with no reason',
  state: _state('v7'),
  submit: (AdminModerationFlow flow) => flow.submitLabel(subject: _subject),
  path: _labelPath,
  response: _applied('v8', ['nsfw']),
  expectedBody: <String, Object>{
    'subject': {'uri': _subjectUri, 'cid': 'bafy-post'},
    'labelValue': 'nsfw',
    'expectedVersion': 'v7',
    'idempotencyKey': 'key-1',
  },
);

final _labelWithReason = (
  name: 'label with reason and private note',
  state: _state('v7'),
  submit: (AdminModerationFlow flow) => flow.submitLabel(
    subject: _subject,
    reason: ModerationReason.harassment,
    privateNote: 'Graphic thumbnail',
  ),
  path: _labelPath,
  response: _applied('v8', ['nsfw']),
  expectedBody: <String, Object>{
    'subject': {'uri': _subjectUri, 'cid': 'bafy-post'},
    'labelValue': 'nsfw',
    'expectedVersion': 'v7',
    'idempotencyKey': 'key-1',
    'reason': 'social.coves.moderation.defs#reasonHarassment',
    'privateNote': 'Graphic thumbnail',
  },
);

final _retractPresentRecord = (
  name: 'retract on a present record',
  state: _labeledState('v9'),
  submit: (AdminModerationFlow flow) => flow.submitLabelRetraction(
    subject: _subject,
    reason: ModerationReason.ruleViolation,
    privateNote: 'Label was a mistake',
  ),
  path: _retractPath,
  response: _applied('v10', ['graphic-media']),
  expectedBody: <String, Object>{
    'actionId': 'A1',
    'expectedVersion': 'v9',
    'idempotencyKey': 'key-1',
    'reason': 'social.coves.moderation.defs#reasonRuleViolation',
    // The card's own subject, not the state's edited current version.
    'reviewedSubject': {'uri': _subjectUri, 'cid': 'bafy-post'},
    'privateNote': 'Label was a mistake',
  },
);

final _retractDeletedRecord = (
  name: 'retract on a deleted record',
  state: _labeledState('v9', recordState: 'deleted'),
  submit: (AdminModerationFlow flow) => flow.submitLabelRetraction(
    subject: _subject,
    reason: ModerationReason.ruleViolation,
    privateNote: 'Label was a mistake',
  ),
  path: _retractPath,
  response: _applied('v10', ['graphic-media']),
  expectedBody: <String, Object>{
    'actionId': 'A1',
    'expectedVersion': 'v9',
    'idempotencyKey': 'key-1',
    'reason': 'social.coves.moderation.defs#reasonRuleViolation',
    'privateNote': 'Label was a mistake',
  },
);

final _retractUnavailableRecord = (
  name: 'retract on an unavailable record',
  state: _labeledState('v9', recordState: 'unavailable'),
  submit: (AdminModerationFlow flow) => flow.submitLabelRetraction(
    subject: _subject,
    reason: ModerationReason.ruleViolation,
    privateNote: 'Label was a mistake',
  ),
  path: _retractPath,
  response: _applied('v10', ['graphic-media']),
  expectedBody: <String, Object>{
    'actionId': 'A1',
    'expectedVersion': 'v9',
    'idempotencyKey': 'key-1',
    'reason': 'social.coves.moderation.defs#reasonRuleViolation',
    'privateNote': 'Label was a mistake',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('admin moderation flow NSFW label and retraction', () {
    late FakeAuthProvider auth;
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService api;
    late AdminModerationFlow flow;
    late List<RequestOptions> requests;
    late ViewerAuthorityProvider authority;

    setUp(() async {
      auth = FakeAuthProvider(signedInDid: 'did:plc:admin');
      final authorityApi = MockCovesApiService();
      when(authorityApi.getViewerAuthority()).thenAnswer((_) async => true);
      authority = ViewerAuthorityProvider(
        apiService: authorityApi,
        authProvider: auth,
      );
      addTearDown(() {
        authority.dispose();
        auth.dispose();
      });
      await pumpEventQueue();

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
      api = CovesApiService(
        sessionKeyOf: () => null,
        dio: dio,
        tokenGetter: () async => null,
      );
      var nextKey = 0;
      flow = AdminModerationFlow(
        api,
        authority: authority,
        idempotencyKeyGenerator: () => 'key-${++nextKey}',
      );
    });

    tearDown(() => api.dispose());

    void answerState(Map<String, Object> state) {
      adapter.onGet(
        _statePath,
        (server) => server.reply(200, {'state': state}),
        queryParameters: {'subject': _subjectUri},
      );
    }

    List<RequestOptions> requestsTo(String path) =>
        requests.where((request) => request.path == path).toList();

    for (final row in <_SubmissionRow>[
      _labelWithoutReason,
      _labelWithReason,
      _retractPresentRecord,
      _retractDeletedRecord,
      _retractUnavailableRecord,
    ]) {
      test('B2/B3 ${row.name} sends the state version, a fresh key '
          'and the documented body', () async {
        answerState(row.state);
        adapter.onPost(
          row.path,
          (server) => server.reply(200, row.response),
          data: Matchers.any,
        );

        final result = await row.submit(flow);

        expect(requestsTo(_statePath), hasLength(1));
        expect(requestsTo(row.path).single.data, row.expectedBody);
        expect(result, isA<ModerationFlowSucceeded>());
        expect(
          (result as ModerationFlowSucceeded).result.outcome,
          ModerationMutationOutcome.applied,
        );
      });
    }

    for (final row in <_SubmissionRow>[
      _labelWithReason,
      _retractPresentRecord,
    ]) {
      test('B2/B3 ${row.name}: retry after a lost response re-sends '
          'the identical body without refetching state', () async {
        answerState(row.state);
        adapter.onPost(
          row.path,
          (server) => server.throws(503, _lostResponse(row.path)),
          data: Matchers.any,
        );

        final failed = await row.submit(flow);
        expect(failed, isA<ModerationFlowMutationFailed>());
        expect(
          (failed as ModerationFlowMutationFailed).error.recovery,
          ModerationRecovery.ambiguousRetry,
        );

        adapter.onPost(
          row.path,
          (server) => server.reply(200, row.response),
          data: Matchers.any,
        );
        final replayed = await flow.retry();

        expect(replayed, isA<ModerationFlowSucceeded>());
        expect(requestsTo(_statePath), hasLength(1));
        final posts = requestsTo(row.path);
        expect(posts, hasLength(2));
        expect(posts.first.data, row.expectedBody);
        expect(posts.last.data, row.expectedBody);
      });

      test('B2/B3 ${row.name}: an answer arriving after the session '
          'changed is a stale session', () async {
        answerState(row.state);
        adapter.onPost(
          row.path,
          (server) => server.reply(200, row.response),
          data: Matchers.any,
        );
        // The signed-in account changes while the mutation is in flight.
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path == row.path) {
                auth.setSignedInDid('did:plc:admin-b');
              }
              handler.next(options);
            },
          ),
        );

        final result = await row.submit(flow);

        expect(result, isA<ModerationFlowStaleSession>());
        expect(flow.retainedSubmission, isNull);
      });
    }

    test('B3 retract with no server nsfw label sends nothing '
        'and asks to reload the post', () async {
      answerState(
        _state(
          'v9',
          currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-edit'},
          localLabels: [_graphicMediaLabel],
          contentLabels: ['graphic-media'],
        ),
      );
      adapter.onPost(
        _retractPath,
        (server) => server.reply(200, _applied('v10', [])),
        data: Matchers.any,
      );

      final result = await flow.submitLabelRetraction(
        subject: _subject,
        reason: ModerationReason.spam,
      );

      expect(requestsTo(_retractPath), isEmpty);
      expect(result, isA<ModerationFlowPreflightFailed>());
      expect(
        (result as ModerationFlowPreflightFailed).error.recovery,
        ModerationRecovery.reloadSubject,
      );
    });

    test('B2 retract on a present record with no current subject '
        'reviews the card subject', () async {
      answerState(
        _state(
          'v9',
          localLabels: [_graphicMediaLabel, _nsfwLabel],
          contentLabels: ['graphic-media', 'nsfw'],
        ),
      );
      adapter.onPost(
        _retractPath,
        (server) => server.reply(200, _applied('v10', ['graphic-media'])),
        data: Matchers.any,
      );

      final result = await flow.submitLabelRetraction(subject: _subject);

      final retractions = requestsTo(_retractPath);
      expect(retractions, hasLength(1));
      expect(
        (retractions.single.data as Map<String, dynamic>)['reviewedSubject'],
        {'uri': _subjectUri, 'cid': 'bafy-post'},
      );
      expect(result, isA<ModerationFlowSucceeded>());
    });

    for (final row
        in <
          ({
            String name,
            Map<String, Object> state,
            ModerationErrorCode? expectedError,
            Map<String, Object>? expectedBody,
          })
        >[
          (
            name:
                'a present labeled record is an invalid subject '
                'and sends nothing',
            state: _labeledState('v9'),
            expectedError: ModerationErrorCode.invalidSubject,
            expectedBody: null,
          ),
          (
            name:
                'a present record without the nsfw label still asks to '
                'reload the post first and sends nothing',
            state: _state(
              'v9',
              currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-edit'},
              localLabels: [_graphicMediaLabel],
              contentLabels: ['graphic-media'],
            ),
            expectedError: ModerationErrorCode.decisionNotFound,
            expectedBody: null,
          ),
          (
            name: 'a deleted labeled record sends without a reviewed subject',
            state: _labeledState('v9', recordState: 'deleted'),
            expectedError: null,
            expectedBody: <String, Object>{
              'actionId': 'A1',
              'expectedVersion': 'v9',
              'idempotencyKey': 'key-1',
            },
          ),
        ]) {
      test('B3 retract with an empty card cid: ${row.name}', () async {
        answerState(row.state);
        adapter.onPost(
          _retractPath,
          (server) => server.reply(200, _applied('v10', ['graphic-media'])),
          data: Matchers.any,
        );

        final result = await flow.submitLabelRetraction(
          subject: const StrongRef(uri: _subjectUri, cid: ''),
        );

        final expectedBody = row.expectedBody;
        if (expectedBody == null) {
          expect(requestsTo(_retractPath), isEmpty);
          expect(result, isA<ModerationFlowPreflightFailed>());
          expect(
            (result as ModerationFlowPreflightFailed).error.code,
            row.expectedError,
          );
        } else {
          expect(requestsTo(_retractPath).single.data, expectedBody);
          expect(result, isA<ModerationFlowSucceeded>());
        }
      });
    }
  });
}
