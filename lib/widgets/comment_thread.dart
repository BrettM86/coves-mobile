import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/comment.dart';
import 'comment_card.dart';

/// Comment thread widget for displaying comments and their nested replies
///
/// Recursively displays a ThreadViewComment and its replies:
/// - Renders the comment using CommentCard with optimistic voting
///   via VoteProvider
/// - Indents nested replies visually
/// - Limits nesting depth to prevent excessive indentation
/// - Shows "Load more replies" button when hasMore is true
/// - Supports tap-to-reply via [onCommentTap] callback
///
/// The [maxDepth] parameter controls how deeply nested comments can be
/// before they're rendered at the same level to prevent UI overflow.
class CommentThread extends StatelessWidget {
  const CommentThread({
    required this.thread,
    this.depth = 0,
    this.maxDepth = 5,
    this.currentTime,
    this.onLoadMoreReplies,
    this.onCommentTap,
    super.key,
  });

  final ThreadViewComment thread;
  final int depth;
  final int maxDepth;
  final DateTime? currentTime;
  final VoidCallback? onLoadMoreReplies;

  /// Callback when a comment is tapped (for reply functionality)
  final void Function(ThreadViewComment)? onCommentTap;

  @override
  Widget build(BuildContext context) {
    // Calculate effective depth (flatten after maxDepth)
    final effectiveDepth = depth > maxDepth ? maxDepth : depth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Render the comment with tap handler
        CommentCard(
          comment: thread.comment,
          depth: effectiveDepth,
          currentTime: currentTime,
          onTap: onCommentTap != null ? () => onCommentTap!(thread) : null,
        ),

        // Render replies recursively
        if (thread.replies != null && thread.replies!.isNotEmpty)
          ...thread.replies!.map(
            (reply) => CommentThread(
              thread: reply,
              depth: depth + 1,
              maxDepth: maxDepth,
              currentTime: currentTime,
              onLoadMoreReplies: onLoadMoreReplies,
              onCommentTap: onCommentTap,
            ),
          ),

        // Show "Load more replies" button if there are more
        if (thread.hasMore) _buildLoadMoreButton(context),
      ],
    );
  }

  /// Builds the "Load more replies" button
  Widget _buildLoadMoreButton(BuildContext context) {
    // Calculate left padding based on depth (align with replies)
    final effectiveDepth = depth > maxDepth ? maxDepth : depth;
    final leftPadding = 16.0 + ((effectiveDepth + 1) * 12.0);

    return Container(
      padding: EdgeInsets.fromLTRB(leftPadding, 8, 16, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: InkWell(
        onTap: () {
          if (onLoadMoreReplies != null) {
            onLoadMoreReplies!();
          } else {
            if (kDebugMode) {
              debugPrint('Load more replies tapped (no handler provided)');
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 16,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                'Load more replies',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
