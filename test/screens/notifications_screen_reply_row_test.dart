import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_screen_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';

const _rootUri = 'at://did:plc:me/social.coves.community.postv2/3kpost';
const _parentUri = 'at://did:plc:me/social.coves.community.comment/3kparent';
const _replyUri = 'at://did:plc:writer/social.coves.community.comment/3kreply';
const _title = 'A post about keyboards';

/// A comment reply to the viewer's comment (no preview, so the row shows
/// the root post card) on a live root post with a known author.
Map<String, dynamic> _commentReplyRow() => {
  ...replyNotificationWire(
    reason: 'commentReply',
    rootPost: {
      'uri': _rootUri,
      'cid': 'bafyroot',
      'title': _title,
      'author': {'did': 'did:plc:poster', 'handle': 'poster.test'},
      'createdAt': '2026-10-06T11:00:00.000Z',
      'stats': {'score': 12, 'upvotes': 12, 'downvotes': 0, 'commentCount': 3},
    },
    record: {
      'uri': _replyUri,
      'cid': 'bafyreply',
      'excerpt': 'I use a Keychron K2.',
      'createdAt': '2026-10-06T12:00:00.000Z',
    },
    author: {
      'did': 'did:plc:writer',
      'handle': 'writer.test',
      'displayName': 'Writer',
    },
  ),
  'subject': {'uri': _parentUri, 'cid': 'bafyparent'},
};

void main() {
  testWidgets('B7 a comment reply row shows the post card, offers no Reply '
      'button, and opens the thread', (tester) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(
        NotificationPage.fromJson({
          'notifications': [_commentReplyRow()],
          'cursor': null,
        }),
      );
      await tester.pumpAndSettle();

      final card = find.byType(NotificationReplyCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(_title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('@poster.test')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Reply')),
        findsNothing,
      );

      await tester.tap(find.text(_title));
      await tester.pumpAndSettle();
      expect(
        harness.router.state.uri.toString(),
        '/post/at%3A%2F%2Fdid%3Aplc%3Ame%2Fsocial.coves.community.postv2%2F3kpost'
        '?comment=at%3A%2F%2Fdid%3Aplc%3Awriter'
        '%2Fsocial.coves.community.comment%2F3kreply',
      );
    } finally {
      await harness.dispose(tester);
    }
  });
}
