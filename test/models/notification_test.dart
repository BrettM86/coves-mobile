import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/utils/removal_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rootUri = 'at://did:plc:alice/social.coves.community.postv2/3kpost';
  const commentUri =
      'at://did:plc:bob/social.coves.community.comment/3kcomment';
  const postUri = 'at://did:plc:carol/social.coves.community.postv2/3kmention';
  const parentCommentUri =
      'at://did:plc:alice/social.coves.community.comment/3kparent';

  group('NotificationPage.fromJson', () {
    test('B1 parses every known reason and preserves wire timestamps', () {
      final page = NotificationPage.fromJson({
        'notifications': [
          {
            'reason': 'postReply',
            'sortAt': '2026-10-08T12:01:00.123456789Z',
            'isRead': false,
            'rootPost': {
              'uri': rootUri,
              'cid': 'bafy-root',
              'title': 'Root title',
              'labels': {
                'values': [
                  {'val': 'nsfw'},
                ],
              },
              'thumbnail': 'https://cdn.example/root.jpg',
              'thumbnailAlt': 'Root image',
              'community': {
                'did': 'did:plc:community',
                'name': 'Coves',
                'origin': 'coves.social',
                'handle': 'coves.community.coves.social',
                'avatar': 'https://cdn.example/community.jpg',
              },
            },
            'subject': {
              'uri': rootUri,
              'cid': 'bafy-root',
              'preview': 'Your post',
            },
            'record': {
              'uri': commentUri,
              'cid': 'bafy-reply',
              'excerpt': 'First reply',
              'createdAt': '2026-10-08T11:01:00.987654321Z',
              'labels': {
                'values': [
                  {'val': 'graphic-media'},
                ],
              },
              'thumbnail': 'https://cdn.example/reply.jpg',
              'thumbnailAlt': 'Reply image',
            },
            'author': {
              'did': 'did:plc:bob',
              'handle': 'bob.example',
              'displayName': 'Bob',
              'avatar': 'https://cdn.example/bob.jpg',
            },
          },
          {
            'reason': 'commentReply',
            'sortAt': '2026-10-08T12:02:00.123456789Z',
            'isRead': true,
            'rootPost': {
              'uri': rootUri,
              'cid': 'bafy-root',
              'title': 'Root title',
              'labels': {
                'values': [
                  {'val': 'nsfw'},
                ],
              },
              'thumbnail': 'https://cdn.example/root.jpg',
              'thumbnailAlt': 'Root image',
              'community': {
                'did': 'did:plc:community',
                'name': 'Coves',
                'origin': 'coves.social',
                'handle': 'coves.community.coves.social',
                'avatar': 'https://cdn.example/community.jpg',
              },
            },
            'subject': {
              'uri': parentCommentUri,
              'cid': 'bafy-parent',
              'preview': 'Your comment',
            },
            'record': {
              'uri':
                  'at://did:plc:dana/social.coves.community.comment/3ksecond',
              'cid': 'bafy-second',
              'excerpt': 'Second reply',
              'createdAt': '2026-10-08T11:02:00.987654321Z',
              'labels': {
                'values': [
                  {'val': 'nsfw'},
                ],
              },
              'thumbnail': 'https://cdn.example/second.jpg',
              'thumbnailAlt': 'Second image',
            },
            'author': {
              'did': 'did:plc:dana',
              'handle': 'dana.example',
              'displayName': 'Dana',
              'avatar': 'https://cdn.example/dana.jpg',
            },
          },
          {
            'reason': 'mention',
            'sortAt': '2026-10-08T12:03:00.123456789Z',
            'isRead': false,
            'rootPost': {
              'uri': rootUri,
              'cid': 'bafy-root',
              'title': 'Root title',
              'labels': {
                'values': [
                  {'val': 'nsfw'},
                ],
              },
              'thumbnail': 'https://cdn.example/root.jpg',
              'thumbnailAlt': 'Root image',
              'community': {
                'did': 'did:plc:community',
                'name': 'Coves',
                'origin': 'coves.social',
                'handle': 'coves.community.coves.social',
                'avatar': 'https://cdn.example/community.jpg',
              },
            },
            'record': {
              'uri': postUri,
              'cid': 'bafy-mention',
              'excerpt': 'Mentioned you',
              'createdAt': '2026-10-08T11:03:00.987654321Z',
              'labels': {
                'values': [
                  {'val': 'sexual'},
                ],
              },
              'thumbnail': 'https://cdn.example/mention.jpg',
              'thumbnailAlt': 'Mention image',
            },
            'author': {
              'did': 'did:plc:carol',
              'handle': 'carol.example',
              'displayName': 'Carol',
              'avatar': 'https://cdn.example/carol.jpg',
            },
          },
          {
            'reason': 'upvote',
            'sortAt': '2026-10-08T12:04:00.123456789Z',
            'isRead': true,
            'rootPost': {
              'uri': rootUri,
              'cid': 'bafy-root',
              'title': 'Root title',
              'labels': {
                'values': [
                  {'val': 'nsfw'},
                ],
              },
              'thumbnail': 'https://cdn.example/root.jpg',
              'thumbnailAlt': 'Root image',
              'community': {
                'did': 'did:plc:community',
                'name': 'Coves',
                'origin': 'coves.social',
                'handle': 'coves.community.coves.social',
                'avatar': 'https://cdn.example/community.jpg',
              },
            },
            'subject': {
              'uri': commentUri,
              'cid': 'bafy-subject',
              'preview': 'Voted comment',
              'labels': {
                'values': [
                  {'val': 'graphic-media'},
                ],
              },
              'thumbnail': 'https://cdn.example/subject.jpg',
              'thumbnailAlt': 'Subject image',
            },
            'upvoteCount': 3,
            'recentUpvoters': [
              {
                'did': 'did:plc:eve',
                'handle': 'eve.example',
                'displayName': 'Eve',
                'avatar': 'https://cdn.example/eve.jpg',
              },
              {
                'did': 'did:plc:frank',
                'handle': 'frank.example',
                'displayName': 'Frank',
                'avatar': 'https://cdn.example/frank.jpg',
              },
            ],
          },
        ],
        'cursor': 'next-page',
        'seenAt': '2026-10-08T12:00:00.123456789Z',
      });

      expect(page.cursor, 'next-page');
      expect(page.seenAt, '2026-10-08T12:00:00.123456789Z');
      expect(page.notifications, hasLength(4));

      for (final (index, reason, sortAt, isRead) in [
        (
          0,
          NotificationReason.postReply,
          '2026-10-08T12:01:00.123456789Z',
          false,
        ),
        (
          1,
          NotificationReason.commentReply,
          '2026-10-08T12:02:00.123456789Z',
          true,
        ),
        (
          2,
          NotificationReason.mention,
          '2026-10-08T12:03:00.123456789Z',
          false,
        ),
        (3, NotificationReason.upvote, '2026-10-08T12:04:00.123456789Z', true),
      ]) {
        final row = page.notifications[index];
        expect(row.reason, reason);
        expect(row.sortAt, sortAt);
        expect(row.isRead, isRead);
        expect(row.rootPost.uri, rootUri);
        expect(row.rootPost.cid, 'bafy-root');
        expect(row.rootPost.title, 'Root title');
        expect(row.rootPost.labels, {
          'values': [
            {'val': 'nsfw'},
          ],
        });
        expect(row.rootPost.thumbnail, 'https://cdn.example/root.jpg');
        expect(row.rootPost.thumbnailAlt, 'Root image');
        expect(row.rootPost.community?.did, 'did:plc:community');
        expect(row.rootPost.community?.name, 'Coves');
        expect(row.rootPost.community?.origin, 'coves.social');
        expect(row.rootPost.community?.handle, 'coves.community.coves.social');
        expect(
          row.rootPost.community?.avatar,
          'https://cdn.example/community.jpg',
        );
      }

      for (final (
            index,
            uri,
            cid,
            excerpt,
            createdAt,
            label,
            image,
            alt,
            did,
            handle,
            displayName,
            avatar,
          )
          in [
            (
              0,
              commentUri,
              'bafy-reply',
              'First reply',
              '2026-10-08T11:01:00.987654321Z',
              'graphic-media',
              'https://cdn.example/reply.jpg',
              'Reply image',
              'did:plc:bob',
              'bob.example',
              'Bob',
              'https://cdn.example/bob.jpg',
            ),
            (
              1,
              'at://did:plc:dana/social.coves.community.comment/3ksecond',
              'bafy-second',
              'Second reply',
              '2026-10-08T11:02:00.987654321Z',
              'nsfw',
              'https://cdn.example/second.jpg',
              'Second image',
              'did:plc:dana',
              'dana.example',
              'Dana',
              'https://cdn.example/dana.jpg',
            ),
            (
              2,
              postUri,
              'bafy-mention',
              'Mentioned you',
              '2026-10-08T11:03:00.987654321Z',
              'sexual',
              'https://cdn.example/mention.jpg',
              'Mention image',
              'did:plc:carol',
              'carol.example',
              'Carol',
              'https://cdn.example/carol.jpg',
            ),
          ]) {
        final row = page.notifications[index];
        expect(row.record?.uri, uri);
        expect(row.record?.cid, cid);
        expect(row.record?.excerpt, excerpt);
        expect(row.record?.createdAt, createdAt);
        expect(row.record?.labels, {
          'values': [
            {'val': label},
          ],
        });
        expect(row.record?.thumbnail, image);
        expect(row.record?.thumbnailAlt, alt);
        expect(row.author?.did, did);
        expect(row.author?.handle, handle);
        expect(row.author?.displayName, displayName);
        expect(row.author?.avatar, avatar);
      }

      for (final (index, uri, cid, preview) in [
        (0, rootUri, 'bafy-root', 'Your post'),
        (1, parentCommentUri, 'bafy-parent', 'Your comment'),
      ]) {
        final row = page.notifications[index];
        expect(row.subject?.uri, uri);
        expect(row.subject?.cid, cid);
        expect(row.subject?.preview, preview);
      }
      expect(page.notifications[2].subject, isNull);

      final upvote = page.notifications[3];
      expect(upvote.subject?.uri, commentUri);
      expect(upvote.subject?.cid, 'bafy-subject');
      expect(upvote.subject?.preview, 'Voted comment');
      expect(upvote.subject?.labels, {
        'values': [
          {'val': 'graphic-media'},
        ],
      });
      expect(upvote.subject?.thumbnail, 'https://cdn.example/subject.jpg');
      expect(upvote.subject?.thumbnailAlt, 'Subject image');
      expect(upvote.upvoteCount, 3);
      expect(upvote.recentUpvoters, hasLength(2));
      for (final (index, did, handle, displayName, avatar) in [
        (0, 'did:plc:eve', 'eve.example', 'Eve', 'https://cdn.example/eve.jpg'),
        (
          1,
          'did:plc:frank',
          'frank.example',
          'Frank',
          'https://cdn.example/frank.jpg',
        ),
      ]) {
        final actor = upvote.recentUpvoters[index];
        expect(actor.did, did);
        expect(actor.handle, handle);
        expect(actor.displayName, displayName);
        expect(actor.avatar, avatar);
      }
    });

    test('B2 skips invalid rows while retaining valid order and cursor', () {
      final page = NotificationPage.fromJson({
        'notifications': [
          {
            'reason': 'follow',
            'sortAt': '2026-10-08T12:00:00Z',
            'isRead': false,
            'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
          },
          {
            'reason': 'postReply',
            'sortAt': '2026-10-08T12:01:00Z',
            'isRead': false,
            'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
            'record': {'uri': commentUri, 'cid': 'bafy-reply'},
          },
          for (final reason in [
            'upvote',
            'postReply',
            'commentReply',
            'mention',
          ])
            {
              'reason': reason,
              'sortAt': '2026-10-08T12:02:00Z',
              'isRead': false,
              'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
            },
          {
            'reason': 'upvote',
            'sortAt': '2026-10-08T12:03:00Z',
            'isRead': true,
            'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
            'subject': {'uri': postUri, 'cid': 'bafy-subject'},
          },
        ],
        'cursor': 'next-page',
      });

      expect(page.cursor, 'next-page');
      expect(page.notifications, hasLength(2));
      expect(page.notifications[0].reason, NotificationReason.postReply);
      expect(page.notifications[0].record?.uri, commentUri);
      expect(page.notifications[1].reason, NotificationReason.upvote);
      expect(page.notifications[1].subject?.uri, postUri);
    });

    test('B2 accepts an empty page with a cursor and no seenAt', () {
      final page = NotificationPage.fromJson({
        'notifications': [],
        'cursor': 'empty-next',
      });

      expect(page.notifications, isEmpty);
      expect(page.cursor, 'empty-next');
      expect(page.seenAt, isNull);
    });

    test('B2 keeps the cursor when all rows are skipped', () {
      final page = NotificationPage.fromJson({
        'notifications': [
          {
            'reason': 'follow',
            'sortAt': '2026-10-08T12:00:00Z',
            'isRead': false,
            'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
          },
          {
            'reason': 'upvote',
            'sortAt': '2026-10-08T12:01:00Z',
            'isRead': false,
            'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
          },
        ],
        'cursor': 'skipped-next',
      });

      expect(page.notifications, isEmpty);
      expect(page.cursor, 'skipped-next');
    });

    test(
      'B3 sparse references and did-only actors parse with absent fields',
      () {
        final page = NotificationPage.fromJson({
          'notifications': [
            {
              'reason': 'postReply',
              'sortAt': '2026-10-08T12:00:00Z',
              'isRead': false,
              'rootPost': {
                'uri': rootUri,
                'cid': 'bafy-root',
                'status': 'deleted',
              },
              'record': {
                'uri': commentUri,
                'cid': 'bafy-reply',
                'status': 'removedByModerator',
                'createdAt': '2026-10-08T11:00:00.123456789Z',
              },
              'author': {'did': 'did:plc:bob'},
            },
            {
              'reason': 'upvote',
              'sortAt': '2026-10-08T12:01:00Z',
              'isRead': true,
              'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
              'subject': {'uri': postUri, 'cid': 'bafy-subject'},
              'recentUpvoters': [
                {'did': 'did:plc:carol'},
              ],
            },
            {
              'reason': 'upvote',
              'sortAt': '2026-10-08T12:02:00Z',
              'isRead': false,
              'rootPost': {'uri': rootUri, 'cid': 'bafy-root'},
              'subject': {'uri': postUri, 'cid': 'bafy-subject'},
            },
          ],
        });

        expect(page.notifications, hasLength(3));
        final reply = page.notifications[0];
        expect(reply.rootPost.status, NotificationReferenceStatus.deleted);
        expect(reply.rootPost.title, isNull);
        expect(reply.rootPost.labels, isNull);
        expect(reply.rootPost.thumbnail, isNull);
        expect(reply.rootPost.thumbnailAlt, isNull);
        expect(reply.rootPost.community, isNull);
        expect(
          reply.record?.status,
          NotificationReferenceStatus.removedByModerator,
        );
        expect(reply.record?.createdAt, '2026-10-08T11:00:00.123456789Z');
        expect(reply.record?.excerpt, isNull);
        expect(reply.record?.labels, isNull);
        expect(reply.record?.thumbnail, isNull);
        expect(reply.record?.thumbnailAlt, isNull);
        expect(reply.author?.did, 'did:plc:bob');
        expect(reply.author?.handle, isNull);
        expect(reply.author?.displayName, isNull);
        expect(reply.author?.avatar, isNull);
        expect(
          page.notifications[1].recentUpvoters.single.did,
          'did:plc:carol',
        );
        expect(page.notifications[1].recentUpvoters.single.handle, isNull);
        expect(page.notifications[1].recentUpvoters.single.displayName, isNull);
        expect(page.notifications[1].recentUpvoters.single.avatar, isNull);
        expect(page.notifications[2].recentUpvoters, isEmpty);
      },
    );
  });

  group('NotificationReference.fromJson', () {
    for (final (status, expectedStatus, expectedCopy) in [
      (
        'deleted',
        NotificationReferenceStatus.deleted,
        RemovalCopy.deletedByUser,
      ),
      (
        'removedByModerator',
        NotificationReferenceStatus.removedByModerator,
        RemovalCopy.removedByCommunityModerator,
      ),
      (
        'removedByServerAdmin',
        NotificationReferenceStatus.removedByServerAdmin,
        RemovalCopy.removedByServerAdmin,
      ),
      (
        'quarantined',
        NotificationReferenceStatus.unknown,
        RemovalCopy.removedByModerator,
      ),
    ]) {
      test('B4 $status maps to its placeholder copy', () {
        final reference = NotificationReference.fromJson({
          'uri': rootUri,
          'cid': 'bafy-root',
          'status': status,
        });

        expect(reference.status, expectedStatus);
        expect(reference.placeholderCopy, expectedCopy);
      });
    }

    test('B4 absent status has no placeholder copy', () {
      final reference = NotificationReference.fromJson({
        'uri': rootUri,
        'cid': 'bafy-root',
      });

      expect(reference.status, isNull);
      expect(reference.placeholderCopy, isNull);
    });
  });

  group('NotificationActor.fromJson', () {
    for (final (description, json, expectedName, expectedHandleLine) in [
      (
        'display name and handle',
        {'did': 'did:plc:bob', 'displayName': 'Bob', 'handle': 'bob.example'},
        'Bob',
        '@bob.example',
      ),
      (
        'handle only',
        {'did': 'did:plc:bob', 'handle': 'bob.example'},
        'bob.example',
        '@bob.example',
      ),
      ('did only', {'did': 'did:plc:bob'}, 'Unknown user', null),
    ]) {
      test('B5 $description yields name and handle line', () {
        final actor = NotificationActor.fromJson(json);

        expect(actor.name, expectedName);
        expect(actor.handleLine, expectedHandleLine);
      });
    }
  });

  group('NotificationView.tryFromJson root post card parts', () {
    const validAuthor = <String, dynamic>{
      'did': 'did:plc:poster',
      'handle': 'poster.example',
      'displayName': 'Poster',
      'avatar': 'https://cdn.example/poster.jpg',
    };
    const validStats = <String, dynamic>{
      'score': -3,
      'upvotes': 2,
      'downvotes': 5,
      'commentCount': 7,
    };

    NotificationView? row(Map<String, dynamic> rootPartsOverride) =>
        NotificationView.tryFromJson({
          'reason': 'postReply',
          'sortAt': '2026-10-08T12:00:00Z',
          'isRead': false,
          'rootPost': {
            'uri': rootUri,
            'cid': 'bafy-root',
            'title': 'Root title',
            'author': validAuthor,
            'createdAt': '2026-10-01T12:00:00.000Z',
            'stats': validStats,
            ...rootPartsOverride,
          },
          'subject': {'uri': rootUri, 'cid': 'bafy-root'},
          'record': {'uri': commentUri, 'cid': 'bafy-reply'},
        });

    for (final createdAt in [
      '2026-10-01T12:00:00.000Z',
      '2026-10-01T14:00:00+02:00',
    ]) {
      test('B1 valid author, createdAt $createdAt and stats are exposed', () {
        final notification = row({'createdAt': createdAt});

        expect(notification, isNotNull);
        final rootPost = notification!.rootPost;
        expect(rootPost.author?.did, 'did:plc:poster');
        expect(rootPost.author?.handle, 'poster.example');
        expect(rootPost.author?.displayName, 'Poster');
        expect(rootPost.author?.avatar, 'https://cdn.example/poster.jpg');
        expect(rootPost.createdAt, createdAt);
        expect(rootPost.stats?.score, -3);
        expect(rootPost.stats?.upvotes, 2);
        expect(rootPost.stats?.downvotes, 5);
        expect(rootPost.stats?.commentCount, 7);
      });
    }

    for (final (description, author) in <(String, Object?)>[
      ('invalid DID', {'did': 'not-a-did', 'handle': 'poster.example'}),
      ('non-string DID', {'did': 42, 'handle': 'poster.example'}),
      ('non-string handle', {'did': 'did:plc:poster', 'handle': 42}),
      ('missing handle', {'did': 'did:plc:poster'}),
      ('non-map author', 'did:plc:poster'),
    ]) {
      test('B1 author with $description is dropped alone', () {
        final notification = row({'author': author});

        expect(notification, isNotNull);
        final rootPost = notification!.rootPost;
        expect(rootPost.author, isNull);
        expect(rootPost.title, 'Root title');
        expect(rootPost.createdAt, '2026-10-01T12:00:00.000Z');
        expect(rootPost.stats?.score, -3);
        expect(rootPost.stats?.commentCount, 7);
      });
    }

    for (final (description, createdAt) in <(String, Object?)>[
      ('date only', '2026-10-01'),
      ('missing offset', '2026-10-01T12:00:00'),
      ('invalid calendar date', '2026-02-30T12:00:00Z'),
      ('non-string', 1759320000),
    ]) {
      test('B1 createdAt with $description is dropped alone', () {
        final notification = row({'createdAt': createdAt});

        expect(notification, isNotNull);
        final rootPost = notification!.rootPost;
        expect(rootPost.createdAt, isNull);
        expect(rootPost.author?.handle, 'poster.example');
        expect(rootPost.stats?.score, -3);
      });
    }

    for (final (description, stats) in <(String, Object?)>[
      ('string score', {...validStats, 'score': '-3'}),
      ('fractional score', {...validStats, 'score': 1.5}),
      ('negative upvotes', {...validStats, 'upvotes': -1}),
      ('negative downvotes', {...validStats, 'downvotes': -1}),
      ('negative comment count', {...validStats, 'commentCount': -1}),
      ('string comment count', {...validStats, 'commentCount': '7'}),
      ('missing downvotes', {'score': -3, 'upvotes': 2, 'commentCount': 7}),
      ('non-map stats', [1, 2, 3]),
    ]) {
      test('B1 stats with $description are dropped alone without throwing', () {
        final notification = row({'stats': stats});

        expect(notification, isNotNull);
        final rootPost = notification!.rootPost;
        expect(rootPost.stats, isNull);
        expect(rootPost.author?.handle, 'poster.example');
        expect(rootPost.createdAt, '2026-10-01T12:00:00.000Z');
      });
    }
  });
}
