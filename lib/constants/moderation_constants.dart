import '../models/moderation_action.dart';

/// The reasons an admin can give for removing a post or a comment, in the
/// order the removal sheet lists them.
const List<ModerationReason> removalReasons = [
  ModerationReason.spam,
  ModerationReason.harassment,
  ModerationReason.doxing,
  ModerationReason.illegalContent,
  ModerationReason.ruleViolation,
  ModerationReason.moderatorDiscretion,
];

/// The optional reasons an admin can give for marking a post NSFW or
/// removing its NSFW label, in the order the NSFW sheets list them.
const List<ModerationReason> labelReasons = [
  ModerationReason.spam,
  ModerationReason.harassment,
  ModerationReason.ruleViolation,
  ModerationReason.moderatorDiscretion,
];

/// The reasons an admin can give for restoring a removed post, in the order
/// the restore sheet lists them.
const List<ModerationReason> restoreReasons = [
  ModerationReason.spam,
  ModerationReason.harassment,
  ModerationReason.ruleViolation,
  ModerationReason.moderatorDiscretion,
];

/// Longest private note a moderation action accepts, in grapheme clusters.
const int privateNoteMaxGraphemes = 1000;

/// Longest private note a moderation action accepts, in UTF-8 bytes.
const int privateNoteMaxBytes = 10000;

/// The content label value an admin applies or retracts with the NSFW tools.
const String nsfwLabelValue = 'nsfw';
