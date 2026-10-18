import 'dart:async';

import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/moderation/moderation_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/modlog_fixtures.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

const _commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
const _postUri = 'at://did:plc:author/social.coves.community.postv2/p1';

final Finder _sheet = find.byWidgetPredicate(
  (widget) => widget is ModerationActionSheet,
);

/// The sheet's confirm button; its label becomes a spinner while the request
/// is in flight.
final Finder _sheetConfirm = find.descendant(
  of: _sheet,
  matching: find.bySubtype<FilledButton>(),
);

/// The row's own Restore button. Always scoped to a tile: the sheet also has
/// a 'Restore' button.
Finder _rowRestoreButton(Finder row) =>
    find.descendant(of: row, matching: find.bySubtype<ButtonStyleButton>());

/// The tile of the row every test acts on.
final Finder _removalTile = tile('did:web:coves.social', 'R1');

/// A local removal R1 of [subject] (public) and [privateSubject].
AdminModerationActionView _removalRow({
  ModerationSubjectRef? subject = const ModerationSubjectRef(uri: _commentUri),
  ModerationSubjectRef? privateSubject,
}) => AdminModerationActionView(
  action: action(
    'did:web:coves.social',
    'R1',
    reason: ModerationReason.spam,
    subject: subject,
  ),
  privateSubject: privateSubject,
);

/// [uri]'s moderation state while the local removal [actionId] removes it.
ModerationSubjectState _removedState(String uri, {String actionId = 'R1'}) =>
    ModerationSubjectState(
      subject: uri,
      version: 'v7',
      moderation: const ModerationView(state: ModerationState.removed),
      recordState: ModerationRecordState.present,
      currentSubject: StrongRef(uri: uri, cid: 'bafy-c2'),
      localRemoval: ModerationActionRef(
        serviceDid: 'did:web:coves.social',
        actionId: actionId,
      ),
    );

/// [uri]'s moderation state once nothing removes it.
ModerationSubjectState _clearState(String uri) => ModerationSubjectState(
  subject: uri,
  version: 'v8',
  moderation: const ModerationView(state: ModerationState.clear),
  recordState: ModerationRecordState.present,
  currentSubject: StrongRef(uri: uri, cid: 'bafy-c2'),
);

/// An applied restore of [uri].
ModerationMutationResult _restored(String uri) => ModerationMutationResult(
  outcome: ModerationMutationOutcome.applied,
  state: _clearState(uri),
);

/// Answers the screen's admin-log and public-log requests and records the
/// cursor of each.
class _LogServer {
  _LogServer(
    MockCovesApiService api, {
    required this.adminRows,
    this.publicRows = const [],
  }) {
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) async {
      adminCursors.add(invocation.namedArguments[#cursor] as String?);
      return AdminModerationActionPage(actions: adminRows);
    });
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) async {
      publicCursors.add(invocation.namedArguments[#cursor] as String?);
      return ModerationActionPage(actions: publicRows);
    });
  }

  List<AdminModerationActionView> adminRows;
  List<ModerationActionView> publicRows;
  final List<String?> adminCursors = [];
  final List<String?> publicCursors = [];

  int get requestCount => adminCursors.length + publicCursors.length;
}

/// Answers getModerationSubjectState for [uri] with [states] in turn; the
/// last one repeats.
void _answerStates(
  MockCovesApiService api,
  String uri,
  List<ModerationSubjectState> states,
) {
  var call = 0;
  when(api.getModerationSubjectState(uri)).thenAnswer(
    (_) async => states[call < states.length ? call++ : states.length - 1],
  );
}

