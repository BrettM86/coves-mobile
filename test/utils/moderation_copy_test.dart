import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/utils/moderation_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B9 subject URIs outside the atproto grammar are not posts or '
      'comments', () {
    final rkey512 = 'a' * 512;
    final rkey513 = 'a' * 513;
    for (final (uri, expected) in [
      (
        'at://did:plc:author/social.coves.community.post/p1',
        ModerationSubjectKind.post,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/3kabc',
        ModerationSubjectKind.post,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/$rkey512',
        ModerationSubjectKind.post,
      ),
      (
        'at://did:plc:author/social.coves.community.comment/c1',
        ModerationSubjectKind.comment,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/p!1',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author:/social.coves.community.postv2/p1',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author%/social.coves.community.postv2/p1',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/.',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/..',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author/social.coves.community.postv2/$rkey513',
        ModerationSubjectKind.item,
      ),
      (
        'at://did:plc:author/social.coves.community.comment/..',
        ModerationSubjectKind.item,
      ),
    ]) {
      expect(moderationSubjectUriKind(uri), expected, reason: uri);
    }
  });

  test('Modlog redesign B2 the actor label is the handle, else a generic '
      'moderator or server admin, never the DID', () {
    for (final (actorDid, handle, expected) in [
      ('did:plc:nova', 'nova.coves.social', '@nova.coves.social'),
      ('did:plc:nova', null, 'A moderator'),
      (null, null, 'Server admin'),
    ]) {
      final label = moderationActorLabel(actorDid, handle);
      expect(label, expected, reason: '$actorDid / $handle');
      expect(label, isNot(contains('did:')), reason: '$actorDid / $handle');
    }
  });

  test('Modlog redesign B2 headlines read as one sentence per action and '
      'subject kind', () {
    for (final (kind, subjectKind, expected) in [
      (
        ModerationActionKind.remove,
        ModerationSubjectKind.post,
        '@a removed a post',
      ),
      (
        ModerationActionKind.remove,
        ModerationSubjectKind.comment,
        '@a removed a comment',
      ),
      (
        ModerationActionKind.restore,
        ModerationSubjectKind.post,
        '@a restored a post',
      ),
      (
        ModerationActionKind.restore,
        ModerationSubjectKind.comment,
        '@a restored a comment',
      ),
      (
        ModerationActionKind.label,
        ModerationSubjectKind.post,
        '@a marked a post NSFW',
      ),
      (
        ModerationActionKind.retractLabel,
        ModerationSubjectKind.post,
        '@a removed the NSFW label from a post',
      ),
      (
        ModerationActionKind.unknown,
        ModerationSubjectKind.post,
        '@a took a moderation action on a post',
      ),
      (
        ModerationActionKind.remove,
        ModerationSubjectKind.item,
        '@a removed an item',
      ),
      (
        ModerationActionKind.remove,
        ModerationSubjectKind.hidden,
        '@a removed content',
      ),
      (
        ModerationActionKind.restore,
        ModerationSubjectKind.hidden,
        '@a restored content',
      ),
    ]) {
      expect(
        moderationHeadline(kind, subjectKind, '@a'),
        expected,
        reason: '$kind / $subjectKind',
      );
    }
  });

  test('Modlog redesign B3 day headers name local calendar days relative to '
      'now', () {
    for (final (name, createdAt, now, expected) in [
      (
        'same day',
        DateTime(2026, 10, 15, 9),
        DateTime(2026, 10, 15, 12),
        'Today',
      ),
      (
        'previous day',
        DateTime(2026, 10, 14, 13),
        DateTime(2026, 10, 15, 12),
        'Yesterday',
      ),
      (
        'midnight boundary',
        DateTime(2026, 10, 14, 23, 59),
        DateTime(2026, 10, 15, 0, 1),
        'Yesterday',
      ),
      // The AppView sends UTC instants; the header names their local day.
      (
        'UTC instant early on the previous local day',
        DateTime(2026, 10, 14, 0, 1).toUtc(),
        DateTime(2026, 10, 15, 12),
        'Yesterday',
      ),
      (
        'UTC instant late on the previous local day',
        DateTime(2026, 10, 14, 23, 59).toUtc(),
        DateTime(2026, 10, 15, 12),
        'Yesterday',
      ),
      (
        'month and year rollover',
        DateTime(2026, 12, 31, 22),
        DateTime(2027, 1, 1, 0, 30),
        'Yesterday',
      ),
      (
        'earlier this year',
        DateTime(2026, 10, 12, 9),
        DateTime(2026, 10, 15, 12),
        'Oct 12',
      ),
      (
        'another year',
        DateTime(2025, 10, 12, 9),
        DateTime(2026, 10, 15, 12),
        'Oct 12, 2025',
      ),
    ]) {
      expect(moderationDayLabel(createdAt, now: now), expected, reason: name);
    }
  });
}
