import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notifications_shell_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';

const _rootUri = 'at://did:plc:writer/social.coves.community.post/root';

NotificationPage _page(List<(String, String)> rows) =>
    NotificationPage.fromJson({
      'notifications': [
        for (final (suffix, sortAt) in rows)
          replyNotificationWireFor(
            recordUri:
                'at://did:plc:writer/social.coves.community.comment/$suffix',
            rootUri: _rootUri,
          )..['sortAt'] = sortAt,
      ],
      'cursor': null,
    });

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

Future<void> _showPage(
  WidgetTester tester,
  NotificationsShellHarness harness,
  int index,
  List<(String, String)> rows,
) async {
  harness.pages[index].complete(_page(rows));
  await _pumpFrames(tester);
  for (final (suffix, _) in rows) {
    expect(
      find.text('at://did:plc:writer/social.coves.community.comment/$suffix'),
      findsOneWidget,
    );
  }
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(phoneNavItem(label));
  await _pumpFrames(tester);
}

UnreadNotificationCountProvider _countProvider(WidgetTester tester) => tester
    .element(find.byType(MainShellScreen))
    .read<UnreadNotificationCountProvider>();

void main() {
  testWidgets(
    'B1 steady unread count reloads on return and marks the new page',
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final harness = NotificationsShellHarness(count: 0, pendingPages: true);
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        expect(harness.pages, hasLength(1));
        await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.seenAt, ['2026-10-09T09:00:00Z']);

        await _select(tester, 'Home');
        harness.count = 3;
        await _countProvider(tester).refresh();
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 3);
        expect(harness.pages, hasLength(1));

        await _select(tester, 'Notifications');
        expect(harness.pages, hasLength(2));
        verify(harness.api.listNotifications()).called(2);
        await _showPage(tester, harness, 1, [
          ('new-early', '2026-10-09T10:00:00Z'),
          ('new-late', '2026-10-09T10:05:00Z'),
        ]);
        expect(harness.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T10:05:00Z',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B1 returning with zero unread does not reload or mark again', (
    tester,
  ) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0, pendingPages: true);
    try {
      await harness.mount(tester);
      await _select(tester, 'Notifications');
      await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
      expect(harness.seenAt, ['2026-10-09T09:00:00Z']);
      await _select(tester, 'Home');
      await _countProvider(tester).refresh();
      expect(_countProvider(tester).count, 0);
      await _select(tester, 'Notifications');
      await tester.pump(const Duration(milliseconds: 100));
      await _pumpFrames(tester);
      expect(harness.pages, hasLength(1));
      expect(harness.seenAt, ['2026-10-09T09:00:00Z']);
      verify(harness.api.listNotifications()).called(1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B1 first selection with unread count loads page one only once', (
    tester,
  ) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 3, pendingPages: true);
    try {
      await harness.mount(tester);
      expect(_countProvider(tester).count, 3);
      await _select(tester, 'Notifications');
      await tester.pump(const Duration(milliseconds: 100));
      await _pumpFrames(tester);
      expect(harness.pages, hasLength(1));
      verify(harness.api.listNotifications()).called(1);
      await _showPage(tester, harness, 0, [('first', '2026-10-09T09:00:00Z')]);
      expect(harness.seenAt, ['2026-10-09T09:00:00Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B1 return with unread after failed refresh retries page one and marks it',
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final harness = NotificationsShellHarness(count: 0, pendingPages: true);
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.seenAt, ['2026-10-09T09:00:00Z']);

        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, 600),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(harness.pages, hasLength(2));
        harness.pages[1].completeError(
          ServerException('Server failure', statusCode: 500),
        );
        await _pumpFrames(tester);
        expect(find.text('Retry'), findsOneWidget);
        expect(
          find.text('at://did:plc:writer/social.coves.community.comment/old'),
          findsOneWidget,
        );

        await _select(tester, 'Home');
        harness.count = 3;
        await _countProvider(tester).refresh();
        expect(_countProvider(tester).count, 3);
        await _select(tester, 'Notifications');
        expect(harness.pages, hasLength(3));
        verify(harness.api.listNotifications()).called(3);
        await _showPage(tester, harness, 2, [
          ('recovered-early', '2026-10-09T11:00:00Z'),
          ('recovered-late', '2026-10-09T11:05:00Z'),
        ]);
        expect(harness.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T11:05:00Z',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'B2 count rise on visible Notifications reloads and marks its page',
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final harness = NotificationsShellHarness(count: 2, pendingPages: true);
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.seenAt, ['2026-10-09T09:00:00Z']);
        expect(_countProvider(tester).count, 2);

        harness.count = 5;
        await _countProvider(tester).refresh();
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 5);
        expect(harness.pages, hasLength(2));
        verify(harness.api.listNotifications()).called(2);
        await _showPage(tester, harness, 1, [
          ('new-early', '2026-10-09T12:00:00Z'),
          ('new-late', '2026-10-09T12:05:00Z'),
        ]);
        expect(harness.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T12:05:00Z',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'B2 count fall and unchanged count do not reload the visible list',
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final harness = NotificationsShellHarness(count: 2, pendingPages: true);
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(_countProvider(tester).count, 2);
        harness.count = 5;
        await _countProvider(tester).refresh();
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 5);
        expect(harness.pages, hasLength(2));
        await _showPage(tester, harness, 1, [('new', '2026-10-09T12:00:00Z')]);
        expect(harness.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T12:00:00Z',
        ]);

        harness.count = 3;
        await _countProvider(tester).refresh();
        await tester.pump(const Duration(milliseconds: 100));
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 3);
        expect(harness.pages, hasLength(2));

        await _countProvider(tester).refresh();
        await tester.pump(const Duration(milliseconds: 100));
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 3);
        expect(harness.pages, hasLength(2));
        expect(harness.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T12:00:00Z',
        ]);
        verify(harness.api.listNotifications()).called(2);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'B2 count rise while Feed is selected does not reload Notifications',
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final harness = NotificationsShellHarness(count: 2, pendingPages: true);
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        await _showPage(tester, harness, 0, [('old', '2026-10-09T09:00:00Z')]);
        await _select(tester, 'Home');
        harness.count = 5;
        await _countProvider(tester).refresh();
        await tester.pump(const Duration(milliseconds: 100));
        await _pumpFrames(tester);
        expect(_countProvider(tester).count, 5);
        expect(harness.pages, hasLength(1));
        expect(harness.seenAt, ['2026-10-09T09:00:00Z']);
        verify(harness.api.listNotifications()).called(1);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'B3 a preference change from the previous session does not reload the '
    "next session's list",
    (tester) async {
      useShellViewport(tester, const Size(540, 960));
      final signal = NotificationPreferencesChangeSignal();
      final harness = NotificationsShellHarness(
        count: 0,
        pendingPages: true,
        notificationPreferencesChangeSignal: signal,
      );
      try {
        await harness.mount(tester);
        await _select(tester, 'Notifications');
        await _showPage(tester, harness, 0, [
          ('alice-row', '2026-10-09T09:00:00Z'),
        ]);
        final mountedScreen = tester.state(
          find.byType(NotificationsScreen, skipOffstage: false),
        );

        await _select(tester, 'Home');
        // A Settings save under alice while the list is not selected.
        signal.bump();
        await _pumpFrames(tester);
        expect(harness.requestDids, ['did:plc:alice']);

        harness.auth.setSignedInDid('did:plc:bob');
        await _pumpFrames(tester);
        expect(harness.requestDids, ['did:plc:alice', 'did:plc:bob']);
        harness.pages[1].complete(_page([('bob-row', '2026-10-09T10:00:00Z')]));
        await _pumpFrames(tester);

        await _select(tester, 'Notifications');
        await tester.pump(const Duration(milliseconds: 100));
        await _pumpFrames(tester);
        expect(
          tester.state(find.byType(NotificationsScreen, skipOffstage: false)),
          same(mountedScreen),
          reason: 'the same mounted list must be shown again',
        );
        expect(
          find.text(
            'at://did:plc:writer/social.coves.community.comment/'
            'bob-row',
          ),
          findsOneWidget,
        );
        expect(_countProvider(tester).count, 0);
        expect(harness.requestDids, ['did:plc:alice', 'did:plc:bob']);
        expect(harness.cursors, [null, null]);
      } finally {
        await harness.dispose(tester);
        signal.dispose();
      }
    },
  );
}
