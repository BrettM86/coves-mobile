import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/bluesky_title_fixtures.dart';

void main() {
  PostView buildPostView({
    PostStats? stats,
    PostRecord? record,
    bool isDeleted = false,
    String? deletionReason,
    PostEmbed? embed,
    ViewerState? viewer,
    ModerationView? moderation,
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
      moderation: moderation,
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

    test('should preserve moderation and isSensitive when only stats is '
        'replaced', () {
      const moderation = ModerationView(
        state: ModerationState.clear,
        contentLabels: [
          ContentLabelView(
            value: 'nsfw',
            sources: [
              ModerationSource(
                authorityDid: 'did:web:coves.social',
                scope: ModerationScope(kind: ModerationScopeKind.instance),
              ),
            ],
          ),
        ],
      );
      final post = buildPostView(
        record: const PostRecord(title: 'Title', content: 'Body'),
        moderation: moderation,
      );

      final copy = post.copyWith(stats: post.stats.copyWith(score: 11));

      expect(copy.stats.score, 11);
      expect(copy.moderation, same(moderation));
      expect(copy.isSensitive, isTrue);
    });

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

  group('CommunityRef.fromJson', () {
    test('parses the optional origin field', () {
      final ref = CommunityRef.fromJson({
        'did': 'did:plc:community',
        'name': 'comicstrips',
        'handle': 'comicstrips.lemmy-world.tdpl.io',
        'origin': 'lemmy.world',
      });
      expect(ref.name, 'comicstrips');
      expect(ref.handle, 'comicstrips.lemmy-world.tdpl.io');
      expect(ref.origin, 'lemmy.world');
    });

    test('leaves origin null when the appview omits it', () {
      final ref = CommunityRef.fromJson({
        'did': 'did:plc:community',
        'name': 'testcove',
      });
      expect(ref.origin, null);
      expect(ref.handle, null);
    });

    test('ignores a non-string origin instead of failing the parse', () {
      final ref = CommunityRef.fromJson({
        'did': 'did:plc:community',
        'name': 'testcove',
        'origin': {'platform': 'lemmy'},
      });
      expect(ref.origin, null);
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

  group('PostView.isSensitive', () {
    // The appview serves self-labels inside the record, so every case here
    // goes through PostView.fromJson rather than a hand-built PostRecord:
    // a throw in label parsing would make TimelineResponse.fromJson drop the
    // post entirely, and only the json path can catch that.
    Map<String, dynamic> postJson({
      Map<String, dynamic>? record,
      bool isDeleted = false,
      Object? moderation,
    }) {
      return <String, dynamic>{
        'uri': 'at://did:plc:test/social.coves.community.post/123',
        'cid': 'bafypostcid',
        'rkey': '123',
        'author': <String, dynamic>{
          'did': 'did:plc:author',
          'handle': 'test.user',
        },
        'community': <String, dynamic>{
          'did': 'did:plc:community',
          'name': 'testcove',
        },
        'createdAt': '2025-01-01T12:00:00Z',
        'indexedAt': '2025-01-01T12:00:05Z',
        'record': ?record,
        'isDeleted': isDeleted,
        'moderation': ?moderation,
        'stats': <String, dynamic>{
          'upvotes': 0,
          'downvotes': 0,
          'score': 0,
          'commentCount': 0,
        },
      };
    }

    PostView parseWithLabels(Object? labels) {
      return PostView.fromJson(
        postJson(
          record: <String, dynamic>{
            'title': 'Title',
            'content': 'Body',
            'labels': labels,
          },
        ),
      );
    }

    Map<String, dynamic> selfLabels(List<dynamic> values, {String? type}) {
      return <String, dynamic>{r'$type': ?type, 'values': values};
    }

    test('a bare nsfw self-label marks the post sensitive', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'nsfw'},
        ]),
      );

      expect(post.isSensitive, isTrue);
      expect(post.record!.labels, contains('nsfw'));
    });

    test('the labels object may carry its lexicon type', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'nsfw'},
        ], type: 'com.atproto.label.defs#selfLabels'),
      );

      expect(post.isSensitive, isTrue);
    });

    test('nsfw is found among malformed and unrelated entries', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          null,
          <String, dynamic>{},
          'junk',
          <String, dynamic>{'val': 'other'},
          <String, dynamic>{'val': 'nsfw'},
        ]),
      );

      expect(post.isSensitive, isTrue);
      expect(post.record!.labels, contains('nsfw'));
    });

    test('an explicit neg:false still counts as an active label', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'nsfw', 'neg': false},
        ]),
      );

      expect(post.isSensitive, isTrue);
    });

    test('a record without a labels field is not sensitive', () {
      final post = PostView.fromJson(
        postJson(
          record: <String, dynamic>{'title': 'Title', 'content': 'Body'},
        ),
      );

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('a null labels field is not sensitive', () {
      final post = parseWithLabels(null);

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('an unrelated label is kept but is not sensitive', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'other'},
        ]),
      );

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, <String>['other']);
    });

    test('a negated nsfw label is dropped', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'nsfw', 'neg': true},
        ]),
      );

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('an explicit neg:null drops the label rather than guessing', () {
      // A present `neg` that is not the boolean false is not the value the
      // lexicon specifies, so it cannot be read as "not negated". The web
      // client treats this entry as inactive; a post is only concealed on
      // both clients if they agree.
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 'nsfw', 'neg': null},
        ]),
      );

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('a non-boolean neg drops the label rather than guessing', () {
      // 'false' and 'true' are both strings: neither is the boolean the
      // lexicon specifies, so neither may be interpreted.
      for (final neg in const ['false', 'true']) {
        final post = parseWithLabels(
          selfLabels(<dynamic>[
            <String, dynamic>{'val': 'nsfw', 'neg': neg},
          ]),
        );

        expect(post.isSensitive, isFalse, reason: 'neg: $neg');
        expect(post.record!.labels, isEmpty, reason: 'neg: $neg');
      }
    });

    test('a string labels field is ignored', () {
      final post = parseWithLabels('nsfw');

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('a non-list values field is ignored', () {
      final post = parseWithLabels(<String, dynamic>{'values': 'nsfw'});

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('an entry without a val is ignored', () {
      final post = parseWithLabels(selfLabels(<dynamic>[<String, dynamic>{}]));

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    test('a non-string val is ignored', () {
      final post = parseWithLabels(
        selfLabels(<dynamic>[
          <String, dynamic>{'val': 42},
        ]),
      );

      expect(post.isSensitive, isFalse);
      expect(post.record!.labels, isEmpty);
    });

    group('server moderation content labels', () {
      // Moderator labels arrive on postView.moderation, never in the record.
      const plainRecord = <String, dynamic>{
        'title': 'Title',
        'content': 'Body',
      };
      final rows = <String, (Object?, bool)>{
        'an instance nsfw label marks the post sensitive': (
          <String, dynamic>{
            'state': 'clear',
            'contentLabels': <dynamic>[
              <String, dynamic>{
                'value': 'nsfw',
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:web:coves.social',
                    'scope': <String, dynamic>{'kind': 'instance'},
                  },
                ],
              },
            ],
          },
          true,
        ),
        'a community nsfw label with truncated sources marks it sensitive': (
          <String, dynamic>{
            'state': 'clear',
            'contentLabels': <dynamic>[
              <String, dynamic>{
                'value': 'nsfw',
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:plc:comm',
                    'scope': <String, dynamic>{
                      'kind': 'community',
                      'communityDid': 'did:plc:comm',
                    },
                  },
                ],
                'sourcesTruncated': true,
              },
            ],
          },
          true,
        ),
        'a non-nsfw moderator label is not sensitive': (
          <String, dynamic>{
            'state': 'clear',
            'contentLabels': <dynamic>[
              <String, dynamic>{
                'value': 'spoiler',
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:web:coves.social',
                    'scope': <String, dynamic>{'kind': 'instance'},
                  },
                ],
              },
            ],
          },
          false,
        ),
        'malformed source and label entries are skipped and a valid nsfw '
            'label still marks it sensitive': (
          <String, dynamic>{
            'state': 'clear',
            'sources': <dynamic>[
              <String, dynamic>{
                'scope': <String, dynamic>{'kind': 'instance'},
              },
              'x',
            ],
            'contentLabels': <dynamic>[
              <String, dynamic>{'sources': <dynamic>[]},
              'y',
              <String, dynamic>{'value': 'nsfw'},
            ],
          },
          true,
        ),
        'a malformed moderation field parses and is not sensitive': (
          <String, dynamic>{'state': 42, 'contentLabels': 'nsfw'},
          false,
        ),
      };

      for (final MapEntry(key: name, value: (moderation, sensitive))
          in rows.entries) {
        test(name, () {
          late PostView post;
          expect(
            () => post = PostView.fromJson(
              postJson(record: plainRecord, moderation: moderation),
            ),
            returnsNormally,
          );

          expect(post.isSensitive, sensitive);
        });
      }
    });

    test('a deleted post with no record is not sensitive', () {
      final post = PostView.fromJson(postJson(isDeleted: true));

      expect(post.record, isNull);
      expect(post.isSensitive, isFalse);
    });

    test('PostRecord.fromJson never throws on a malformed labels field', () {
      // TimelineResponse.fromJson skips any feed item whose parse throws, so
      // a hostile labels field must degrade to no labels, never cost the
      // reader the post.
      const malformed = <Object?>[
        null,
        42,
        'nsfw',
        <Object?>[],
        <String, dynamic>{},
        <String, dynamic>{'values': null},
        <String, dynamic>{'values': 'nsfw'},
        <String, dynamic>{'values': 42},
        <String, dynamic>{
          'values': <Object?>[null, 'junk', 42],
        },
        <String, dynamic>{
          'values': <Object?>[<String, dynamic>{}],
        },
        <String, dynamic>{
          'values': <Object?>[
            <String, dynamic>{'val': 42},
          ],
        },
        <String, dynamic>{
          'values': <Object?>[
            <String, dynamic>{'val': 'nsfw', 'neg': 'true'},
          ],
        },
      ];

      for (final labels in malformed) {
        expect(
          () => PostRecord.fromJson(<String, dynamic>{'labels': labels}),
          returnsNormally,
          reason: 'labels: $labels',
        );
      }
    });
  });

  group('PostView.titleDuplicatesBlueskyEmbed', () {
    PostView sharePost({String? title, PostEmbed? embed}) {
      return buildPostView(
        record: PostRecord(title: title, content: ''),
        embed: embed,
      );
    }

    test('is true when the title equals the quoted post text', () {
      final post = sharePost(
        title: 'Hello world',
        embed: blueskyQuoteEmbed(text: 'Hello world'),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isTrue);
    });

    test('is true when only whitespace differs', () {
      final post = sharePost(
        title: 'Hello  world',
        embed: blueskyQuoteEmbed(text: '  Hello\n\nworld \n'),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isTrue);
    });

    test('is false when the title differs from the quoted post text', () {
      final post = sharePost(
        title: 'My take on this',
        embed: blueskyQuoteEmbed(text: 'Hello world'),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false when only letter case differs', () {
      final post = sharePost(
        title: 'Hello World',
        embed: blueskyQuoteEmbed(text: 'hello world'),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test(
      'is false when the title is only a prefix of the quoted post text',
      () {
        final post = sharePost(
          title: 'Shipping the new release',
          embed: blueskyQuoteEmbed(text: 'Shipping the new release today'),
        );

        expect(post.titleDuplicatesBlueskyEmbed, isFalse);
      },
    );

    test('is false for a post without a title', () {
      final post = sharePost(embed: blueskyQuoteEmbed(text: 'Hello world'));

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false for an empty title over an empty quoted post', () {
      final post = sharePost(
        title: '',
        embed: blueskyQuoteEmbed(text: ''),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false for a post without an embed', () {
      final post = sharePost(title: 'Hello world');

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false for a link embed', () {
      final post = sharePost(
        title: 'Hello world',
        embed: PostEmbed.fromJson(<String, dynamic>{
          r'$type': EmbedTypes.externalView,
          'external': <String, dynamic>{
            'uri': 'https://example.com',
            'title': 'Hello world',
            'description': 'Hello world',
          },
        }),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false when the quoted post was not resolved', () {
      final post = sharePost(title: 'Hello world', embed: blueskyQuoteEmbed());

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('is false when the quoted post is unavailable', () {
      final post = sharePost(
        title: 'Hello world',
        embed: blueskyQuoteEmbed(text: 'Hello world', unavailable: true),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isFalse);
    });

    test('leaves the title itself unchanged', () {
      final post = sharePost(
        title: 'Hello  world',
        embed: blueskyQuoteEmbed(text: 'Hello world'),
      );

      expect(post.titleDuplicatesBlueskyEmbed, isTrue);
      expect(post.title, 'Hello  world');
    });
  });
}
