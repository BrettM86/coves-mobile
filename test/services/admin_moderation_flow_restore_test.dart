import 'package:coves_flutter/models/moderation_action.dart';
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
const _statePath = '/xrpc/social.coves.moderation.getSubjectState';
const _restorePath = '/xrpc/social.coves.moderation.restoreContent';

const _localRemoval = {
  'serviceDid': 'did:web:s1.coves.social',
  'actionId': 'R1',
};

Map<String, Object> _state(
  String version, {
  String moderationState = 'removed',
  String recordState = 'present',
  Map<String, String>? currentSubject,
  Map<String, String>? localRemoval,
}) => {
  'subject': _subjectUri,
  'version': version,
  'moderation': {'state': moderationState, 'contentLabels': <Object>[]},
  'recordState': recordState,
  'currentSubject': ?currentSubject,
  'localRemoval': ?localRemoval,
};

/// The removed post, still present, with an edited current version.
Map<String, Object> _removedPresentState() => _state(
  'v7',
  currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
  localRemoval: _localRemoval,
);

Map<String, Object> _mutation(
  Map<String, Object> state, {
  String outcome = 'applied',
}) => {'outcome': outcome, 'state': state};

final _restoredResponse = _mutation(
  _state(
    'v8',
    moderationState: 'clear',
    currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
  ),
);

DioException _lostResponse(String path) => DioException(
  requestOptions: RequestOptions(path: path, method: 'POST'),
  type: DioExceptionType.connectionError,
  message: 'Connection closed after send',
);

typedef _BodyRow = ({
  String name,
  Map<String, Object> state,
  ModerationReason reason,
  String? privateNote,
  Map<String, Object> expectedBody,
});

typedef _OutcomeRow = ({
  String name,
  Map<String, Object> response,
  RestoreOutcome expected,
});

