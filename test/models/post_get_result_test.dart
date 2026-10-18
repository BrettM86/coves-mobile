import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/3abc';

  /// Literal moderatedPost item as served by the backend.
  Map<String, dynamic> moderatedPostJson() => <String, dynamic>{
    r'$type': 'social.coves.community.post.defs#moderatedPost',
    'uri': postUri,
    'moderation': <String, dynamic>{
      'state': 'removed',
      'sources': <dynamic>[
        <String, dynamic>{
          'authorityDid': 'did:web:coves.social',
          'scope': <String, dynamic>{'kind': 'instance'},
        },
      ],
    },
    'authorDid': 'did:plc:author',
    'community': <String, dynamic>{
      'did': 'did:plc:comm',
      'handle': 'c-gaming.coves.social',
      'name': 'gaming',
    },
  };

  /// Parses [json], failing the test (rather than erroring) if it throws,
  /// so "never throws" is the asserted outcome of every row.
  PostGetResult parse(Map<String, dynamic> json) {
    late PostGetResult result;
    expect(
      () => result = PostGetResult.fromJson(json),
      returnsNormally,
      reason: 'PostGetResult.fromJson must not throw',
    );
    return result;
  }

  group('PostGetResult.fromJson moderatedPost', () {
    test('parses uri, moderation, authorDid and community', () {
      final result = parse(moderatedPostJson());

      expect(result, isA<PostGetModerated>());
      final moderated = result as PostGetModerated;
      expect(moderated.uri, postUri);
      expect(moderated.moderation.state, ModerationState.removed);
      expect(moderated.moderation.sources, hasLength(1));
      final source = moderated.moderation.sources.single;
      expect(source.authorityDid, 'did:web:coves.social');
      expect(source.scope.kind, ModerationScopeKind.instance);
      expect(moderated.authorDid, 'did:plc:author');
      expect(moderated.community?.did, 'did:plc:comm');
      expect(moderated.community?.name, 'gaming');
      expect(moderated.community?.handle, 'c-gaming.coves.social');
    });

    test('parses with only uri and moderation', () {
      final result = parse(<String, dynamic>{
        r'$type': 'social.coves.community.post.defs#moderatedPost',
        'uri': postUri,
        'moderation': <String, dynamic>{
          'state': 'removed',
          'sources': <dynamic>[
            <String, dynamic>{
              'authorityDid': 'did:web:coves.social',
              'scope': <String, dynamic>{'kind': 'instance'},
            },
          ],
        },
      });

      expect(result, isA<PostGetModerated>());
      final moderated = result as PostGetModerated;
      expect(moderated.uri, postUri);
      expect(moderated.moderation.state, ModerationState.removed);
      expect(moderated.authorDid, isNull);
      expect(moderated.community, isNull);
    });

    // Tolerance rows: open enums and unknown fields never throw and never
    // demote the item to not-found.
    final toleranceRows =
        <String, (Map<String, dynamic>, void Function(PostGetModerated))>{
          'unknown scope kind maps to unknown': (
            moderatedPostJson()
              ..['moderation'] = <String, dynamic>{
                'state': 'removed',
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:web:coves.social',
                    'scope': <String, dynamic>{'kind': 'galaxy'},
                  },
                ],
              },
            (moderated) {
              final source = moderated.moderation.sources.single;
              expect(source.authorityDid, 'did:web:coves.social');
              expect(source.scope.kind, ModerationScopeKind.unknown);
            },
          ),
          'source without a scope maps to unknown kind': (
            moderatedPostJson()
              ..['moderation'] = <String, dynamic>{
                'state': 'removed',
                'sources': <dynamic>[
                  <String, dynamic>{'authorityDid': 'did:web:coves.social'},
                ],
              },
            (moderated) {
              final source = moderated.moderation.sources.single;
              expect(source.authorityDid, 'did:web:coves.social');
              expect(source.scope.kind, ModerationScopeKind.unknown);
            },
          ),
          'unknown moderation state maps to unknown': (
            moderatedPostJson()
              ..['moderation'] = <String, dynamic>{
                'state': 'quarantined',
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:web:coves.social',
                    'scope': <String, dynamic>{'kind': 'instance'},
                  },
                ],
              },
            (moderated) {
              expect(moderated.moderation.state, ModerationState.unknown);
              expect(
                moderated.moderation.sources.single.scope.kind,
                ModerationScopeKind.instance,
              );
            },
          ),
          'unknown extra fields are ignored': (
            moderatedPostJson()
              ..['futureField'] = <String, dynamic>{'x': 1}
              ..['moderation'] = <String, dynamic>{
                'state': 'removed',
                'futureModerationField': 42,
                'sources': <dynamic>[
                  <String, dynamic>{
                    'authorityDid': 'did:web:coves.social',
                    'scope': <String, dynamic>{
                      'kind': 'community',
                      'communityDid': 'did:plc:comm',
                      'futureScopeField': true,
                    },
                    'action': <String, dynamic>{
                      'serviceDid': 'did:web:coves.social',
                      'actionId': 'a1',
                    },
                    'futureSourceField': 'y',
                  },
                ],
              },
            (moderated) {
              expect(moderated.uri, postUri);
              expect(moderated.moderation.state, ModerationState.removed);
              final source = moderated.moderation.sources.single;
              expect(source.scope.kind, ModerationScopeKind.community);
              expect(source.scope.communityDid, 'did:plc:comm');
              expect(moderated.community?.name, 'gaming');
            },
          ),
        };

    for (final MapEntry(key: name, value: (json, check))
        in toleranceRows.entries) {
      test('tolerance: $name', () {
        final result = parse(json);

        expect(result, isA<PostGetModerated>());
        check(result as PostGetModerated);
      });
    }
  });

  group('PostGetResult.fromJson removedPost (community removal)', () {
    final rows = <String, (Map<String, dynamic>, String?)>{
      'with a code': (
        <String, dynamic>{'uri': postUri, 'removed': true, 'code': 'spam'},
        'spam',
      ),
      'without a code': (
        <String, dynamic>{'uri': postUri, 'removed': true},
        null,
      ),
    };

    for (final MapEntry(key: name, value: (json, expectedCode))
        in rows.entries) {
      test('parses a community-removed result $name', () {
        final result = parse(json);

        expect(result, isA<PostGetCommunityRemoved>());
        final removed = result as PostGetCommunityRemoved;
        expect(removed.uri, postUri);
        expect(removed.code, expectedCode);
      });
    }
  });

  test('a moderatedPost whose community has a wrong-typed optional field '
      'parses with no community', () {
    final result = parse(
      moderatedPostJson()
        ..['community'] = <String, dynamic>{
          'did': 'did:plc:comm',
          'name': 'gaming',
          'handle': 42,
        },
    );

    expect(result, isA<PostGetModerated>());
    final moderated = result as PostGetModerated;
    expect(moderated.uri, postUri);
    expect(moderated.moderation.state, ModerationState.removed);
    expect(moderated.community, isNull);
  });

  group(r'PostGetResult.fromJson discriminates by $type alone', () {
    final rows = <String, Matcher>{
      'social.coves.community.post.defs#notFoundPost': isA<PostGetNotFound>(),
      'social.coves.community.post.defs#blockedPost': isA<PostGetBlocked>(),
      'social.coves.community.post.defs#removedPost':
          isA<PostGetCommunityRemoved>(),
    };

    for (final MapEntry(key: type, value: matcher) in rows.entries) {
      test(type, () {
        final result = parse(<String, dynamic>{r'$type': type, 'uri': postUri});

        expect(result, matcher);
        expect(result.uri, postUri);
      });
    }
  });

  test(r'an unrecognized $type is not found', () {
    final result = parse(<String, dynamic>{
      r'$type': 'social.coves.community.post.defs#somethingNew',
      'uri': postUri,
    });

    expect(result, isA<PostGetNotFound>());
    expect(result.uri, postUri);
  });
}
