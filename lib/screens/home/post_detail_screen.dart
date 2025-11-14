import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../providers/vote_provider.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/error_messages.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/comments_header.dart';
import '../../widgets/icons/share_icon.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_action_bar.dart';
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
      body: _buildContent(),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  /// Build community title with avatar and handle
  Widget _buildCommunityTitle() {
    final community = widget.post.post.community;
    final displayHandle = CommunityHandleUtils.formatHandleForDisplay(
      community.handle,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Community avatar
        if (community.avatar != null && community.avatar!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: community.avatar!,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildFallbackAvatar(community),
              errorWidget:
                  (context, url, error) => _buildFallbackAvatar(community),
            ),
          )
        else
          _buildFallbackAvatar(community),
        const SizedBox(width: 8),
        // Community handle with styled parts
        if (displayHandle != null)
          Flexible(child: _buildStyledHandle(displayHandle))
        else
          Flexible(
            child: Text(
              community.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// Build styled community handle with color-coded parts
  Widget _buildStyledHandle(String displayHandle) {
    // Format: !gaming@coves.social
    final atIndex = displayHandle.indexOf('@');
    final communityPart = displayHandle.substring(0, atIndex);
    final instancePart = displayHandle.substring(atIndex);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: communityPart,
            style: const TextStyle(
              color: AppColors.communityName,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: instancePart,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Build fallback avatar with first letter
  Widget _buildFallbackAvatar(CommunityRef community) {
    final firstLetter = community.name.isNotEmpty ? community.name[0] : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          firstLetter.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Handle share button tap
  Future<void> _handleShare() async {
    // Add haptic feedback
    await HapticFeedback.lightImpact();

    // TODO: Generate proper deep link URL when deep linking is implemented
    final postUri = widget.post.post.uri;
    final title = widget.post.post.title ?? 'Check out this post';

    await Share.share('$title\n\n$postUri', subject: title);
  }

  /// Build bottom action bar with comment input and buttons
  Widget _buildActionBar() {
    return Consumer<VoteProvider>(
      builder: (context, voteProvider, child) {
        final isVoted = voteProvider.isLiked(widget.post.post.uri);
        final adjustedScore = voteProvider.getAdjustedScore(
          widget.post.post.uri,
          widget.post.post.stats.score,
        );

        // Create a modified post with adjusted score for display
        final displayPost = FeedViewPost(
          post: PostView(
            uri: widget.post.post.uri,
            cid: widget.post.post.cid,
            rkey: widget.post.post.rkey,
            author: widget.post.post.author,
            community: widget.post.post.community,
            createdAt: widget.post.post.createdAt,
            indexedAt: widget.post.post.indexedAt,
            text: widget.post.post.text,
            title: widget.post.post.title,
            stats: PostStats(
              upvotes: widget.post.post.stats.upvotes,
              downvotes: widget.post.post.stats.downvotes,
              score: adjustedScore,
              commentCount: widget.post.post.stats.commentCount,
            ),
            embed: widget.post.post.embed,
            facets: widget.post.post.facets,
          ),
          reason: widget.post.reason,
        );

        return PostActionBar(
          post: displayPost,
          isVoted: isVoted,
          onCommentTap: () {
            // TODO: Open comment composer
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comment composer coming soon!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onVoteTap: () async {
            // Check authentication
            final authProvider = context.read<AuthProvider>();
            if (!authProvider.isAuthenticated) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sign in to vote on posts'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }

            // Light haptic feedback on both like and unlike
            await HapticFeedback.lightImpact();

            // Toggle vote
            final messenger = ScaffoldMessenger.of(context);
            try {
              await voteProvider.toggleVote(
                postUri: widget.post.post.uri,
                postCid: widget.post.post.cid,
              );
            } on Exception catch (e) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to vote: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
          onSaveTap: () {
            // TODO: Add save functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Save feature coming soon!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
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

        // Content with RefreshIndicator and floating SliverAppBar
        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Floating app bar that hides on scroll down, shows on scroll up
              SliverAppBar(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                foregroundColor: AppColors.textPrimary,
                title: _buildCommunityTitle(),
                centerTitle: false,
                elevation: 0,
                floating: true,
                snap: true,
                actions: [
                  IconButton(
                    icon: const ShareIcon(color: AppColors.textPrimary),
                    onPressed: _handleShare,
                    tooltip: 'Share',
                  ),
                ],
              ),

              // Post + comments + loading indicator
              SliverSafeArea(
                top: false,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Post card (index 0)
                      if (index == 0) {
                        return Column(
                          children: [
                            // Reuse PostCard (hide comment button in detail view)
                            // Use ValueListenableBuilder to only rebuild when time changes
                            _PostHeader(
                              post: widget.post,
                              currentTimeNotifier:
                                  commentsProvider.currentTimeNotifier,
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
                        currentTimeNotifier:
                            commentsProvider.currentTimeNotifier,
                      );
                    },
                    childCount:
                        1 +
                        comments.length +
                        (isLoadingMore || error != null ? 1 : 0),
                  ),
                ),
              ),
            ],
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
  const _PostHeader({required this.post, required this.currentTimeNotifier});

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
          showActions: false,
          showHeader: false,
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
