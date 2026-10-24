import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/settings_screen_harness.dart';

const _alice = 'did:plc:alice';
const _bob = 'did:plc:bob';

/// Alice's first session: [true, false, true, false].
const _alicePreferences = NotificationPreferences(
  postReply: true,
  commentReply: false,
  mention: true,
  upvote: false,
);

/// The server's answer to Alice's Mentions-off put.
const _aliceMentionOff = NotificationPreferences(
  postReply: true,
  commentReply: false,
  mention: false,
  upvote: false,
);

/// Bob's session: [false, true, false, true].
const _bobPreferences = NotificationPreferences(
  postReply: false,
  commentReply: true,
  mention: false,
  upvote: true,
);

/// Alice's preferences when she signs in again: [false, false, false, true].
const _aliceAgainPreferences = NotificationPreferences(
  postReply: false,
  commentReply: false,
  mention: false,
  upvote: true,
);

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Settings open and loaded for Alice: [true, false, true, false].
Future<void> _openLoadedAsAlice(
  WidgetTester tester,
  SettingsHarness harness,
) async {
  harness.stubPendingPreferenceRequests();
  await harness.pumpRouter(tester);
  await harness.openSettings(tester);
  expect(harness.loadRequestDids, [_alice]);
  harness.loadResponses[0].complete(_alicePreferences);
  await _pumpFrames(tester);
  expectSwitchStates(tester, [true, false, true, false]);
}

/// Alice's Mentions put in flight, her Upvotes toggle queued behind it.
Future<void> _toggleMentionsAndQueueUpvotes(WidgetTester tester) async {
  await tester.tap(find.text('Mentions'));
  await tester.pump();
  await tester.tap(find.text('Likes'));
  await tester.pump();
  expectSwitchStates(tester, [true, false, false, true]);
}

