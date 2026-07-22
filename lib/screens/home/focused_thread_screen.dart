import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../widgets/comment_card.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/loading_error_states.dart';
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
///
/// ## Provider Sharing
/// Receives the parent's CommentsProvider for draft text preservation and
/// consistent vote state display.
class FocusedThreadScreen extends StatelessWidget {
  const FocusedThreadScreen({
    required this.thread,
    required this.ancestors,
    required this.onReply,
    required this.commentsProvider,
    super.key,
  });

  /// The comment thread to focus on (becomes the new root)
  final ThreadViewComment thread;

  /// Ancestor comments leading to this thread (for context display)
  final List<ThreadViewComment> ancestors;

  /// Callback when user replies to a comment
  final Future<void> Function(String content, List<RichTextFacet> facets, ThreadViewComment parent) onReply;

  /// Parent's CommentsProvider for draft preservation and vote state
  final CommentsProvider commentsProvider;

  @override
  Widget build(BuildContext context) {
    // Expose parent's CommentsProvider for ReplyScreen draft access
    return ChangeNotifierProvider.value(
      value: commentsProvider,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _FocusedThreadBody(
          thread: thread,
          ancestors: ancestors,
          onReply: onReply,
        ),
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
  final Future<void> Function(String content, List<RichTextFacet> facets, ThreadViewComment parent) onReply;

  @override
  State<_FocusedThreadBody> createState() => _FocusedThreadBodyState();
}

class _FocusedThreadBodyState extends State<_FocusedThreadBody> {
  final Set<String> _collapsedComments = {};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _anchorKey = GlobalKey();

  /// Local fallback subtree rooted at the anchor comment.
  ///
  /// Starts as the snapshot passed from the parent thread (which may be
  /// truncated by the original fetch depth) and is refreshed from the
  /// server so deep replies and newly posted replies show up. The build
  /// method prefers the provider's live copy of the anchor node when it is
  /// still present in the loaded tree; this is the fallback for anchors
  /// outside it.
  late ThreadViewComment _thread;

  /// Monotonic sequence for subtree fetches so an older in-flight response
  /// can never overwrite the result of a newer one.
  int _refreshSeq = 0;

  /// Whether the most recent anchor-subtree hydration failed.
  ///
  /// Only surfaced in the UI when the snapshot has no replies to fall back
  /// on (otherwise the stale-but-usable subtree stays visible silently).
  bool _hydrationFailed = false;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    // Scroll to anchor comment after build, then hydrate the full subtree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAnchor();
      _refreshSubtree();
    });
  }

  /// Re-fetch the anchor's subtree from the server and update the view.
  ///
  /// Also merges the subtree into the parent CommentsProvider tree (when
  /// the anchor is still present there), keeping the full thread in sync.
  /// Failures are non-fatal when a snapshot with replies is already
  /// visible; with an empty snapshot a retryable error state is shown.
  Future<void> _refreshSubtree() async {
    if (!mounted) {
      return;
    }
    final provider = context.read<CommentsProvider>();
    final seq = ++_refreshSeq;
    try {
      final subtree = await provider.loadMoreReplies(widget.thread.comment.uri);
      if (!mounted || seq != _refreshSeq) {
        return;
      }
      setState(() {
        _hydrationFailed = false;
        if (subtree != null) {
          _thread = subtree;
        }
      });
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to refresh focused subtree: $e');
      }
      if (!mounted || seq != _refreshSeq) {
        return;
      }
      setState(() => _hydrationFailed = true);
    }
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
        builder: (navigatorContext) => ReplyScreen(
          comment: comment,
          onSubmit: (content, facets) async {
            await widget.onReply(content, facets, comment);
            if (!mounted) {
              return;
            }
            // Re-fetch the subtree so the new reply appears in this view
            await _refreshSubtree();
          },
          commentsProvider: context.read<CommentsProvider>(),
        ),
      ),
    );
  }

  /// Load hidden replies for a nested comment inside the focused view
  Future<void> _onLoadMoreReplies(ThreadViewComment node) async {
    final provider = context.read<CommentsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // Skip the local merge when a newer anchor refresh starts while this
    // fetch is in flight (the refreshed subtree supersedes it).
    final seq = _refreshSeq;
    try {
      final subtree = await provider.loadMoreReplies(node.comment.uri);
      if (subtree != null && mounted && seq == _refreshSeq) {
        setState(() => _thread = _thread.replaceDescendant(subtree));
      }
    } on Exception {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to load replies. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Delete a comment, then refresh both the full thread and this subtree
  Future<void> _onDelete(String uri) async {
    await context.read<CommentsProvider>().deleteComment(commentUri: uri);
    if (!mounted) {
      return;
    }
    await _refreshSubtree();
  }

  /// Navigate deeper into a nested thread
  void _onContinueThread(
    ThreadViewComment thread,
    List<ThreadViewComment> ancestors,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (navigatorContext) => FocusedThreadScreen(
          thread: thread,
          ancestors: ancestors,
          onReply: widget.onReply,
          commentsProvider: context.read<CommentsProvider>(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on provider changes (e.g. per-node reply-loading spinners)
    final commentsProvider = context.watch<CommentsProvider>();

    // Prefer the provider's live copy of the anchor node when it is still
    // present in the loaded tree, so deletes, sort changes, and hydrations
    // performed elsewhere reach this screen. The local snapshot is the
    // fallback for anchors outside the provider's loaded tree.
    var thread = _thread;
    for (final root in commentsProvider.comments) {
      final live = root.findByUri(widget.thread.comment.uri);
      if (live != null) {
        thread = live;
        break;
      }
    }

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
                    child: _buildAnchorComment(thread),
                  ),

                  // Replies (if any)
                  if (thread.replies != null && thread.replies!.isNotEmpty)
                    ...thread.replies!.map((reply) {
                      return CommentThread(
                        key: ValueKey(reply.comment.uri),
                        thread: reply,
                        depth: 1,
                        maxDepth: 6,
                        onCommentTap: _openReplyScreen,
                        collapsedComments: _collapsedComments,
                        onCollapseToggle: _toggleCollapsed,
                        onContinueThread: _onContinueThread,
                        onLoadMoreReplies: _onLoadMoreReplies,
                        loadingMoreReplies:
                            commentsProvider.loadingMoreReplies,
                        ancestors: [thread],
                        onDelete: _onDelete,
                      );
                    }),

                  // More direct replies to the anchor beyond this page
                  if (thread.hasMore &&
                      !_collapsedComments.contains(thread.comment.uri))
                    LoadMoreRepliesButton(
                      depth: 0,
                      isLoading: commentsProvider.loadingMoreReplies
                          .contains(thread.comment.uri),
                      onTap: () => _onLoadMoreReplies(thread),
                    ),

                  // Empty state (or retryable error) if no replies loaded
                  if (thread.replies == null || thread.replies!.isEmpty) ...[
                    if (_hydrationFailed)
                      InlineError(
                        message: 'Could not load replies. Please try again.',
                        onRetry: _refreshSubtree,
                      )
                    else if (!thread.hasMore)
                      _buildNoReplies(),
                  ],

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
        onDelete: _onDelete,
      ),
    );
  }

  /// Build the anchor comment (the focused comment) with prominent styling
  Widget _buildAnchorComment(ThreadViewComment thread) {
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
        comment: thread.comment,
        onTap: () => _openReplyScreen(thread),
        onLongPress: () => _toggleCollapsed(thread.comment.uri),
        isCollapsed: _collapsedComments.contains(thread.comment.uri),
        collapsedCount: _collapsedComments.contains(thread.comment.uri)
            ? thread.comment.stats.replyCount
            : 0,
        onDelete: _onDelete,
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
