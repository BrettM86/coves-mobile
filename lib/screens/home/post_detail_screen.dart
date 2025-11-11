import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/comments_provider.dart';
import '../../utils/error_messages.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/comments_header.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_card.dart';

/// Post Detail Screen
///
/// Displays a full post with its comments.
/// Architecture: Standalone screen for route destination and PageView child.
///
/// Features:
/// - Full post display (reuses PostCard widget)
/// - Sort selector (Hot/Top/New) using dropdown
/// - Comment list with ListView.builder for performance
/// - Pull-to-refresh with RefreshIndicator
/// - Loading, empty, and error states
/// - Automatic comment loading on screen init
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({required this.post, super.key});

  /// Post to display (passed via route extras)
  final FeedViewPost post;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  // Current sort option
  String _currentSort = 'hot';

  @override
  void initState() {
    super.initState();

    // Initialize scroll controller for pagination
    _scrollController.addListener(_onScroll);

    // Load comments after frame is built using provider from tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadComments();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load comments for the current post
  void _loadComments() {
    context.read<CommentsProvider>().loadComments(
      postUri: widget.post.post.uri,
      refresh: true,
    );
  }

  /// Handle sort changes from dropdown
  Future<void> _onSortChanged(String newSort) async {
    final previousSort = _currentSort;

    setState(() {
      _currentSort = newSort;
    });

    final commentsProvider = context.read<CommentsProvider>();
    final success = await commentsProvider.setSortOption(newSort);

    // Show error snackbar and revert UI if sort change failed
    if (!success && mounted) {
      setState(() {
        _currentSort = previousSort;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to change sort order. Please try again.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Retry',
            textColor: AppColors.textPrimary,
            onPressed: () {
              _onSortChanged(newSort);
            },
          ),
        ),
      );
    }
  }

  /// Handle scroll for pagination
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CommentsProvider>().loadMoreComments();
    }
  }

  /// Handle pull-to-refresh
  Future<void> _onRefresh() async {
    final commentsProvider = context.read<CommentsProvider>();
    await commentsProvider.refreshComments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(widget.post.post.title ?? 'Post'),
        elevation: 0,
      ),
      body: SafeArea(
        // Explicitly set bottom to prevent iOS home indicator overlap
        bottom: true,
        child: _buildContent(),
      ),
    );
  }


  /// Build main content area
  Widget _buildContent() {
    // Use Consumer to rebuild when comments provider changes
    return Consumer<CommentsProvider>(
      builder: (context, commentsProvider, child) {
        final isLoading = commentsProvider.isLoading;
        final error = commentsProvider.error;
        final comments = commentsProvider.comments;
        final isLoadingMore = commentsProvider.isLoadingMore;

        // Loading state (only show full-screen loader for initial load)
        if (isLoading && comments.isEmpty) {
          return const FullScreenLoading();
        }

        // Error state (only show full-screen error when no comments loaded yet)
        if (error != null && comments.isEmpty) {
          return FullScreenError(
            title: 'Failed to load comments',
            message: ErrorMessages.getUserFriendly(error),
            onRetry: commentsProvider.retry,
          );
        }

        // Content with RefreshIndicator
        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView.builder(
            controller: _scrollController,
            // Post + comments + loading indicator
            itemCount:
                1 + comments.length + (isLoadingMore || error != null ? 1 : 0),
            itemBuilder: (context, index) {
              // Post card (index 0)
              if (index == 0) {
                return Column(
                  children: [
                    // Reuse PostCard (hide comment button in detail view)
                    // Use ValueListenableBuilder to only rebuild when time changes
                    _PostHeader(
                      post: widget.post,
                      currentTimeNotifier: commentsProvider.currentTimeNotifier,
                    ),
                    // Comments header with sort dropdown
                    CommentsHeader(
                      commentCount: comments.length,
                      currentSort: _currentSort,
                      onSortChanged: _onSortChanged,
                    ),
                  ],
                );
              }

              // Loading indicator or error at the end
              if (index == comments.length + 1) {
                if (isLoadingMore) {
                  return const InlineLoading();
                }
                if (error != null) {
                  return InlineError(
                    message: ErrorMessages.getUserFriendly(error),
                    onRetry: () {
                      commentsProvider
                        ..clearError()
                        ..loadMoreComments();
                    },
                  );
                }
              }

              // Comment item - use existing CommentThread widget
              final comment = comments[index - 1];
              return _CommentItem(
                comment: comment,
                currentTimeNotifier: commentsProvider.currentTimeNotifier,
              );
            },
          ),
        );
      },
    );
  }

}

/// Post header widget that only rebuilds when time changes
///
/// Extracted to prevent unnecessary rebuilds when comment list changes.
/// Uses ValueListenableBuilder to listen only to time updates.
class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.currentTimeNotifier,
  });

  final FeedViewPost post;
  final ValueNotifier<DateTime?> currentTimeNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: currentTimeNotifier,
      builder: (context, currentTime, child) {
        return PostCard(
          post: post,
          currentTime: currentTime,
          showCommentButton: false,
          disableNavigation: true,
        );
      },
    );
  }
}

/// Comment item wrapper that only rebuilds when time changes
///
/// Uses ValueListenableBuilder to prevent rebuilds when unrelated
/// provider state changes (like loading state or error state).
class _CommentItem extends StatelessWidget {
  const _CommentItem({
    required this.comment,
    required this.currentTimeNotifier,
  });

  final ThreadViewComment comment;
  final ValueNotifier<DateTime?> currentTimeNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: currentTimeNotifier,
      builder: (context, currentTime, child) {
        return CommentThread(
          thread: comment,
          currentTime: currentTime,
          maxDepth: 6,
        );
      },
    );
  }
}
