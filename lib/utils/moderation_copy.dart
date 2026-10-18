import '../models/moderation.dart';
import '../models/moderation_action.dart';

enum ModerationSubjectKind { post, comment, item, hidden }

ModerationSubjectKind moderationSubjectKind(ModerationSubjectRef? subject) {
  if (subject == null) {
    return ModerationSubjectKind.hidden;
  }
  return moderationSubjectUriKind(subject.uri);
}

/// An AT-URI naming a record: a DID authority, a collection and a record key,
/// each within the atproto grammar. Group 1 is the collection, group 2 the
/// record key.
final RegExp _recordUriPattern = RegExp(
  '^at://did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]'
  r'/([^/?#]+)/([A-Za-z0-9._:~-]{1,512})$',
);

/// Kind of record an AT-URI names. Only a URI within the atproto grammar with
/// a DID authority and a post collection is [ModerationSubjectKind.post];
/// anything else, including a malformed value, is a comment or
/// [ModerationSubjectKind.item].
ModerationSubjectKind moderationSubjectUriKind(String uri) {
  final match = _recordUriPattern.firstMatch(uri);
  final recordKey = match?.group(2);
  if (match == null || recordKey == '.' || recordKey == '..') {
    return ModerationSubjectKind.item;
  }
  return switch (match.group(1)) {
    'social.coves.community.post' ||
    'social.coves.community.postv2' => ModerationSubjectKind.post,
    'social.coves.community.comment' => ModerationSubjectKind.comment,
    _ => ModerationSubjectKind.item,
  };
}

const String moderationPrivateNoteLabel = 'Private note';

/// Tag on an admin-log row whose subject the public log does not show.
const String moderationHiddenFromPublicLogLabel = 'Hidden from public log';

/// Tag on an admin-log row whose public subject is shown with text only the
/// admin log holds.
const String moderationTextHiddenFromPublicLogLabel =
    'Text hidden from public log';

String moderationSubjectLabel(ModerationSubjectKind kind) => switch (kind) {
  ModerationSubjectKind.post => 'Post',
  ModerationSubjectKind.comment => 'Comment',
  ModerationSubjectKind.item => 'Item',
  ModerationSubjectKind.hidden => 'Subject hidden',
};

String moderationScopeLabel(ModerationScopeKind kind) => switch (kind) {
  ModerationScopeKind.instance => 'Server',
  ModerationScopeKind.community => 'Community',
  ModerationScopeKind.unknown => 'Other scope',
};

/// Copy for a row that reverses an earlier action, keyed on the row's own
/// [kind]: a label retraction reverses an NSFW label, anything else a removal.
String moderationReversesLabel(
  ModerationActionKind kind,
  ModerationActionView? reversedAction,
) {
  if (kind == ModerationActionKind.retractLabel) {
    return 'Reverses an earlier NSFW label';
  }
  final reason = reversedAction?.action == ModerationActionKind.remove
      ? moderationReasonLabel(reversedAction?.reason)
      : null;
  return reason == null
      ? 'Reverses an earlier removal'
      : 'Reverses removal for $reason';
}

String? moderationReasonLabel(ModerationReason? reason) => switch (reason) {
  null => null,
  ModerationReason.spam => 'Spam',
  ModerationReason.harassment => 'Harassment',
  ModerationReason.doxing => 'Doxing',
  ModerationReason.illegalContent => 'Illegal content',
  ModerationReason.ruleViolation => 'Rule violation',
  ModerationReason.moderatorDiscretion => 'Moderator discretion',
  ModerationReason.unknown => 'Other reason',
};

/// Who took a modlog action: "@handle", "A moderator" when the actor's handle
/// is unresolved, or "Server admin" when the row names no actor.
String moderationActorLabel(String? actorDid, String? handle) {
  if (actorDid == null) {
    return 'Server admin';
  }
  return handle == null ? 'A moderator' : '@$handle';
}

/// One-sentence modlog headline, e.g. "@alice removed a post".
String moderationHeadline(
  ModerationActionKind kind,
  ModerationSubjectKind subjectKind,
  String actorLabel,
) => '$actorLabel ${moderationHeadlinePredicate(kind, subjectKind)}';

/// The headline after its actor, e.g. "removed a post".
String moderationHeadlinePredicate(
  ModerationActionKind kind,
  ModerationSubjectKind subjectKind,
) {
  final noun = switch (subjectKind) {
    ModerationSubjectKind.post => 'a post',
    ModerationSubjectKind.comment => 'a comment',
    ModerationSubjectKind.item => 'an item',
    ModerationSubjectKind.hidden => 'content',
  };
  return switch (kind) {
    ModerationActionKind.remove => 'removed $noun',
    ModerationActionKind.restore => 'restored $noun',
    ModerationActionKind.label => 'marked $noun NSFW',
    ModerationActionKind.retractLabel => 'removed the NSFW label from $noun',
    ModerationActionKind.unknown => 'took a moderation action on $noun',
  };
}

const List<String> _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Modlog day-header label for [createdAt] relative to [now], by local
/// calendar day: "Today", "Yesterday", "Oct 12", or "Oct 12, 2025".
String moderationDayLabel(DateTime createdAt, {required DateTime now}) {
  final created = createdAt.toLocal();
  final current = now.toLocal();
  if (isSameLocalDay(created, current)) {
    return 'Today';
  }
  if (isSameLocalDay(
    created,
    DateTime(current.year, current.month, current.day - 1),
  )) {
    return 'Yesterday';
  }
  final dayAndMonth =
      '${_monthAbbreviations[created.month - 1]} ${created.day}';
  return created.year == current.year
      ? dayAndMonth
      : '$dayAndMonth, ${created.year}';
}

/// Whether [a] and [b] fall on the same local calendar day.
bool isSameLocalDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}
