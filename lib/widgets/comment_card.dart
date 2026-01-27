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
import '../services/api_exceptions.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'rich_text_renderer.dart';
import 'sign_in_dialog.dart';
import 'tappable_author.dart';

/// Comment card widget for displaying individual comments
///
/// Displays a comment with:
/// - Author information (avatar, handle, timestamp)
/// - Comment content (supports facets for links/mentions)
/// - Heart vote button with optimistic updates via VoteProvider
/// - Visual threading indicator based on nesting depth
/// - Tap-to-reply functionality via [onTap] callback
/// - Long-press to collapse thread via [onLongPress] callback
/// - Three-dots menu with delete option (for comment author only)
///
/// ## Deleted Comments
///
/// When the comment's `isDeleted` flag is true, the card displays a
/// placeholder based on [deletionReason]: `[removed by moderator]` or
/// `[deleted by user]`. The vote button and actions are hidden.
/// Author information is hidden for deleted comments to preserve privacy.
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling periodic updates and testing.
///
/// When [isCollapsed] is true, displays a badge showing [collapsedCount]
/// hidden replies on the threading indicator bar.
class CommentCard extends StatefulWidget {
  const CommentCard({
    required this.comment,
    this.depth = 0,
    this.currentTime,
    this.onTap,
    this.onLongPress,
    this.isCollapsed = false,
    this.collapsedCount = 0,
    this.onDelete,
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

  /// Callback when the comment is deleted
  final Future<void> Function(String commentUri)? onDelete;

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  bool _isDeleting = false;

  CommentView get comment => widget.comment;
  int get depth => widget.depth;
  DateTime? get currentTime => widget.currentTime;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onLongPress => widget.onLongPress;
  bool get isCollapsed => widget.isCollapsed;
  int get collapsedCount => widget.collapsedCount;
  Future<void> Function(String commentUri)? get onDelete => widget.onDelete;

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
                ? () async {
                  try {
                    await HapticFeedback.mediumImpact();
                  } on PlatformException catch (e) {
                    if (kDebugMode) {
                      debugPrint('Haptics not supported: $e');
                    }
                  }
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
                      12,
                      16,
                      isCollapsed || comment.isDeleted ? 12 : 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author info row
                        Row(
                          children: [
                            // Author avatar and handle (or placeholder for deleted)
                            if (comment.isDeleted)
                              // Show deletion reason as placeholder
                              Text(
                                comment.deletionReason == 'moderator'
                                    ? '[removed by moderator]'
                                    : '[deleted by user]',
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else
                              // Show tappable author for active comments
                              TappableAuthor(
                                authorDid: comment.author.did,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Author avatar
                                    _buildAuthorAvatar(comment.author),
                                    const SizedBox(width: 8),
                                    Text(
                                      '@${comment.author.handle}',
                                      style: TextStyle(
                                        color: AppColors.textPrimary.withValues(
                                          alpha: isCollapsed ? 0.7 : 0.5,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Spacer(),
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

                        // Only show content and actions when expanded (skip for deleted)
                        if (!isCollapsed && !comment.isDeleted) ...[
                          const SizedBox(height: 8),

                          // Comment content
                          if (comment.content.isNotEmpty) ...[
                            _buildCommentContent(comment),
                            const SizedBox(height: 8),
                          ],

                          // Action buttons (menu and vote)
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
          // Disable fade animation to prevent scroll jitter
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
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
    return RichTextRenderer(
      text: comment.content,
      facets: comment.contentFacets,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }

  /// Handles menu action selection (delete)
  Future<void> _handleMenuAction(BuildContext context, String action) async {
    if (action == 'delete') {
      // Prevent multiple taps - set flag immediately before dialog
      if (_isDeleting) return;
      setState(() => _isDeleting = true);

      // Only proceed if onDelete callback is available
      if (onDelete == null) {
        if (kDebugMode) {
          debugPrint('Delete action triggered but onDelete callback is null');
        }
        setState(() => _isDeleting = false);
        return;
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Comment'),
          content: const Text(
            'Are you sure you want to delete this comment? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) {
        if (mounted) setState(() => _isDeleting = false);
        return;
      }

      try {
        await HapticFeedback.lightImpact();
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('Haptics not supported: $e');
        }
      }

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      try {
        await onDelete!(comment.uri);

        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Comment deleted'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on NetworkException catch (e) {
        if (kDebugMode) {
          debugPrint('Network error deleting comment: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Network error. Please check your connection and try again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on NotFoundException catch (e) {
        if (kDebugMode) {
          debugPrint('Comment not found: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Comment not found. It may have already been deleted.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on ApiException catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to delete comment: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                e.statusCode == 403
                    ? 'You can only delete your own comments'
                    : 'Could not delete comment. Please try again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on Exception catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to delete comment: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not delete comment. Please try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  /// Builds the three-dots menu for comment actions (only shown for author)
  Widget _buildCommentMenu(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (!authProvider.isAuthenticated ||
            authProvider.did != comment.author.did) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<String>(
          icon: Icon(
            Icons.more_horiz,
            size: 18,
            color: AppColors.textPrimary.withValues(alpha: 0.6),
          ),
          tooltip: 'Comment options',
          color: AppColors.backgroundSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (action) => _handleMenuAction(context, action),
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Delete comment',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Builds the action buttons row (menu and vote button)
  Widget _buildActionButtons(BuildContext context) {
    return Consumer<VoteProvider>(
      builder: (context, voteProvider, child) {
        final isLiked = voteProvider.isLiked(comment.uri);
        final adjustedScore = voteProvider.getAdjustedScore(
          comment.uri,
          comment.stats.score,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildCommentMenu(context),
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
                      await Navigator.of(context).pushNamed('/sign-in');
                    }
                    return;
                  }

                  try {
                    await HapticFeedback.lightImpact();
                  } on PlatformException catch (e) {
                    if (kDebugMode) {
                      debugPrint('Haptics not supported: $e');
                    }
                  }

                  try {
                    await voteProvider.toggleVote(
                      postUri: comment.uri,
                      postCid: comment.cid,
                    );
                  } on Exception catch (e) {
                    if (kDebugMode) {
                      debugPrint('Failed to vote on comment: $e');
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to vote. Please try again.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
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