/// Answers restoreContent with [answers] in turn (the last one repeats) and
/// returns the idempotency keys the server received.
List<String> _answerRestore(
  MockCovesApiService api,
  List<Future<ModerationMutationResult> Function()> answers,
) {
  final idempotencyKeys = <String>[];
  when(
    api.restoreContent(
      actionId: anyNamed('actionId'),
      expectedVersion: anyNamed('expectedVersion'),
      idempotencyKey: anyNamed('idempotencyKey'),
      reason: anyNamed('reason'),
      reviewedSubject: anyNamed('reviewedSubject'),
      privateNote: anyNamed('privateNote'),
    ),
  ).thenAnswer((invocation) {
    final call = idempotencyKeys.length;
    idempotencyKeys.add(invocation.namedArguments[#idempotencyKey] as String);
    return answers[call < answers.length ? call : answers.length - 1]();
  });
  return idempotencyKeys;
}

/// Signs in an instance admin and pumps the admin log.
Future<(FakeAuthProvider, ViewerAuthorityProvider)> _pumpAdminLog(
  WidgetTester tester,
  MockCovesApiService api,
) async {
  final (auth, authority) = await signedInAdmin(tester, api);
  await pumpModlog(tester, api: api, auth: auth, authority: authority);
  return (auth, authority);
}

/// Taps [row]'s Restore and waits for the sheet.
Future<void> _openRestoreSheet(WidgetTester tester, Finder row) async {
  expect(row, findsOneWidget);
  final restoreButton = _rowRestoreButton(row);
  expect(
    find.descendant(of: restoreButton, matching: find.text('Restore')),
    findsOneWidget,
  );
  await tester.tap(restoreButton);
  await pumpFrames(tester);
  expect(_sheet, findsOneWidget);
}

/// Picks a reason and presses the sheet's confirm, pumping only two frames
/// so a held answer stays held.
Future<void> _confirmRestore(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _sheet, matching: find.text('Rule violation')),
  );
  await pumpFrames(tester);
  await tester.tap(_sheetConfirm);
  await tester.pump();
  await tester.pump();
}

/// Restores [row] from its Restore button and lets the answers land.
Future<void> _restoreRow(WidgetTester tester, Finder row) async {
  await _openRestoreSheet(tester, row);
  await _confirmRestore(tester);
  await pumpFrames(tester);
  await pumpFrames(tester);
}

/// Who is looking at the log in the gate matrix.
enum _Viewer { admin, signedOut, notAdmin, revoked }

