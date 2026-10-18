import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import '../../models/moderation_action.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/moderation_copy.dart';
import '../icons/lucide_icon_painter.dart';
import '../icons/lucide_paths.dart';

class ModlogEntryTile extends StatelessWidget {
  const ModlogEntryTile({
    required this.action,
    this.actorHandle,
    this.reversedAction,
    this.privateActorDid,
    this.privateNote,
    this.privateSubject,
    this.privateContentSnapshot,
    this.onRestore,
    this.restoring = false,
    this.communityHandle,
    this.now,
    super.key,
  });

  final ModerationActionView action;

  /// Handle of the row's actor: [privateActorDid] when set, otherwise the
  /// public actor.
  final String? actorHandle;
  final ModerationActionView? reversedAction;

  /// Admin-log only: the acting admin, which the public log may withhold.
  final String? privateActorDid;

  /// Admin-log only: the note the moderator kept off the public log.
  final String? privateNote;

  /// Admin-log only: the subject as the admin log records it. Shown when the
  /// row has no public subject, and the source of a comment's root post when
  /// the public subject withholds it.
  final ModerationSubjectRef? privateSubject;

  /// Admin-log only: the subject's content snapshot as the admin log records
  /// it. Previewed when the public snapshot has no text, and then tagged as
  /// text hidden from the public log.
  final ModerationContentSnapshot? privateContentSnapshot;

  /// Restores the row's removal; the row shows "Restore" only when set.
  final VoidCallback? onRestore;

  /// A restore of this row is in flight, so its "Restore" is disabled.
  final bool restoring;

  /// Display handle of the row's community, e.g. "!gaming@coves.social",
  /// shown in the subject box, also when the subject itself is withheld;
  /// the box omits the community line when null.
  final String? communityHandle;

