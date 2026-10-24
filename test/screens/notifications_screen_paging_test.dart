import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_screen_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/upvote_notification_fixture.dart';

NotificationPage _page(List<Map<String, dynamic>> rows, {String? cursor}) =>
    NotificationPage.fromJson({'notifications': rows, 'cursor': cursor});

Map<String, dynamic> _reply(String suffix) => replyNotificationWireFor(
  recordUri: 'at://did:plc:writer/social.coves.community.comment/$suffix',
  rootUri: postUri,
);

List<Map<String, dynamic>> _replies(int count, {String prefix = 'row'}) => [
  for (var index = 1; index <= count; index++) _reply('$prefix$index'),
];

List<String> _visibleUris() => [
  for (final card in find.byType(NotificationReplyCard).evaluate())
    (card.widget as NotificationReplyCard).notification.record!.uri,
];

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

Future<void> _pullToRefresh(WidgetTester tester) async {
  // RefreshIndicator arms only past a quarter of the viewport (about 436 px
  // at the default 1744 px list height), so pull farther than that.
  await tester.fling(find.byType(CustomScrollView), const Offset(0, 600), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('B7 a short page fetches the next cursor without scrolling', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page(_replies(3), cursor: 'c1'));
      await _pumpFrames(tester);

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, 0);
      expect(harness.cursors, [null, 'c1']);
      harness.responses[1].complete(_page([_reply('second1')]));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/row1',
        'at://did:plc:writer/social.coves.community.comment/row2',
        'at://did:plc:writer/social.coves.community.comment/row3',
        'at://did:plc:writer/social.coves.community.comment/second1',
      ]);
      await _pumpFrames(tester);
      expect(harness.cursors, [null, 'c1']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B8 an empty first page follows its cursor while loading', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness(
      immediatePages: [_page([], cursor: 'c1')],
    );
    try {
      await harness.mount(tester);
      await _pumpFrames(tester);
      expect(harness.cursors, [null, 'c1']);
      expect(find.text('No notifications yet'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      harness.responses[1].complete(_page([_reply('after-empty')]));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/after-empty',
      ]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B8 terminal empty page shows the empty state', (tester) async {
    final harness = NotificationsScreenHarness(
      immediatePages: [
        _page([], cursor: 'c1'),
        _page([]),
      ],
    );
    try {
      await harness.mount(tester);
      await _pumpFrames(tester);
      expect(harness.cursors, [null, 'c1']);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B8 immediately empty pages follow three cursors without a throttle',
    (tester) async {
      final harness = NotificationsScreenHarness(
        immediatePages: [
          _page([], cursor: 'c1'),
          _page([], cursor: 'c2'),
          _page([], cursor: 'c3'),
          _page([_reply('fourth')]),
        ],
      );
      try {
        await harness.mount(tester);
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump();
        }
        expect(harness.cursors, [null, 'c1', 'c2', 'c3']);
        expect(_visibleUris(), [
          'at://did:plc:writer/social.coves.community.comment/fourth',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B9 a full first page waits for scroll near the end', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness(
      viewportSize: const Size(540, 600),
    );
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page(_replies(18), cursor: 'c1'));
      await _pumpFrames(tester);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(900));
      expect(harness.cursors, [null]);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.cursors, [null, 'c1']);
      harness.responses[1].complete(_page([_reply('last-page')]));
      await _pumpFrames(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
      await _pumpFrames(tester);
      expect(
        _visibleUris(),
        contains('at://did:plc:writer/social.coves.community.comment/row18'),
      );
      expect(
        _visibleUris().last,
        'at://did:plc:writer/social.coves.community.comment/last-page',
      );
      expect(harness.cursors, [null, 'c1']);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B10 later-page error keeps rows and footer Retry appends', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page(_replies(3), cursor: 'c1'));
      await _pumpFrames(tester);
      expect(harness.cursors, [null, 'c1']);
      harness.responses[1].completeError(
        ServerException('Server failure', statusCode: 500),
      );
      await _pumpFrames(tester);
      await tester.ensureVisible(find.text('Retry'));
      expect(
        _visibleUris(),
        contains('at://did:plc:writer/social.coves.community.comment/row1'),
      );
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(harness.cursors, [null, 'c1', 'c1']);
      harness.responses[2].complete(_page([_reply('retried')]));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/row1',
        'at://did:plc:writer/social.coves.community.comment/row2',
        'at://did:plc:writer/social.coves.community.comment/row3',
        'at://did:plc:writer/social.coves.community.comment/retried',
      ]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B10 empty later-page error shows Retry instead of empty or spinner',
    (tester) async {
      final harness = NotificationsScreenHarness(
        immediatePages: [_page([], cursor: 'c1')],
      );
      try {
        await harness.mount(tester);
        await _pumpFrames(tester);
        expect(harness.cursors, [null, 'c1']);
        harness.responses[1].completeError(
          ServerException('Server failure', statusCode: 500),
        );
        await _pumpFrames(tester);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No notifications yet'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(harness.cursors, [null, 'c1', 'c1']);
        harness.responses[2].complete(_page([_reply('recovered')]));
        await _pumpFrames(tester);
        expect(_visibleUris(), [
          'at://did:plc:writer/social.coves.community.comment/recovered',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B11 pulling a two-page list replaces all old rows', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness(
      viewportSize: const Size(540, 600),
    );
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page(_replies(18), cursor: 'c1'));
      await _pumpFrames(tester);
      expect(harness.cursors, [null]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.cursors, [null, 'c1']);
      harness.responses[1].complete(_page([_reply('old-second')]));
      await _pumpFrames(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 9000));
      await _pumpFrames(tester);
      expect(
        _visibleUris(),
        contains('at://did:plc:writer/social.coves.community.comment/row1'),
      );

      await _pullToRefresh(tester);
      expect(harness.cursors, [null, 'c1', null]);
      harness.responses[2].complete(_page([_reply('fresh')]));
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/fresh',
      ]);
      expect(harness.cursors, [null, 'c1', null]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B11 pulling a short list replaces its row', (tester) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page([_reply('old-short')]));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/old-short',
      ]);
      await _pullToRefresh(tester);
      expect(harness.cursors, [null, null]);
      harness.responses[1].complete(_page([_reply('new-short')]));
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/new-short',
      ]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B11 pulling a terminal empty state loads new rows', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page([]));
      await _pumpFrames(tester);
      expect(find.text('No notifications yet'), findsOneWidget);
      await _pullToRefresh(tester);
      expect(harness.cursors, [null, null]);
      harness.responses[1].complete(_page([_reply('new-from-empty')]));
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester);
      expect(_visibleUris(), [
        'at://did:plc:writer/social.coves.community.comment/new-from-empty',
      ]);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'B11 failed refresh retains rows and footer Retry replaces them',
    (tester) async {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        harness.responses.first.complete(_page([_reply('old-refresh')]));
        await _pumpFrames(tester);
        await _pullToRefresh(tester);
        expect(harness.cursors, [null, null]);
        harness.responses[1].completeError(
          ServerException('Server failure', statusCode: 500),
        );
        await tester.pump(const Duration(seconds: 1));
        await _pumpFrames(tester);
        await tester.ensureVisible(find.text('Retry'));
        expect(_visibleUris(), [
          'at://did:plc:writer/social.coves.community.comment/old-refresh',
        ]);
        expect(find.text('Retry'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(harness.cursors, [null, null, null]);
        harness.responses[2].complete(_page([_reply('replaced')]));
        await _pumpFrames(tester);
        expect(_visibleUris(), [
          'at://did:plc:writer/social.coves.community.comment/replaced',
        ]);
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