/// `restoredActionId` is the actionId the restore request carries, or null
/// when no restore may be sent.
typedef _ExpectedRemovalRow = ({
  String name,
  Map<String, Object> state,
  String? restoredActionId,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('admin moderation flow restore', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService api;
    late AdminModerationFlow flow;
    late List<RequestOptions> requests;
    late ViewerAuthorityProvider authority;

    setUp(() async {
      final auth = FakeAuthProvider(signedInDid: 'did:plc:admin');
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
      api = CovesApiService(dio: dio, tokenGetter: () async => null);
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

    void answerRestore(Map<String, Object> response) {
      adapter.onPost(
        _restorePath,
        (server) => server.reply(200, response),
        data: Matchers.any,
      );
    }

    List<RequestOptions> requestsTo(String path) =>
        requests.where((request) => request.path == path).toList();

    final bodyRows = <_BodyRow>[
      (
        name: 'a present record with a current subject',
        state: _removedPresentState(),
        reason: ModerationReason.ruleViolation,
        privateNote: null,
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'key-1',
          'reason': 'social.coves.moderation.defs#reasonRuleViolation',
          'reviewedSubject': {'uri': _subjectUri, 'cid': 'bafy-c2'},
        },
      ),
      (
        name: 'a deleted record with a private note',
        state: _state(
          'v7',
          recordState: 'deleted',
          localRemoval: _localRemoval,
        ),
        reason: ModerationReason.spam,
        privateNote: 'literal note',
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'key-1',
          'reason': 'social.coves.moderation.defs#reasonSpam',
          'privateNote': 'literal note',
        },
      ),
      (
        name: 'an unavailable record',
        state: _state(
          'v7',
          recordState: 'unavailable',
          localRemoval: _localRemoval,
        ),
        reason: ModerationReason.harassment,
        privateNote: null,
        expectedBody: {
          'actionId': 'R1',
          'expectedVersion': 'v7',
          'idempotencyKey': 'key-1',
          'reason': 'social.coves.moderation.defs#reasonHarassment',
        },
      ),
    ];

    for (final row in bodyRows) {
      test(
        'B3 restore on ${row.name} sends the removal action, '
        'the state version, the injected key and the documented body',
        () async {
          answerState(row.state);
          answerRestore(_restoredResponse);

          final result = await flow.submitRestore(
            subjectUri: _subjectUri,
            reason: row.reason,
            privateNote: row.privateNote,
          );

          expect(requestsTo(_restorePath).single.data, row.expectedBody);
          expect(result, isA<ModerationFlowSucceeded>());
        },
      );
    }

    test('B3 restore with no local removal sends nothing '
        'and reports not removed', () async {
      answerState(
        _state(
          'v7',
          moderationState: 'clear',
          currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
        ),
      );
      answerRestore(_restoredResponse);

      final result = await flow.submitRestore(
        subjectUri: _subjectUri,
        reason: ModerationReason.ruleViolation,
      );

      expect(requestsTo(_restorePath), isEmpty);
      expect(result, isA<ModerationFlowNotRemoved>());
      expect(restoreOutcomeOf(result), RestoreOutcome.notRemoved);
    });

    test('B3 restore on a present record with no current subject '
        'sends nothing and does not succeed', () async {
      answerState(_state('v7', localRemoval: _localRemoval));
      answerRestore(_restoredResponse);

      final result = await flow.submitRestore(
        subjectUri: _subjectUri,
        reason: ModerationReason.ruleViolation,
      );

      expect(requestsTo(_restorePath), isEmpty);
      expect(result, isNot(isA<ModerationFlowSucceeded>()));
      expect(restoreOutcomeOf(result), isNull);
    });

    test('B3 retry after a lost restore response re-sends the identical '
        'body without refetching state', () async {
      answerState(_removedPresentState());
      adapter.onPost(
        _restorePath,
        (server) => server.throws(503, _lostResponse(_restorePath)),
        data: Matchers.any,
      );

      final failed = await flow.submitRestore(
        subjectUri: _subjectUri,
        reason: ModerationReason.ruleViolation,
      );
      expect(failed, isA<ModerationFlowMutationFailed>());
      expect(
        (failed as ModerationFlowMutationFailed).error.recovery,
        ModerationRecovery.ambiguousRetry,
      );

      answerRestore(_restoredResponse);
      final replayed = await flow.retry();

      expect(replayed, isA<ModerationFlowSucceeded>());
      expect(requestsTo(_statePath), hasLength(1));
      const expectedBody = {
        'actionId': 'R1',
        'expectedVersion': 'v7',
        'idempotencyKey': 'key-1',
        'reason': 'social.coves.moderation.defs#reasonRuleViolation',
        'reviewedSubject': {'uri': _subjectUri, 'cid': 'bafy-c2'},
      };
      final posts = requestsTo(_restorePath);
      expect(posts, hasLength(2));
      expect(posts.first.data, expectedBody);
      expect(posts.last.data, expectedBody);
    });

    final outcomeRows = <_OutcomeRow>[
      (
        name: 'a deleted record',
        response: _mutation(
          _state('v8', moderationState: 'clear', recordState: 'deleted'),
        ),
        expected: RestoreOutcome.restoredButDeleted,
      ),
      (
        name: 'a present record whose answer still reads removed',
        response: _mutation(
          _state(
            'v8',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
          ),
        ),
        expected: RestoreOutcome.restored,
      ),
      (
        name: 'an unavailable record',
        response: _mutation(
          _state('v8', moderationState: 'clear', recordState: 'unavailable'),
        ),
        expected: RestoreOutcome.restoredButUnavailable,
      ),
      (
        name: 'a present and clear record',
        response: _restoredResponse,
        expected: RestoreOutcome.restored,
      ),
      (
        name: 'an unchanged answer on a present and clear record',
        response: _mutation(
          _state(
            'v7',
            moderationState: 'clear',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
          ),
          outcome: 'unchanged',
        ),
        expected: RestoreOutcome.restored,
      ),
      (
        name: 'a deleted record that is still removed',
        response: _mutation(_state('v8', recordState: 'deleted')),
        expected: RestoreOutcome.restoredButDeleted,
      ),
      (
        name: 'an unavailable record that is still removed',
        response: _mutation(_state('v8', recordState: 'unavailable')),
        expected: RestoreOutcome.restoredButUnavailable,
      ),
      (
        name: 'an unrecognized record state that still reads removed',
        response: _mutation(_state('v8', recordState: 'archived')),
        expected: RestoreOutcome.restored,
      ),
    ];

    for (final row in outcomeRows) {
      test('B4 restore answered with ${row.name} '
          'is ${row.expected.name}', () async {
        answerState(_removedPresentState());
        answerRestore(row.response);

        final result = await flow.submitRestore(
          subjectUri: _subjectUri,
          reason: ModerationReason.ruleViolation,
        );

        expect(result, isA<ModerationFlowSucceeded>());
        expect(restoreOutcomeOf(result), row.expected);
      });
    }

    group('B1 restore of an expected removal', () {
      const expectedRemoval = ModerationActionRef(
        serviceDid: 'did:web:s1.coves.social',
        actionId: 'R1',
      );

      final rows = <_ExpectedRemovalRow>[
        (
          name: 'the same removal (S1, R1)',
          state: _state(
            'v7',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
            localRemoval: const {
              'serviceDid': 'did:web:s1.coves.social',
              'actionId': 'R1',
            },
          ),
          restoredActionId: 'R1',
        ),
        (
          name: 'another action on the same service (S1, R2)',
          state: _state(
            'v7',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
            localRemoval: const {
              'serviceDid': 'did:web:s1.coves.social',
              'actionId': 'R2',
            },
          ),
          restoredActionId: null,
        ),
        (
          name: 'the same action id on another service (S2, R1)',
          state: _state(
            'v7',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
            localRemoval: const {
              'serviceDid': 'did:web:s2.coves.social',
              'actionId': 'R1',
            },
          ),
          restoredActionId: null,
        ),
        (
          name: 'no local removal',
          state: _state(
            'v7',
            moderationState: 'clear',
            currentSubject: const {'uri': _subjectUri, 'cid': 'bafy-c2'},
          ),
          restoredActionId: null,
        ),
      ];

      for (final row in rows) {
        test('when the subject state has ${row.name}', () async {
          answerState(row.state);
          answerRestore(_restoredResponse);

          final result = await flow.submitRestore(
            subjectUri: _subjectUri,
            reason: ModerationReason.ruleViolation,
            expectedRemoval: expectedRemoval,
          );

          final restoreRequests = requestsTo(_restorePath);
          final restoredActionId = row.restoredActionId;
          if (restoredActionId == null) {
            expect(restoreRequests, isEmpty);
            expect(result, isA<ModerationFlowRemovalNoLongerActive>());
          } else {
            expect(
              (restoreRequests.single.data as Map)['actionId'],
              restoredActionId,
            );
            expect(result, isA<ModerationFlowSucceeded>());
          }
        });
      }
    });
  });
}
