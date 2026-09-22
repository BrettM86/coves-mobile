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
        'author':
            author ??
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
        'message': ?message,
        'quotedPost': ?quotedPost,
      };
    }

    group('valid JSON parsing', () {
      test('parses all required fields correctly', () {
        final json = validPostJson();
        final result = BlueskyPostResult.fromJson(json);

        expect(result.uri, 'at://did:plc:abc123/app.bsky.feed.post/xyz789');
        expect(result.cid, 'bafyreiabc123');
        expect(result.createdAt, DateTime.utc(2025, 1, 15, 12, 30));
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
        final json = validPostJson()..remove('uri');

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
        final json = validPostJson()..remove('cid');

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
        final json = validPostJson()..remove('createdAt');

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
        final json = validPostJson()..remove('author');

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
        final json = validPostJson()..remove('text');

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
        final json = validPostJson()..remove('replyCount');

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
        final json = validPostJson()..remove('repostCount');

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
        final json = validPostJson()..remove('likeCount');

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
        final json = validPostJson()..remove('hasMedia');

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
        final json = validPostJson()..remove('mediaCount');

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
        final json = validPostJson()..remove('unavailable');

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
          'author': {'did': 'did:plc:xyz', 'handle': 'test.bsky.social'},
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
      const atUri =
          'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3k5qmrblv5c2a';

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
        final json = {'title': 'Some Title', 'description': 'Some description'};

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
        final embed = BlueskyExternalEmbed(uri: 'https://www.example.com/page');

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
    Map<String, dynamic> validPostJsonWithEmbed({Map<String, dynamic>? embed}) {
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
        'embed': ?embed,
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

  group('unavailable quoted posts', () {
    // Backend wire shape for a quoted post that cannot be shown. A deleted or
    // detached quote carries no `author` key at all; a blocked quote carries a
    // partial author. Literal JSON here on purpose: the `validPostJson` helper
    // above substitutes a valid author when passed null.
    Map<String, dynamic> quotedPostJson({
      required bool unavailable,
      String? message,
      Map<String, dynamic>? author,
    }) {
      return {
        'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
        'cid': '',
        'text': '',
        'createdAt': '0001-01-01T00:00:00Z',
        'replyCount': 0,
        'repostCount': 0,
        'likeCount': 0,
        'mediaCount': 0,
        'hasMedia': false,
        'unavailable': unavailable,
        'message': ?message,
        'author': ?author,
      };
    }

    Map<String, dynamic> embedJson({
      Map<String, dynamic>? quotedPost,
      Map<String, dynamic>? parentAuthor = const {
        'did': 'did:plc:parent',
        'handle': 'parent.bsky.social',
      },
      bool parentUnavailable = false,
      String? parentMessage,
    }) {
      return {
        'post': {
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
        },
        'resolved': {
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
          'text': 'Parent post text',
          'createdAt': '2026-09-01T12:00:00Z',
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'mediaCount': 0,
          'hasMedia': false,
          'unavailable': parentUnavailable,
          'message': ?parentMessage,
          'author': ?parentAuthor,
          'quotedPost': ?quotedPost,
        },
      };
    }

    test('keeps the parent when a deleted quote has no author', () {
      final embed = BlueskyPostEmbed.fromJson(
        embedJson(
          quotedPost: quotedPostJson(
            unavailable: true,
            message: 'This post has been deleted',
          ),
        ),
      );

      expect(embed.resolved, isNotNull);
      expect(embed.resolved!.text, 'Parent post text');
      expect(embed.resolved!.quotedPost, isNotNull);
      expect(embed.resolved!.quotedPost!.unavailable, true);
      expect(embed.resolved!.quotedPost!.message, 'This post has been deleted');
    });

    test('keeps the parent when a detached quote has no author', () {
      final embed = BlueskyPostEmbed.fromJson(
        embedJson(
          quotedPost: quotedPostJson(
            unavailable: true,
            message: 'This post is unavailable',
          ),
        ),
      );

      expect(embed.resolved, isNotNull);
      expect(embed.resolved!.text, 'Parent post text');
      expect(embed.resolved!.quotedPost, isNotNull);
      expect(embed.resolved!.quotedPost!.unavailable, true);
      expect(embed.resolved!.quotedPost!.message, 'This post is unavailable');
    });

    test('keeps the parent when a blocked quote has a partial author', () {
      final embed = BlueskyPostEmbed.fromJson(
        embedJson(
          quotedPost: quotedPostJson(
            unavailable: true,
            message: 'This post is from a blocked account',
            author: const {'did': 'did:plc:blocked', 'handle': ''},
          ),
        ),
      );

      expect(embed.resolved, isNotNull);
      expect(embed.resolved!.quotedPost, isNotNull);
      expect(embed.resolved!.quotedPost!.unavailable, true);
      expect(
        embed.resolved!.quotedPost!.message,
        'This post is from a blocked account',
      );
    });

    test('treats an available quote without an author as malformed', () {
      final embed = BlueskyPostEmbed.fromJson(
        embedJson(quotedPost: quotedPostJson(unavailable: false)),
      );

      expect(embed.resolved, isNull);
    });

    test('treats an available parent without an author as malformed', () {
      final embed = BlueskyPostEmbed.fromJson(embedJson(parentAuthor: null));

      expect(embed.resolved, isNull);
    });

    test('keeps the parent when a deleted quote sends a null author', () {
      // The helper drops null-valued keys, so set the explicit null here.
      final quotedPost = quotedPostJson(
        unavailable: true,
        message: 'This post has been deleted',
      );
      quotedPost['author'] = null;

      final embed = BlueskyPostEmbed.fromJson(
        embedJson(quotedPost: quotedPost),
      );

      expect(embed.resolved, isNotNull);
      expect(embed.resolved!.text, 'Parent post text');
      expect(embed.resolved!.quotedPost, isNotNull);
      expect(embed.resolved!.quotedPost!.unavailable, true);
      expect(embed.resolved!.quotedPost!.message, 'This post has been deleted');
    });

    test('treats a quote missing both author and unavailable as malformed', () {
      final quotedPost = quotedPostJson(
        unavailable: true,
        message: 'This post has been deleted',
      )..remove('unavailable');

      final embed = BlueskyPostEmbed.fromJson(
        embedJson(quotedPost: quotedPost),
      );

      expect(embed.resolved, isNull);
    });
  });

  group('images', () {
    // Backend wire shape (coves e92395d). The parent and the quote use
    // different cdn.bsky.app paths so a gallery attributed to the wrong post
    // is detectable.
    const parentThumb1 =
        'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:parent/bafyparent1@jpeg';
    const parentFullsize1 =
        'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:parent/bafyparent1@jpeg';
    const parentThumb2 =
        'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:parent/bafyparent2@jpeg';
    const parentFullsize2 =
        'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:parent/bafyparent2@jpeg';
    const quoteThumb1 =
        'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:quoted/bafyquote1@jpeg';
    const quoteFullsize1 =
        'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:quoted/bafyquote1@jpeg';

    Map<String, dynamic> imageJson({
      required String thumb,
      required String fullsize,
      String? alt,
      int? aspectWidth,
      int? aspectHeight,
    }) {
      return {
        'thumb': thumb,
        'fullsize': fullsize,
        'alt': ?alt,
        'aspectRatio': ?(aspectWidth != null && aspectHeight != null
            ? {'width': aspectWidth, 'height': aspectHeight}
            : null),
      };
    }

    /// A post with an optional gallery. A null [images] omits the key, which is
    /// what the backend sends for a post with no images.
    Map<String, dynamic> postJson({
      List<Map<String, dynamic>>? images,
      Map<String, dynamic>? quotedPost,
      String uri = 'at://did:plc:parent/app.bsky.feed.post/p1',
      String text = 'Look at these cats',
      String handle = 'images.bsky.social',
    }) {
      return {
        'uri': uri,
        'cid': 'bafyparentcid',
        'createdAt': '2026-09-01T12:00:00Z',
        'author': {'did': 'did:plc:parent', 'handle': handle},
        'text': text,
        'replyCount': 0,
        'repostCount': 0,
        'likeCount': 0,
        'hasMedia': images != null && images.isNotEmpty,
        'mediaCount': images?.length ?? 0,
        'unavailable': false,
        'images': ?images,
        'quotedPost': ?quotedPost,
      };
    }

    test('parses each image with its alt text and aspect ratio', () {
      final result = BlueskyPostResult.fromJson(
        postJson(
          images: [
            imageJson(
              thumb: parentThumb1,
              fullsize: parentFullsize1,
              alt: 'A cat',
              aspectWidth: 1200,
              aspectHeight: 900,
            ),
            imageJson(thumb: parentThumb2, fullsize: parentFullsize2),
          ],
        ),
      );

      expect(result.images, hasLength(2));

      final first = result.images.first;
      expect(first.thumb, parentThumb1);
      expect(first.fullsize, parentFullsize1);
      expect(first.alt, 'A cat');
      expect(first.aspectRatio, isNotNull);
      expect(first.aspectRatio!.width, 1200);
      expect(first.aspectRatio!.height, 900);
    });

    test('leaves alt and aspectRatio null when those keys are absent', () {
      final result = BlueskyPostResult.fromJson(
        postJson(
          images: [imageJson(thumb: parentThumb2, fullsize: parentFullsize2)],
        ),
      );

      expect(result.images, hasLength(1));
      expect(result.images.single.thumb, parentThumb2);
      expect(result.images.single.fullsize, parentFullsize2);
      expect(result.images.single.alt, isNull);
      expect(result.images.single.aspectRatio, isNull);
    });

    test('keeps an empty alt string as sent', () {
      final result = BlueskyPostResult.fromJson(
        postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1, alt: ''),
          ],
        ),
      );

      expect(result.images.single.alt, '');
    });

    test('exposes an empty list when the images key is absent', () {
      final result = BlueskyPostResult.fromJson(postJson());

      expect(result.images, isEmpty);
    });

    test('parses the quoted post gallery independently of the parent', () {
      final result = BlueskyPostResult.fromJson(
        postJson(
          images: [imageJson(thumb: parentThumb1, fullsize: parentFullsize1)],
          quotedPost: postJson(
            uri: 'at://did:plc:quoted/app.bsky.feed.post/q1',
            text: 'The quoted post',
            handle: 'quoted.bsky.social',
            images: [imageJson(thumb: quoteThumb1, fullsize: quoteFullsize1)],
          ),
        ),
      );

      expect(result.images.single.thumb, parentThumb1);
      expect(result.quotedPost, isNotNull);
      expect(result.quotedPost!.images, hasLength(1));
      expect(result.quotedPost!.images.single.thumb, quoteThumb1);
      expect(result.quotedPost!.images.single.fullsize, quoteFullsize1);
    });

    test('a parent without images keeps an empty list beside a quote that '
        'has them', () {
      final result = BlueskyPostResult.fromJson(
        postJson(
          quotedPost: postJson(
            uri: 'at://did:plc:quoted/app.bsky.feed.post/q1',
            text: 'The quoted post',
            handle: 'quoted.bsky.social',
            images: [imageJson(thumb: quoteThumb1, fullsize: quoteFullsize1)],
          ),
        ),
      );

      expect(result.images, isEmpty);
      expect(result.quotedPost!.images.single.thumb, quoteThumb1);
    });

    // A malformed gallery must not cost the reader the post: the text still
    // parses and the gallery drops out whole, so a half-rendered set of
    // images can never reach the card.
    group('validation', () {
      test('drops the gallery when images is a map', () {
        final json = postJson()
          ..['images'] = {'thumb': parentThumb1, 'fullsize': parentFullsize1};

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, isEmpty);
        expect(result.text, 'Look at these cats');
      });

      test('drops the gallery when images is a string', () {
        final json = postJson()..['images'] = 'nope';

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the gallery when an entry is not a map', () {
        final json = postJson()..['images'] = ['not a map'];

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the gallery when an entry lacks thumb', () {
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1)
              ..remove('thumb'),
          ],
        );

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the gallery when an entry lacks fullsize', () {
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1)
              ..remove('fullsize'),
          ],
        );

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the gallery when thumb is not an allowed web url', () {
        final json = postJson(
          images: [
            imageJson(thumb: 'javascript:alert(1)', fullsize: parentFullsize1),
          ],
        );

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the gallery when fullsize is a bare path', () {
        final json = postJson(
          images: [imageJson(thumb: parentThumb1, fullsize: '/img/x.jpg')],
        );

        expect(BlueskyPostResult.fromJson(json).images, isEmpty);
      });

      test('drops the whole gallery when only the second entry is invalid', () {
        final json = postJson()
          ..['images'] = [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1),
            {'thumb': parentThumb2},
          ];

        expect(
          BlueskyPostResult.fromJson(json).images,
          isEmpty,
          reason: 'all-or-nothing: no partial galleries',
        );
      });

      test('keeps the image with a null aspectRatio when it is not a map', () {
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1)
              ..['aspectRatio'] = '1200x900',
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, hasLength(1));
        expect(result.images.single.thumb, parentThumb1);
        expect(result.images.single.aspectRatio, isNull);
      });

      test('keeps the image with a null aspectRatio when a dimension is not '
          'an int', () {
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1)
              ..['aspectRatio'] = {'width': '1200', 'height': 900},
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, hasLength(1));
        expect(result.images.single.aspectRatio, isNull);
      });

      test('keeps the image with a null aspectRatio when a dimension is below '
          'one', () {
        final json = postJson(
          images: [
            imageJson(
              thumb: parentThumb1,
              fullsize: parentFullsize1,
              aspectWidth: 1200,
              aspectHeight: 0,
            ),
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, hasLength(1));
        expect(result.images.single.aspectRatio, isNull);
      });

      test('keeps the image with a null alt when alt is not a string', () {
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1)
              ..['alt'] = 42,
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, hasLength(1));
        expect(result.images.single.thumb, parentThumb1);
        expect(result.images.single.alt, isNull);
      });

      test('truncates alt longer than 10000 characters to exactly 10000', () {
        final json = postJson(
          images: [
            imageJson(
              thumb: parentThumb1,
              fullsize: parentFullsize1,
              alt: 'a' * 20000,
            ),
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, hasLength(1));
        expect(result.images.single.thumb, parentThumb1);
        expect(result.images.single.alt?.length, 10000);
        expect(result.images.single.alt, 'a' * 10000);
      });

      test('keeps alt of exactly 10000 characters unchanged', () {
        final alt = 'b' * 10000;
        final json = postJson(
          images: [
            imageJson(thumb: parentThumb1, fullsize: parentFullsize1, alt: alt),
          ],
        );

        expect(BlueskyPostResult.fromJson(json).images.single.alt, alt);
      });

      // Bluesky allows at most four images per post; a longer list is not a
      // real gallery and drops out whole.
      test('drops the gallery when it has more than four entries', () {
        final json = postJson(
          images: [
            for (var index = 0; index < 5; index++)
              imageJson(thumb: parentThumb1, fullsize: parentFullsize1),
          ],
        );

        final result = BlueskyPostResult.fromJson(json);

        expect(result.images, isEmpty);
        expect(result.text, 'Look at these cats');
      });

      test('keeps a gallery of exactly four entries', () {
        final json = postJson(
          images: [
            for (var index = 0; index < 4; index++)
              imageJson(thumb: parentThumb1, fullsize: parentFullsize1),
          ],
        );

        expect(BlueskyPostResult.fromJson(json).images, hasLength(4));
      });

      test('an invalid quote gallery leaves the parent gallery intact', () {
        final result = BlueskyPostResult.fromJson(
          postJson(
            images: [imageJson(thumb: parentThumb1, fullsize: parentFullsize1)],
            quotedPost: postJson(
              uri: 'at://did:plc:quoted/app.bsky.feed.post/q1',
              text: 'The quoted post',
              handle: 'quoted.bsky.social',
              images: [
                imageJson(
                  thumb: 'javascript:alert(1)',
                  fullsize: quoteFullsize1,
                ),
              ],
            ),
          ),
        );

        expect(result.images, hasLength(1));
        expect(result.images.single.thumb, parentThumb1);
        expect(result.quotedPost!.images, isEmpty);
        expect(result.quotedPost!.text, 'The quoted post');
      });

      test('an invalid parent gallery leaves the quote gallery intact', () {
        final result = BlueskyPostResult.fromJson(
          postJson(
            images: [
              imageJson(
                thumb: 'javascript:alert(1)',
                fullsize: parentFullsize1,
              ),
            ],
            quotedPost: postJson(
              uri: 'at://did:plc:quoted/app.bsky.feed.post/q1',
              text: 'The quoted post',
              handle: 'quoted.bsky.social',
              images: [imageJson(thumb: quoteThumb1, fullsize: quoteFullsize1)],
            ),
          ),
        );

        expect(result.images, isEmpty);
        expect(result.text, 'Look at these cats');
        expect(result.quotedPost!.images, hasLength(1));
        expect(result.quotedPost!.images.single.thumb, quoteThumb1);
      });

      test('still requires hasMedia on a post that has valid images', () {
        final json = postJson(
          images: [imageJson(thumb: parentThumb1, fullsize: parentFullsize1)],
        )..remove('hasMedia');

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

      test('still requires mediaCount on a post that has valid images', () {
        final json = postJson(
          images: [imageJson(thumb: parentThumb1, fullsize: parentFullsize1)],
        )..remove('mediaCount');

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
