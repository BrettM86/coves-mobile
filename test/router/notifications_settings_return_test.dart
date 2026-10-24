import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/screens/settings/settings_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_shell_harness.dart';

const _initialSeen = '2026-10-09T09:00:00Z';
const _mentionOff = NotificationPreferences(
  postReply: true,
  commentReply: false,
  mention: false,
  upvote: false,
);
const _mentionAndUpvote = NotificationPreferences(
  postReply: true,
  commentReply: false,
  mention: false,
  upvote: true,
);

Future<void> _showInitialNotifications(
  WidgetTester tester,
  NotificationsRouterHarness harness,
) async {
  await harness.mount(tester);
  await harness.select(tester, 'Notifications');
  expect(harness.shell.cursors, [null]);
  await harness.showPage(tester, 0, [('old', _initialSeen)]);
  expect(harness.shell.seenAt, [_initialSeen]);
  expect(harness.countProvider(tester).count, 0);
}

Future<void> _toggle(
  WidgetTester tester,
  NotificationsRouterHarness harness,
  String label,
  int expectedPuts,
) async {
  await tester.tap(find.text(label));
  await holdRouterFrames(tester);
  expect(harness.settingsPuts, hasLength(expectedPuts));
}

void main() {
  testWidgets('B4 signed-in Notifications gear opens the real Settings route', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await holdRouterFrames(tester);
      expect(harness.router.state.uri.path, '/settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B4 signed-out Notifications has no Settings gear', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness(signedIn: false);
    try {
      await harness.mount(tester);
      await harness.select(tester, 'Notifications');
      expect(find.text('Sign in to view your notifications'), findsOneWidget);
      await holdRouterFrames(tester);
      expect(find.byTooltip('Settings'), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6 gear return after a successful toggle reloads once', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await holdRouterFrames(tester);
      expect(harness.router.state.uri.path, '/settings');
      await _toggle(tester, harness, 'Mentions', 1);
      harness.settingsPuts.single.complete(_mentionOff);
      await holdRouterFrames(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, [_initialSeen]);

      await harness.pop(tester);
      expect(harness.shell.cursors, [null, null]);
      await harness.showPage(tester, 1, [('changed', '2026-10-09T11:07:00Z')]);
      expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);

      await tester.tap(find.byTooltip('Settings'));
      await holdRouterFrames(tester);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null, null]);
      expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6 Settings return without toggle sends no reload', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      await harness.openSettings(tester);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, [_initialSeen]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6 failed Settings toggle sends no reload on return', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      await harness.openSettings(tester);
      await _toggle(tester, harness, 'Mentions', 1);
      harness.settingsPuts.single.completeError(ServerException('Unavailable'));
      await holdRouterFrames(tester);
      expect(harness.shell.cursors, [null]);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, [_initialSeen]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6 two successful Settings toggles coalesce on return', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      await harness.openSettings(tester);
      await _toggle(tester, harness, 'Mentions', 1);
      harness.settingsPuts[0].complete(_mentionOff);
      await holdRouterFrames(tester);
      await _toggle(tester, harness, 'Likes', 2);
      harness.settingsPuts[1].complete(_mentionAndUpvote);
      await holdRouterFrames(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, [_initialSeen]);

      await harness.pop(tester);
      expect(harness.shell.cursors, [null, null]);
      await harness.showPage(tester, 1, [('changed', '2026-10-09T11:07:00Z')]);
      expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);
      await harness.openSettings(tester);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null, null]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6 late successful put reloads visible list after return', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness()..stubSettings();
    try {
      await _showInitialNotifications(tester, harness);
      await harness.openSettings(tester);
      await _toggle(tester, harness, 'Mentions', 1);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, [_initialSeen]);

      harness.settingsPuts.single.complete(_mentionOff);
      await holdRouterFrames(tester);
      expect(harness.shell.cursors, [null, null]);
      await harness.showPage(tester, 1, [('changed', '2026-10-09T11:07:00Z')]);
      expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B7 count rise and Settings toggle merge into one return reload',
    (tester) async {
      final harness = NotificationsRouterHarness()..stubSettings();
      try {
        await _showInitialNotifications(tester, harness);
        await harness.openSettings(tester);
        await _toggle(tester, harness, 'Mentions', 1);
        harness.settingsPuts.single.complete(_mentionOff);
        await holdRouterFrames(tester);
        harness.shell.count = 3;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 3);
        expect(harness.shell.cursors, [null]);
        expect(harness.shell.seenAt, [_initialSeen]);

        await harness.pop(tester);
        expect(harness.shell.cursors, [null, null]);
        await harness.showPage(tester, 1, [('merged', '2026-10-09T11:07:00Z')]);
        expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  for (final countOnReturn in [0, 3]) {
    testWidgets(
      'B8 Profile change reloads on Notifications (count $countOnReturn)',
      (tester) async {
        final harness = NotificationsRouterHarness()..stubSettings();
        try {
          await _showInitialNotifications(tester, harness);
          await harness.select(tester, 'Me');
          await tester.tap(find.byTooltip('Menu'));
          await holdRouterFrames(tester);
          expect(find.text('Settings'), findsOneWidget);
          await tester.tap(find.text('Settings'));
          await holdRouterFrames(tester);
          expect(harness.router.state.uri.path, '/settings');
          expect(find.byType(SettingsScreen), findsOneWidget);

          await _toggle(tester, harness, 'Mentions', 1);
          harness.settingsPuts.single.complete(_mentionOff);
          await holdRouterFrames(tester);
          await harness.pop(tester);
          expect(harness.shell.cursors, [null]);
          expect(harness.shell.seenAt, [_initialSeen]);
          if (countOnReturn == 3) {
            harness.shell.count = 3;
            await harness.countProvider(tester).refresh();
            await holdRouterFrames(tester);
            expect(harness.countProvider(tester).count, 3);
            expect(harness.shell.cursors, [null]);
          }
          await harness.select(tester, 'Notifications');
          expect(harness.shell.cursors, [null, null]);
          await harness.showPage(tester, 1, [
            ('changed', '2026-10-09T11:07:00Z'),
          ]);
          expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);

          await harness.select(tester, 'Home');
          harness.shell.count = 0;
          await harness.countProvider(tester).refresh();
          await holdRouterFrames(tester);
          expect(harness.countProvider(tester).count, 0);
          await harness.select(tester, 'Notifications');
          expect(harness.shell.cursors, [null, null]);
          expect(harness.shell.seenAt, [_initialSeen, '2026-10-09T11:07:00Z']);
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }
}