/// The section is loading: no switches, no Retry, a spinner.
void _expectLoading() {
  expectNoSwitchLabels();
  expect(find.text('Retry'), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
}

enum _Completion { success, networkFailure, accountNotIndexed }

enum _AliceLoad {
  landsAfterBob,
  landsWhileBobPending,
  failsAfterSwitch,
  failedBeforeSwitch,
}

enum _ShownState { loaded, loading, loadFailed }

enum _SignedOutRequest { staleRetry, queuedToggle, staleSwitch }

enum _Reopen { afterLoad, afterLoadFailure, toggleDuringReload }

void main() {
  for (final row in [
    (name: 'Settings stays open', closeDuringSwitch: false),
    (name: 'Settings closed during the switch', closeDuringSwitch: true),
  ]) {
    testWidgets(
      'S1 an account switch drops the old session and loads the new one once: '
      '${row.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = SettingsHarness();
        try {
          await _openLoadedAsAlice(tester, harness);
          await _toggleMentionsAndQueueUpvotes(tester);
          expect(harness.sentPuts, [
            {'mention': false},
          ]);
          expect(harness.putRequestDids, [_alice]);

          if (row.closeDuringSwitch) {
            await harness.closeSettings(tester);
            harness.auth.setSignedInDid(_bob);
            await _pumpFrames(tester);
            harness.putResponses[0].complete(_aliceMentionOff);
            await _pumpFrames(tester);
            expect(harness.sentPuts, [
              {'mention': false},
            ]);
            expect(harness.putRequestDids, [_alice]);
            expect(harness.unreadCount.refreshCalls, 0);
            expect(harness.notificationPreferencesChangeSignal.version, 0);

            await harness.openSettings(tester);
            _expectLoading();
            expect(harness.loadRequestDids, [_alice, _bob]);
            harness.loadResponses[1].complete(_bobPreferences);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [false, true, false, true]);
          } else {
            harness.auth.setSignedInDid(_bob);
            await _pumpFrames(tester);
            _expectLoading();
            expect(harness.loadRequestDids, [_alice, _bob]);

            harness.loadResponses[1].complete(_bobPreferences);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [false, true, false, true]);

            harness.putResponses[0].complete(_aliceMentionOff);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [false, true, false, true]);
          }

          await _pumpFrames(tester);
          expect(harness.sentPuts, [
            {'mention': false},
          ]);
          expect(harness.putRequestDids, [_alice]);
          expect(harness.loadRequestDids, [_alice, _bob]);
        } finally {
          await harness.dispose(tester);
          semantics.dispose();
        }
      },
    );
  }

  for (final row in [
    (
      name: 'success',
      completion: _Completion.success,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      newSessionToggles: false,
    ),
    (
      name: 'network failure',
      completion: _Completion.networkFailure,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      newSessionToggles: false,
    ),
    (
      name: 'AccountNotIndexed failure',
      completion: _Completion.accountNotIndexed,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      newSessionToggles: false,
    ),
    (
      name: 'the new session sends its own queue meanwhile',
      completion: _Completion.success,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      newSessionToggles: true,
    ),
    (
      name: 'the new session sends its own queue meanwhile, the old put fails',
      completion: _Completion.networkFailure,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      newSessionToggles: true,
    ),
    (
      name: 'the same account signs in again',
      completion: _Completion.success,
      newDid: _alice,
      newPreferences: _aliceAgainPreferences,
      newStates: [false, false, false, true],
      newSessionToggles: false,
    ),
  ]) {
    testWidgets(
      "S2 the old session's in-flight put completing after the switch has no "
      'effect: ${row.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = SettingsHarness();
        try {
          await _openLoadedAsAlice(tester, harness);
          await tester.tap(find.text('Mentions'));
          await tester.pump();
          expect(harness.sentPuts, [
            {'mention': false},
          ]);

          if (row.newDid == _alice) {
            harness.auth.setSignedInDid(null);
            await _pumpFrames(tester);
          }
          harness.auth.setSignedInDid(row.newDid);
          await _pumpFrames(tester);
          expect(harness.loadRequestDids, [_alice, row.newDid]);
          harness.loadResponses[1].complete(row.newPreferences);
          await _pumpFrames(tester);
          expectSwitchStates(tester, row.newStates);

          var statesAfterOldPut = row.newStates;
          if (row.newSessionToggles) {
            await tester.tap(find.text('Mentions'));
            await tester.pump();
            expectSwitchStates(tester, [false, true, true, true]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
            ]);
            expect(harness.putRequestDids, [_alice, _bob]);
            await tester.tap(find.text('Likes'));
            await tester.pump();
            statesAfterOldPut = [false, true, true, false];
            expectSwitchStates(tester, statesAfterOldPut);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
            ]);
          }

          switch (row.completion) {
            case _Completion.success:
              harness.putResponses[0].complete(_aliceMentionOff);
            case _Completion.networkFailure:
              harness.putResponses[0].completeError(
                NetworkException('Connection unavailable'),
              );
            case _Completion.accountNotIndexed:
              harness.putResponses[0].completeError(
                ApiException(
                  'Bad request',
                  statusCode: 400,
                  errorCode: 'AccountNotIndexed',
                ),
              );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SnackBar), findsNothing);
          expectSwitchStates(tester, statesAfterOldPut);
          expect(harness.unreadCount.refreshCalls, 0);
          expect(harness.notificationPreferencesChangeSignal.version, 0);

          if (row.newSessionToggles) {
            // The old session's loop has stopped without ending Bob's: a
            // toggle now queues behind his in-flight put, not beside it.
            await tester.tap(find.text('Replies to your posts'));
            await tester.pump();
            expectSwitchStates(tester, [true, true, true, false]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
            ]);
            harness.putResponses[1].complete(
              const NotificationPreferences(
                postReply: false,
                commentReply: true,
                mention: true,
                upvote: true,
              ),
            );
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, true, true, false]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
              {'upvote': false},
            ]);
            expect(harness.putRequestDids, [_alice, _bob, _bob]);

            harness.putResponses[2].complete(
              const NotificationPreferences(
                postReply: false,
                commentReply: true,
                mention: true,
                upvote: false,
              ),
            );
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, true, true, false]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
              {'upvote': false},
              {'postReply': true},
            ]);
            expect(harness.putRequestDids, [_alice, _bob, _bob, _bob]);

            harness.putResponses[3].complete(
              const NotificationPreferences(
                postReply: true,
                commentReply: true,
                mention: true,
                upvote: false,
              ),
            );
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, true, true, false]);
            expect(harness.unreadCount.refreshCalls, 3);
            expect(harness.notificationPreferencesChangeSignal.version, 3);
          } else {
            expect(harness.sentPuts, [
              {'mention': false},
            ]);
          }
        } finally {
          await harness.dispose(tester);
          semantics.dispose();
        }
      },
    );
  }

  for (final row in [
    (
      name: "Alice's load lands after Bob's",
      aliceLoad: _AliceLoad.landsAfterBob,
    ),
    (
      name: "Alice's load lands while Bob's is pending",
      aliceLoad: _AliceLoad.landsWhileBobPending,
    ),
    (
      name: "Alice's load fails after the switch",
      aliceLoad: _AliceLoad.failsAfterSwitch,
    ),
    (
      name: "Alice's load had already failed with Retry on screen",
      aliceLoad: _AliceLoad.failedBeforeSwitch,
    ),
  ]) {
    testWidgets(
      "S3 the old session's load never shows over the new one: ${row.name}",
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = SettingsHarness();
        try {
          harness.stubPendingPreferenceRequests();
          await harness.pumpRouter(tester);
          await harness.openSettings(tester);
          expect(harness.loadRequestDids, [_alice]);
          _expectLoading();

          if (row.aliceLoad == _AliceLoad.failedBeforeSwitch) {
            harness.loadResponses[0].completeError(
              NetworkException('Connection unavailable'),
            );
            await _pumpFrames(tester);
            expect(find.text('Retry'), findsOneWidget);
          }

          harness.auth.setSignedInDid(_bob);
          await _pumpFrames(tester);
          _expectLoading();
          expect(harness.loadRequestDids, [_alice, _bob]);

          switch (row.aliceLoad) {
            case _AliceLoad.landsAfterBob:
              harness.loadResponses[1].complete(_bobPreferences);
              await _pumpFrames(tester);
              expectSwitchStates(tester, [false, true, false, true]);
              harness.loadResponses[0].complete(_alicePreferences);
              await _pumpFrames(tester);
            case _AliceLoad.landsWhileBobPending:
              harness.loadResponses[0].complete(_alicePreferences);
              await _pumpFrames(tester);
              _expectLoading();
              harness.loadResponses[1].complete(_bobPreferences);
              await _pumpFrames(tester);
            case _AliceLoad.failsAfterSwitch:
              harness.loadResponses[0].completeError(
                NetworkException('Connection unavailable'),
              );
              await _pumpFrames(tester);
              _expectLoading();
              harness.loadResponses[1].complete(_bobPreferences);
              await _pumpFrames(tester);
            case _AliceLoad.failedBeforeSwitch:
              harness.loadResponses[1].complete(_bobPreferences);
              await _pumpFrames(tester);
          }

          expectSwitchStates(tester, [false, true, false, true]);
          expect(find.text('Retry'), findsNothing);
          expect(harness.loadRequestDids, [_alice, _bob]);
        } finally {
          await harness.dispose(tester);
          semantics.dispose();
        }
      },
    );
  }

  for (final row in [
    (name: 'from loaded preferences', shown: _ShownState.loaded),
    (name: 'while loading', shown: _ShownState.loading),
    (name: 'from a load failure', shown: _ShownState.loadFailed),
  ]) {
    testWidgets(
      'S4 sign-out replaces the section with a Sign in prompt that pushes '
      '/login: ${row.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = SettingsHarness();
        try {
          harness.stubPendingPreferenceRequests();
          await harness.pumpRouter(tester);
          await harness.openSettings(tester);
          expect(harness.loadRequestDids, [_alice]);
          switch (row.shown) {
            case _ShownState.loaded:
              harness.loadResponses[0].complete(_alicePreferences);
              await _pumpFrames(tester);
              expectSwitchStates(tester, [true, false, true, false]);
            case _ShownState.loading:
              _expectLoading();
            case _ShownState.loadFailed:
              harness.loadResponses[0].completeError(
                NetworkException('Connection unavailable'),
              );
              await _pumpFrames(tester);
              expect(find.text('Retry'), findsOneWidget);
          }

          harness.auth.setSignedInDid(null);
          await _pumpFrames(tester);
          expect(find.text('Sign in'), findsOneWidget);
          expectNoSwitchLabels();
          expect(find.text('Retry'), findsNothing);

          await tester.tap(find.text('Sign in'));
          await settleRouterFrames(tester);
          expect(harness.router.state.uri.path, '/login');
          expect(find.text('Login destination'), findsOneWidget);

          // Pushed, so signing in returns to Settings.
          expect(harness.router.canPop(), isTrue);
          harness.router.pop();
          await settleRouterFrames(tester);
          expect(harness.router.state.uri.path, '/settings');
        } finally {
          await harness.dispose(tester);
          semantics.dispose();
        }
      },
    );
  }

  for (final row in [
    (
      name: 'a stale Retry tapped in the frame of sign-out',
      request: _SignedOutRequest.staleRetry,
    ),
    (
      name: 'a queued toggle once the in-flight put completes',
      request: _SignedOutRequest.queuedToggle,
    ),
    (
      name: 'a switch tapped in the frame of sign-out',
      request: _SignedOutRequest.staleSwitch,
    ),
  ]) {
    testWidgets(
      'S5 no preference request is sent while signed out: ${row.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = SettingsHarness();
        try {
          switch (row.request) {
            case _SignedOutRequest.staleRetry:
              harness.stubPendingPreferenceRequests();
              await harness.pumpRouter(tester);
              await harness.openSettings(tester);
              harness.loadResponses[0].completeError(
                NetworkException('Connection unavailable'),
              );
              await _pumpFrames(tester);
              expect(find.text('Retry'), findsOneWidget);

              harness.auth.setSignedInDid(null);
              await tester.tap(find.text('Retry'));
              await _pumpFrames(tester);
              expect(harness.putRequestDids, <String?>[]);
            case _SignedOutRequest.queuedToggle:
              await _openLoadedAsAlice(tester, harness);
              await _toggleMentionsAndQueueUpvotes(tester);
              expect(harness.sentPuts, [
                {'mention': false},
              ]);

              harness.auth.setSignedInDid(null);
              await _pumpFrames(tester);
              harness.putResponses[0].complete(_aliceMentionOff);
              await _pumpFrames(tester);
              expect(harness.sentPuts, [
                {'mention': false},
              ]);
              expect(harness.putRequestDids, [_alice]);
            case _SignedOutRequest.staleSwitch:
              await _openLoadedAsAlice(tester, harness);

              harness.auth.setSignedInDid(null);
              await tester.tap(find.text('Mentions'));
              await _pumpFrames(tester);
              expect(harness.sentPuts, <Map<String, bool>>[]);
              expect(harness.putRequestDids, <String?>[]);
          }

          await tester.pump(const Duration(milliseconds: 300));
          expect(harness.loadRequestDids, [_alice]);
        } finally {
          await harness.dispose(tester);
          semantics.dispose();
        }
      },
    );
  }

  for (final row in [
    (
      name: 'opened signed out, then Bob signs in',
      startSignedIn: false,
      newDid: _bob,
      newPreferences: _bobPreferences,
      newStates: [false, true, false, true],
      expectedLoadDids: [_bob],
    ),
    (
      name: 'Alice signs out and back in',
      startSignedIn: true,
      newDid: _alice,
      newPreferences: _aliceAgainPreferences,
      newStates: [false, false, false, true],
      expectedLoadDids: [_alice, _alice],
    ),
  ]) {
    testWidgets('S6 signing in loads the new session once: ${row.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = SettingsHarness(
        signedInDid: row.startSignedIn ? _alice : null,
      );
      try {
        if (row.startSignedIn) {
          await _openLoadedAsAlice(tester, harness);
          harness.auth.setSignedInDid(null);
          await _pumpFrames(tester);
        } else {
          harness.stubPendingPreferenceRequests();
          await harness.pumpRouter(tester);
          await harness.openSettings(tester);
          expect(harness.loadRequestDids, <String?>[]);
        }

        harness.auth.setSignedInDid(row.newDid);
        await _pumpFrames(tester);
        expect(harness.loadRequestDids, row.expectedLoadDids);
        harness.loadResponses.last.complete(row.newPreferences);
        await _pumpFrames(tester);
        expectSwitchStates(tester, row.newStates);

        await tester.pump(const Duration(milliseconds: 300));
        await _pumpFrames(tester);
        expectSwitchStates(tester, row.newStates);
        expect(harness.loadRequestDids, row.expectedLoadDids);
      } finally {
        await harness.dispose(tester);
        semantics.dispose();
      }
    });
  }

  for (final row in [
    (name: 'new values from another device', reopen: _Reopen.afterLoad),
    (
      name: 'a fresh load, not the earlier failure',
      reopen: _Reopen.afterLoadFailure,
    ),
    (
      name: 'a reload landing after a toggle does not overwrite it',
      reopen: _Reopen.toggleDuringReload,
    ),
  ]) {
    testWidgets('S7 reopening Settings reloads the preferences: ${row.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = SettingsHarness();
      try {
        harness.stubPendingPreferenceRequests();
        await harness.pumpRouter(tester);
        await harness.openSettings(tester);
        expect(harness.loadRequestDids, [_alice]);
        if (row.reopen == _Reopen.afterLoadFailure) {
          harness.loadResponses[0].completeError(
            NetworkException('Connection unavailable'),
          );
          await _pumpFrames(tester);
          expect(find.text('Retry'), findsOneWidget);
        } else {
          harness.loadResponses[0].complete(_alicePreferences);
          await _pumpFrames(tester);
          expectSwitchStates(tester, [true, false, true, false]);
        }

        await harness.closeSettings(tester);
        await harness.openSettings(tester);
        expect(harness.loadRequestDids, [_alice, _alice]);

        switch (row.reopen) {
          case _Reopen.afterLoad:
            // The earlier values stay on screen while the reload runs.
            expectSwitchStates(tester, [true, false, true, false]);
            harness.loadResponses[1].complete(_aliceAgainPreferences);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [false, false, false, true]);
          case _Reopen.afterLoadFailure:
            _expectLoading();
            harness.loadResponses[1].complete(_alicePreferences);
            await _pumpFrames(tester);
            expect(find.text('Retry'), findsNothing);
            expectSwitchStates(tester, [true, false, true, false]);
          case _Reopen.toggleDuringReload:
            await tester.tap(find.text('Mentions'));
            await tester.pump();
            expect(harness.sentPuts, [
              {'mention': false},
            ]);
            harness.putResponses[0].complete(_aliceMentionOff);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, false, false, false]);

            // Sent before the put was applied, so it still says Mentions on.
            harness.loadResponses[1].complete(_alicePreferences);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, false, false, false]);

            // The discarded reload still finished: the next open loads again.
            await harness.closeSettings(tester);
            await harness.openSettings(tester);
            expect(harness.loadRequestDids, [_alice, _alice, _alice]);
            harness.loadResponses[2].complete(_aliceMentionOff);
            await _pumpFrames(tester);
            expectSwitchStates(tester, [true, false, false, false]);
            expect(harness.sentPuts, [
              {'mention': false},
            ]);
        }
      } finally {
        await harness.dispose(tester);
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'S8 an auth notify for the same session, as a token refresh sends, keeps '
    'the values and the queue',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = SettingsHarness();
      try {
        await _openLoadedAsAlice(tester, harness);
        await _toggleMentionsAndQueueUpvotes(tester);

        harness.auth.notifyWithoutChange();
        await _pumpFrames(tester);
        expectSwitchStates(tester, [true, false, false, true]);
        expect(harness.loadRequestDids, [_alice]);

        harness.putResponses[0].complete(_aliceMentionOff);
        await _pumpFrames(tester);
        expect(harness.sentPuts, [
          {'mention': false},
          {'upvote': true},
        ]);
        expect(harness.unreadCount.refreshCalls, 1);
      } finally {
        await harness.dispose(tester);
        semantics.dispose();
      }
    },
  );
}