/// Pumps the log as [viewer]; the admin log answers [row], the public log
/// answers [row]'s public action.
Future<void> _pumpLogAs(
  WidgetTester tester,
  MockCovesApiService api,
  _Viewer viewer,
  AdminModerationActionView row,
) async {
  _LogServer(api, adminRows: [row], publicRows: [row.action]);
  switch (viewer) {
    case _Viewer.admin:
      await _pumpAdminLog(tester, api);
    case _Viewer.revoked:
      final (_, authority) = await _pumpAdminLog(tester, api);
      authority.markRevoked();
      await pumpFrames(tester);
      expect(authority.status, ViewerAuthorityStatus.revoked);
    case _Viewer.signedOut || _Viewer.notAdmin:
      final signedIn = viewer == _Viewer.notAdmin;
      when(api.getViewerAuthority()).thenAnswer((_) async => false);
      final auth = FakeAuthProvider(
        signedInDid: signedIn ? 'did:plc:member' : null,
      );
      final authority = ViewerAuthorityProvider(
        apiService: api,
        authProvider: auth,
      );
      await tester.pump();
      expect(
        authority.status,
        signedIn
            ? ViewerAuthorityStatus.notAdmin
            : ViewerAuthorityStatus.signedOut,
      );
      await pumpModlog(tester, api: api, auth: auth, authority: authority);
  }
}

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  testWidgets('B5 an admin restores a comment from its removal row and the '
      'log reloads from the first page', (tester) async {
    final removalRow = _removalRow();
    // Another removal on the log; its Restore stays enabled while R1's runs.
    final otherRemovalRow = AdminModerationActionView(
      action: action(
        'did:web:coves.social',
        'R3',
        reason: ModerationReason.spam,
        subject: const ModerationSubjectRef(
          uri: 'at://did:plc:author/social.coves.community.comment/c3',
        ),
      ),
    );
    final otherRemovalTile = tile('did:web:coves.social', 'R3');
    final restoreRow = AdminModerationActionView(
      action: action(
        'did:web:coves.social',
        'R2',
        kind: ModerationActionKind.restore,
        reason: ModerationReason.ruleViolation,
        createdAt: DateTime.utc(2026, 10, 1, 13),
        reverses: const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'R1',
        ),
        subject: const ModerationSubjectRef(uri: _commentUri),
      ),
    );

    final server = _LogServer(api, adminRows: [removalRow, otherRemovalRow]);
    _answerStates(api, _commentUri, [_removedState(_commentUri)]);
    final restoreAnswer = Completer<ModerationMutationResult>();
    _answerRestore(api, [() => restoreAnswer.future]);
    await _pumpAdminLog(tester, api);

    await _openRestoreSheet(tester, _removalTile);
    await _confirmRestore(tester);

    expect(
      tester
          .widget<ButtonStyleButton>(_rowRestoreButton(_removalTile))
          .onPressed,
      isNull,
    );
    expect(otherRemovalTile, findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(_rowRestoreButton(otherRemovalTile))
          .onPressed,
      isNotNull,
    );

    server.adminRows = [restoreRow, removalRow, otherRemovalRow];
    final requestsBeforeRestore = server.adminCursors.length;
    restoreAnswer.complete(_restored(_commentUri));
    await pumpFrames(tester);
    await pumpFrames(tester);

    verify(
      api.restoreContent(
        actionId: 'R1',
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        reviewedSubject: anyNamed('reviewedSubject'),
        privateNote: anyNamed('privateNote'),
      ),
    );
    expect(find.text('Comment restored'), findsOneWidget);
    expect(_sheet, findsNothing);
    expect(server.adminCursors.sublist(requestsBeforeRestore), contains(null));
    expect(tile('did:web:coves.social', 'R2'), findsOneWidget);
    // The reloaded log still lists R1; its Restore is usable again.
    expect(_removalTile, findsOneWidget);
    expect(_rowRestoreButton(_removalTile), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(_rowRestoreButton(_removalTile))
          .onPressed,
      isNotNull,
    );
  });

  group('B2+B3 which rows offer Restore', () {
    const otherRemoval = ModerationActionRef(
      serviceDid: 'did:web:coves.social',
      actionId: 'R0',
    );
    AdminModerationActionView row(
      ModerationActionKind kind, {
      ModerationSubjectRef? subject = const ModerationSubjectRef(
        uri: _commentUri,
      ),
      ModerationSubjectRef? privateSubject,
      String origin = 'local',
    }) => AdminModerationActionView(
      action: action(
        'did:web:coves.social',
        'R1',
        kind: kind,
        reason: ModerationReason.spam,
        reverses: kind == ModerationActionKind.restore ? otherRemoval : null,
        subject: subject,
        origin: origin,
      ),
      privateSubject: privateSubject,
    );

    for (final (name, viewer, entry, offersRestore) in [
      (
        'admin: a local removal with a public subject',
        _Viewer.admin,
        row(ModerationActionKind.remove),
        true,
      ),
      (
        'admin: a local removal with only a private subject',
        _Viewer.admin,
        row(
          ModerationActionKind.remove,
          subject: null,
          privateSubject: const ModerationSubjectRef(uri: _postUri),
        ),
        true,
      ),
      (
        'admin: a restore row',
        _Viewer.admin,
        row(ModerationActionKind.restore),
        false,
      ),
      (
        'admin: a label row',
        _Viewer.admin,
        row(ModerationActionKind.label),
        false,
      ),
      (
        'admin: a retract-label row',
        _Viewer.admin,
        row(ModerationActionKind.retractLabel),
        false,
      ),
      (
        'admin: an inherited removal',
        _Viewer.admin,
        row(ModerationActionKind.remove, origin: 'inherited'),
        false,
      ),
      (
        'admin: a local removal without any subject',
        _Viewer.admin,
        row(ModerationActionKind.remove, subject: null),
        false,
      ),
      (
        'signed out: a local removal with a subject',
        _Viewer.signedOut,
        row(ModerationActionKind.remove),
        false,
      ),
      (
        'signed-in non-admin: a local removal with a subject',
        _Viewer.notAdmin,
        row(ModerationActionKind.remove),
        false,
      ),
      (
        'revoked admin: a local removal with a subject',
        _Viewer.revoked,
        row(ModerationActionKind.remove),
        false,
      ),
    ]) {
      testWidgets(name, (tester) async {
        await _pumpLogAs(tester, api, viewer, entry);

        expect(_removalTile, findsOneWidget);
        expect(
          find.descendant(of: _removalTile, matching: find.text('Restore')),
          offersRestore ? findsOneWidget : findsNothing,
        );
        expect(
          _rowRestoreButton(_removalTile),
          offersRestore ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  testWidgets('B4 a removal with only a private post subject restores that '
      'post', (tester) async {
    _LogServer(
      api,
      adminRows: [
        _removalRow(
          subject: null,
          privateSubject: const ModerationSubjectRef(uri: _postUri),
        ),
      ],
    );
    _answerStates(api, _postUri, [_removedState(_postUri)]);
    _answerRestore(api, [() async => _restored(_postUri)]);
    await _pumpAdminLog(tester, api);

    await _openRestoreSheet(tester, _removalTile);
    expect(
      find.descendant(of: _sheet, matching: find.text('Restore post')),
      findsOneWidget,
    );
    await _confirmRestore(tester);
    await pumpFrames(tester);
    await pumpFrames(tester);

    verify(api.getModerationSubjectState(_postUri));
    verify(
      api.restoreContent(
        actionId: 'R1',
        expectedVersion: 'v7',
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: ModerationReason.ruleViolation,
        reviewedSubject: const StrongRef(uri: _postUri, cid: 'bafy-c2'),
        privateNote: anyNamed('privateNote'),
      ),
    );
    expect(find.text('Post restored'), findsOneWidget);
  });

  testWidgets('a post restore answered with a present record that still '
      'reads removed says Post restored and reloads the log from the first '
      'page', (tester) async {
    final removalRow = _removalRow(
      subject: const ModerationSubjectRef(uri: _postUri),
    );
    final restoreRow = AdminModerationActionView(
      action: action(
        'did:web:coves.social',
        'R2',
        kind: ModerationActionKind.restore,
        reason: ModerationReason.ruleViolation,
        createdAt: DateTime.utc(2026, 10, 1, 13),
        reverses: const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'R1',
        ),
        subject: const ModerationSubjectRef(uri: _postUri),
      ),
    );
    final server = _LogServer(api, adminRows: [removalRow]);
    _answerStates(api, _postUri, [_removedState(_postUri)]);
    final restoreAnswer = Completer<ModerationMutationResult>();
    _answerRestore(api, [() => restoreAnswer.future]);
    await _pumpAdminLog(tester, api);

    await _openRestoreSheet(tester, _removalTile);
    await _confirmRestore(tester);

    server.adminRows = [restoreRow, removalRow];
    final requestsBeforeRestore = server.adminCursors.length;
    restoreAnswer.complete(
      const ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: ModerationSubjectState(
          subject: _postUri,
          version: 'v8',
          moderation: ModerationView(state: ModerationState.removed),
          recordState: ModerationRecordState.present,
          currentSubject: StrongRef(uri: _postUri, cid: 'bafy-c2'),
        ),
      ),
    );
    await pumpFrames(tester);
    await pumpFrames(tester);

    expect(find.text('Post restored'), findsOneWidget);
    expect(_sheet, findsNothing);
    expect(server.adminCursors.sublist(requestsBeforeRestore), contains(null));
    expect(tile('did:web:coves.social', 'R2'), findsOneWidget);
  });

  testWidgets('B6 a row whose removal is no longer the active one says so '
      'and reloads the log from the first page', (tester) async {
    final server = _LogServer(api, adminRows: [_removalRow()]);
    _answerStates(api, _commentUri, [
      _removedState(_commentUri, actionId: 'R9'),
    ]);
    _answerRestore(api, [() async => _restored(_commentUri)]);
    await _pumpAdminLog(tester, api);

    await _openRestoreSheet(tester, _removalTile);
    final requestsBeforeConfirm = server.adminCursors.length;
    await _confirmRestore(tester);
    await pumpFrames(tester);
    await pumpFrames(tester);

    expect(find.text('This removal is no longer active.'), findsOneWidget);
    expect(_sheet, findsNothing);
    expect(server.adminCursors.sublist(requestsBeforeConfirm), contains(null));
  });

  testWidgets('B7 a Forbidden restore revokes authority and shows the public '
      'log without Restore', (tester) async {
    final server = _LogServer(
      api,
      adminRows: [_removalRow()],
      publicRows: [_removalRow().action],
    );
    _answerStates(api, _commentUri, [_removedState(_commentUri)]);
    _answerRestore(api, [
      () async => throw ApiException(
        'Forbidden',
        statusCode: 403,
        errorCode: 'Forbidden',
      ),
    ]);
    final (_, authority) = await _pumpAdminLog(tester, api);

    await _restoreRow(tester, _removalTile);

    expect(find.text('You no longer have admin access.'), findsOneWidget);
    expect(authority.status, ViewerAuthorityStatus.revoked);
    expect(server.publicCursors, contains(null));
    expect(_removalTile, findsOneWidget);
    expect(_rowRestoreButton(_removalTile), findsNothing);
  });

  group('B8 a restore answer for an ended session shows nothing and reloads '
      'nothing', () {
    // The switched-to account is also an instance admin, so the log it
    // reloads is the admin log again.
    for (final (name, String? nextDid) in [
      ('sign-out', null),
      ('account switch', 'did:plc:other-admin'),
    ]) {
      testWidgets(name, (tester) async {
        final server = _LogServer(
          api,
          adminRows: [_removalRow()],
          publicRows: [_removalRow().action],
        );
        _answerStates(api, _commentUri, [_removedState(_commentUri)]);
        final restoreAnswer = Completer<ModerationMutationResult>();
        _answerRestore(api, [() => restoreAnswer.future]);
        final (auth, _) = await _pumpAdminLog(tester, api);

        await _openRestoreSheet(tester, _removalTile);
        await _confirmRestore(tester);
        auth.setSignedInDid(nextDid);
        await pumpFrames(tester);
        await pumpFrames(tester);
        final requestsBeforeAnswer = server.requestCount;

        restoreAnswer.complete(_restored(_commentUri));
        await pumpFrames(tester);
        await pumpFrames(tester);

        expect(find.text('Comment restored'), findsNothing);
        expect(find.text('Post restored'), findsNothing);
        expect(server.requestCount, requestsBeforeAnswer);
      });
    }
  });

  group('B9 restore recovery on the log', () {
    for (final (name, int statusCode, errorCode, followUpState) in [
      ('StateConflict', 409, 'StateConflict', _clearState(_commentUri)),
      ('DecisionNotFound', 404, 'DecisionNotFound', null),
      ('SubjectNotFound', 404, 'SubjectNotFound', null),
    ]) {
      testWidgets('$name closes the sheet and reloads the log from the first '
          'page', (tester) async {
        final server = _LogServer(api, adminRows: [_removalRow()]);
        _answerStates(api, _commentUri, [
          _removedState(_commentUri),
          ?followUpState,
        ]);
        _answerRestore(api, [
          () async => throw ApiException(
            errorCode,
            statusCode: statusCode,
            errorCode: errorCode,
          ),
        ]);
        await _pumpAdminLog(tester, api);

        await _openRestoreSheet(tester, _removalTile);
        final requestsBeforeConfirm = server.adminCursors.length;
        await _confirmRestore(tester);
        await pumpFrames(tester);
        await pumpFrames(tester);

        expect(_sheet, findsNothing);
        expect(
          server.adminCursors.sublist(requestsBeforeConfirm),
          contains(null),
        );
      });
    }

    testWidgets('an unavailable answer offers Try again, which resends the '
        'same request', (tester) async {
      _LogServer(api, adminRows: [_removalRow()]);
      _answerStates(api, _commentUri, [_removedState(_commentUri)]);
      final idempotencyKeys = _answerRestore(api, [
        () async => throw ApiException(
          'Down',
          statusCode: 503,
          errorCode: 'ModerationUnavailable',
        ),
        () async => _restored(_commentUri),
      ]);
      await _pumpAdminLog(tester, api);

      await _restoreRow(tester, _removalTile);

      expect(_sheet, findsOneWidget);
      final tryAgain = find.descendant(
        of: _sheetConfirm,
        matching: find.text('Try again'),
      );
      expect(tryAgain, findsOneWidget);
      await tester.tap(tryAgain);
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(idempotencyKeys, hasLength(2));
      expect(idempotencyKeys[1], idempotencyKeys[0]);
    });
  });
}
