import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../constants/threading_colors.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/vote_provider.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'sign_in_dialog.dart';

/// Comment card widget for displaying individual comments
///
/// Displays a comment with:
/// - Author information (avatar, handle, timestamp)
/// - Comment content (supports facets for links/mentions)
/// - Heart vote button with optimistic updates via VoteProvider
/// - Visual threading indicator based on nesting depth
/// - Tap-to-reply functionality via [onTap] callback
/// - Long-press to collapse thread via [onLongPress] callback
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling periodic updates and testing.
///
/// When [isCollapsed] is true, displays a badge showing [collapsedCount]
/// hidden replies on the threading indicator bar.
class CommentCard extends StatelessWidget {
  const CommentCard({
    required this.comment,
    this.depth = 0,
    this.currentTime,
    this.onTap,
    this.onLongPress,
    this.isCollapsed = false,
    this.collapsedCount = 0,
    super.key,
  });

  final CommentView comment;
  final int depth;
  final DateTime? currentTime;

  /// Callback when the comment is tapped (for reply functionality)
  final VoidCallback? onTap;

  /// Callback when the comment is long-pressed (for collapse functionality)
  final VoidCallback? onLongPress;

  /// Whether this comment's thread is currently collapsed
  final bool isCollapsed;

  /// Number of replies hidden when collapsed
  final int collapsedCount;

  @override
  Widget build(BuildContext context) {
    // All comments get at least 1 threading line (depth + 1)
    final threadingLineCount = depth + 1;
    // Calculate left padding: (6px per line) + 14px base padding
    final leftPadding = (threadingLineCount * 6.0) + 14.0;
    // Border should start after the threading lines (add 2px to clear
    // the stroke width)
    final borderLeftOffset = (threadingLineCount * 6.0) + 2.0;

    return Semantics(
      button: true,
      hint:
          onLongPress != null
              ? (isCollapsed
                  ? 'Double tap and hold to expand thread'
                  : 'Double tap and hold to collapse thread')
              : null,
      child: GestureDetector(
        onLongPress:
            onLongPress != null
                ? () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
                }
                : null,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(color: AppColors.background),
            child: Stack(
              children: [
                // Threading indicators - vertical lines showing
                // nesting ancestry
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CommentDepthPainter(depth: threadingLineCount),
                  ),
                ),
                // Bottom border
                // (starts after threading lines, not overlapping them)
                Positioned(
                  left: borderLeftOffset,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 1, color: AppColors.border),
                ),
                // Comment content with depth-based left padding
                // Animate height changes when collapsing/expanding
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      leftPadding,
                      isCollapsed ? 10 : 12,
                      16,
                      isCollapsed ? 10 : 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author info row
                        Row(
                          children: [
                            // Author avatar
                            _buildAuthorAvatar(comment.author),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '@${comment.author.handle}',
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(
                                    alpha: isCollapsed ? 0.7 : 0.5,
                                  ),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            // Show collapsed count OR time ago
                            if (isCollapsed && collapsedCount > 0)
                              _buildCollapsedBadge()
                            else
                              Text(
                                DateTimeUtils.formatTimeAgo(
                                  comment.createdAt,
                                  currentTime: currentTime,
                                ),
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),

                        // Only show content and actions when expanded
                        if (!isCollapsed) ...[
                          const SizedBox(height: 8),

                          // Comment content
                          if (comment.content.isNotEmpty) ...[
                            _buildCommentContent(comment),
                            const SizedBox(height: 8),
                          ],

                          // Action buttons (just vote for now)
                          _buildActionButtons(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the author avatar widget
  Widget _buildAuthorAvatar(AuthorView author) {
    if (author.avatar != null && author.avatar!.isNotEmpty) {
      // Show real author avatar
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: author.avatar!,
          width: 14,
          height: 14,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallbackAvatar(author),
          errorWidget: (context, url, error) => _buildFallbackAvatar(author),
        ),
      );
    }

    // Fallback to letter placeholder
    return _buildFallbackAvatar(author);
  }

  /// Builds a fallback avatar with the first letter of handle
  Widget _buildFallbackAvatar(AuthorView author) {
    final firstLetter = author.handle.isNotEmpty ? author.handle[0] : '?';
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          firstLetter.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Builds the compact collapsed badge showing "+X"
  Widget _buildCollapsedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$collapsedCount',
        style: TextStyle(
          color: AppColors.primary.withValues(alpha: 0.9),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Builds the comment content with support for facets
  Widget _buildCommentContent(CommentView comment) {
    // TODO: Add facet support for links and mentions like PostCard does
    // For now, just render plain text
    return Text(
      comment.content,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }

  /// Builds the action buttons row (vote button)
  Widget _buildActionButtons(BuildContext context) {
    return Consumer<VoteProvider>(
      builder: (context, voteProvider, child) {
        // Get optimistic vote state from provider
        final isLiked = voteProvider.isLiked(comment.uri);
        final adjustedScore = voteProvider.getAdjustedScore(
          comment.uri,
          comment.stats.score,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Heart vote button
            Semantics(
              button: true,
              label:
                  isLiked
                      ? 'Unlike comment, $adjustedScore '
                          '${adjustedScore == 1 ? "like" : "likes"}'
                      : 'Like comment, $adjustedScore '
                          '${adjustedScore == 1 ? "like" : "likes"}',
              child: InkWell(
                onTap: () async {
                  // Check authentication
                  final authProvider = context.read<AuthProvider>();
                  if (!authProvider.isAuthenticated) {
                    // Show sign-in dialog
                    final shouldSignIn = await SignInDialog.show(
                      context,
                      message: 'You need to sign in to vote on comments.',
                    );

                    if ((shouldSignIn ?? false) && context.mounted) {
                      // TODO: Navigate to sign-in screen
                      if (kDebugMode) {
                        debugPrint('Navigate to sign-in screen');
                      }
                    }
                    return;
                  }

                  // Light haptic feedback
                  await HapticFeedback.lightImpact();

                  // Toggle vote with optimistic update via VoteProvider
                  try {
                    await voteProvider.toggleVote(
                      postUri: comment.uri,
                      postCid: comment.cid,
                    );
                  } on Exception catch (e) {
                    if (kDebugMode) {
                      debugPrint('Failed to vote on comment: $e');
                    }
                    // TODO: Show error snackbar
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedHeartIcon(
                        isLiked: isLiked,
                        size: 16,
                        color: AppColors.textPrimary.withValues(alpha: 0.6),
                        likedColor: const Color(0xFFFF0033),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        DateTimeUtils.formatCount(adjustedScore),
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom painter for drawing comment depth indicator lines
class _CommentDepthPainter extends CustomPainter {
  _CommentDepthPainter({required this.depth});
  final int depth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    // Draw vertical line for each depth level with different colors
    for (var i = 0; i < depth; i++) {
      // Cycle through colors based on depth level
      paint.color = kThreadingColors[i % kThreadingColors.length].withValues(
        alpha: 0.5,
      );

      final xPosition = (i + 1) * 6.0;
      canvas.drawLine(
        Offset(xPosition, 0),
        Offset(xPosition, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CommentDepthPainter oldDelegate) {
    return oldDelegate.depth != depth;
  }
}
