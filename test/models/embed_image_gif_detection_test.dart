import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

// The images#view the AppView serves carries no MIME type; the stored blob
// in the raw record does. Shapes below match the live AppView.

Map<String, dynamic> _viewImage(String name, {String? alt}) => {
  'thumb': 'https://cdn.test/$name-thumb.jpg',
  'fullsize': 'https://cdn.test/$name-full.jpg',
  'alt': ?alt,
};

Map<String, dynamic> _recordImage(String mimeType, {String? alt}) => {
  'image': {
    r'$type': 'blob',
    'mimeType': mimeType,
    'ref': {r'$link': 'bafkreigifcid'},
    'size': 217564,
  },
  'alt': ?alt,
};

Map<String, dynamic> _imagesView(List<Map<String, dynamic>> images) => {
  r'$type': 'social.coves.embed.images#view',
  'images': images,
};

Map<String, dynamic> _imagesRecord(Object? images) => {
  r'$type': 'social.coves.embed.images',
  'images': images,
};

Map<String, dynamic> _postJson({
  required Map<String, dynamic> embed,
  Map<String, dynamic>? recordEmbed,
}) => {
  'uri': 'at://did:plc:test/social.coves.community.post/123',
  'cid': 'bafypostcid',
  'rkey': '123',
  'author': {'did': 'did:plc:author', 'handle': 'test.user'},
  'community': {'did': 'did:plc:community', 'name': 'testcove'},
  'createdAt': '2025-01-01T12:00:00Z',
  'indexedAt': '2025-01-01T12:00:05Z',
  'record': {
    r'$type': 'social.coves.community.post',
    'content': 'A post with images',
    'embed': ?recordEmbed,
  },
  'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0, 'commentCount': 0},
  'embed': embed,
};

List<bool> _gifFlags(PostEmbed? embed) => switch (embed) {
  ImagesPostEmbed(:final images) => [for (final i in images) i.isGif],
  ImagesWithAttachmentPostEmbed(:final images) => [
    for (final i in images) i.isGif,
  ],
  _ => throw StateError('not an image gallery: $embed'),
};

void main() {
  final twoViewImages = _imagesView([
    _viewImage('a', alt: 'Dancing cat'),
    _viewImage('b'),
  ]);

  group('PostView.fromJson GIF detection', () {
    test('flags each image whose record blob is image/gif', () {
      final post = PostView.fromJson(
        _postJson(
          embed: twoViewImages,
          recordEmbed: _imagesRecord([
            _recordImage('image/gif', alt: 'Dancing cat'),
            _recordImage('image/jpeg'),
          ]),
        ),
      );

      expect(_gifFlags(post.embed), [true, false]);
    });

    test('flags imagesWithAttachment from the nested record gallery', () {
      final post = PostView.fromJson(
        _postJson(
          embed: {
            r'$type': 'social.coves.embed.imagesWithAttachment#view',
            'images': twoViewImages,
            'attachment': {
              r'$type': 'social.coves.embed.external#viewExternal',
              'uri': 'https://example.com/maps',
            },
          },
          recordEmbed: {
            r'$type': 'social.coves.embed.imagesWithAttachment',
            'images': _imagesRecord([
              _recordImage('image/jpeg'),
              _recordImage('image/gif'),
            ]),
            'attachment': {
              r'$type': 'social.coves.embed.external',
              'external': {'uri': 'https://example.com/maps'},
            },
          },
        ),
      );

      expect(_gifFlags(post.embed), [false, true]);
    });

    final noFlagRows = <(String, Map<String, dynamic>?)>[
      ('record has no embed', null),
      (
        'record gallery count differs from the view',
        _imagesRecord([_recordImage('image/gif')]),
      ),
      ('record images is not a list', _imagesRecord('image/gif')),
      (
        'record image entries are malformed',
        _imagesRecord([
          {'image': 'image/gif'},
          {
            'image': {r'$type': 'blob', 'mimeType': 42},
          },
        ]),
      ),
    ];

    for (final (name, recordEmbed) in noFlagRows) {
      test('$name: no image is flagged and the post parses', () {
        final post = PostView.fromJson(
          _postJson(embed: twoViewImages, recordEmbed: recordEmbed),
        );

        expect(_gifFlags(post.embed), [false, false]);
        expect(post.text, 'A post with images');
      });
    }
  });

  group('CommentView.fromJson GIF detection', () {
    test('flags parsedEmbed images from the comment record blob', () {
      final comment = CommentView.fromJson({
        'uri': 'at://did:plc:test/social.coves.community.comment/1',
        'cid': 'bafycommentcid',
        'record': {
          r'$type': 'social.coves.community.comment',
          'content': 'Look at this',
          'embed': _imagesRecord([
            _recordImage('image/gif', alt: 'Dancing cat'),
            _recordImage('image/jpeg'),
          ]),
        },
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:00Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
        'embed': twoViewImages,
      });

      expect(_gifFlags(comment.parsedEmbed), [true, false]);
    });
  });
}
