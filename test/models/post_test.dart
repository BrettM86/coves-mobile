import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PostView buildPostView({
    PostStats? stats,
    PostRecord? record,
    bool isDeleted = false,
    String? deletionReason,
    PostEmbed? embed,
    ViewerState? viewer,
  }) {
    return PostView(
      uri: 'at://did:plc:test/social.coves.community.post/123',
      cid: 'bafypostcid',
      rkey: '123',
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:05Z'),
      record: record,
      isDeleted: isDeleted,
      deletionReason: deletionReason,
      stats:
          stats ??
          PostStats(upvotes: 12, downvotes: 2, score: 10, commentCount: 3),
      embed: embed,
      viewer: viewer,
    );
  }

  group('PostStats.copyWith', () {
    test('should replace only the score', () {
      final stats = PostStats(
        upvotes: 12,
        downvotes: 2,
        score: 10,
        commentCount: 3,
      );

      final copy = stats.copyWith(score: 11);

      expect(copy.score, 11);
      expect(copy.upvotes, 12);
      expect(copy.downvotes, 2);
      expect(copy.commentCount, 3);
    });

    test('should return an equivalent copy when given no arguments', () {
      final stats = PostStats(
        upvotes: 12,
        downvotes: 2,
        score: 10,
        commentCount: 3,
      );

      final copy = stats.copyWith();

      expect(copy.upvotes, 12);
      expect(copy.downvotes, 2);
      expect(copy.score, 10);
      expect(copy.commentCount, 3);
    });

    test('should replace every field when all are provided', () {
      final copy = PostStats(
        upvotes: 1,
        downvotes: 1,
        score: 0,
        commentCount: 0,
      ).copyWith(upvotes: 5, downvotes: 3, score: 2, commentCount: 7);

      expect(copy.upvotes, 5);
      expect(copy.downvotes, 3);
      expect(copy.score, 2);
      expect(copy.commentCount, 7);
    });
  });

  group('PostView.copyWith', () {
    test(
      'should preserve viewer, record and embed when only stats is replaced',
      () {
        const record = PostRecord(title: 'Title', content: 'Body');
        final embed = PostEmbed.fromJson(<String, dynamic>{
          r'$type': EmbedTypes.externalView,
          'external': <String, dynamic>{'uri': 'https://example.com'},
        });
        final viewer = ViewerState(
          vote: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
          saved: true,
          savedUri: 'at://did:plc:test/social.coves.feed.save/789',
          tags: const ['spoiler'],
        );
        final post = buildPostView(
          record: record,
          embed: embed,
          viewer: viewer,
        );

        final copy = post.copyWith(stats: post.stats.copyWith(score: 11));

        // The field the caller changed.
        expect(copy.stats.score, 11);
        expect(copy.stats.upvotes, 12);

        // Everything the old field-by-field rebuild silently dropped.
        expect(copy.viewer, same(viewer));
        expect(copy.viewer?.vote, 'up');
        expect(copy.embed, same(embed));
        expect(copy.record, same(record));
        expect(copy.title, 'Title');
        expect(copy.text, 'Body');
        expect(copy.isDeleted, false);
        expect(copy.deletionReason, null);

        // And the identity/metadata fields.
        expect(copy.uri, post.uri);
        expect(copy.cid, post.cid);
        expect(copy.rkey, post.rkey);
        expect(copy.author, same(post.author));
        expect(copy.community, same(post.community));
        expect(copy.createdAt, post.createdAt);
        expect(copy.indexedAt, post.indexedAt);
      },
    );

    test('should preserve deletion state when only stats is replaced', () {
      final post = buildPostView(isDeleted: true, deletionReason: 'moderator');

      final copy = post.copyWith(stats: post.stats.copyWith(score: 0));

      expect(copy.isDeleted, true);
      expect(copy.deletionReason, 'moderator');
      expect(copy.record, null);
      expect(copy.stats.score, 0);
    });

    test('should replace each field it is given', () {
      final post = buildPostView();
      final newViewer = ViewerState(vote: 'down');
      final newStats = PostStats(
        upvotes: 0,
        downvotes: 1,
        score: -1,
        commentCount: 0,
      );

      final copy = post.copyWith(
        uri: 'at://did:plc:other/social.coves.community.post/999',
        cid: 'bafyother',
        rkey: '999',
        author: AuthorView(did: 'did:plc:other', handle: 'other.user'),
        community: CommunityRef(did: 'did:plc:other', name: 'othercove'),
        createdAt: DateTime.parse('2025-02-02T00:00:00Z'),
        indexedAt: DateTime.parse('2025-02-02T00:00:01Z'),
        record: const PostRecord(title: 'New', content: 'New body'),
        stats: newStats,
        viewer: newViewer,
      );

      expect(copy.uri, 'at://did:plc:other/social.coves.community.post/999');
      expect(copy.cid, 'bafyother');
      expect(copy.rkey, '999');
      expect(copy.author.handle, 'other.user');
      expect(copy.community.name, 'othercove');
      expect(copy.createdAt, DateTime.parse('2025-02-02T00:00:00Z'));
      expect(copy.indexedAt, DateTime.parse('2025-02-02T00:00:01Z'));
      expect(copy.title, 'New');
      expect(copy.stats, same(newStats));
      expect(copy.viewer, same(newViewer));
    });

    test('should return an equivalent copy when given no arguments', () {
      final viewer = ViewerState(vote: 'up');
      final post = buildPostView(
        record: const PostRecord(title: 'Title', content: 'Body'),
        viewer: viewer,
      );

      final copy = post.copyWith();

      expect(copy.uri, post.uri);
      expect(copy.stats, same(post.stats));
      expect(copy.viewer, same(viewer));
      expect(copy.record, same(post.record));
    });
  });

  group('FeedViewPost.copyWith', () {
    test('should preserve the reason when only the post is replaced', () {
      final reason = FeedReason.fromJson(<String, dynamic>{
        r'$type': 'social.coves.feed.defs#reasonRepost',
      });
      final feedItem = FeedViewPost(
        post: buildPostView(viewer: ViewerState(vote: 'up')),
        reason: reason,
      );

      final copy = feedItem.copyWith(
        post: feedItem.post.copyWith(
          stats: feedItem.post.stats.copyWith(score: 11),
        ),
      );

      expect(copy.post.stats.score, 11);
      expect(copy.post.viewer?.vote, 'up');
      expect(copy.reason, same(reason));
    });

    test('should replace the reason when it is given', () {
      final feedItem = FeedViewPost(post: buildPostView());
      final reason = FeedReason.fromJson(<String, dynamic>{
        r'$type': 'social.coves.feed.defs#reasonRepost',
      });

      final copy = feedItem.copyWith(reason: reason);

      expect(copy.reason, same(reason));
      expect(copy.post, same(feedItem.post));
    });
  });

  group('EmbedSource.fromJson url policy', () {
    // A megathread source uri is rendered as a tappable outbound link, so it
    // must satisfy the same allowlist the rest of the app enforces: an
    // http/https scheme AND a non-empty host. A scheme-only uri carries an
    // allowed scheme with no authority at all and must be rejected too.
    test('accepts an http(s) uri with a host', () {
      final source = EmbedSource.fromJson({
        'uri': 'https://example.com/article',
        'title': 'Article',
        'domain': 'example.com',
      });

      expect(source.uri, 'https://example.com/article');
      expect(source.title, 'Article');
      expect(source.domain, 'example.com');
    });

    test('accepts an uppercase scheme', () {
      expect(
        EmbedSource.fromJson({'uri': 'HTTPS://example.com'}).uri,
        'HTTPS://example.com',
      );
    });

    test('rejects a disallowed scheme', () {
      for (final uri in const [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,<h1>x</h1>',
        'content://media/external/images/1',
        'httpx://evil.com',
      ]) {
        expect(
          () => EmbedSource.fromJson({'uri': uri}),
          throwsA(isA<FormatException>()),
          reason: uri,
        );
      }
    });

    test('rejects an allowed scheme with no host', () {
      for (final uri in const ['https:///nohost', 'http:foo', 'http://']) {
        expect(
          () => EmbedSource.fromJson({'uri': uri}),
          throwsA(isA<FormatException>()),
          reason: uri,
        );
      }
    });

    test('rejects a missing or empty uri', () {
      expect(
        () => EmbedSource.fromJson(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => EmbedSource.fromJson({'uri': ''}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => EmbedSource.fromJson({'uri': 42}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
