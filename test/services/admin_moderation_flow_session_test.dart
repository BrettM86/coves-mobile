import 'dart:async';

import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/admin_moderation_flow.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _subjectUri = 'at://did:plc:author/social.coves.community.post/p1';
const _subject = StrongRef(uri: _subjectUri, cid: 'bafy-post');

ModerationSubjectState _state(
  String version, {
  ModerationState moderation = ModerationState.clear,
}) => ModerationSubjectState(
  subject: _subjectUri,
  version: version,
  moderation: ModerationView(state: moderation),
  recordState: ModerationRecordState.present,
);

ModerationMutationResult _applied() => ModerationMutationResult(
  outcome: ModerationMutationOutcome.applied,
  state: _state('v8', moderation: ModerationState.removed),
);

ApiException _unavailable() =>
    ApiException('Down', statusCode: 503, errorCode: 'ModerationUnavailable');

ApiException _forbidden() =>
    ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden');

ApiException _stateConflict() =>
    ApiException('Changed', statusCode: 400, errorCode: 'StateConflict');

/// Which request a row holds in flight while the session changes.
enum _Held { preflight, removal, conflictFollowUp }

typedef _Row = ({
  String name,
  _Held held,
  void Function(
    Completer<ModerationSubjectState> state,
    Completer<ModerationMutationResult> removal,
  )
  release,
  int removals,
  int stateFetches,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late ViewerAuthorityProvider authority;
  late AdminModerationFlow flow;
  late int stateFetches;
  late int removals;

  /// Answers for getModerationSubjectState calls, by call index; calls
  /// without an entry answer v7 at once.
  late Map<int, Future<ModerationSubjectState> Function()> stateAnswers;

  /// Answer for every removeContent call; defaults to `applied` at once.
  late Future<ModerationMutationResult> Function() removalAnswer;

  setUp(() async {
    auth = FakeAuthProvider(signedInDid: 'did:plc:admin-a');
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    stateFetches = 0;
    removals = 0;
    stateAnswers = {};
    removalAnswer = () async => _applied();
    when(api.getModerationSubjectState(any)).thenAnswer((_) {
      final answer = stateAnswers[stateFetches++];
      return answer != null ? answer() : Future.value(_state('v7'));
    });
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) {
      removals++;
      return removalAnswer();
    });
    authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
    addTearDown(() {
      authority.dispose();
      auth.dispose();
    });
    await pumpEventQueue();
    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    var nextKey = 0;
    flow = AdminModerationFlow(
      api,
      authority: authority,
      idempotencyKeyGenerator: () => 'key-${++nextKey}',
    );
  });

  test('S3 a retained submission is discarded when the session changes '
      'and retry sends nothing', () async {
    removalAnswer = () => Future.error(_unavailable());

    final failed = await flow.submitRemoval(
      subject: _subject,
      reason: ModerationReason.spam,
    );
    expect(failed, isA<ModerationFlowMutationFailed>());
    expect(flow.retainedSubmission?.idempotencyKey, 'key-1');
    expect(removals, 1);

    auth.setSignedInDid('did:plc:admin-b');
    await pumpEventQueue();

    expect(flow.retainedSubmission, isNull);
    await flow.retry();
    expect(removals, 1);
  });

  final rows = <_Row>[
    (
      name: 'a removal in flight answers applied',
      held: _Held.removal,
      release: (_, removal) => removal.complete(_applied()),
      removals: 1,
      stateFetches: 1,
    ),
    (
      name: 'a removal in flight answers 403 Forbidden',
      held: _Held.removal,
      release: (_, removal) => removal.completeError(_forbidden()),
      removals: 1,
      stateFetches: 1,
    ),
    (
      name: 'a removal in flight answers 503 ModerationUnavailable',
      held: _Held.removal,
      release: (_, removal) => removal.completeError(_unavailable()),
      removals: 1,
      stateFetches: 1,
    ),
    (
      name: 'a preflight in flight answers a version',
      held: _Held.preflight,
      release: (state, _) => state.complete(_state('v7')),
      removals: 0,
      stateFetches: 1,
    ),
    (
      name: 'a preflight in flight answers an ApiException',
      held: _Held.preflight,
      release: (state, _) => state.completeError(_forbidden()),
      removals: 0,
      stateFetches: 1,
    ),
    (
      name: 'a StateConflict follow-up fetch in flight answers',
      held: _Held.conflictFollowUp,
      release: (state, _) => state.complete(_state('v8')),
      removals: 1,
      stateFetches: 2,
    ),
  ];

  for (final row in rows) {
    test('S4 late answers after a session change are stale sessions '
        '(${row.name})', () async {
      final heldState = Completer<ModerationSubjectState>();
      final heldRemoval = Completer<ModerationMutationResult>();
      switch (row.held) {
        case _Held.preflight:
          stateAnswers[0] = () => heldState.future;
        case _Held.removal:
          removalAnswer = () => heldRemoval.future;
        case _Held.conflictFollowUp:
          removalAnswer = () => Future.error(_stateConflict());
          stateAnswers[1] = () => heldState.future;
      }

      final pending = flow.submitRemoval(
        subject: _subject,
        reason: ModerationReason.spam,
      );
      await pumpEventQueue();
      expect(stateFetches, row.held == _Held.conflictFollowUp ? 2 : 1);
      expect(removals, row.held == _Held.preflight ? 0 : 1);

      auth.setSignedInDid('did:plc:admin-b');
      row.release(heldState, heldRemoval);
      final result = await pending;

      expect(result, isA<ModerationFlowStaleSession>());
      expect(removals, row.removals);
      expect(stateFetches, row.stateFetches);
      expect(flow.retainedSubmission, isNull);
      await flow.retry();
      expect(removals, row.removals);
      expect(stateFetches, row.stateFetches);
    });
  }
}
