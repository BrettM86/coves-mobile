import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notifications_shell_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';

const _rootUri = 'at://did:plc:writer/social.coves.community.post/root';
const _firstUri = 'at://did:plc:writer/social.coves.community.comment/first';
const _secondUri = 'at://did:plc:writer/social.coves.community.comment/second';

NotificationPage _page(List<(String, String)> entries) =>
    NotificationPage.fromJson({
      'notifications': [
        for (final (uri, sortAt) in entries)
          replyNotificationWireFor(recordUri: uri, rootUri: _rootUri)
            ..['sortAt'] = sortAt,
      ],
      'cursor': null,
    });

void main() {
  testWidgets('B3 marks page one only after its selected tab draws the rows', (
    tester,
  ) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0, pendingPages: true);
    try {
      await harness.mount(tester);
      await tester.tap(phoneNavItem('Notifications'));
      await tester.pump();
      expect(harness.pages, hasLength(1));

      harness.pages.single.complete(
        _page([
          (_firstUri, '2026-10-08T12:00:00.123456789Z'),
          (_secondUri, '2026-10-08T12:00:00.123456790Z'),
        ]),
      );
      await tester.idle();
      final provider = tester
          .element(find.byType(NotificationsScreen))
          .read<NotificationsListProvider>();
      expect(provider.controller.items.map((row) => row.record!.uri).toList(), [
        'at://did:plc:writer/social.coves.community.comment/first',
        'at://did:plc:writer/social.coves.community.comment/second',
      ]);
      expect(harness.seenAt, isEmpty);

      await tester.pump();
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/first'),
        findsOneWidget,
      );
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/second'),
        findsOneWidget,
      );
      expect(harness.seenAt, ['2026-10-08T12:00:00.123456790Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B4 page one landing on Home waits for Notifications selection', (
    tester,
  ) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0, pendingPages: true);
    try {
      await harness.mount(tester);
      await tester.tap(phoneNavItem('Notifications'));
      await tester.pump();
      expect(harness.pages, hasLength(1));
      await tester.tap(phoneNavItem('Home'));
      await tester.pump();
      harness.pages.single.complete(
        _page([(_firstUri, '2026-10-08T12:05:00Z')]),
      );
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      expect(harness.seenAt, isEmpty);

      await tester.tap(phoneNavItem('Notifications'));
      await tester.pump();
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/first'),
        findsOneWidget,
      );
      expect(harness.seenAt, ['2026-10-08T12:05:00Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B5 selected empty page one does not send an update', (
    tester,
  ) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0, pendingPages: true);
    try {
      await harness.mount(tester);
      await tester.tap(phoneNavItem('Notifications'));
      await tester.pump();
      expect(harness.pages, hasLength(1));
      harness.pages.single.complete(_page([]));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(harness.seenAt, isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });
}
