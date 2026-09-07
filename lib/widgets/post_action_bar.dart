import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/display_utils.dart';
import 'animated_vote_count.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/lucide_icon_painter.dart';
import 'icons/lucide_paths.dart';
import 'icons/reply_icon.dart';

/// Post Action Bar
///
/// Bottom bar with comment input, voting, bookmark, and comment count actions.
/// Displays:
/// - Comment input field (opens composer when tapped)
/// - Heart with vote count and bookmark control
/// - Comment bubble icon with comment count (scrolls to comments when tapped)
class PostActionBar extends StatelessWidget {
  const PostActionBar({
    required this.post,
    this.onCommentTap,
    this.onCommentInputTap,
    this.onCommentCountTap,
    this.onVoteTap,
    this.onSaveTap,
    this.isVoted = false,
    this.isSaved = false,
    this.isVotePending = false,
    super.key,
  });

  final FeedViewPost post;

  /// Deprecated: Use onCommentInputTap and onCommentCountTap instead
  final VoidCallback? onCommentTap;

  /// Callback when comment input field is tapped (typically opens composer)
  final VoidCallback? onCommentInputTap;

  /// Callback when comment count button is tapped (typically scrolls to
  /// comments)
  final VoidCallback? onCommentCountTap;

  final VoidCallback? onVoteTap;
  final VoidCallback? onSaveTap;
  final bool isVoted;
  final bool isSaved;
  final bool isVotePending;

  @override
  Widget build(BuildContext context) {
    final commentCount = post.post.stats.commentCount;
    final score = post.post.stats.score;
    final neutralColor = AppColors.textPrimary.withValues(alpha: 0.7);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.backgroundSecondary)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Comment input field
            Expanded(
              child: GestureDetector(
                onTap: onCommentInputTap ?? onCommentTap,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      LucideGlyph(
                        LucidePaths.pencilSparkles,
                        size: 16,
                        color: AppColors.textPrimary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      // This pill is the only child the outer Row can squeeze,
                      // so it is where a crowded action bar lands. The label
                      // yields rather than the counts beside it: it is a hint
                      // whose affordance the edit icon already carries, while
                      // a truncated number would be misinformation.
                      Flexible(
                        child: Text(
                          'Comment',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            Semantics(
              button: true,
              enabled: !isVotePending,
              label: isVoted ? 'Remove upvote' : 'Upvote post',
              value: 'Score $score',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isVotePending ? null : onVoteTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedHeartIcon(
                        isLiked: isVoted,
                        color: neutralColor,
                        likedColor: AppColors.voteLiked,
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      ExcludeSemantics(
                        child: AnimatedVoteCount(
                          count: score,
                          key: ValueKey('vote-count:${post.post.uri}'),
                          style: TextStyle(
                            color: isVoted ? AppColors.voteLiked : neutralColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            _ActionButton(
              iconWidget: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                size: 24,
              ),
              count: 0,
              color: isSaved ? AppColors.primary : null,
              semanticLabel: isSaved ? 'Unsave post' : 'Save post',
              onTap: onSaveTap,
            ),
            const SizedBox(width: 16),

            // Comment count button
            _ActionButton(
              iconWidget: const ReplyIcon(size: 22),
              count: commentCount,
              onTap: onCommentCountTap ?? onCommentTap,
              semanticLabel:
                  'View $commentCount '
                  '${commentCount == 1 ? "comment" : "comments"}',
            ),
          ],
        ),
      ),
    );
  }
}

/// Action button with icon and count
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.iconWidget,
    required this.count,
    this.color,
    this.onTap,
    this.semanticLabel,
  });

  final Widget iconWidget;
  final int count;
  final Color? color;
  final VoidCallback? onTap;

  /// Accessibility label announced by screen readers (the visual button is
  /// an icon plus a bare number, which is meaningless on its own).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? AppColors.textPrimary.withValues(alpha: 0.7);

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: effectiveColor),
              child: iconWidget,
            ),
            const SizedBox(width: 4),
            Text(
              DisplayUtils.formatCount(count),
              style: TextStyle(
                color: effectiveColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
