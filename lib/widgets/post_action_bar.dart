import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';

/// Post Action Bar
///
/// Bottom bar with comment input and action buttons (vote, save,
/// comment count).
/// Displays:
/// - Comment input field
/// - Heart icon with vote count
/// - Star icon with save count
/// - Comment bubble icon with comment count
class PostActionBar extends StatelessWidget {
  const PostActionBar({
    required this.post,
    this.onCommentTap,
    this.onVoteTap,
    this.onSaveTap,
    this.isVoted = false,
    this.isSaved = false,
    super.key,
  });

  final FeedViewPost post;
  final VoidCallback? onCommentTap;
  final VoidCallback? onVoteTap;
  final VoidCallback? onSaveTap;
  final bool isVoted;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.backgroundSecondary),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Comment input field
            Expanded(
              child: GestureDetector(
                onTap: onCommentTap,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppColors.textPrimary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Comment',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Vote button with animated heart icon
            GestureDetector(
              onTap: onVoteTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedHeartIcon(
                    isLiked: isVoted,
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    likedColor: const Color(0xFFFF0033),
                    size: 24,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateTimeUtils.formatCount(post.post.stats.score),
                    style: TextStyle(
                      color:
                          isVoted
                              ? const Color(0xFFFF0033)
                              : AppColors.textPrimary.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Save button with count (placeholder for now)
            _ActionButton(
              icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
              count: 0, // TODO: Add save count when backend supports it
              color: isSaved ? AppColors.primary : null,
              onTap: onSaveTap,
            ),
            const SizedBox(width: 16),

            // Comment count button
            _ActionButton(
              icon: Icons.chat_bubble_outline,
              count: post.post.stats.commentCount,
              onTap: onCommentTap,
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
    required this.icon,
    required this.count,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? AppColors.textPrimary.withValues(alpha: 0.7);

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: effectiveColor),
          const SizedBox(width: 4),
          Text(
            DateTimeUtils.formatCount(count),
            style: TextStyle(
              color: effectiveColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
