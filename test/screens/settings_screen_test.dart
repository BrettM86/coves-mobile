import 'dart:async';

import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/screens/settings/settings_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/settings_screen_harness.dart';

const _loadedPreferences = NotificationPreferences(
  postReply: true,
  commentReply: false,
  mention: true,
  upvote: false,
);

Future<void> _pumpLoadedSettings(
  WidgetTester tester,
  SettingsHarness harness,
  List<Completer<NotificationPreferences>> responses, {
  Widget home = const SettingsScreen(),
}) async {
  when(harness.api.getNotificationPreferences())
      .thenAnswer((_) async => _loadedPreferences);
  when(
    harness.api.putNotificationPreferences(
      postReply: anyNamed('postReply'),
      commentReply: anyNamed('commentReply'),
      mention: anyNamed('mention'),
      upvote: anyNamed('upvote'),
    ),
  ).thenAnswer((invocation) {
    final named = invocation.namedArguments;
    final postReply = named[#postReply] as bool?;
    final commentReply = named[#commentReply] as bool?;
    final mention = named[#mention] as bool?;
    final upvote = named[#upvote] as bool?;
    harness.sentPuts.add({
      'postReply': ?postReply,
      'commentReply': ?commentReply,
      'mention': ?mention,
      'upvote': ?upvote,
    });
    return responses.removeAt(0).future;
  });
  await harness.pump(tester, home: home);
  await tester.pumpAndSettle();
}

String _snackBarText(WidgetTester tester) {
  expect(find.byType(SnackBar), findsOneWidget);
  final text = tester.widget<Text>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
  );
  return text.data ?? '';
}

void main() {
  testWidgets('B4 loading yields four labelled switches with server states', (
    tester,
  ) async {
    final harness = SettingsHarness();
    final pending = Completer<NotificationPreferences>();
    when(harness.api.getNotificationPreferences())
        .thenAnswer((_) => pending.future);
    try {
      await harness.pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expectNoSwitchLabels();

      pending.complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: false,
          upvote: true,
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expectSwitchStates(tester, [true, false, false, true]);
      } finally {
        semantics.dispose();
      }
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B5 load failure retries and renders returned preferences', (
    tester,
  ) async {
    final harness = SettingsHarness();
    var calls = 0;
    when(harness.api.getNotificationPreferences()).thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        throw NetworkException('Connection unavailable');
      }
      return const NotificationPreferences(
        postReply: false,
        commentReply: true,
        mention: true,
        upvote: false,
      );
    });
    try {
      await harness.pump(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('No connection. Please check your internet.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expectNoSwitchLabels();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expectSwitchStates(tester, [false, true, true, false]);
      } finally {
        semantics.dispose();
      }
      expect(calls, 2);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B6 each toggle sends only its key and applies the full response',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final rows = [
          (
            label: 'Replies to your posts',
            pending: [false, false, true, false],
            sent: {'postReply': false},
          ),
          (
            label: 'Replies to your comments',
            pending: [true, true, true, false],
            sent: {'commentReply': true},
          ),
          (
            label: 'Mentions',
            pending: [true, false, false, false],
            sent: {'mention': false},
          ),
          (
            label: 'Likes',
            pending: [true, false, true, true],
            sent: {'upvote': true},
          ),
        ];
        for (final row in rows) {
          final harness = SettingsHarness();
          final response = Completer<NotificationPreferences>();
          try {
            await _pumpLoadedSettings(tester, harness, [response]);
            expectSwitchStates(tester, [true, false, true, false]);

            await tester.tap(find.text(row.label));
            await tester.pump();
            expectSwitchStates(tester, row.pending);
            expect(harness.sentPuts, [row.sent]);

            response.complete(
              const NotificationPreferences(
                postReply: false,
                commentReply: false,
                mention: false,
                upvote: false,
              ),
            );
            await tester.pump();
            expectSwitchStates(tester, [false, false, false, false]);
          } finally {
            await harness.dispose(tester);
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('B7 failed toggle reverts and explains the failure', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final rows = [
        (error: ServerException('Server unavailable'), indexed: false),
        (
          error: ApiException(
            'Bad request',
            statusCode: 400,
            errorCode: 'AccountNotIndexed',
          ),
          indexed: true,
        ),
        (
          error: ApiException(
            'AccountNotIndexed',
            statusCode: 400,
            errorCode: 'SomethingElse',
          ),
          indexed: false,
        ),
      ];
      for (final row in rows) {
        final harness = SettingsHarness();
        final response = Completer<NotificationPreferences>();
        try {
          await _pumpLoadedSettings(tester, harness, [response]);
          expectSwitchStates(tester, [true, false, true, false]);

          await tester.tap(find.text('Mentions'));
          await tester.pump();
          expectSwitchStates(tester, [true, false, false, false]);
          expect(harness.sentPuts, [
            {'mention': false},
          ]);

          response.completeError(row.error);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expectSwitchStates(tester, [true, false, true, false]);
          final message = _snackBarText(tester);
          expect(message, isNotEmpty);
          if (row.indexed) {
            expect(
              message,
              'Your account is still being set up. Try again in a minute.',
            );
          } else {
            expect(
              message,
              isNot(
                'Your account is still being set up. Try again in a minute.',
              ),
            );
          }
        } finally {
          await harness.dispose(tester);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('B8 unread count refreshes after success but not failure', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final succeeds in [true, false]) {
        final harness = SettingsHarness();
        final response = Completer<NotificationPreferences>();
        try {
          await _pumpLoadedSettings(tester, harness, [response]);
          expectSwitchStates(tester, [true, false, true, false]);

          await tester.tap(find.text('Mentions'));
          await tester.pump();
          expect(harness.sentPuts, [
            {'mention': false},
          ]);
          expect(harness.unreadCount.refreshCalls, 0);

          if (succeeds) {
            response.complete(
              const NotificationPreferences(
                postReply: true,
                commentReply: false,
                mention: false,
                upvote: false,
              ),
            );
          } else {
            response.completeError(ServerException('Server unavailable'));
          }
          await tester.pump();
          await tester.pump();
          expect(harness.unreadCount.refreshCalls, succeeds ? 1 : 0);
        } finally {
          await harness.dispose(tester);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('B9 sends serialize and later toggle survives older response', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = SettingsHarness();
    final mentionResponse = Completer<NotificationPreferences>();
    final upvoteResponse = Completer<NotificationPreferences>();
    final postReplyResponse = Completer<NotificationPreferences>();
    try {
      await _pumpLoadedSettings(tester, harness, [
        mentionResponse,
        upvoteResponse,
        postReplyResponse,
      ]);
      expectSwitchStates(tester, [true, false, true, false]);

      await tester.tap(find.text('Mentions'));
      await tester.pump();
      await tester.tap(find.text('Likes'));
      await tester.pump();
      expectSwitchStates(tester, [true, false, false, true]);
      expect(harness.sentPuts, [
        {'mention': false},
      ]);
      expect(harness.unreadCount.refreshCalls, 0);

      mentionResponse.complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: false,
          upvote: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expectSwitchStates(tester, [true, false, false, true]);
      expect(harness.sentPuts, [
        {'mention': false},
        {'upvote': true},
      ]);

      upvoteResponse.complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: true,
          mention: false,
          upvote: true,
        ),
      );
      await tester.pump();
      expectSwitchStates(tester, [true, true, false, true]);
      expect(harness.unreadCount.refreshCalls, 2);

      // The queue has drained; a new toggle must start sending again.
      await tester.tap(find.text('Replies to your posts'));
      await tester.pump();
      expectSwitchStates(tester, [false, true, false, true]);
      expect(harness.sentPuts, [
        {'mention': false},
        {'upvote': true},
        {'postReply': false},
      ]);

      postReplyResponse.complete(
        const NotificationPreferences(
          postReply: false,
          commentReply: true,
          mention: false,
          upvote: true,
        ),
      );
      await tester.pump();
      expectSwitchStates(tester, [false, true, false, true]);
      expect(harness.unreadCount.refreshCalls, 3);
    } finally {
      semantics.dispose();
      await harness.dispose(tester);
    }
  });

  testWidgets('B10 a failed toggle drops only its own queued change', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final secondIsMention in [false, true]) {
        final harness = SettingsHarness();
        final firstResponse = Completer<NotificationPreferences>();
        final secondResponse = Completer<NotificationPreferences>();
        final thirdResponse = Completer<NotificationPreferences>();
        final fourthResponse = Completer<NotificationPreferences>();
        try {
          await _pumpLoadedSettings(tester, harness, [
            firstResponse,
            secondResponse,
            thirdResponse,
            fourthResponse,
          ]);
          expectSwitchStates(tester, [true, false, true, false]);

          await tester.tap(find.text('Mentions'));
          await tester.pump();
          await tester.tap(find.text(secondIsMention ? 'Mentions' : 'Likes'));
          await tester.pump();
          if (secondIsMention) {
            // A third tap makes the latest pending Mentions value (false)
            // differ from the loaded server value (true).
            await tester.tap(find.text('Mentions'));
            await tester.pump();
          }
          expectSwitchStates(
            tester,
            secondIsMention
                ? [true, false, false, false]
                : [true, false, false, true],
          );
          expect(harness.sentPuts, [
            {'mention': false},
          ]);

          firstResponse.completeError(ServerException('Server unavailable'));
          await tester.pump();
          await tester.pump();
          expectSwitchStates(
            tester,
            secondIsMention
                ? [true, false, false, false]
                : [true, false, true, true],
          );
          if (secondIsMention) {
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
            ]);
          } else {
            expect(harness.sentPuts, [
              {'mention': false},
              {'upvote': true},
            ]);
          }

          secondResponse.complete(
            secondIsMention
                ? const NotificationPreferences(
                    postReply: true,
                    commentReply: true,
                    mention: true,
                    upvote: false,
                  )
                : const NotificationPreferences(
                    postReply: false,
                    commentReply: true,
                    mention: true,
                    upvote: true,
                  ),
          );
          await tester.pump();
          if (secondIsMention) {
            expectSwitchStates(tester, [true, true, false, false]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
              {'mention': false},
            ]);

            // The last queued change fails, draining the queue; a new toggle
            // must start sending again.
            thirdResponse.completeError(ServerException('Server unavailable'));
            await tester.pump();
            await tester.pump();
            expectSwitchStates(tester, [true, true, true, false]);

            await tester.tap(find.text('Likes'));
            await tester.pump();
            expectSwitchStates(tester, [true, true, true, true]);
            expect(harness.sentPuts, [
              {'mention': false},
              {'mention': true},
              {'mention': false},
              {'upvote': true},
            ]);

            fourthResponse.complete(
              const NotificationPreferences(
                postReply: true,
                commentReply: true,
                mention: true,
                upvote: true,
              ),
            );
            await tester.pump();
            expectSwitchStates(tester, [true, true, true, true]);
          } else {
            expectSwitchStates(tester, [false, true, true, true]);
          }
        } finally {
          await harness.dispose(tester);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('B11 leaving Settings keeps sending queued toggles', (
    tester,
  ) async {
    final harness = SettingsHarness();
    final mentionResponse = Completer<NotificationPreferences>();
    final upvoteResponse = Completer<NotificationPreferences>();
    try {
      await _pumpLoadedSettings(tester, harness, [
        mentionResponse,
        upvoteResponse,
      ], home: const Scaffold(body: Text('Home')));
      unawaited(
        harness.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mentions'));
      await tester.pump();
      await tester.tap(find.text('Likes'));
      await tester.pump();
      expect(harness.sentPuts, [
        {'mention': false},
      ]);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      mentionResponse.complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: false,
          upvote: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(harness.sentPuts, [
        {'mention': false},
        {'upvote': true},
      ]);
      expect(harness.unreadCount.refreshCalls, 1);

      upvoteResponse.completeError(NetworkException('Connection unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.unreadCount.refreshCalls, 1);
      expect(
        _snackBarText(tester),
        'No connection. Please check your internet.',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B13 reopened Settings joins the queue of the popped screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = SettingsHarness();
    try {
      harness.stubPendingPreferenceRequests();
      when(harness.api.getNotificationPreferences())
          .thenAnswer((_) async => _loadedPreferences);
      await harness.pumpRouter(tester);
      await harness.openSettings(tester);
      expectSwitchStates(tester, [true, false, true, false]);

      await tester.tap(find.text('Mentions'));
      await tester.pump();
      expectSwitchStates(tester, [true, false, false, false]);
      expect(harness.sentPuts, [
        {'mention': false},
      ]);

      await harness.closeSettings(tester);
      await harness.openSettings(tester);
      expectSwitchStates(tester, [true, false, false, false]);

      await tester.tap(find.text('Likes'));
      await tester.pump();
      expectSwitchStates(tester, [true, false, false, true]);
      expect(harness.sentPuts, [
        {'mention': false},
      ]);

      harness.putResponses[0].complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: false,
          upvote: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(harness.sentPuts, [
        {'mention': false},
        {'upvote': true},
      ]);
      expectSwitchStates(tester, [true, false, false, true]);

      harness.putResponses[1].complete(
        const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: false,
          upvote: true,
        ),
      );
      await tester.pump();
      expectSwitchStates(tester, [true, false, false, true]);
    } finally {
      semantics.dispose();
      await harness.dispose(tester);
    }
  });

  testWidgets('B12 a toggle failure shows the mapped error message', (
    tester,
  ) async {
    final harness = SettingsHarness();
    final response = Completer<NotificationPreferences>();
    try {
      await _pumpLoadedSettings(tester, harness, [response]);

      await tester.tap(find.text('Mentions'));
      await tester.pump();
      response.completeError(NetworkException('Connection unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        _snackBarText(tester),
        'No connection. Please check your internet.',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6b the signed-out prompt shows the Lucide bell', (
    tester,
  ) async {
    final harness = SettingsHarness(signedInDid: null);
    try {
      await harness.pump(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Sign in to manage your notification settings'),
        findsOneWidget,
      );

      expectLucideGlyph(
        tester,
        within: find.byType(SettingsScreen),
        paths: LucidePaths.bell,
        color: const Color(0xFFFF8040),
        size: 64,
      );
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B7 preference switches paint a coral track when on and a muted '
      'one when off', (tester) async {
    final harness = SettingsHarness();
    try {
      await _pumpLoadedSettings(tester, harness, []);
      // _loadedPreferences: postReply on, commentReply off.
      final onSwitch = tester.renderObject(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Replies to your posts'),
          matching: find.byType(Switch),
        ),
      );
      final offSwitch = tester.renderObject(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Replies to your comments'),
          matching: find.byType(Switch),
        ),
      );

      expect(
        onSwitch,
        paints
          // Track: solid coral.
          ..rrect(color: const Color(0xFFFF8040), style: PaintingStyle.fill)
          // Track outline: transparent.
          ..rrect(color: const Color(0x00000000), style: PaintingStyle.stroke)
          // Thumb: textPrimary.
          ..rrect(color: const Color(0xFFFFF8F0), style: PaintingStyle.fill),
      );
      expect(
        offSwitch,
        paints
          // Track: textMuted.
          ..rrect(color: const Color(0xFF5A6B70), style: PaintingStyle.fill)
          // Track outline: transparent.
          ..rrect(color: const Color(0x00000000), style: PaintingStyle.stroke)
          // Thumb: textPrimary.
          ..rrect(color: const Color(0xFFFFF8F0), style: PaintingStyle.fill),
      );
    } finally {
      await harness.dispose(tester);
    }
  });
}
