import 'package:coves_flutter/models/liked_item.dart';
import 'package:flutter_test/flutter_test.dart';

const likedPostType = 'social.coves.actor.getLikes#likedPost';
const likedCommentType = 'social.coves.actor.getLikes#likedComment';

Map<String, dynamic> postViewJson(String rkey) => {
  'uri': 'at://did:plc:community1/social.coves.community.post/$rkey',
  'cid': 'cid-$rkey',
  'rkey': rkey,
  'author': {'did': 'did:plc:author1', 'handle': 'author.test'},
  'community': {'did': 'did:plc:community1', 'name': 'testcommunity'},
  'record': {'title': 'Post $rkey', 'content': 'body'},
  'createdAt': '2025-06-01T12:00:00Z',
  'indexedAt': '2025-06-01T12:00:01Z',
  'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1, 'commentCount': 0},
};

Map<String, dynamic> commentViewJson(String rkey, {required String root}) => {
  'uri': 'at://did:plc:author1/social.coves.community.comment/$rkey',
  'cid': 'cid-$rkey',
  'record': {'content': 'Comment $rkey'},
  'createdAt': '2025-06-01T12:00:00Z',
  'indexedAt': '2025-06-01T12:00:01Z',
  'author': {'did': 'did:plc:author1', 'handle': 'author.test'},
  'post': {
    'uri': 'at://did:plc:community1/social.coves.community.post/$root',
    'cid': 'cid-$root',
  },
  'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1},
};

Map<String, dynamic> likedPostJson(String rkey) => {
  r'$type': likedPostType,
  'post': postViewJson(rkey),
};

Map<String, dynamic> likedCommentJson(String rkey, {required String root}) => {
  r'$type': likedCommentType,
  'comment': commentViewJson(rkey, root: root),
  'post': postViewJson(root),
};

const likedCommentCccOnRoot1 =
    'comment at://did:plc:author1/social.coves.community.comment/ccc '
    'on at://did:plc:community1/social.coves.community.post/root1';

String describeLike(LikedItem item) => switch (item) {
  LikedPost(:final feedViewPost) => 'post ${feedViewPost.post.uri}',
  LikedComment(:final comment, :final post) =>
    'comment ${comment.uri} on ${post.uri}',
};

void main() {
  group('LikesResponse.fromJson', () {
    test('parses a mixed feed in order with its cursor', () {
      final response = LikesResponse.fromJson({
        'feed': [
          likedPostJson('aaa'),
          likedCommentJson('ccc', root: 'root1'),
          likedPostJson('bbb'),
        ],
        'cursor': 'next-1',
      });

      expect(response.feed.map(describeLike).toList(), <String>[
        'post at://did:plc:community1/social.coves.community.post/aaa',
        likedCommentCccOnRoot1,
        'post at://did:plc:community1/social.coves.community.post/bbb',
      ]);
      expect(response.cursor, 'next-1');
    });

    // Each bad item sits between two valid ones: it alone is dropped and
    // the valid rows keep their order.
    final skippedRows = <({String name, Object? item})>[
      (
        name: r'an unknown $type',
        item: {
          r'$type': 'social.coves.actor.getLikes#likedSomethingElse',
          'post': postViewJson('zzz'),
        },
      ),
      (name: r'a missing $type', item: {'post': postViewJson('zzz')}),
      (name: 'a non-map item', item: 'not-an-item'),
      (
        name: 'a liked comment without its post',
        item: {
          r'$type': likedCommentType,
          'comment': commentViewJson('zzz', root: 'root1'),
        },
      ),
      (
        name: 'a liked comment without its comment',
        item: {r'$type': likedCommentType, 'post': postViewJson('root1')},
      ),
      (
        name: 'a liked post whose post uri is not a string',
        item: {
          r'$type': likedPostType,
          'post': {...postViewJson('zzz'), 'uri': 42},
        },
      ),
      (
        name: 'a liked comment with an invalid createdAt',
        item: {
          r'$type': likedCommentType,
          'comment': {
            ...commentViewJson('zzz', root: 'root1'),
            'createdAt': 'not-a-date',
          },
          'post': postViewJson('root1'),
        },
      ),
    ];
    for (final row in skippedRows) {
      test('skips ${row.name}', () {
        final response = LikesResponse.fromJson({
          'feed': [
            likedPostJson('aaa'),
            row.item,
            likedCommentJson('ccc', root: 'root1'),
          ],
          'cursor': 'next-1',
        });

        expect(response.feed.map(describeLike).toList(), <String>[
          'post at://did:plc:community1/social.coves.community.post/aaa',
          likedCommentCccOnRoot1,
        ]);
        expect(response.cursor, 'next-1');
      });
    }
  });
}
