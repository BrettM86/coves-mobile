import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B0 action refs compare by service DID and action ID', () {
    // Not const: canonicalized consts would be identical, hiding ==.
    // ignore: prefer_const_constructors
    final original = ModerationActionRef(
      serviceDid: 'did:web:coves.social',
      actionId: 'a1',
    );
    // Not const: canonicalized consts would be identical, hiding ==.
    // ignore: prefer_const_constructors
    final equal = ModerationActionRef(
      serviceDid: 'did:web:coves.social',
      actionId: 'a1',
    );
    const otherService = ModerationActionRef(
      serviceDid: 'did:web:another.social',
      actionId: 'a1',
    );
    const otherAction = ModerationActionRef(
      serviceDid: 'did:web:coves.social',
      actionId: 'a2',
    );

    // Construct the lookup key afresh so identity cannot satisfy the contract.
    final lookup = ModerationActionRef(
      serviceDid: equal.serviceDid,
      actionId: equal.actionId,
    );
    expect(original, equal);
    expect(original.hashCode, equal.hashCode);
    expect({original}.contains(lookup), isTrue);
    expect({original: 'found'}[lookup], 'found');
    expect(original, isNot(otherService));
    expect(original, isNot(otherAction));
  });

  test('B1 parses valid actions in order, skips malformed entries and '
      'preserves cursor', () {
    final page = ModerationActionPage.fromJson({
      'actions': [
        {
          'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
          'action': 'remove',
          'createdAt': '2026-10-01T12:00:00.000Z',
          'actor': {'did': 'did:plc:admin'},
          'subject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
            'communityDid': 'did:plc:community',
          },
          'reason': 'social.coves.moderation.defs#reasonSpam',
          'authorityDid': 'did:web:coves.social',
          'scope': {'kind': 'community', 'communityDid': 'did:plc:community'},
          'origin': 'local',
        },
        {
          'ref': {'serviceDid': 'did:web:coves.social'},
          'action': 'remove',
          'createdAt': '2026-10-01T12:01:00.000Z',
          'authorityDid': 'did:web:coves.social',
          'scope': {'kind': 'instance'},
          'origin': 'local',
        },
        {
          'ref': {'serviceDid': 'did:plc:other-service', 'actionId': 'b2'},
          'action': 'restore',
          'createdAt': '2026-10-02T09:30:00.000Z',
          'reverses': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
          'authorityDid': 'did:plc:other-authority',
          'scope': {'kind': 'instance'},
          'origin': 'federated',
        },
        {
          'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'bad'},
          'action': 'remove',
          'createdAt': 'not-a-date',
          'authorityDid': 'did:web:coves.social',
          'scope': {'kind': 'instance'},
          'origin': 'local',
        },
      ],
      'cursor': 'c2',
    });

    expect(page.actions, hasLength(2));
    final first = page.actions[0];
    expect(first.ref.serviceDid, 'did:web:coves.social');
    expect(first.ref.actionId, 'a1');
    expect(first.action, ModerationActionKind.remove);
    expect(first.createdAt, DateTime.utc(2026, 10, 1, 12));
    expect(first.actorDid, 'did:plc:admin');
    expect(
      first.subject?.uri,
      'at://did:plc:author/social.coves.community.post/p1',
    );
    expect(first.subject?.cid, 'bafy-post');
    expect(first.subject?.communityDid, 'did:plc:community');
    expect(first.reason, ModerationReason.spam);
    expect(first.authorityDid, 'did:web:coves.social');
    expect(first.scope.kind, ModerationScopeKind.community);
    expect(first.scope.communityDid, 'did:plc:community');
    expect(first.origin, 'local');

    final second = page.actions[1];
    expect(second.ref.serviceDid, 'did:plc:other-service');
    expect(second.ref.actionId, 'b2');
    expect(second.action, ModerationActionKind.restore);
    expect(second.createdAt, DateTime.utc(2026, 10, 2, 9, 30));
    expect(second.reverses?.serviceDid, 'did:web:coves.social');
    expect(second.reverses?.actionId, 'a1');
    expect(second.authorityDid, 'did:plc:other-authority');
    expect(second.scope.kind, ModerationScopeKind.instance);
    expect(second.scope.communityDid, isNull);
    expect(second.origin, 'federated');
    expect(page.cursor, 'c2');
    expect(ModerationActionPage.fromJson({'actions': []}).cursor, isNull);
  });

  test('B2 maps all fully-qualified moderation reason tokens', () {
    const cases = <String, ModerationReason>{
      'social.coves.moderation.defs#reasonSpam': ModerationReason.spam,
      'social.coves.moderation.defs#reasonHarassment':
          ModerationReason.harassment,
      'social.coves.moderation.defs#reasonDoxing': ModerationReason.doxing,
      'social.coves.moderation.defs#reasonIllegalContent':
          ModerationReason.illegalContent,
      'social.coves.moderation.defs#reasonRuleViolation':
          ModerationReason.ruleViolation,
      'social.coves.moderation.defs#reasonModeratorDiscretion':
          ModerationReason.moderatorDiscretion,
    };
    for (final entry in cases.entries) {
      final action = ModerationActionView.tryParse({
        'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'reason'},
        'action': 'remove',
        'createdAt': '2026-10-01T12:00:00.000Z',
        'reason': entry.key,
        'authorityDid': 'did:web:coves.social',
        'scope': {'kind': 'instance'},
        'origin': 'local',
      });
      expect(action?.reason, entry.value, reason: entry.key);
    }
  });

  test(
    'B2 keeps unknown action, reason and scope values and optional fields',
    () {
      final page = ModerationActionPage.fromJson({
        'actions': [
          {
            'ref': {
              'serviceDid': 'did:web:coves.social',
              'actionId': 'unknown',
            },
            'action': 'apply-removal',
            'createdAt': '2026-10-01T12:00:00.000Z',
            'reason': 'social.coves.moderation.defs#reasonSomethingNew',
            'authorityDid': 'did:web:coves.social',
            'scope': {'kind': 'galaxy'},
            'origin': 'local',
          },
          {
            'ref': {
              'serviceDid': 'did:web:coves.social',
              'actionId': 'restore',
            },
            'action': 'restore',
            'createdAt': '2026-10-01T12:01:00.000Z',
            'authorityDid': 'did:web:coves.social',
            'scope': {'kind': 'instance'},
            'origin': 'local',
          },
        ],
      });

      expect(page.actions, hasLength(2));
      expect(page.actions[0].action, ModerationActionKind.unknown);
      expect(page.actions[0].reason, ModerationReason.unknown);
      expect(page.actions[0].scope.kind, ModerationScopeKind.unknown);
      expect(page.actions[0].subject, isNull);
      expect(page.actions[1].action, ModerationActionKind.restore);
      expect(page.actions[1].reason, isNull);
    },
  );

  test('B6 every known reason round-trips its exact lexicon token', () {
    const tokens = {
      ModerationReason.spam: 'social.coves.moderation.defs#reasonSpam',
      ModerationReason.harassment:
          'social.coves.moderation.defs#reasonHarassment',
      ModerationReason.doxing: 'social.coves.moderation.defs#reasonDoxing',
      ModerationReason.illegalContent:
          'social.coves.moderation.defs#reasonIllegalContent',
      ModerationReason.ruleViolation:
          'social.coves.moderation.defs#reasonRuleViolation',
      ModerationReason.moderatorDiscretion:
          'social.coves.moderation.defs#reasonModeratorDiscretion',
    };
    expect(
      tokens.keys.toSet(),
      ModerationReason.values.toSet()..remove(ModerationReason.unknown),
    );
    expect(ModerationReason.unknown.wireToken, isNull);

    for (final MapEntry(key: reason, value: token) in tokens.entries) {
      expect(reason.wireToken, token, reason: '$reason');
      final parsed = ModerationActionView.tryParse({
        'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
        'action': 'remove',
        'createdAt': '2026-10-01T12:00:00.000Z',
        'authorityDid': 'did:web:coves.social',
        'scope': {'kind': 'instance'},
        'origin': 'local',
        'reason': reason.wireToken,
      });
      expect(parsed?.reason, reason, reason: token);
    }
  });

  test('B1 a comment subject keeps its optional root post URI from the public '
      'subject and the admin private subject', () {
    const commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
    const rootUri = 'at://did:plc:author/social.coves.community.post/p1';
    Map<String, dynamic> actionJson({Object? subject}) => {
      'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
      'action': 'remove',
      'createdAt': '2026-10-01T12:00:00.000Z',
      'authorityDid': 'did:web:coves.social',
      'scope': {'kind': 'instance'},
      'origin': 'local',
      'subject': ?subject,
    };
    ModerationSubjectRef? publicSubject(Map<String, dynamic> subject) =>
        ModerationActionPage.fromJson({
          'actions': [actionJson(subject: subject)],
        }).actions.single.subject;
    ModerationSubjectRef? privateSubject(Map<String, dynamic> subject) =>
        AdminModerationActionPage.fromJson({
          'actions': [
            {'action': actionJson(), 'privateSubject': subject},
          ],
        }).actions.single.privateSubject;

    final cases = [
      (
        'public subject with rootUri',
        publicSubject,
        {'uri': commentUri, 'rootUri': rootUri},
        rootUri,
      ),
      (
        'public subject without rootUri',
        publicSubject,
        {'uri': commentUri},
        null,
      ),
      (
        'public subject with non-string rootUri',
        publicSubject,
        {'uri': commentUri, 'rootUri': 5},
        null,
      ),
      (
        'admin privateSubject with rootUri',
        privateSubject,
        {'uri': commentUri, 'rootUri': rootUri},
        rootUri,
      ),
    ];
    for (final (name, parse, subjectJson, expectedRoot) in cases) {
      final subject = parse(subjectJson);
      expect(subject?.uri, commentUri, reason: name);
      expect(subject?.rootUri, expectedRoot, reason: name);
    }
  });

  test('Modlog redesign B1 content snapshots parse on public and admin rows; '
      'a malformed snapshot becomes null and malformed fields drop alone', () {
    Map<String, dynamic> actionJson({Object? contentSnapshot}) => {
      'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
      'action': 'remove',
      'createdAt': '2026-10-01T12:00:00.000Z',
      'authorityDid': 'did:web:coves.social',
      'scope': {'kind': 'instance'},
      'origin': 'local',
      'contentSnapshot': ?contentSnapshot,
    };
    (String, ModerationContentSnapshot?) parsePublic(Object snapshot) {
      final row = ModerationActionView.tryParse(
        actionJson(contentSnapshot: snapshot),
      );
      return (row == null ? 'rejected' : 'kept', row?.contentSnapshot);
    }

    (String, ModerationContentSnapshot?) parseAdmin(Object snapshot) {
      final row = AdminModerationActionView.tryParse({
        'action': actionJson(),
        'privateNote': 'See ticket 42.',
        'contentSnapshot': snapshot,
      });
      return (row == null ? 'rejected' : 'kept', row?.contentSnapshot);
    }

    (String?, String?, String?, String)? fields(
      ModerationContentSnapshot? snapshot,
    ) => snapshot == null
        ? null
        : (
            snapshot.title,
            snapshot.text,
            snapshot.linkUrl,
            snapshot.capturedCid,
          );

    final cases = <(String, Object, (String?, String?, String?, String)?)>[
      (
        'all fields',
        {
          'title': 'Free Steam keys',
          'text': 'DM me for a code',
          'linkUrl': 'https://example.com/keys',
          'capturedCid': 'bafy-snapshot',
        },
        (
          'Free Steam keys',
          'DM me for a code',
          'https://example.com/keys',
          'bafy-snapshot',
        ),
      ),
      (
        'only capturedCid',
        {'capturedCid': 'bafy-snapshot'},
        (null, null, null, 'bafy-snapshot'),
      ),
      (
        'non-string title dropped alone',
        {
          'title': 5,
          'text': 'DM me for a code',
          'linkUrl': 'https://example.com/keys',
          'capturedCid': 'bafy-snapshot',
        },
        (null, 'DM me for a code', 'https://example.com/keys', 'bafy-snapshot'),
      ),
      (
        'non-string text and linkUrl dropped alone',
        {
          'title': 'Free Steam keys',
          'text': ['DM me'],
          'linkUrl': {'href': 'https://example.com/keys'},
          'capturedCid': 'bafy-snapshot',
        },
        ('Free Steam keys', null, null, 'bafy-snapshot'),
      ),
      ('not an object', 'Free Steam keys', null),
      ('missing capturedCid', {'title': 'Free Steam keys'}, null),
      (
        'empty capturedCid',
        {'title': 'Free Steam keys', 'capturedCid': ''},
        null,
      ),
      (
        'non-string capturedCid',
        {'title': 'Free Steam keys', 'capturedCid': 7},
        null,
      ),
    ];
    for (final (name, snapshot, expected) in cases) {
      for (final (log, parse) in [
        ('public', parsePublic),
        ('admin', parseAdmin),
      ]) {
        final (outcome, parsed) = parse(snapshot);
        expect(outcome, 'kept', reason: '$log: $name');
        expect(fields(parsed), expected, reason: '$log: $name');
      }
    }
  });
}
