import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_shell_harness.dart';

void main() {
  testWidgets(
    'B3 two rises under post cover coalesce into one reload and mark',
    (tester) async {
      final harness = NotificationsRouterHarness();
      try {
        await harness.mount(tester);
        await harness.select(tester, 'Notifications');
        expect(harness.shell.cursors, [null]);
        await harness.showPage(tester, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
        expect(harness.countProvider(tester).count, 0);

        await harness.pushPost(tester);
        harness.shell.count = 2;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 2);
        harness.shell.count = 4;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 4);
        expect(harness.shell.cursors, [null]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);

        await harness.pop(tester);
        expect(harness.shell.cursors, [null, null]);
        await harness.showPage(tester, 1, [
          ('early', '2026-10-09T11:00:00Z'),
          ('latest', '2026-10-09T11:07:00Z'),
        ]);
        expect(harness.shell.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T11:07:00Z',
        ]);

        await harness.pushPost(tester);
        await harness.pop(tester);
        expect(harness.shell.cursors, [null, null]);
        expect(harness.shell.seenAt, [
          '2026-10-09T09:00:00Z',
          '2026-10-09T11:07:00Z',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B3 post cover without count rise sends no reload or mark', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness();
    try {
      await harness.mount(tester);
      await harness.select(tester, 'Notifications');
      await harness.showPage(tester, 0, [('old', '2026-10-09T09:00:00Z')]);
      expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);

      await harness.pushPost(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
      await harness.pop(tester);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B3 rise then fall under post cover still reloads on return', (
    tester,
  ) async {
    final harness = NotificationsRouterHarness();
    try {
      await harness.mount(tester);
      await harness.select(tester, 'Notifications');
      await harness.showPage(tester, 0, [('old', '2026-10-09T09:00:00Z')]);
      expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);

      await harness.pushPost(tester);
      harness.shell.count = 2;
      await harness.countProvider(tester).refresh();
      await holdRouterFrames(tester);
      expect(harness.countProvider(tester).count, 2);
      harness.shell.count = 0;
      await harness.countProvider(tester).refresh();
      await holdRouterFrames(tester);
      expect(harness.countProvider(tester).count, 0);
      expect(harness.shell.cursors, [null]);
      expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);

      await harness.pop(tester);
      expect(harness.shell.cursors, [null, null]);
      await harness.showPage(tester, 1, [('new', '2026-10-09T11:07:00Z')]);
      expect(harness.shell.seenAt, [
        '2026-10-09T09:00:00Z',
        '2026-10-09T11:07:00Z',
      ]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B3 rise answered by a same-frame tab switch does not reload on a later '
    'pop',
    (tester) async {
      final harness = NotificationsRouterHarness();
      try {
        await harness.mount(tester);
        await harness.select(tester, 'Notifications');
        await harness.showPage(tester, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);

        harness.shell.count = 3;
        await harness.countProvider(tester).refresh();
        expect(harness.countProvider(tester).count, 3);
        await tester.tap(phoneNavItem('Home'));
        await holdRouterFrames(tester);
        expect(harness.shell.cursors, [null]);

        harness.shell.count = 0;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 0);
        await harness.select(tester, 'Notifications');
        expect(harness.countProvider(tester).count, 0);
        expect(harness.shell.cursors, [null]);

        await harness.pushPost(tester);
        await harness.pop(tester);
        expect(harness.shell.cursors, [null]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'B3 rise and fall while another tab is selected does not reload on a '
    'later pop',
    (tester) async {
      final harness = NotificationsRouterHarness();
      try {
        await harness.mount(tester);
        await harness.select(tester, 'Notifications');
        await harness.showPage(tester, 0, [('old', '2026-10-09T09:00:00Z')]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
        await harness.select(tester, 'Home');

        harness.shell.count = 3;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 3);
        harness.shell.count = 0;
        await harness.countProvider(tester).refresh();
        await holdRouterFrames(tester);
        expect(harness.countProvider(tester).count, 0);

        await harness.select(tester, 'Notifications');
        expect(harness.shell.cursors, [null]);
        await harness.pushPost(tester);
        await harness.pop(tester);
        expect(harness.shell.cursors, [null]);
        expect(harness.shell.seenAt, ['2026-10-09T09:00:00Z']);
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
