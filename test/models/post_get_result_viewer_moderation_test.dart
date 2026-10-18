import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Literal moderatedPost item as served by the backend, plus [extra] keys.
Map<String, dynamic> _moderatedPostJson([
  Map<String, dynamic> extra = const {},
]) => <String, dynamic>{
  r'$type': 'social.coves.community.post.defs#moderatedPost',
  'uri': 'at://did:plc:author/social.coves.community.post/3abc',
  'moderation': <String, dynamic>{
    'state': 'removed',
    'sources': <dynamic>[
      <String, dynamic>{
        'authorityDid': 'did:web:coves.social',
        'scope': <String, dynamic>{'kind': 'instance'},
      },
    ],
  },
  ...extra,
};

/// Parses [json] as a tombstone, failing the test (rather than erroring) if
/// parsing throws or demotes the item.
PostGetModerated _parse(Map<String, dynamic> json) {
  late PostGetResult result;
  expect(
    () => result = PostGetResult.fromJson(json),
    returnsNormally,
    reason: 'PostGetResult.fromJson must not throw',
  );
  expect(result, isA<PostGetModerated>());
  return result as PostGetModerated;
}

void main() {
  group('PostGetModerated.viewerModeration', () {
    final restoreRows = <String, Map<String, dynamic>>{
      'viewer.moderation with an unknown token and saved': {
        'viewer': <String, dynamic>{
          'moderation': <dynamic>['restore', 'x'],
          'saved': true,
        },
      },
      'viewer.moderation beside a wrong-typed unrelated field': {
        'viewer': <String, dynamic>{
          'moderation': <dynamic>['restore'],
          'saved': 'ignored',
        },
      },
    };

    for (final MapEntry(key: name, value: extra) in restoreRows.entries) {
      test('B1 $name parses to {restore}', () {
        final moderated = _parse(_moderatedPostJson(extra));

        expect(moderated.viewerModeration, {ModerationCapability.restore});
      });
    }

    final emptyRows = <String, Map<String, dynamic>>{
      'no viewer': {},
      'viewer without moderation': {
        'viewer': <String, dynamic>{'saved': true},
      },
    };

    for (final MapEntry(key: name, value: extra) in emptyRows.entries) {
      test('B1 $name parses to no capabilities', () {
        final moderated = _parse(_moderatedPostJson(extra));

        expect(moderated.viewerModeration, isEmpty);
      });
    }
  });
}
