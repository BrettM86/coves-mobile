import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'B3 subject state parses refs, record states and rejects bad versions',
    () {
      final full = ModerationSubjectState.fromJson({
        'subject': 'at://did:plc:author/social.coves.community.post/p1',
        'version': 'v3',
        'moderation': {
          'state': 'removed',
          'contentLabels': [
            {'value': 'nsfw'},
          ],
        },
        'recordState': 'present',
        'currentSubject': {
          'uri': 'at://did:plc:author/social.coves.community.post/p1',
          'cid': 'bafy-post',
        },
        'localRemoval': {
          'serviceDid': 'did:web:coves.social',
          'actionId': 'a1',
        },
        'localLabels': [
          {
            'value': 'nsfw',
            'action': {'serviceDid': 'did:web:coves.social', 'actionId': 'a2'},
          },
          {'value': 'invalid-no-ref'},
        ],
      });
      expect(
        full.subject,
        'at://did:plc:author/social.coves.community.post/p1',
      );
      expect(full.version, 'v3');
      expect(full.moderation.state, ModerationState.removed);
      expect(full.moderation.contentLabels.single.value, 'nsfw');
      expect(full.recordState, ModerationRecordState.present);
      expect(
        full.currentSubject?.uri,
        'at://did:plc:author/social.coves.community.post/p1',
      );
      expect(full.currentSubject?.cid, 'bafy-post');
      expect(
        full.localRemoval,
        const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'a1',
        ),
      );
      expect(full.localLabels, hasLength(1));
      expect(full.localLabels.single.value, 'nsfw');
      expect(
        full.localLabels.single.action,
        const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'a2',
        ),
      );

      for (final (raw, expected) in [
        ('deleted', ModerationRecordState.deleted),
        ('unavailable', ModerationRecordState.unavailable),
        ('archived', ModerationRecordState.unknown),
      ]) {
        final state = ModerationSubjectState.fromJson({
          'subject': 'at://did:plc:author/social.coves.community.post/p1',
          'version': 'v3',
          'moderation': {'state': 'clear', 'contentLabels': []},
          'recordState': raw,
        });
        expect(state.recordState, expected, reason: raw);
        expect(state.currentSubject, isNull);
        expect(state.localRemoval, isNull);
        expect(state.localLabels, isEmpty);
      }

      for (final versionFields in [
        <String, Object>{},
        <String, Object>{'version': ''},
        <String, Object>{'version': 3},
      ]) {
        expect(
          () => ModerationSubjectState.fromJson({
            'subject': 'at://did:plc:author/social.coves.community.post/p1',
            ...versionFields,
            'moderation': {'state': 'clear', 'contentLabels': []},
            'recordState': 'present',
          }),
          throwsFormatException,
          reason: 'version fields: $versionFields',
        );
      }
    },
  );

  test(
    'B4 mutation result parses private action, omission and unknown outcome',
    () {
      final applied = ModerationMutationResult.fromJson({
        'outcome': 'applied',
        'state': {
          'subject': 'at://did:plc:author/social.coves.community.post/p1',
          'version': 'v4',
          'moderation': {
            'state': 'removed',
            'contentLabels': [
              {'value': 'nsfw'},
            ],
          },
          'recordState': 'present',
          'localRemoval': {
            'serviceDid': 'did:web:coves.social',
            'actionId': 'a1',
          },
        },
        'action': {
          'action': {
            'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
            'action': 'remove',
            'createdAt': '2026-10-01T12:00:00.000Z',
            'authorityDid': 'did:web:coves.social',
            'scope': {'kind': 'instance'},
            'origin': 'local',
          },
          'actorDid': 'did:plc:admin',
          'privateNote': 'Review note',
          'privateSubject': {
            'uri': 'at://did:plc:author/social.coves.community.post/p1',
            'cid': 'bafy-post',
            'communityDid': 'did:plc:community',
          },
        },
      });
      expect(applied.outcome, ModerationMutationOutcome.applied);
      expect(
        applied.state.localRemoval,
        const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'a1',
        ),
      );
      expect(applied.state.moderation.state, ModerationState.removed);
      expect(applied.state.moderation.sources, isEmpty);
      expect(applied.action?.actorDid, 'did:plc:admin');
      expect(applied.action?.privateNote, 'Review note');
      expect(
        applied.action?.privateSubject?.uri,
        'at://did:plc:author/social.coves.community.post/p1',
      );
      expect(applied.action?.privateSubject?.cid, 'bafy-post');
      expect(applied.action?.privateSubject?.communityDid, 'did:plc:community');
      expect(
        applied.action?.action.ref,
        const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'a1',
        ),
      );

      final withoutPrivateFields = ModerationMutationResult.fromJson({
        'outcome': 'applied',
        'state': {
          'subject': 'at://did:plc:author/social.coves.community.post/p1',
          'version': 'v5',
          'moderation': {'state': 'clear', 'contentLabels': []},
          'recordState': 'present',
        },
        'action': {
          'action': {
            'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a2'},
            'action': 'restore',
            'createdAt': '2026-10-01T12:00:00.000Z',
            'authorityDid': 'did:web:coves.social',
            'scope': {'kind': 'instance'},
            'origin': 'local',
          },
        },
      });
      expect(withoutPrivateFields.action, isNotNull);
      expect(withoutPrivateFields.action?.actorDid, isNull);
      expect(withoutPrivateFields.action?.privateNote, isNull);
      expect(withoutPrivateFields.action?.privateSubject, isNull);

      for (final (raw, expected) in [
        ('unchanged', ModerationMutationOutcome.unchanged),
        ('superseded', ModerationMutationOutcome.unknown),
      ]) {
        final result = ModerationMutationResult.fromJson({
          'outcome': raw,
          'state': {
            'subject': 'at://did:plc:author/social.coves.community.post/p1',
            'version': 'v5',
            'moderation': {'state': 'clear', 'contentLabels': []},
            'recordState': 'present',
          },
        });
        expect(result.outcome, expected, reason: raw);
        expect(result.action, isNull);
      }
    },
  );
}
