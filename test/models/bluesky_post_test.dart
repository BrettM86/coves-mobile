import 'package:coves_flutter/models/bluesky_post.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlueskyPostResult.fromJson', () {
    // Helper to create valid JSON with all required fields
    Map<String, dynamic> validPostJson({
      String uri = 'at://did:plc:abc123/app.bsky.feed.post/xyz789',
      String cid = 'bafyreiabc123',
      String createdAt = '2025-01-15T12:30:00.000Z',
      Map<String, dynamic>? author,
      String text = 'Hello world!',
      int replyCount = 5,
      int repostCount = 10,
      int likeCount = 25,
      bool hasMedia = false,
      int mediaCount = 0,
      bool unavailable = false,
      String? message,
      Map<String, dynamic>? quotedPost,
    }) {
      return {
        'uri': uri,
        'cid': cid,
        'createdAt': createdAt,
        'author': author ??
            {
              'did': 'did:plc:testuser123',
              'handle': 'testuser.bsky.social',
              'displayName': 'Test User',
              'avatar': 'https://example.com/avatar.jpg',
            },
        'text': text,
        'replyCount': replyCount,
        'repostCount': repostCount,
        'likeCount': likeCount,
        'hasMedia': hasMedia,
        'mediaCount': mediaCount,
        'unavailable': unavailable,
        if (message != null) 'message': message,
        if (quotedPost != null) 'quotedPost': quotedPost,
      };
    }

    group('valid JSON parsing', () {
      test('parses all required fields correctly', () {
        final json = validPostJson();
        final result = BlueskyPostResult.fromJson(json);

        expect(result.uri, 'at://did:plc:abc123/app.bsky.feed.post/xyz789');
        expect(result.cid, 'bafyreiabc123');
        expect(result.createdAt, DateTime.utc(2025, 1, 15, 12, 30, 0, 0));
        expect(result.author.did, 'did:plc:testuser123');
        expect(result.author.handle, 'testuser.bsky.social');
        expect(result.author.displayName, 'Test User');
        expect(result.text, 'Hello world!');
        expect(result.replyCount, 5);
        expect(result.repostCount, 10);
        expect(result.likeCount, 25);
        expect(result.hasMedia, false);
        expect(result.mediaCount, 0);
        expect(result.unavailable, false);
        expect(result.quotedPost, isNull);
        expect(result.message, isNull);
      });

      test('parses post with media', () {
        final json = validPostJson(hasMedia: true, mediaCount: 3);
        final result = BlueskyPostResult.fromJson(json);

        expect(result.hasMedia, true);
        expect(result.mediaCount, 3);
      });

      test('parses unavailable post with message', () {
        final json = validPostJson(
          unavailable: true,
          message: 'Post was deleted by author',
        );
        final result = BlueskyPostResult.fromJson(json);

        expect(result.unavailable, true);
        expect(result.message, 'Post was deleted by author');
      });

      test('parses author with minimal fields', () {
        final json = validPostJson(
          author: {
            'did': 'did:plc:minimal',
            'handle': 'minimal.bsky.social',
            // displayName and avatar are optional
          },
        );
        final result = BlueskyPostResult.fromJson(json);

        expect(result.author.did, 'did:plc:minimal');
        expect(result.author.handle, 'minimal.bsky.social');
        expect(result.author.displayName, isNull);
        expect(result.author.avatar, isNull);
      });
    });

    group('optional quotedPost parsing', () {
      test('parses nested quotedPost correctly', () {
        final quotedPostJson = validPostJson(
          uri: 'at://did:plc:quoted/app.bsky.feed.post/quoted123',
          text: 'This is the quoted post',
          author: {
            'did': 'did:plc:quotedauthor',
            'handle': 'quotedauthor.bsky.social',
            'displayName': 'Quoted Author',
          },
        );
        final json = validPostJson(quotedPost: quotedPostJson);
        final result = BlueskyPostResult.fromJson(json);

        expect(result.quotedPost, isNotNull);
        expect(
          result.quotedPost!.uri,
          'at://did:plc:quoted/app.bsky.feed.post/quoted123',
        );
        expect(result.quotedPost!.text, 'This is the quoted post');
        expect(result.quotedPost!.author.handle, 'quotedauthor.bsky.social');
      });

      test('handles null quotedPost', () {
        final json = validPostJson();
        final result = BlueskyPostResult.fromJson(json);

        expect(result.quotedPost, isNull);
      });
    });

    group('missing required fields', () {
      test('throws FormatException when uri is missing', () {
        final json = validPostJson();
        json.remove('uri');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('uri'),
            ),
          ),
        );
      });

      test('throws FormatException when cid is missing', () {
        final json = validPostJson();
        json.remove('cid');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('cid'),
            ),
          ),
        );
      });

      test('throws FormatException when createdAt is missing', () {
        final json = validPostJson();
        json.remove('createdAt');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('createdAt'),
            ),
          ),
        );
      });

      test('throws FormatException when author is missing', () {
        final json = validPostJson();
        json.remove('author');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('author'),
            ),
          ),
        );
      });

      test('throws FormatException when text is missing', () {
        final json = validPostJson();
        json.remove('text');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('text'),
            ),
          ),
        );
      });

      test('throws FormatException when replyCount is missing', () {
        final json = validPostJson();
        json.remove('replyCount');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('replyCount'),
            ),
          ),
        );
      });

      test('throws FormatException when repostCount is missing', () {
        final json = validPostJson();
        json.remove('repostCount');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('repostCount'),
            ),
          ),
        );
      });

      test('throws FormatException when likeCount is missing', () {
        final json = validPostJson();
        json.remove('likeCount');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('likeCount'),
            ),
          ),
        );
      });

      test('throws FormatException when hasMedia is missing', () {
        final json = validPostJson();
        json.remove('hasMedia');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('hasMedia'),
            ),
          ),
        );
      });

      test('throws FormatException when mediaCount is missing', () {
        final json = validPostJson();
        json.remove('mediaCount');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('mediaCount'),
            ),
          ),
        );
      });

      test('throws FormatException when unavailable is missing', () {
        final json = validPostJson();
        json.remove('unavailable');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('unavailable'),
            ),
          ),
        );
      });
    });

    group('invalid field types', () {
      test('throws FormatException when uri is not a string', () {
        final json = validPostJson();
        json['uri'] = 123;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('uri'),
            ),
          ),
        );
      });

      test('throws FormatException when cid is not a string', () {
        final json = validPostJson();
        json['cid'] = true;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('cid'),
            ),
          ),
        );
      });

      test('throws FormatException when createdAt is not a string', () {
        final json = validPostJson();
        json['createdAt'] = 1234567890;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('createdAt'),
            ),
          ),
        );
      });

      test('throws FormatException when author is not a map', () {
        final json = validPostJson();
        json['author'] = 'not a map';

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('author'),
            ),
          ),
        );
      });

      test('throws FormatException when text is not a string', () {
        final json = validPostJson();
        json['text'] = ['not', 'a', 'string'];

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('text'),
            ),
          ),
        );
      });

      test('throws FormatException when replyCount is not an int', () {
        final json = validPostJson();
        json['replyCount'] = '5';

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('replyCount'),
            ),
          ),
        );
      });

      test('throws FormatException when repostCount is not an int', () {
        final json = validPostJson();
        json['repostCount'] = 10.5;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('repostCount'),
            ),
          ),
        );
      });

      test('throws FormatException when likeCount is not an int', () {
        final json = validPostJson();
        json['likeCount'] = null;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('likeCount'),
            ),
          ),
        );
      });

      test('throws FormatException when hasMedia is not a bool', () {
        final json = validPostJson();
        json['hasMedia'] = 'true';

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('hasMedia'),
            ),
          ),
        );
      });

      test('throws FormatException when mediaCount is not an int', () {
        final json = validPostJson();
        json['mediaCount'] = false;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('mediaCount'),
            ),
          ),
        );
      });

      test('throws FormatException when unavailable is not a bool', () {
        final json = validPostJson();
        json['unavailable'] = 0;

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('unavailable'),
            ),
          ),
        );
      });
    });

    group('invalid date format for createdAt', () {
      test('throws FormatException for invalid date string', () {
        final json = validPostJson(createdAt: 'not-a-date');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid date format'),
            ),
          ),
        );
      });

      test('throws FormatException for malformed ISO date', () {
        // Use a format that DateTime.parse definitely rejects
        final json = validPostJson(createdAt: '2025/01/15 12:00:00');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid date format'),
            ),
          ),
        );
      });

      test('throws FormatException for empty date string', () {
        final json = validPostJson(createdAt: '');

        expect(
          () => BlueskyPostResult.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid date format'),
            ),
          ),
        );
      });

      test('parses valid ISO 8601 date formats', () {
        // Standard ISO 8601 with timezone
        final json1 = validPostJson(createdAt: '2025-06-15T08:30:00.000Z');
        final result1 = BlueskyPostResult.fromJson(json1);
        expect(result1.createdAt, DateTime.utc(2025, 6, 15, 8, 30));

        // Without milliseconds
        final json2 = validPostJson(createdAt: '2025-06-15T08:30:00Z');
        final result2 = BlueskyPostResult.fromJson(json2);
        expect(result2.createdAt, DateTime.utc(2025, 6, 15, 8, 30));
      });
    });
  });

  group('BlueskyPostEmbed.fromJson', () {
    test('parses valid embed JSON', () {
      final json = {
        'post': {
          'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
          'cid': 'bafyrei123',
        },
      };

      final embed = BlueskyPostEmbed.fromJson(json);

      expect(embed.uri, 'at://did:plc:xyz/app.bsky.feed.post/abc');
      expect(embed.cid, 'bafyrei123');
      expect(embed.resolved, isNull);
    });

    test('parses embed with resolved post', () {
      final json = {
        'post': {
          'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
          'cid': 'bafyrei123',
        },
        'resolved': {
          'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
          'cid': 'bafyrei123',
          'createdAt': '2025-01-15T12:00:00Z',
          'author': {
            'did': 'did:plc:xyz',
            'handle': 'test.bsky.social',
          },
          'text': 'Resolved post text',
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'hasMedia': false,
          'mediaCount': 0,
          'unavailable': false,
        },
      };

      final embed = BlueskyPostEmbed.fromJson(json);

      expect(embed.resolved, isNotNull);
      expect(embed.resolved!.text, 'Resolved post text');
    });

    test('throws FormatException when post field is missing', () {
      final json = <String, dynamic>{};

      expect(
        () => BlueskyPostEmbed.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('post field'),
          ),
        ),
      );
    });

    test('throws FormatException when post field is not a map', () {
      final json = {'post': 'not a map'};

      expect(
        () => BlueskyPostEmbed.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('post field'),
          ),
        ),
      );
    });

    test('throws FormatException when uri in post is missing', () {
      final json = {
        'post': {'cid': 'bafyrei123'},
      };

      expect(
        () => BlueskyPostEmbed.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('uri'),
          ),
        ),
      );
    });

    test('throws FormatException when cid in post is missing', () {
      final json = {
        'post': {'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc'},
      };

      expect(
        () => BlueskyPostEmbed.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cid'),
          ),
        ),
      );
    });
  });

  group('BlueskyPostEmbed.getPostWebUrl', () {
    // Helper to create a minimal BlueskyPostResult for testing
    BlueskyPostResult createPost({String handle = 'testuser.bsky.social'}) {
      return BlueskyPostResult(
        uri: 'at://did:plc:test/app.bsky.feed.post/test123',
        cid: 'bafyrei123',
        createdAt: DateTime.now(),
        author: _createAuthorView(handle: handle),
        text: 'Test post',
        replyCount: 0,
        repostCount: 0,
        likeCount: 0,
        hasMedia: false,
        mediaCount: 0,
        unavailable: false,
      );
    }

    test('parses valid AT-URI correctly', () {
      final post = createPost(handle: 'alice.bsky.social');
      const atUri = 'at://did:plc:abc123xyz/app.bsky.feed.post/rkey456';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, 'https://bsky.app/profile/alice.bsky.social/post/rkey456');
    });

    test('handles AT-URI with complex DID', () {
      final post = createPost(handle: 'bob.bsky.social');
      const atUri = 'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3k5qmrblv5c2a';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(
        url,
        'https://bsky.app/profile/bob.bsky.social/post/3k5qmrblv5c2a',
      );
    });

    test('returns null when AT-URI is missing at:// prefix', () {
      final post = createPost();
      const atUri = 'did:plc:abc123/app.bsky.feed.post/rkey456';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });

    test('returns null when AT-URI has wrong prefix', () {
      final post = createPost();
      const atUri = 'https://did:plc:abc123/app.bsky.feed.post/rkey456';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });

    test('returns null when AT-URI has no path', () {
      final post = createPost();
      const atUri = 'at://did:plc:abc123';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });

    test('returns null when path has less than 2 segments', () {
      final post = createPost();
      const atUri = 'at://did:plc:abc123/app.bsky.feed.post';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });

    test('handles path with exactly 2 segments', () {
      final post = createPost(handle: 'minimal.bsky.social');
      const atUri = 'at://did:plc:abc123/collection/rkey';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, 'https://bsky.app/profile/minimal.bsky.social/post/rkey');
    });

    test('extracts last segment as rkey even with extra segments', () {
      final post = createPost(handle: 'user.bsky.social');
      const atUri = 'at://did:plc:abc123/extra/path/segments/finalrkey';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, 'https://bsky.app/profile/user.bsky.social/post/finalrkey');
    });

    test('handles empty string AT-URI', () {
      final post = createPost();
      const atUri = '';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });

    test('handles AT-URI with only at:// prefix', () {
      final post = createPost();
      const atUri = 'at://';

      final url = BlueskyPostEmbed.getPostWebUrl(post, atUri);

      expect(url, isNull);
    });
  });

  group('BlueskyPostEmbed.getProfileUrl', () {
    test('builds profile URL from handle', () {
      final url = BlueskyPostEmbed.getProfileUrl('alice.bsky.social');

      expect(url, 'https://bsky.app/profile/alice.bsky.social');
    });

    test('handles custom domain handle', () {
      final url = BlueskyPostEmbed.getProfileUrl('alice.dev');

      expect(url, 'https://bsky.app/profile/alice.dev');
    });

    test('handles handle with numbers', () {
      final url = BlueskyPostEmbed.getProfileUrl('user123.bsky.social');

      expect(url, 'https://bsky.app/profile/user123.bsky.social');
    });

    test('handles empty handle', () {
      final url = BlueskyPostEmbed.getProfileUrl('');

      expect(url, 'https://bsky.app/profile/');
    });
  });

  group('BlueskyExternalEmbed', () {
    group('fromJson', () {
      test('parses valid embed with all fields', () {
        final json = {
          'uri': 'https://lemonde.fr/article',
          'title': 'Breaking News',
          'description': 'An important article about world events.',
          'thumb': 'https://cdn.lemonde.fr/thumbnail.jpg',
        };

        final embed = BlueskyExternalEmbed.fromJson(json);

        expect(embed.uri, 'https://lemonde.fr/article');
        expect(embed.title, 'Breaking News');
        expect(embed.description, 'An important article about world events.');
        expect(embed.thumb, 'https://cdn.lemonde.fr/thumbnail.jpg');
      });

      test('parses embed with only required uri field', () {
        final json = {'uri': 'https://example.com'};

        final embed = BlueskyExternalEmbed.fromJson(json);

        expect(embed.uri, 'https://example.com');
        expect(embed.title, isNull);
        expect(embed.description, isNull);
        expect(embed.thumb, isNull);
      });

      test('throws FormatException when uri is missing', () {
        final json = {
          'title': 'Some Title',
          'description': 'Some description',
        };

        expect(
          () => BlueskyExternalEmbed.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException when uri is not a string', () {
        final json = {'uri': 123};

        expect(
          () => BlueskyExternalEmbed.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException when uri is null', () {
        final json = {'uri': null};

        expect(
          () => BlueskyExternalEmbed.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('domain getter', () {
      test('extracts domain from full URL', () {
        final embed = BlueskyExternalEmbed(
          uri: 'https://www.lemonde.fr/article/123',
        );

        expect(embed.domain, 'lemonde.fr');
      });

      test('removes www prefix', () {
        final embed = BlueskyExternalEmbed(
          uri: 'https://www.example.com/page',
        );

        expect(embed.domain, 'example.com');
      });

      test('handles URL without www', () {
        final embed = BlueskyExternalEmbed(uri: 'https://bbc.co.uk/news');

        expect(embed.domain, 'bbc.co.uk');
      });

      test('handles subdomain', () {
        final embed = BlueskyExternalEmbed(
          uri: 'https://blog.example.com/post',
        );

        expect(embed.domain, 'blog.example.com');
      });

      test('returns uri for invalid URL', () {
        final embed = BlueskyExternalEmbed(uri: 'not-a-valid-url');

        expect(embed.domain, 'not-a-valid-url');
      });

      test('handles empty uri', () {
        final embed = BlueskyExternalEmbed(uri: '');

        expect(embed.domain, '');
      });
    });
  });

  group('BlueskyPostResult with embed', () {
    Map<String, dynamic> validPostJsonWithEmbed({
      Map<String, dynamic>? embed,
    }) {
      return {
        'uri': 'at://did:plc:abc123/app.bsky.feed.post/xyz789',
        'cid': 'bafyreiabc123',
        'createdAt': '2025-01-15T12:30:00.000Z',
        'author': {
          'did': 'did:plc:testuser123',
          'handle': 'testuser.bsky.social',
          'displayName': 'Test User',
          'avatar': 'https://example.com/avatar.jpg',
        },
        'text': 'Check out this article!',
        'replyCount': 5,
        'repostCount': 10,
        'likeCount': 25,
        'hasMedia': false,
        'mediaCount': 0,
        'unavailable': false,
        if (embed != null) 'embed': embed,
      };
    }

    test('parses post with external embed', () {
      final json = validPostJsonWithEmbed(
        embed: {
          'uri': 'https://lemonde.fr/article',
          'title': 'News Article',
          'description': 'Article description',
          'thumb': 'https://cdn.lemonde.fr/thumb.jpg',
        },
      );

      final result = BlueskyPostResult.fromJson(json);

      expect(result.embed, isNotNull);
      expect(result.embed!.uri, 'https://lemonde.fr/article');
      expect(result.embed!.title, 'News Article');
      expect(result.embed!.description, 'Article description');
      expect(result.embed!.thumb, 'https://cdn.lemonde.fr/thumb.jpg');
    });

    test('parses post without embed', () {
      final json = validPostJsonWithEmbed();

      final result = BlueskyPostResult.fromJson(json);

      expect(result.embed, isNull);
    });

    test('handles malformed embed gracefully', () {
      final json = validPostJsonWithEmbed(
        embed: {'title': 'Missing URI'}, // Missing required 'uri' field
      );

      // Should not throw - malformed embed is silently ignored
      final result = BlueskyPostResult.fromJson(json);

      expect(result.embed, isNull);
      expect(result.text, 'Check out this article!');
    });

    test('parses embed with minimal fields', () {
      final json = validPostJsonWithEmbed(
        embed: {'uri': 'https://example.com'},
      );

      final result = BlueskyPostResult.fromJson(json);

      expect(result.embed, isNotNull);
      expect(result.embed!.uri, 'https://example.com');
      expect(result.embed!.title, isNull);
      expect(result.embed!.description, isNull);
      expect(result.embed!.thumb, isNull);
    });
  });
}

// Helper to create AuthorView for tests
AuthorView _createAuthorView({
  String did = 'did:plc:test',
  required String handle,
  String? displayName,
  String? avatar,
}) {
  return AuthorView(
    did: did,
    handle: handle,
    displayName: displayName,
    avatar: avatar,
  );
}
