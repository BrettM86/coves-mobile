import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_screen_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _sharedRootUri = 'at://did:plc:me/social.coves.community.postv2/3kroot';

NotificationPage _page(List<Map<String, dynamic>> rows) =>
    NotificationPage.fromJson({'notifications': rows, 'cursor': null});

/// A post reply whose reply record its author marked as sensitive.
Map<String, dynamic> _sensitiveReply({
  required String recordUri,
  required String excerpt,
  required String authorName,
  String rootUri = postUri,
}) => replyNotificationWire(
  rootPost: {'uri': rootUri, 'cid': 'bafyroot', 'title': 'Plain root title'},
  record: {
    'uri': recordUri,
    'cid': 'bafyrecord',
    'excerpt': excerpt,
    'createdAt': '2026-10-06T12:00:00.000Z',
    'labels': nsfwLabels,
  },
  author: {
    'did': 'did:plc:writer',
    'handle': 'writer.test',
    'displayName': authorName,
  },
);

Finder _banners() => find.byType(SensitiveContentBanner);

Finder _bannerOffering(String action) =>
    find.descendant(of: _banners(), matching: find.text(action));

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

Future<void> _pullToRefresh(WidgetTester tester) async {
  // RefreshIndicator arms only past a quarter of the viewport, so pull
  // farther than that.
  await tester.fling(find.byType(CustomScrollView), const Offset(0, 600), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('B6 a banner tap reveals and re-conceals only its own row '
      'without opening it', (tester) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(
        _page([
          upvoteWire(
            upvoters: [],
            count: 1,
            subject: {
              ...commentSubject,
              'preview': 'Spicy comment preview',
              'labels': nsfwLabels,
            },
          ),
          _sensitiveReply(
            recordUri: 'at://did:plc:writer/social.coves.community.comment/r1',
            excerpt: 'Spicy reply excerpt',
            authorName: 'Writer',
          ),
        ]),
      );
      await _pumpFrames(tester);

      expect(find.text('Spicy comment preview'), findsNothing);
      expect(find.text('Spicy reply excerpt'), findsNothing);
      expect(_banners(), findsNWidgets(2));

      await tester.tap(_banners().first);
      await _pumpFrames(tester);

      expect(find.text('Spicy comment preview'), findsOneWidget);
      expect(
        find.text('Spicy reply excerpt'),
        findsNothing,
        reason: 'revealing one row leaves the other concealed',
      );

      await tester.tap(_banners().first);
      await _pumpFrames(tester);

      expect(find.text('Spicy comment preview'), findsNothing);
      expect(find.text('Spicy reply excerpt'), findsNothing);
      expect(
        harness.router.state.uri.toString(),
        '/',
        reason: 'a banner tap must not open the row',
      );
      expect(harness.router.canPop(), isFalse);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B7 a refreshed row with a new identity in the same position '
      'starts concealed', (tester) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(
        _page([
          _sensitiveReply(
            recordUri:
                'at://did:plc:writer/social.coves.community.comment/first',
            excerpt: 'First spicy excerpt',
            authorName: 'First Writer',
            rootUri: _sharedRootUri,
          ),
        ]),
      );
      await _pumpFrames(tester);

      expect(find.text('First spicy excerpt'), findsNothing);
      expect(_bannerOffering('Show'), findsOneWidget);
      await tester.tap(_banners().first);
      await _pumpFrames(tester);
      expect(find.text('First spicy excerpt'), findsOneWidget);

      await _pullToRefresh(tester);
      expect(harness.cursors, [null, null]);
      harness.responses[1].complete(
        _page([
          _sensitiveReply(
            recordUri:
                'at://did:plc:writer/social.coves.community.comment/second',
            excerpt: 'Second spicy excerpt',
            authorName: 'Second Writer',
            rootUri: _sharedRootUri,
          ),
        ]),
      );
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester);

      expect(
        find.text('Second Writer'),
        findsOneWidget,
        reason: 'the refreshed page replaced the row',
      );
      expect(
        find.text('Second spicy excerpt'),
        findsNothing,
        reason: 'a reveal belongs to the row identity, not its position',
      );
      expect(_bannerOffering('Show'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B8 a reveal does not carry into the next session', (
    tester,
  ) async {
    const sharedRecordUri =
        'at://did:plc:writer/social.coves.community.comment/shared';
    final rows = [
      (
        name: 'switch to bob',
        changeSession: (NotificationsScreenHarness harness) async {
          harness.auth.setSignedInDid('did:plc:bob');
          await _pumpFrames(tester);
        },
        nextDid: 'did:plc:bob',
      ),
      (
        name: 'sign out then sign back in as alice',
        changeSession: (NotificationsScreenHarness harness) async {
          harness.auth.setSignedInDid(null);
          await _pumpFrames(tester);
          harness.auth.setSignedInDid('did:plc:alice');
          await _pumpFrames(tester);
        },
        nextDid: 'did:plc:alice',
      ),
    ];
    for (final row in rows) {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        harness.responses.first.complete(
          _page([
            _sensitiveReply(
              recordUri: sharedRecordUri,
              excerpt: 'First session spicy excerpt',
              authorName: 'First Session Writer',
              rootUri: _sharedRootUri,
            ),
          ]),
        );
        await _pumpFrames(tester);
        final mountedScreen = tester.state(find.byType(NotificationsScreen));

        expect(find.text('First session spicy excerpt'), findsNothing);
        await tester.tap(_bannerOffering('Show'));
        await _pumpFrames(tester);
        expect(
          find.text('First session spicy excerpt'),
          findsOneWidget,
          reason: '${row.name}: revealed in the first session',
        );

        // A token refresh notifies while the session stays the same.
        harness.auth.notifyWithoutChange();
        await _pumpFrames(tester);
        expect(
          find.text('First session spicy excerpt'),
          findsOneWidget,
          reason: '${row.name}: a same-session notify keeps the reveal',
        );

        await row.changeSession(harness);
        expect(harness.cursors, [null, null], reason: row.name);
        expect(harness.requestDids, [
          'did:plc:alice',
          row.nextDid,
        ], reason: row.name);
        harness.responses[1].complete(
          _page([
            _sensitiveReply(
              recordUri: sharedRecordUri,
              excerpt: 'Next session spicy excerpt',
              authorName: 'Next Session Writer',
              rootUri: _sharedRootUri,
            ),
          ]),
        );
        await _pumpFrames(tester);

        expect(
          tester.state(find.byType(NotificationsScreen)),
          same(mountedScreen),
          reason: '${row.name}: the same mounted screen',
        );
        expect(
          find.text('Next Session Writer'),
          findsOneWidget,
          reason: "${row.name}: the next session's row rendered",
        );
        expect(
          find.text('Next session spicy excerpt'),
          findsNothing,
          reason: '${row.name}: a reveal belongs to its session',
        );
        expect(_bannerOffering('Show'), findsOneWidget, reason: row.name);
      } finally {
        await harness.dispose(tester);
      }
    }
  });
}
