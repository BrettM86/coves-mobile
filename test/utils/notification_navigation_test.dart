import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/utils/notification_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = NotificationReference(
    uri: 'at://did:plc:alice/social.coves.community.postv2/3kpost',
    cid: 'bafy-root',
  );
  const removedRoot = NotificationReference(
    uri: 'at://did:plc:alice/social.coves.community.postv2/3kpost',
    cid: 'bafy-root',
    status: NotificationReferenceStatus.deleted,
  );
  const comment = NotificationReference(
    uri: 'at://did:plc:bob/social.coves.community.comment/3kcomment',
    cid: 'bafy-comment',
  );
  const removedComment = NotificationReference(
    uri: 'at://did:plc:bob/social.coves.community.comment/3kcomment',
    cid: 'bafy-comment',
    status: NotificationReferenceStatus.deleted,
  );
  const parentComment = NotificationReference(
    uri: 'at://did:plc:alice/social.coves.community.comment/3kparent',
    cid: 'bafy-parent',
  );
  const post = NotificationReference(
    uri: 'at://did:plc:carol/social.coves.community.postv2/3kmention',
    cid: 'bafy-post',
  );
  const removedPost = NotificationReference(
    uri: 'at://did:plc:carol/social.coves.community.postv2/3kmention',
    cid: 'bafy-post',
    status: NotificationReferenceStatus.deleted,
  );

  group('notificationRoute', () {
    for (final (name, reason, rootPost, record, subject, expectedRoute)
        in <
          (
            String,
            NotificationReason,
            NotificationReference,
            NotificationReference?,
            NotificationReference?,
            String,
          )
        >[
          (
            'post reply comment',
            NotificationReason.postReply,
            root,
            comment,
            root,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'comment reply comment',
            NotificationReason.commentReply,
            root,
            comment,
            parentComment,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'mention in comment',
            NotificationReason.mention,
            root,
            comment,
            null,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'mention in postv2 post',
            NotificationReason.mention,
            root,
            post,
            null,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost',
          ),
          (
            'upvote on comment',
            NotificationReason.upvote,
            root,
            null,
            comment,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'upvote on postv2 post',
            NotificationReason.upvote,
            root,
            null,
            post,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost',
          ),
          (
            'removed reply comment and root post',
            NotificationReason.postReply,
            removedRoot,
            removedComment,
            removedRoot,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'removed mention post',
            NotificationReason.mention,
            root,
            removedPost,
            null,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost',
          ),
          (
            'removed upvoted comment',
            NotificationReason.upvote,
            root,
            null,
            removedComment,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Abob%2Fsocial.coves.community.comment%2F3kcomment',
          ),
          (
            'removed upvoted post',
            NotificationReason.upvote,
            root,
            null,
            removedPost,
            '/post/at%3A%2F%2Fdid%3Aplc%3Aalice%2Fsocial.coves.community.postv2%2F3kpost',
          ),
        ]) {
      test('B6 $name routes to its root post and optional comment', () {
        final notification = NotificationView(
          reason: reason,
          sortAt: '2026-10-08T12:00:00Z',
          isRead: false,
          rootPost: rootPost,
          record: record,
          subject: subject,
        );

        expect(notificationRoute(notification), expectedRoute);
      });
    }
  });
}
