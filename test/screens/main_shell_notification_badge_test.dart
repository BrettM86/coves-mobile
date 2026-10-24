import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/notifications_shell_harness.dart';

Finder _bellIcon(WidgetTester tester, {required bool tablet}) {
  if (!tablet) {
    return phoneNavItem('Notifications');
  }
  final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
  final destination = rail.destinations[3];
  final icon = rail.selectedIndex == 3
      ? destination.selectedIcon
      : destination.icon;
  return find.byWidgetPredicate((widget) => identical(widget, icon));
}

void main() {
  testWidgets('B6 every phone tab tap refreshes unread count once, including '
      'reselecting Notifications and Home', (tester) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0);
    try {
      await harness.mount(tester);
      clearInteractions(harness.api);

      for (final label in [
        'Communities',
        'Create',
        'Notifications',
        'Notifications',
        'Me',
        'Home',
        'Home',
      ]) {
        await tester.tap(phoneNavItem(label));
        await tester.pump();
        await tester.pump();
        verify(harness.api.getUnreadCount()).called(1);
      }
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('the phone bell sits centered in its tab slot with the badge '
      'overlapping its upper right', (tester) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 4);
    try {
      await harness.mount(tester);
      final slot = tester.getRect(phoneNavItem('Notifications'));
      final glyph = tester.getRect(
        find.descendant(
          of: phoneNavItem('Notifications'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(glyph.size, const Size(24, 24));
      expect(glyph.center.dx, moreOrLessEquals(slot.center.dx));
      expect(glyph.center.dy, moreOrLessEquals(slot.center.dy));

      Rect badgeFor(String text) => tester.getRect(
        find
            .ancestor(of: find.text(text), matching: find.byType(Container))
            .first,
      );

      // As on the web: the badge overlaps the bell's upper right, its left
      // edge at the bell's centre for one digit and further left for more.
      final single = badgeFor('4');
      expect(single.left, moreOrLessEquals(glyph.left + 12));
      expect(single.top, moreOrLessEquals(glyph.top - 4));
      expect(single.height, moreOrLessEquals(16));

      harness.count = 120;
      await tester.tap(phoneNavItem('Home'));
      await tester.pump();
      await tester.pump();
      final wide = badgeFor('99+');
      expect(wide.left, moreOrLessEquals(glyph.left + 8));
      expect(wide.top, moreOrLessEquals(glyph.top - 4));
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final (layout, size, tablet) in [
    ('phone', const Size(540, 960), false),
    ('tablet', const Size(1080, 2400), true),
  ]) {
    testWidgets(
      'B7 $layout bell badge shows 0/1/99/99+/99+ and announces 1/99+',
      (tester) async {
        useShellViewport(tester, size);
        final harness = NotificationsShellHarness(count: 0);
        try {
          await harness.mount(tester);
          for (final (count, shown) in [
            (0, null),
            (1, '1'),
            (99, '99'),
            (100, '99+'),
            (101, '99+'),
          ]) {
            if (count != 0) {
              harness.count = count;
              await tester.tap(
                tablet ? find.text('Home').last : phoneNavItem('Home'),
              );
              await tester.pump();
              await tester.pump();
            }
            final bell = _bellIcon(tester, tablet: tablet);
            expect(bell, findsOneWidget);
            if (shown == null) {
              expect(
                find.descendant(
                  of: bell,
                  matching: find.textContaining(RegExp(r'^\d+\+?$')),
                ),
                findsNothing,
              );
            } else {
              expect(
                find.descendant(of: bell, matching: find.text(shown)),
                findsOneWidget,
              );
            }
            if (count == 1 || count == 101 || (tablet && count == 0)) {
              final semantics = tester.ensureSemantics();
              try {
                final notificationDestination = tablet
                    ? find.descendant(
                        of: find.byType(NavigationRail),
                        matching: find.bySemanticsLabel(
                          RegExp('^Notifications'),
                        ),
                      )
                    : phoneNavItem('Notifications');
                // The rail merges icon and label into one destination node,
                // so the name must be announced exactly once.
                expect(
                  tester.getSemantics(notificationDestination).label,
                  tablet
                      ? equals(
                          shown == null
                              ? 'Notifications\nTab 4 of 5'
                              : 'Notifications, $shown unread\nTab 4 of 5',
                        )
                      : contains(shown),
                );
              } finally {
                semantics.dispose();
              }
            }
          }
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  testWidgets('B7 refresh updates the mounted phone bell from 1 to 5 and '
      'sign-out clears it', (tester) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 1);
    try {
      await harness.mount(tester);
      expect(
        find.descendant(
          of: _bellIcon(tester, tablet: false),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      harness.count = 5;
      await tester.tap(phoneNavItem('Communities'));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: _bellIcon(tester, tablet: false),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      harness.auth.setSignedInDid(null);
      await tester.pump();
      expect(
        find.descendant(
          of: _bellIcon(tester, tablet: false),
          matching: find.textContaining(RegExp(r'^\d+\+?$')),
        ),
        findsNothing,
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B7 selected tablet Notifications destination retains its badge',
    (tester) async {
      useShellViewport(tester, const Size(1080, 2400));
      final harness = NotificationsShellHarness(count: 1);
      try {
        await harness.mount(tester);
        await tester.tap(find.text('Notifications').last);
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          3,
        );
        expect(
          find.descendant(
            of: _bellIcon(tester, tablet: true),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
