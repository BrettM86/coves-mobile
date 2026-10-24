import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/widgets/notifications/notification_post_card.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:coves_flutter/widgets/notifications/notification_upvote_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_screen_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/theme_pump.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _seenAt = '2026-10-08T12:00:00.000Z';

String _replyUri(String suffix) =>
    'at://did:plc:writer/social.coves.community.comment/$suffix';

Map<String, dynamic> _reply(
  String suffix, {
  required String sortAt,
  required bool isRead,
}) => replyNotificationWireFor(recordUri: _replyUri(suffix), rootUri: postUri)
  ..['sortAt'] = sortAt
  ..['isRead'] = isRead;

NotificationView _parse(Map<String, dynamic> wire) {
  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  return notification!;
}

/// The background Material the row widget builds itself: the outermost
/// Material below the row, not the test scaffold's Material above it.
Color? _rowBackground(WidgetTester tester, Finder row) => tester
    .widget<Material>(
      find.descendant(of: row, matching: find.byType(Material)).first,
    )
    .color;

bool _hasUnreadDot(Finder row) => find
    .descendant(of: row, matching: find.byType(NotificationUnreadDot))
    .evaluate()
    .isNotEmpty;

/// The row's background and whether it shows the unread dot.
Future<(Color?, bool)> _pumpedRow(WidgetTester tester, Widget row) async {
  await pumpUnderAppTheme(tester, SingleChildScrollView(child: row));
  final finder = find.byWidget(row);
  return (_rowBackground(tester, finder), _hasUnreadDot(finder));
}

