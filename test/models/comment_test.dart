import 'package:coves_flutter/models/comment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentsResponse', () {
    test('should parse valid JSON with comments', () {
      final json = {
        'post': {'uri': 'at://test/post/123'},
        'cursor': 'next-cursor',
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'content': 'Test comment',
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'test.user'},
              'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
              'stats': {'upvotes': 10, 'downvotes': 2, 'score': 8},
            },
            'hasMore': false,
          },
        ],
      };

      final response = CommentsResponse.fromJson(json);

      expect(response.comments.length, 1);
      expect(response.cursor, 'next-cursor');
      expect(response.comments[0].comment.uri, 'at://did:plc:test/comment/1');
      expect(response.comments[0].comment.content, 'Test comment');
    });

    test('should handle null comments array', () {
      final json = {
        'post': {'uri': 'at://test/post/123'},
        'cursor': null,
        'comments': null,
      };

      final response = CommentsResponse.fromJson(json);

      expect(response.comments, isEmpty);
      expect(response.cursor, null);
    });

    test('should handle empty comments array', () {
      final json = {
        'post': {'uri': 'at://test/post/123'},
        'cursor': null,
        'comments': [],
      };

      final response = CommentsResponse.fromJson(json);

      expect(response.comments, isEmpty);
      expect(response.cursor, null);
    });

    test('should parse without cursor', () {
      final json = {
        'post': {'uri': 'at://test/post/123'},
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'content': 'Test',
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'test.user'},
              'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
              'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
            },
            'hasMore': false,
          },
        ],
      };

      final response = CommentsResponse.fromJson(json);

      expect(response.cursor, null);
      expect(response.comments.length, 1);
    });
  });

  group('ThreadViewComment', () {
    test('should parse valid JSON', () {
      final json = {
        'comment': {
          'uri': 'at://did:plc:test/comment/1',
          'cid': 'cid1',
          'content': 'Test comment',
          'createdAt': '2025-01-01T12:00:00Z',
          'indexedAt': '2025-01-01T12:00:00Z',
          'author': {'did': 'did:plc:author', 'handle': 'test.user'},
          'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
          'stats': {'upvotes': 10, 'downvotes': 2, 'score': 8},
        },
        'hasMore': true,
      };

      final thread = ThreadViewComment.fromJson(json);

      expect(thread.comment.uri, 'at://did:plc:test/comment/1');
      expect(thread.hasMore, true);
      expect(thread.replies, null);
    });

    test('should parse with nested replies', () {
      final json = {
        'comment': {
          'uri': 'at://did:plc:test/comment/1',
          'cid': 'cid1',
          'content': 'Parent comment',
          'createdAt': '2025-01-01T12:00:00Z',
          'indexedAt': '2025-01-01T12:00:00Z',
          'author': {'did': 'did:plc:author', 'handle': 'test.user'},
          'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
          'stats': {'upvotes': 5, 'downvotes': 1, 'score': 4},
        },
        'replies': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/2',
              'cid': 'cid2',
              'content': 'Reply comment',
              'createdAt': '2025-01-01T13:00:00Z',
              'indexedAt': '2025-01-01T13:00:00Z',
              'author': {'did': 'did:plc:author2', 'handle': 'test.user2'},
              'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
              'parent': {'uri': 'at://did:plc:test/comment/1', 'cid': 'cid1'},
              'stats': {'upvotes': 3, 'downvotes': 0, 'score': 3},
            },
            'hasMore': false,
          },
        ],
        'hasMore': false,
      };

      final thread = ThreadViewComment.fromJson(json);

      expect(thread.comment.uri, 'at://did:plc:test/comment/1');
      expect(thread.replies, isNotNull);
      expect(thread.replies!.length, 1);
      expect(thread.replies![0].comment.uri, 'at://did:plc:test/comment/2');
      expect(thread.replies![0].comment.content, 'Reply comment');
    });

    test('should default hasMore to false when missing', () {
      final json = {
        'comment': {
          'uri': 'at://did:plc:test/comment/1',
          'cid': 'cid1',
          'content': 'Test',
          'createdAt': '2025-01-01T12:00:00Z',
          'indexedAt': '2025-01-01T12:00:00Z',
          'author': {'did': 'did:plc:author', 'handle': 'test.user'},
          'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
          'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
        },
      };

      final thread = ThreadViewComment.fromJson(json);

      expect(thread.hasMore, false);
    });
  });

  group('CommentView', () {
    test('should parse complete JSON', () {
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': 'Test comment content',
        // Facets are now in record['facets'] per backend update
        'record': {
          'facets': [
            {
              'index': {'byteStart': 0, 'byteEnd': 10},
              'features': [
                {
                  r'$type': 'social.coves.richtext.facet#link',
                  'uri': 'https://example.com',
                },
              ],
            },
          ],
        },
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:05:00Z',
        'author': {
          'did': 'did:plc:author',
          'handle': 'test.user',
          'displayName': 'Test User',
        },
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'parent': {
          'uri': 'at://did:plc:test/comment/parent',
          'cid': 'parent-cid',
        },
        'stats': {'upvotes': 10, 'downvotes': 2, 'score': 8},
        'viewer': {'vote': 'upvote'},
        'embed': {'type': 'social.coves.embed.external', 'data': {}},
      };

      final comment = CommentView.fromJson(json);

      expect(comment.uri, 'at://did:plc:test/comment/1');
      expect(comment.cid, 'cid1');
      expect(comment.content, 'Test comment content');
      expect(comment.contentFacets, isNotNull);
      expect(comment.contentFacets!.length, 1);
      expect(comment.createdAt, DateTime.parse('2025-01-01T12:00:00Z'));
      expect(comment.indexedAt, DateTime.parse('2025-01-01T12:05:00Z'));
      expect(comment.author.did, 'did:plc:author');
      expect(comment.post.uri, 'at://did:plc:test/post/123');
      expect(comment.parent, isNotNull);
      expect(comment.parent!.uri, 'at://did:plc:test/comment/parent');
      expect(comment.stats.score, 8);
      expect(comment.viewer, isNotNull);
      expect(comment.viewer!.vote, 'upvote');
      expect(comment.embed, isNotNull);
    });

    test('should parse minimal JSON with required fields only', () {
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': 'Test',
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:00Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
      };

      final comment = CommentView.fromJson(json);

      expect(comment.uri, 'at://did:plc:test/comment/1');
      expect(comment.content, 'Test');
      expect(comment.contentFacets, null);
      expect(comment.parent, null);
      expect(comment.viewer, null);
      expect(comment.embed, null);
    });

    test('should handle null optional fields', () {
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': 'Test',
        'record': null, // No record means no facets
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:00Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'parent': null,
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
        'viewer': null,
        'embed': null,
      };

      final comment = CommentView.fromJson(json);

      expect(comment.contentFacets, null);
      expect(comment.parent, null);
      expect(comment.viewer, null);
      expect(comment.embed, null);
    });

    test('should parse dates correctly', () {
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': 'Test',
        'createdAt': '2025-01-15T14:30:45.123Z',
        'indexedAt': '2025-01-15T14:30:50.456Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
      };

      final comment = CommentView.fromJson(json);

      expect(comment.createdAt.year, 2025);
      expect(comment.createdAt.month, 1);
      expect(comment.createdAt.day, 15);
      expect(comment.createdAt.hour, 14);
      expect(comment.createdAt.minute, 30);
      expect(comment.indexedAt, isA<DateTime>());
    });
  });

  group('CommentRef', () {
    test('should parse valid JSON', () {
      final json = {'uri': 'at://did:plc:test/comment/1', 'cid': 'cid1'};

      final ref = CommentRef.fromJson(json);

      expect(ref.uri, 'at://did:plc:test/comment/1');
      expect(ref.cid, 'cid1');
    });
  });

  group('CommentStats', () {
    test('should parse valid JSON with all fields', () {
      final json = {'upvotes': 15, 'downvotes': 3, 'score': 12};

      final stats = CommentStats.fromJson(json);

      expect(stats.upvotes, 15);
      expect(stats.downvotes, 3);
      expect(stats.score, 12);
    });

    test('should default to zero for missing fields', () {
      final json = <String, dynamic>{};

      final stats = CommentStats.fromJson(json);

      expect(stats.upvotes, 0);
      expect(stats.downvotes, 0);
      expect(stats.score, 0);
    });

    test('should handle null values with defaults', () {
      final json = {'upvotes': null, 'downvotes': null, 'score': null};

      final stats = CommentStats.fromJson(json);

      expect(stats.upvotes, 0);
      expect(stats.downvotes, 0);
      expect(stats.score, 0);
    });

    test('should parse mixed null and valid values', () {
      final json = {'upvotes': 10, 'downvotes': null, 'score': 8};

      final stats = CommentStats.fromJson(json);

      expect(stats.upvotes, 10);
      expect(stats.downvotes, 0);
      expect(stats.score, 8);
    });
  });

  group('CommentViewerState', () {
    test('should parse with vote', () {
      final json = {'vote': 'upvote'};

      final viewer = CommentViewerState.fromJson(json);

      expect(viewer.vote, 'upvote');
    });

    test('should parse with downvote', () {
      final json = {'vote': 'downvote'};

      final viewer = CommentViewerState.fromJson(json);

      expect(viewer.vote, 'downvote');
    });

    test('should parse with null vote', () {
      final json = {'vote': null};

      final viewer = CommentViewerState.fromJson(json);

      expect(viewer.vote, null);
    });

    test('should handle missing vote field', () {
      final json = <String, dynamic>{};

      final viewer = CommentViewerState.fromJson(json);

      expect(viewer.vote, null);
    });
  });

  group('Edge cases', () {
    test('should handle deeply nested comment threads', () {
      final json = {
        'comment': {
          'uri': 'at://did:plc:test/comment/1',
          'cid': 'cid1',
          'content': 'Level 1',
          'createdAt': '2025-01-01T12:00:00Z',
          'indexedAt': '2025-01-01T12:00:00Z',
          'author': {'did': 'did:plc:author', 'handle': 'test.user'},
          'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
          'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
        },
        'replies': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/2',
              'cid': 'cid2',
              'content': 'Level 2',
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'test.user'},
              'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
              'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
            },
            'replies': [
              {
                'comment': {
                  'uri': 'at://did:plc:test/comment/3',
                  'cid': 'cid3',
                  'content': 'Level 3',
                  'createdAt': '2025-01-01T12:00:00Z',
                  'indexedAt': '2025-01-01T12:00:00Z',
                  'author': {'did': 'did:plc:author', 'handle': 'test.user'},
                  'post': {
                    'uri': 'at://did:plc:test/post/123',
                    'cid': 'post-cid',
                  },
                  'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
                },
                'hasMore': false,
              },
            ],
            'hasMore': false,
          },
        ],
        'hasMore': false,
      };

      final thread = ThreadViewComment.fromJson(json);

      expect(thread.comment.content, 'Level 1');
      expect(thread.replies![0].comment.content, 'Level 2');
      expect(thread.replies![0].replies![0].comment.content, 'Level 3');
    });

    test('should handle empty content string', () {
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': '',
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:00Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
      };

      final comment = CommentView.fromJson(json);

      expect(comment.content, '');
    });

    test('should handle very long content', () {
      final longContent = 'a' * 10000;
      final json = {
        'uri': 'at://did:plc:test/comment/1',
        'cid': 'cid1',
        'content': longContent,
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:00Z',
        'author': {'did': 'did:plc:author', 'handle': 'test.user'},
        'post': {'uri': 'at://did:plc:test/post/123', 'cid': 'post-cid'},
        'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
      };

      final comment = CommentView.fromJson(json);

      expect(comment.content.length, 10000);
    });

    test('should handle negative vote counts', () {
      final json = {'upvotes': 5, 'downvotes': 20, 'score': -15};

      final stats = CommentStats.fromJson(json);

      expect(stats.upvotes, 5);
      expect(stats.downvotes, 20);
      expect(stats.score, -15);
    });
  });
}