  /// The current time for the row's relative time; [DateTime.now] when null.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final reason = moderationReasonLabel(action.reason);
    final privateNote = this.privateNote;
    final hiddenFromPublicLog =
        action.subject == null && privateSubject != null;
    final subject = action.subject ?? privateSubject;
    final publicPreview = _preview(action.contentSnapshot);
    final preview = publicPreview ?? _preview(privateContentSnapshot);
    final textHiddenFromPublicLog =
        action.subject != null && publicPreview == null && preview != null;
    final subjectKind = moderationSubjectKind(subject);
    final actorDid = privateActorDid ?? action.actorDid;
    final actorLabel = moderationActorLabel(actorDid, actorHandle);
    final predicate = moderationHeadlinePredicate(action.action, subjectKind);
    final (tint, glyph) = _actionAppearance(action.action);
    final textTheme = Theme.of(context).textTheme;
    final metaStyle = textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 18 / 13,
      color: AppColors.textMeta,
    );
    final onRestore = this.onRestore;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: LucideGlyph(glyph, size: 18, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 8,
                    children: [
                      Expanded(
                        child: _ActorHeadline(
                          actorLabel: actorLabel,
                          // Only an @handle names a profile to open.
                          profileDid: actorHandle != null ? actorDid : null,
                          predicate: predicate,
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 20 / 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        DateTimeUtils.formatTimeAgo(
                          action.createdAt,
                          currentTime: now,
                        ),
                        style: metaStyle,
                      ),
                    ],
                  ),
                ),
                _buildSubjectBox(
                  context,
                  subject,
                  subjectKind,
                  preview,
                  metaStyle,
                ),
                if (hiddenFromPublicLog || textHiddenFromPublicLog)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: _AdminOnlyLabel(
                        label: hiddenFromPublicLog
                            ? moderationHiddenFromPublicLogLabel
                            : moderationTextHiddenFromPublicLogLabel,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (privateNote != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 3,
                        children: [
                          const _AdminOnlyLabel(
                            label: moderationPrivateNoteLabel,
                            fontWeight: FontWeight.w600,
                          ),
                          Text(
                            privateNote,
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 20 / 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (reason != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundTertiary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    reason,
                                    style: textTheme.labelSmall?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              Text(
                                moderationScopeLabel(action.scope.kind),
                                style: metaStyle,
                              ),
                            ],
                          ),
                          // On its own line: beside the scope it wraps on a
                          // phone and leaves a separator dangling.
                          if (action.reverses != null)
                            Text(
                              moderationReversesLabel(
                                action.action,
                                reversedAction,
                              ),
                              style: metaStyle,
                            ),
                        ],
                      ),
                    ),
                    if (onRestore != null)
                      OutlinedButton.icon(
                        onPressed: restoring ? null : onRestore,
                        icon: LucideGlyph(
                          LucidePaths.rotateCcw,
                          size: 15,
                          color: restoring
                              ? AppColors.textMeta
                              : AppColors.textPrimary,
                        ),
                        label: const Text('Restore'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          backgroundColor: AppColors.insetSurface,
                          disabledForegroundColor: AppColors.textMeta,
                          side: const BorderSide(color: AppColors.border),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The boxed subject: [preview] of what it said, then its community and
  /// kind, tappable when the subject has a destination. Without a subject
  /// it says the content is not shown, above the community when known.
  Widget _buildSubjectBox(
    BuildContext context,
    ModerationSubjectRef? subject,
    ModerationSubjectKind subjectKind,
    String? preview,
    TextStyle? metaStyle,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.insetBorder),
    );
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final communityHandle = this.communityHandle;
    if (subject == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: AppColors.insetSurface,
          shape: shape,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  'Content not shown',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMeta,
                  ),
                ),
                if (communityHandle != null)
                  Text(
                    communityHandle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle?.copyWith(color: AppColors.communityName),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (preview != null)
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              height: 20 / 15,
              color: AppColors.textPrimary,
            ),
          ),
        Row(
          children: [
            if (communityHandle != null) ...[
              Flexible(
                child: Text(
                  communityHandle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle?.copyWith(color: AppColors.communityName),
                ),
              ),
              ExcludeSemantics(child: Text(' · ', style: metaStyle)),
            ],
            Text(moderationSubjectLabel(subjectKind), style: metaStyle),
          ],
        ),
      ],
    );
    final location = _subjectLocation(subject, subjectKind);
    final box = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
    if (location == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: AppColors.insetSurface,
          shape: shape,
        ),
        child: box,
      );
    }
    return Semantics(
      container: true,
      link: true,
      child: Material(
        color: AppColors.insetSurface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: () => context.push(location), child: box),
      ),
    );
  }

  /// The snapshot's title, else its text, else its link; null when it has
  /// none of them.
  static String? _preview(ModerationContentSnapshot? snapshot) {
    for (final candidate in [
      snapshot?.title,
      snapshot?.text,
      snapshot?.linkUrl,
    ]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  /// The tint and glyph of an action's icon circle.
  static (Color, List<String>) _actionAppearance(
    ModerationActionKind kind,
  ) => switch (kind) {
    ModerationActionKind.remove => (AppColors.error, LucidePaths.ban),
    ModerationActionKind.restore => (AppColors.success, LucidePaths.rotateCcw),
    ModerationActionKind.label => (AppColors.nsfwLabel, LucidePaths.eyeOff),
    ModerationActionKind.retractLabel => (AppColors.nsfwLabel, LucidePaths.eye),
    ModerationActionKind.unknown => (AppColors.textMeta, LucidePaths.ban),
  };

  /// Where tapping the subject goes: a post opens its thread, and a comment
  /// opens its root post's thread focused on the comment. Null when the
  /// subject is not a link.
  String? _subjectLocation(
    ModerationSubjectRef? subject,
    ModerationSubjectKind subjectKind,
  ) {
    if (subject == null) {
      return null;
    }
    switch (subjectKind) {
      case ModerationSubjectKind.post:
        return '/post/${Uri.encodeComponent(subject.uri)}';
      case ModerationSubjectKind.comment:
        final root = subject.rootUri ?? privateSubject?.rootUri;
        if (root == null ||
            moderationSubjectUriKind(root) != ModerationSubjectKind.post) {
          return null;
        }
        return '/post/${Uri.encodeComponent(root)}'
            '?comment=${Uri.encodeQueryComponent(subject.uri)}';
      case ModerationSubjectKind.item:
      case ModerationSubjectKind.hidden:
        return null;
    }
  }
}

/// The row's headline: [actorLabel] then [predicate]. When [profileDid] is
/// set the actor is drawn in the feed's handle color and opens that profile.
class _ActorHeadline extends StatefulWidget {
  const _ActorHeadline({
    required this.actorLabel,
    required this.profileDid,
    required this.predicate,
    required this.style,
  });

  final String actorLabel;
  final String? profileDid;
  final String predicate;
  final TextStyle? style;

  @override
  State<_ActorHeadline> createState() => _ActorHeadlineState();
}

class _ActorHeadlineState extends State<_ActorHeadline> {
  late final TapGestureRecognizer _profileTap = TapGestureRecognizer()
    ..onTap = _openProfile;

  void _openProfile() {
    final did = widget.profileDid;
    if (did != null) {
      context.push('/profile/$did');
    }
  }

  @override
  void dispose() {
    _profileTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMention = widget.profileDid != null;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: widget.actorLabel,
            style: TextStyle(
              color: isMention
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: isMention ? _profileTap : null,
          ),
          TextSpan(text: ' ${widget.predicate}'),
        ],
      ),
      style: widget.style,
    );
  }
}

/// Label of admin-only content on a row: a lock glyph and [label] in warm
/// coral.
class _AdminOnlyLabel extends StatelessWidget {
  const _AdminOnlyLabel({required this.label, required this.fontWeight});

  final String label;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      const LucideGlyph(
        LucidePaths.lock,
        size: 12,
        color: AppColors.coralLight,
      ),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: fontWeight,
            color: AppColors.coralLight,
          ),
        ),
      ),
    ],
  );
}
