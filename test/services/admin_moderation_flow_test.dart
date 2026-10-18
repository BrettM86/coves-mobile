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
const _removePath = '/xrpc/social.coves.moderation.removeContent';

Map<String, Object> _state(String version, {String state = 'clear'}) => {
  'subject': _subjectUri,
  'version': version,
  'moderation': {'state': state, 'contentLabels': <String>[]},
  'recordState': 'present',
};

Map<String, Object> _applied(String version) => {
  'outcome': 'applied',
  'state': _state(version, state: 'removed'),
};

DioException _lostResponse(String path, {RequestOptions? requestOptions}) =>
    DioException(
      requestOptions:
          requestOptions ??
          RequestOptions(
            path: path,
            method: path == _statePath ? 'GET' : 'POST',
            queryParameters: path == _statePath
                ? {'subject': _subjectUri}
                : null,
          ),
      type: DioExceptionType.connectionError,
      message: 'Connection closed after send',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('admin moderation flow', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService api;
    late AdminModerationFlow flow;
    late List<RequestOptions> requests;
    late ViewerAuthorityProvider authority;

    setUp(() {
      // The flow belongs to a signed-in admin session for its whole life.
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

    test('U2 retry replays the exact lost removeContent request', () async {
      adapter
        ..onGet(
          _statePath,
          (server) => server.reply(200, {'state': _state('v7')}),
          queryParameters: {'subject': _subjectUri},
        )
        ..onPost(
          _removePath,
          (server) => server.throws(503, _lostResponse(_removePath)),
          data: Matchers.any,
        );

      final failed = await flow.submitRemoval(
        subject: _subject,
        reason: ModerationReason.spam,
        privateNote: 'Private context',
      );
      expect(failed, isA<ModerationFlowMutationFailed>());
      expect(
        (failed as ModerationFlowMutationFailed).error.code,
        ModerationErrorCode.network,
      );
      expect(flow.retainedSubmission?.idempotencyKey, 'key-1');
      final firstBody = requests
          .singleWhere((request) => request.path == _removePath)
          .data;
      expect(firstBody, {
        'subject': {'uri': _subjectUri, 'cid': 'bafy-post'},
        'expectedVersion': 'v7',
        'idempotencyKey': 'key-1',
        'reason': 'social.coves.moderation.defs#reasonSpam',
        'privateNote': 'Private context',
      });

      adapter.onPost(
        _removePath,
        (server) => server.reply(200, _applied('v8')),
        data: Matchers.any,
      );
      final replayed = await flow.retry();
      expect(
        requests.where((request) => request.path == _statePath),
        hasLength(1),
      );
      final posts = requests
          .where((request) => request.path == _removePath)
          .toList();
      expect(posts, hasLength(2));
      expect(posts.last.data, firstBody);
      expect(replayed, isA<ModerationFlowSucceeded>());
      expect(
        (replayed! as ModerationFlowSucceeded).result.outcome,
        ModerationMutationOutcome.applied,
      );
      expect(flow.retainedSubmission, isNull);
    });

    test('U3 new confirmations after abandonment or conflicts '
        'use fresh state and key', () async {
      for (final scenario in [
        'abandon',
        'idempotencyConflict',
        'stateConflict',
      ]) {
        requests.clear();
        adapter.onGet(
          _statePath,
          (server) => server.reply(200, {'state': _state('v7')}),
          queryParameters: {'subject': _subjectUri},
        );
        if (scenario == 'stateConflict') {
          adapter.onPost(
            _removePath,
            (server) => server.reply(400, {
              'error': 'StateConflict',
              'message': 'Changed',
            }),
            data: Matchers.any,
          );
          // StateConflict refetches inside submitRemoval. Change the GET
          // route after preflight and before that internal refetch.
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                if (options.path == _removePath &&
                    requests
                            .where((request) => request.path == _removePath)
                            .length ==
                        1) {
                  adapter.onGet(
                    _statePath,
                    (server) => server.reply(200, {'state': _state('v8')}),
                    queryParameters: {'subject': _subjectUri},
                  );
                }
                handler.next(options);
              },
            ),
          );
        } else {
          adapter.onPost(
            _removePath,
            (server) => server.throws(503, _lostResponse(_removePath)),
            data: Matchers.any,
          );
        }
        // A new sheet owns a fresh flow and a deterministic key sequence.
        var nextKey = 0;
        final scenarioFlow = AdminModerationFlow(
          api,
          authority: authority,
          idempotencyKeyGenerator: () => 'key-${++nextKey}',
        );

        final failed = await scenarioFlow.submitRemoval(
          subject: _subject,
          reason: ModerationReason.spam,
        );
        expect(failed, isA<ModerationFlowMutationFailed>(), reason: scenario);
        if (scenario != 'stateConflict') {
          expect(
            scenarioFlow.retainedSubmission?.idempotencyKey,
            'key-1',
            reason: scenario,
          );
        }
        if (scenario == 'idempotencyConflict') {
          adapter.onPost(
            _removePath,
            (server) => server.reply(400, {
              'error': 'IdempotencyConflict',
              'message': 'Different request',
            }),
            data: Matchers.any,
          );
          final conflict = await scenarioFlow.retry();
          expect(conflict, isA<ModerationFlowMutationFailed>());
          expect(
            (conflict! as ModerationFlowMutationFailed).error.code,
            ModerationErrorCode.idempotencyConflict,
          );
        }
        if (scenario != 'abandon') {
          expect(scenarioFlow.retainedSubmission, isNull, reason: scenario);
        }
        adapter
          ..onGet(
            _statePath,
            (server) => server.reply(200, {'state': _state('v8')}),
            queryParameters: {'subject': _subjectUri},
          )
          ..onPost(
            _removePath,
            (server) => server.reply(200, _applied('v9')),
            data: Matchers.any,
          );
        final result = await scenarioFlow.submitRemoval(
          subject: _subject,
          reason: ModerationReason.harassment,
        );
        expect(result, isA<ModerationFlowSucceeded>(), reason: scenario);
        final posts = requests
            .where((request) => request.path == _removePath)
            .toList();
        expect(posts.last.data['expectedVersion'], 'v8', reason: scenario);
        expect(posts.last.data['idempotencyKey'], 'key-2', reason: scenario);
        expect(posts.first.data['idempotencyKey'], 'key-1', reason: scenario);
        if (scenario == 'idempotencyConflict') {
          expect(posts[1].data['idempotencyKey'], 'key-1');
        }
        expect(
          requests.where((request) => request.path == _statePath),
          hasLength(scenario == 'stateConflict' ? 3 : 2),
          reason: scenario,
        );
        expect(scenarioFlow.retainedSubmission, isNull, reason: scenario);
      }
    });

    test('U4 preflight errors leave no request to retry '
        'and next submission refetches', () async {
      for (final failure in ['connection', 'unavailable', 'auth']) {
        requests.clear();
        final failedGetOptions = RequestOptions(
          path: _statePath,
          queryParameters: {'subject': _subjectUri},
        );
        switch (failure) {
          case 'connection':
            adapter.onGet(
              _statePath,
              (server) => server.throws(
                503,
                _lostResponse(_statePath, requestOptions: failedGetOptions),
              ),
              queryParameters: {'subject': _subjectUri},
            );
          case 'unavailable':
            adapter.onGet(
              _statePath,
              (server) => server.reply(503, {
                'error': 'ModerationUnavailable',
                'message': 'Down',
              }),
              queryParameters: {'subject': _subjectUri},
            );
          case 'auth':
            adapter.onGet(
              _statePath,
              (server) => server.reply(401, {
                'error': 'AuthRequired',
                'message': 'Sign in',
              }),
              queryParameters: {'subject': _subjectUri},
            );
        }
        adapter.onPost(
          _removePath,
          (server) => server.reply(200, _applied('v9')),
          data: Matchers.any,
        );
        var nextKey = 0;
        final scenarioFlow = AdminModerationFlow(
          api,
          authority: authority,
          idempotencyKeyGenerator: () => 'key-${++nextKey}',
        );

        final failed = await scenarioFlow.submitRemoval(
          subject: _subject,
          reason: ModerationReason.spam,
        );
        expect(failed, isA<ModerationFlowPreflightFailed>(), reason: failure);
        expect(
          requests.where((request) => request.path == _removePath),
          isEmpty,
          reason: failure,
        );
        expect(scenarioFlow.retainedSubmission, isNull, reason: failure);
        final beforeRetry = requests
            .where((request) => request.path == _statePath)
            .length;
        expect(await scenarioFlow.retry(), isNull, reason: failure);
        expect(
          requests.where((request) => request.path == _statePath),
          hasLength(beforeRetry),
          reason: failure,
        );
        expect(
          requests.where((request) => request.path == _removePath),
          isEmpty,
          reason: failure,
        );

        final failedGetCount = requests
            .where((request) => request.path == _statePath)
            .length;
        adapter.onGet(
          _statePath,
          (server) => server.reply(200, {'state': _state('v8')}),
          queryParameters: {'subject': _subjectUri},
        );
        final result = await scenarioFlow.submitRemoval(
          subject: _subject,
          reason: ModerationReason.spam,
        );
        expect(result, isA<ModerationFlowSucceeded>(), reason: failure);
        expect(
          requests.where((request) => request.path == _statePath),
          hasLength(failedGetCount + 1),
          reason: failure,
        );
        final posts = requests
            .where((request) => request.path == _removePath)
            .toList();
        expect(posts, hasLength(1), reason: failure);
        expect(posts.single.data['expectedVersion'], 'v8', reason: failure);
      }
    });

    test(
      'U5 unrecognized or malformed successful responses cannot be replayed',
      () async {
        for (final response in [
          {'outcome': 'somethingNew', 'state': _state('v8')},
          <String, Object>{},
        ]) {
          requests.clear();
          adapter
            ..onGet(
              _statePath,
              (server) => server.reply(200, {'state': _state('v7')}),
              queryParameters: {'subject': _subjectUri},
            )
            ..onPost(
              _removePath,
              (server) => server.reply(200, response),
              data: Matchers.any,
            );

          final submitted = flow.submitRemoval(
            subject: _subject,
            reason: ModerationReason.spam,
          );
          if (response.isEmpty) {
            final failed = await submitted;
            expect(
              failed,
              isA<ModerationFlowMutationFailed>(),
              reason: '$response',
            );
            final error = (failed as ModerationFlowMutationFailed).error;
            expect(error.code, ModerationErrorCode.unknown);
            expect(error.recovery, ModerationRecovery.clientBug);
          } else {
            // A 2xx outcome the app does not recognise is a client bug that
            // must reach the error reporter rather than become a failure.
            await expectLater(submitted, throwsA(isA<StateError>()));
          }
          expect(flow.retainedSubmission, isNull);
          final count = requests.length;
          expect(await flow.retry(), isNull);
          expect(requests, hasLength(count));
        }
      },
    );
  });
}
