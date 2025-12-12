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
/// - Supports long-press to collapse threads via [onCollapseToggle] callback
///
/// The [maxDepth] parameter controls how deeply nested comments can be
/// before they're rendered at the same level to prevent UI overflow.
///
/// When a comment is collapsed (via [collapsedComments]), its replies are
/// hidden with a smooth animation and a badge shows the hidden count.
class CommentThread extends StatelessWidget {
  const CommentThread({
    required this.thread,
    this.depth = 0,
    this.maxDepth = 5,
    this.currentTime,
    this.onLoadMoreReplies,
    this.onCommentTap,
    this.collapsedComments = const {},
    this.onCollapseToggle,
    super.key,
  });

  final ThreadViewComment thread;
  final int depth;
  final int maxDepth;
  final DateTime? currentTime;
  final VoidCallback? onLoadMoreReplies;

  /// Callback when a comment is tapped (for reply functionality)
  final void Function(ThreadViewComment)? onCommentTap;

  /// Set of collapsed comment URIs
  final Set<String> collapsedComments;

  /// Callback when a comment collapse state is toggled
  final void Function(String uri)? onCollapseToggle;

  /// Count all descendants recursively
  static int countDescendants(ThreadViewComment thread) {
    if (thread.replies == null || thread.replies!.isEmpty) {
      return 0;
    }
    var count = thread.replies!.length;
    for (final reply in thread.replies!) {
      count += countDescendants(reply);
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate effective depth (flatten after maxDepth)
    final effectiveDepth = depth > maxDepth ? maxDepth : depth;

    // Check if this comment is collapsed
    final isCollapsed = collapsedComments.contains(thread.comment.uri);
    final collapsedCount = isCollapsed ? countDescendants(thread) : 0;

    // Check if there are replies to render
    final hasReplies = thread.replies != null && thread.replies!.isNotEmpty;

    // Only build replies widget when NOT collapsed (optimization)
    // When collapsed, AnimatedSwitcher shows SizedBox.shrink() so children
    // are never mounted - no need to build them at all
    final repliesWidget =
        hasReplies && !isCollapsed
            ? Column(
              key: const ValueKey('replies'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  thread.replies!.map((reply) {
                    return CommentThread(
                      thread: reply,
                      depth: depth + 1,
                      maxDepth: maxDepth,
                      currentTime: currentTime,
                      onLoadMoreReplies: onLoadMoreReplies,
                      onCommentTap: onCommentTap,
                      collapsedComments: collapsedComments,
                      onCollapseToggle: onCollapseToggle,
                    );
                  }).toList(),
            )
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Render the comment with tap and long-press handlers
        CommentCard(
          comment: thread.comment,
          depth: effectiveDepth,
          currentTime: currentTime,
          onTap: onCommentTap != null ? () => onCommentTap!(thread) : null,
          onLongPress:
              onCollapseToggle != null
                  ? () => onCollapseToggle!(thread.comment.uri)
                  : null,
          isCollapsed: isCollapsed,
          collapsedCount: collapsedCount,
        ),

        // Render replies with animation
        if (hasReplies)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            reverseDuration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              // Determine if we're expanding or collapsing based on key
              final isExpanding = child.key == const ValueKey('replies');

              // Different fade curves for expand vs collapse
              final fadeCurve =
                  isExpanding
                      ? const Interval(0, 0.7, curve: Curves.easeOut)
                      : const Interval(0, 0.5, curve: Curves.easeIn);

              // Slide down from parent on expand, slide up on collapse
              final slideOffset =
                  isExpanding
                      ? Tween<Offset>(
                        begin: const Offset(0, -0.15),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: const Interval(
                            0.2,
                            1,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      )
                      : Tween<Offset>(
                        begin: Offset.zero,
                        end: const Offset(0, -0.05),
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeIn,
                        ),
                      );

              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: fadeCurve),
                child: ClipRect(
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: SlideTransition(position: slideOffset, child: child),
                  ),
                ),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              // Stack children during transition - ClipRect prevents
              // overflow artifacts on deeply nested threads
              return ClipRect(
                child: Stack(
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
              );
            },
            child:
                isCollapsed
                    ? const SizedBox.shrink(key: ValueKey('collapsed'))
                    : repliesWidget,
          ),

        // Show "Load more replies" button if there are more (and not collapsed)
        if (thread.hasMore && !isCollapsed) _buildLoadMoreButton(context),
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
