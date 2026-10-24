import 'package:coves_flutter/models/notification.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/upvote_notification_fixture.dart';

void main() {
  test('B1 notification identities use reason and record or subject URI', () {
    final wires = [
      replyNotificationWireFor(
        recordUri:
            'at://did:plc:writer/social.coves.community.comment/post-reply',
        rootUri: postUri,
      ),
      replyNotificationWireFor(
        reason: 'commentReply',
        recordUri:
            'at://did:plc:writer/social.coves.community.comment/comment-reply',
        rootUri: postUri,
      ),
      replyNotificationWireFor(
        reason: 'mention',
        recordUri: 'at://did:plc:writer/social.coves.community.postv2/mention',
        rootUri: postUri,
      ),
      upvoteWire(upvoters: [], count: 1),
      upvoteWire(subject: commentSubject, upvoters: [], count: 1),
    ];
    final rows = wires.map(NotificationView.tryFromJson).toList();
    expect(rows, everyElement(isNotNull), reason: 'wire fixtures must parse');

    final identities = rows.map((row) => row!.identity).toList();
    expect(identities, [
      'postReply|at://did:plc:writer/social.coves.community.comment/post-reply',
      'commentReply|at://did:plc:writer/social.coves.community.comment/comment-reply',
      'mention|at://did:plc:writer/social.coves.community.postv2/mention',
      'upvote|at://did:plc:me/social.coves.community.postv2/3kpost',
      'upvote|at://did:plc:me/social.coves.community.comment/3kcomment',
    ]);
    expect(identities.toSet(), hasLength(5));
  });
}
