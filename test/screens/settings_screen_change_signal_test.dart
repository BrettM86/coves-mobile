import 'dart:async';

import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/settings_screen_harness.dart';

void main() {
  testWidgets(
    'B5 each successful preference toggle increments the change version once',
    (tester) async {
      final signal = NotificationPreferencesChangeSignal();
      final harness = SettingsHarness(
        notificationPreferencesChangeSignal: signal,
      );
      final first = Completer<NotificationPreferences>();
      final second = Completer<NotificationPreferences>();
      var putCalls = 0;
      when(harness.api.getNotificationPreferences()).thenAnswer(
        (_) async => const NotificationPreferences(
          postReply: true,
          commentReply: false,
          mention: true,
          upvote: false,
        ),
      );
      when(
        harness.api.putNotificationPreferences(
          postReply: anyNamed('postReply'),
          commentReply: anyNamed('commentReply'),
          mention: anyNamed('mention'),
          upvote: anyNamed('upvote'),
        ),
      ).thenAnswer((_) => ++putCalls == 1 ? first.future : second.future);
      try {
        await harness.pump(tester);
        await tester.pumpAndSettle();
        expect(signal.version, 0);

        await tester.tap(find.text('Mentions'));
        await tester.pump();
        expect(signal.version, 0);
        first.complete(
          const NotificationPreferences(
            postReply: true,
            commentReply: false,
            mention: false,
            upvote: false,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(signal.version, 1);

        await tester.tap(find.text('Likes'));
        await tester.pump();
        expect(putCalls, 2);
        second.complete(
          const NotificationPreferences(
            postReply: true,
            commentReply: false,
            mention: false,
            upvote: true,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(signal.version, 2);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B5 failed preference toggle leaves the change version at zero', (
    tester,
  ) async {
    final signal = NotificationPreferencesChangeSignal();
    final harness = SettingsHarness(
      notificationPreferencesChangeSignal: signal,
    );
    final response = Completer<NotificationPreferences>();
    when(harness.api.getNotificationPreferences()).thenAnswer(
      (_) async => const NotificationPreferences(
        postReply: true,
        commentReply: false,
        mention: true,
        upvote: false,
      ),
    );
    when(
      harness.api.putNotificationPreferences(
        postReply: anyNamed('postReply'),
        commentReply: anyNamed('commentReply'),
        mention: anyNamed('mention'),
        upvote: anyNamed('upvote'),
      ),
    ).thenAnswer((_) => response.future);
    try {
      await harness.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mentions'));
      await tester.pump();
      response.completeError(ServerException('Server unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(signal.version, 0);
    } finally {
      await harness.dispose(tester);
    }
  });
}
