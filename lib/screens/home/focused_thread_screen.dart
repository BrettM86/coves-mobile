import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/comment_card.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/status_bar_overlay.dart';
import '../compose/reply_screen.dart';

/// Focused thread screen for viewing deep comment threads
///
/// Displays a specific comment as the "anchor" with its full reply tree.
/// Used when user taps "Read X more replies" on a deeply nested thread.
///
/// Shows:
/// - Ancestor comments shown flat at the top (walking up the chain)
/// - The anchor comment (highlighted as the focus)
/// - All replies threaded below with fresh depth starting at 0
///
/// ## Collapsed State
/// This screen maintains its own collapsed comment state, intentionally
/// providing a "fresh slate" experience. When the user navigates back,
/// any collapsed state is reset. This is by design - it allows users to
/// explore deep threads without their collapse choices persisting across
/// navigation, keeping the focused view clean and predictable.
class FocusedThreadScreen extends StatelessWidget {
  const FocusedThreadScreen({
    required this.thread,
    required this.ancestors,
    required this.onReply,
    super.key,
  });

  /// The comment thread to focus on (becomes the new root)
  final ThreadViewComment thread;

  /// Ancestor comments leading to this thread (for context display)
  final List<ThreadViewComment> ancestors;

  /// Callback when user replies to a comment
  final Future<void> Function(String content, ThreadViewComment parent) onReply;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _FocusedThreadBody(
        thread: thread,
        ancestors: ancestors,
        onReply: onReply,
      ),
    );
  }
}

class _FocusedThreadBody extends StatefulWidget {
  const _FocusedThreadBody({
    required this.thread,
    required this.ancestors,
    required this.onReply,
  });

  final ThreadViewComment thread;
  final List<ThreadViewComment> ancestors;
  final Future<void> Function(String content, ThreadViewComment parent) onReply;

  @override
  State<_FocusedThreadBody> createState() => _FocusedThreadBodyState();
}

class _FocusedThreadBodyState extends State<_FocusedThreadBody> {
  final Set<String> _collapsedComments = {};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Scroll to anchor comment after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAnchor();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToAnchor() {
    final context = _anchorKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleCollapsed(String uri) {
    setState(() {
      if (_collapsedComments.contains(uri)) {
        _collapsedComments.remove(uri);
      } else {
        _collapsedComments.add(uri);
      }
    });
  }

  void _openReplyScreen(ThreadViewComment comment) {
    // Check authentication
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to reply'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReplyScreen(
          comment: comment,
          onSubmit: (content) => widget.onReply(content, comment),
        ),
      ),
    );
  }

  /// Navigate deeper into a nested thread
  void _onContinueThread(
    ThreadViewComment thread,
    List<ThreadViewComment> ancestors,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FocusedThreadScreen(
          thread: thread,
          ancestors: ancestors,
          onReply: widget.onReply,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate minimum bottom padding to allow anchor to scroll to top
    final screenHeight = MediaQuery.of(context).size.height;
    final minBottomPadding = screenHeight * 0.6;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            // App bar
            const SliverAppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              foregroundColor: AppColors.textPrimary,
              title: Text(
                'Thread',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              centerTitle: false,
              elevation: 0,
              floating: true,
              snap: true,
            ),

            // Content
            SliverSafeArea(
              top: false,
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Ancestor comments (shown flat, not nested)
                  ...widget.ancestors.map(_buildAncestorComment),

                  // Anchor comment (the focused comment) - made prominent
                  KeyedSubtree(
                    key: _anchorKey,
                    child: _buildAnchorComment(),
                  ),

                  // Replies (if any)
                  if (widget.thread.replies != null &&
                      widget.thread.replies!.isNotEmpty)
                    ...widget.thread.replies!.map((reply) {
                      return CommentThread(
                        thread: reply,
                        depth: 1,
                        maxDepth: 6,
                        onCommentTap: _openReplyScreen,
                        collapsedComments: _collapsedComments,
                        onCollapseToggle: _toggleCollapsed,
                        onContinueThread: _onContinueThread,
                        ancestors: [widget.thread],
                      );
                    }),

                  // Empty state if no replies
                  if (widget.thread.replies == null ||
                      widget.thread.replies!.isEmpty)
                    _buildNoReplies(),

                  // Bottom padding to allow anchor to scroll to top
                  SizedBox(height: minBottomPadding),
                ]),
              ),
            ),
          ],
        ),

        // Prevents content showing through transparent status bar
        const StatusBarOverlay(),
      ],
    );
  }

  /// Build an ancestor comment (shown flat as context above anchor)
  /// Styled more subtly than the anchor to show it's contextual
  Widget _buildAncestorComment(ThreadViewComment ancestor) {
    return Opacity(
      opacity: 0.6,
      child: CommentCard(
        comment: ancestor.comment,
        onTap: () => _openReplyScreen(ancestor),
      ),
    );
  }

  /// Build the anchor comment (the focused comment) with prominent styling
  Widget _buildAnchorComment() {
    // Note: CommentCard has its own Consumer<VoteProvider> for vote state
    return Container(
      decoration: BoxDecoration(
        // Subtle highlight to distinguish anchor from ancestors
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      child: CommentCard(
        comment: widget.thread.comment,
        onTap: () => _openReplyScreen(widget.thread),
        onLongPress: () => _toggleCollapsed(widget.thread.comment.uri),
        isCollapsed: _collapsedComments.contains(widget.thread.comment.uri),
        collapsedCount: _collapsedComments.contains(widget.thread.comment.uri)
            ? CommentThread.countDescendants(widget.thread)
            : 0,
      ),
    );
  }

  /// Build empty state when there are no replies
  Widget _buildNoReplies() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No replies yet',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to reply to this comment',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