Finder _replyCardFor(String suffix) => find.byWidgetPredicate(
  (widget) =>
      widget is NotificationReplyCard &&
      widget.notification.record?.uri == _replyUri(suffix),
);

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'B8 unread rows show the unread dot; every row paints the background',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final currentTime = DateTime.utc(2026, 10, 7, 12);

      NotificationReplyCard replyCard({required bool isRead}) =>
          NotificationReplyCard(
            notification: _parse(
              _reply(
                'card',
                sortAt: '2026-10-06T12:00:00.000Z',
                isRead: isRead,
              ),
            ),
            onTap: () {},
            onSensitiveContentToggle: () {},
            currentTime: currentTime,
          );
      NotificationUpvoteRow upvoteRow({required bool isRead}) =>
          NotificationUpvoteRow(
            notification: _parse(
              upvoteWire(upvoters: [aliceUpvoter], count: 1)
                ..['isRead'] = isRead,
            ),
            onTap: () {},
            onSensitiveContentToggle: () {},
            currentTime: currentTime,
          );

      final rows = <String, (Color?, bool)>{
        'unread reply': await _pumpedRow(tester, replyCard(isRead: false)),
        'unread upvote': await _pumpedRow(tester, upvoteRow(isRead: false)),
        'read reply': await _pumpedRow(tester, replyCard(isRead: true)),
        'read upvote': await _pumpedRow(tester, upvoteRow(isRead: true)),
      };

      expect(rows, {
        'unread reply': (AppColors.background, true),
        'unread upvote': (AppColors.background, true),
        'read reply': (AppColors.background, false),
        'read upvote': (AppColors.background, false),
      });
    },
  );

  testWidgets('unread rows say so first to a screen reader; read rows do not', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final currentTime = DateTime.utc(2026, 10, 7, 12);
    final unreadLabel = find.bySemanticsLabel(RegExp('^Unread, '));
    final rows = <String, Widget Function({required bool isRead})>{
      'reply': ({required isRead}) => NotificationReplyCard(
        notification: _parse(
          _reply('card', sortAt: '2026-10-06T12:00:00.000Z', isRead: isRead),
        ),
        onTap: () {},
        onSensitiveContentToggle: () {},
        currentTime: currentTime,
      ),
      'upvote': ({required isRead}) => NotificationUpvoteRow(
        notification: _parse(
          upvoteWire(upvoters: [aliceUpvoter], count: 1)..['isRead'] = isRead,
        ),
        onTap: () {},
        onSensitiveContentToggle: () {},
        currentTime: currentTime,
      ),
    };

    for (final MapEntry(key: kind, value: row) in rows.entries) {
      await pumpUnderAppTheme(
        tester,
        SingleChildScrollView(child: row(isRead: false)),
      );
      expect(unreadLabel, findsOneWidget, reason: 'unread $kind');
      await pumpUnderAppTheme(
        tester,
        SingleChildScrollView(child: row(isRead: true)),
      );
      expect(unreadLabel, findsNothing, reason: 'read $kind');
    }
    semantics.dispose();
  });

  for (final status in ['removedByModerator', 'deleted']) {
    testWidgets('an unread reply on a $status root shows the unread dot', (
      tester,
    ) async {
      final wire = _reply(
        'gone-root',
        sortAt: '2026-10-06T12:00:00.000Z',
        isRead: false,
      )..['rootPost'] = {'uri': postUri, 'cid': 'bafyroot', 'status': status};
      final row = NotificationReplyCard(
        notification: _parse(wire),
        onTap: () {},
        onSensitiveContentToggle: () {},
        currentTime: DateTime.utc(2026, 10, 7, 12),
      );

      final (_, hasDot) = await _pumpedRow(tester, row);

      expect(hasDot, isTrue);
    });
  }

  testWidgets('unread rows with no time still show the dot and say Unread', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final currentTime = DateTime.utc(2026, 10, 7, 12);
    // The reply's time comes from its record's createdAt, the upvote's from
    // sortAt.
    final replyWire = _reply(
      'no-time',
      sortAt: '2026-10-06T12:00:00.000Z',
      isRead: false,
    );
    (replyWire['record'] as Map<String, dynamic>).remove('createdAt');
    final rows = <String, Widget>{
      'reply': NotificationReplyCard(
        notification: _parse(replyWire),
        onTap: () {},
        onSensitiveContentToggle: () {},
        currentTime: currentTime,
      ),
      'upvote': NotificationUpvoteRow(
        notification: _parse(
          upvoteWire(upvoters: [aliceUpvoter], count: 1)
            ..['isRead'] = false
            ..['sortAt'] = 'not-a-date',
        ),
        onTap: () {},
        onSensitiveContentToggle: () {},
        currentTime: currentTime,
      ),
    };

    for (final MapEntry(key: kind, value: row) in rows.entries) {
      final (_, hasDot) = await _pumpedRow(tester, row);
      expect(hasDot, isTrue, reason: kind);
      expect(
        find.bySemanticsLabel(RegExp('^Unread, ')),
        findsOneWidget,
        reason: kind,
      );
    }
    semantics.dispose();
  });

  testWidgets(
    'B9 the screen marks a later-page row by its computed read state',
    (tester) async {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        harness.responses.first.complete(
          NotificationPage.fromJson({
            'notifications': [
              _reply(
                'page-one',
                sortAt: '2026-10-08T14:00:00.000Z',
                isRead: false,
              ),
            ],
            'cursor': 'c1',
            'seenAt': _seenAt,
          }),
        );
        await _pumpFrames(tester);
        expect(harness.cursors, [null, 'c1']);

        harness.responses[1].complete(
          NotificationPage.fromJson({
            'notifications': [
              _reply(
                'later-than-seen',
                sortAt: '2026-10-08T13:00:00.000Z',
                isRead: true,
              ),
              _reply(
                'earlier-than-seen',
                sortAt: '2026-10-08T11:00:00.000Z',
                isRead: false,
              ),
            ],
            'cursor': null,
          }),
        );
        await _pumpFrames(tester);

        expect(
          {
            'later than seenAt': _hasUnreadDot(
              _replyCardFor('later-than-seen'),
            ),
            'earlier than seenAt': _hasUnreadDot(
              _replyCardFor('earlier-than-seen'),
            ),
          },
          {'later than seenAt': true, 'earlier than seenAt': false},
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
