import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/comments_provider_cache.dart';
import '../../utils/error_messages.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/comments_header.dart';
import '../../widgets/icons/share_icon.dart';
import '../../widgets/detailed_post_view.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_action_bar.dart';
import '../../widgets/status_bar_overlay.dart';
import '../compose/reply_screen.dart';
import 'focused_thread_screen.dart';

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
  const PostDetailScreen({
    required this.post,
    this.isOptimistic = false,
    super.key,
  });

  /// Post to display (passed via route extras)
  final FeedViewPost post;

  /// Whether this is an optimistic post (just created, not yet indexed)
  /// When true, skips initial comment load since we know there are no comments
  final bool isOptimistic;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  // ScrollController created lazily with cached scroll position for instant restoration
  late ScrollController _scrollController;
  final GlobalKey _commentsHeaderKey = GlobalKey();

  // Cached provider from CommentsProviderCache
  late CommentsProvider _commentsProvider;
  CommentsProviderCache? _commentsCache;

  // Track initialization state
  bool _isInitialized = false;

  // Track if provider has been invalidated (e.g., by sign-out)
  bool _providerInvalidated = false;

  @override
  void initState() {
    super.initState();
    // ScrollController and provider initialization moved to didChangeDependencies
    // where we have access to context for synchronous provider acquisition
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize provider synchronously on first call (has context access)
    // This ensures cached data is available for the first build, avoiding
    // the flash from loading state → content → scroll position jump
    if (!_isInitialized) {
      _initializeProviderSync();
    }
  }

  /// Listen for auth state changes to handle sign-out
  void _setupAuthListener() {
    final authProvider = context.read<AuthProvider>();
    authProvider.addListener(_onAuthChanged);
  }

  /// Handle auth state changes (specifically sign-out)
  void _onAuthChanged() {
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();

    // If user signed out while viewing this screen, navigate back
    // The CommentsProviderCache has already disposed our provider
    if (!authProvider.isAuthenticated &&
        _isInitialized &&
        !_providerInvalidated) {
      _providerInvalidated = true;

      if (kDebugMode) {
        debugPrint('🚪 User signed out - cleaning up PostDetailScreen');
      }

      // Remove listener from provider (it's disposed but this is safe)
      try {
        _commentsProvider.removeListener(_onProviderChanged);
      } on Exception {
        // Provider already disposed - expected
      }

      // Navigate back to feed
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  /// Initialize provider synchronously from cache
  ///
  /// Called from didChangeDependencies to ensure cached data is available
  /// for the first build. Creates ScrollController with initialScrollOffset
  /// set to cached position for instant scroll restoration without flicker.
  void _initializeProviderSync() {
    // Get or create provider from cache
    final cache = context.read<CommentsProviderCache>();
    _commentsCache = cache;
    _commentsProvider = cache.acquireProvider(
      postUri: widget.post.post.uri,
      postCid: widget.post.post.cid,
    );

    // Create scroll controller with cached position for instant restoration
    // This avoids the flash: loading → content at top → jump to cached position
    final cachedScrollPosition = _commentsProvider.scrollPosition;
    _scrollController = ScrollController(
      initialScrollOffset: cachedScrollPosition,
    );
    _scrollController.addListener(_onScroll);

    if (kDebugMode && cachedScrollPosition > 0) {
      debugPrint(
        '📍 Created ScrollController with initial offset: $cachedScrollPosition',
      );
    }

    // Listen for changes to trigger rebuilds
    _commentsProvider.addListener(_onProviderChanged);

    // Setup auth listener
    _setupAuthListener();

    // Mark as initialized before triggering any loads
    // This ensures the first build shows content (not loading) when cached
    _isInitialized = true;

    // Skip loading for optimistic posts (just created, not yet indexed)
    if (widget.isOptimistic) {
      if (kDebugMode) {
        debugPrint('✨ Optimistic post - skipping initial comment load');
      }
      // Don't load comments - there won't be any yet
    } else if (_commentsProvider.comments.isNotEmpty) {
      // Already have cached data - it will render immediately
      if (kDebugMode) {
        debugPrint(
          '📦 Using cached comments (${_commentsProvider.comments.length})',
        );
      }

      // Background refresh if data is stale (won't cause flicker)
      if (_commentsProvider.isStale) {
        if (kDebugMode) {
          debugPrint('🔄 Data stale, refreshing in background');
        }
        _commentsProvider.loadComments(refresh: true);
      }
    } else {
      // No cached data - load fresh
      _commentsProvider.loadComments(refresh: true);
    }
  }

  @override
  void dispose() {
    // Remove auth listener
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } on Exception catch (e) {
      // Context may not be valid during dispose - expected behavior
      if (kDebugMode) {
        debugPrint('dispose: auth listener removal failed: $e');
      }
    }

    // Release provider pin in cache (prevents LRU eviction disposing an active
    // provider while this screen is in the navigation stack).
    if (_isInitialized) {
      try {
        _commentsCache?.releaseProvider(widget.post.post.uri);
      } on Exception catch (e) {
        // Cache may already be disposed - expected behavior
        if (kDebugMode) {
          debugPrint('dispose: cache release failed: $e');
        }
      }
    }

    // Remove provider listener if not already invalidated
    if (_isInitialized && !_providerInvalidated) {
      try {
        _commentsProvider.removeListener(_onProviderChanged);
      } on Exception catch (e) {
        // Provider may already be disposed - expected behavior
        if (kDebugMode) {
          debugPrint('dispose: provider listener removal failed: $e');
        }
      }
    }
    _scrollController.dispose();
    super.dispose();
  }

  /// Handle provider changes
  void _onProviderChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Handle sort changes from dropdown
  Future<void> _onSortChanged(String newSort) async {
    final success = await _commentsProvider.setSortOption(newSort);

    // Show error snackbar if sort change failed
    if (!success && mounted) {
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
    // Don't interact with disposed provider
    if (_providerInvalidated) return;

    // Save scroll position to provider on every scroll event
    if (_scrollController.hasClients) {
      _commentsProvider.saveScrollPosition(_scrollController.position.pixels);
    }

    // Load more comments when near bottom
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _commentsProvider.loadMoreComments();
    }
  }

  /// Handle pull-to-refresh
  Future<void> _onRefresh() async {
    // Don't interact with disposed provider
    if (_providerInvalidated) return;

    await _commentsProvider.refreshComments();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading until provider is initialized
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: FullScreenLoading(),
      );
    }

    // If provider was invalidated (sign-out), show loading while navigating away
    if (_providerInvalidated) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: FullScreenLoading(),
      );
    }

    // Provide the cached CommentsProvider to descendant widgets
    return ChangeNotifierProvider.value(
      value: _commentsProvider,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _buildContent(),
        bottomNavigationBar: _buildActionBar(),
      ),
    );
  }

  /// Build community title with avatar, name on top and instance below
  Widget _buildCommunityTitle() {
    final community = widget.post.post.community;

    // Extract instance from handle - take last two segments
    // e.g., "test-science.coves.social" -> "coves.social"
    var instance = 'coves.social'; // default
    if (community.handle != null && community.handle!.contains('.')) {
      final parts = community.handle!.split('.');
      if (parts.length >= 2) {
        // Take last two segments for the instance
        instance = parts.sublist(parts.length - 2).join('.');
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Community avatar
        _buildCommunityAvatar(community),
        const SizedBox(width: 10),
        // Text column
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Community name with ! prefix - bigger, teal
              Text(
                '!${community.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.communityName,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              // Instance below - smaller
              Text(
                instance,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build community avatar or fallback
  Widget _buildCommunityAvatar(CommunityRef community) {
    const size = 28.0;

    if (community.avatar != null && community.avatar!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: community.avatar!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallbackAvatar(community, size),
          errorWidget: (_, __, ___) => _buildFallbackAvatar(community, size),
        ),
      );
    }

    return _buildFallbackAvatar(community, size);
  }

  /// Build fallback avatar with first letter
  Widget _buildFallbackAvatar(CommunityRef community, double size) {
    final firstLetter = community.name.isNotEmpty ? community.name[0] : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.communityName.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          firstLetter.toUpperCase(),
          style: TextStyle(
            color: AppColors.communityName,
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Handle share button tap
  Future<void> _handleShare() async {
    // Haptic feedback is non-essential, silently fail if unsupported
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics not supported on this platform - ignore
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share feature coming soon!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Handle menu action selection
  Future<void> _handleMenuAction(String action) async {
    // Haptic feedback is non-essential, silently fail if unsupported
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics not supported on this platform - ignore
    }

    switch (action) {
      case 'copy_link':
        final postUri = widget.post.post.uri;
        try {
          await Clipboard.setData(ClipboardData(text: postUri));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Link copied to clipboard'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } on PlatformException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to copy link to clipboard'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.primary,
              ),
            );
          }
        }
      case 'report':
        // TODO: Implement report functionality
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report feature coming soon!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case 'hide':
        // TODO: Implement hide functionality
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hide feature coming soon!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  /// Build bottom action bar with vote, save, and comment actions
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
            record: widget.post.post.record,
            stats: PostStats(
              upvotes: widget.post.post.stats.upvotes,
              downvotes: widget.post.post.stats.downvotes,
              score: adjustedScore,
              commentCount: widget.post.post.stats.commentCount,
            ),
            embed: widget.post.post.embed,
          ),
          reason: widget.post.reason,
        );

        return PostActionBar(
          post: displayPost,
          isVoted: isVoted,
          onCommentInputTap: _openCommentComposer,
          onCommentCountTap: _scrollToComments,
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

            // Capture messenger before async operations
            final messenger = ScaffoldMessenger.of(context);

            // Light haptic feedback on both like and unlike
            // Haptic feedback is non-essential, silently fail if unsupported
            try {
              await HapticFeedback.lightImpact();
            } on PlatformException {
              // Haptics not supported on this platform - ignore
            }
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

  /// Scroll to the comments section
  void _scrollToComments() {
    final context = _commentsHeaderKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Open the reply screen for composing a comment
  void _openCommentComposer() {
    // Check authentication
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to comment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to reply screen with full post context
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (context) => ReplyScreen(
              post: widget.post,
              onSubmit: _handleCommentSubmit,
              commentsProvider: _commentsProvider,
            ),
      ),
    );
  }

  /// Handle comment submission (reply to post)
  Future<void> _handleCommentSubmit(String content, List<RichTextFacet> facets) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _commentsProvider.createComment(content: content, contentFacets: facets);

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Comment posted'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to post comment: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
      rethrow; // Let ReplyScreen know submission failed
    }
  }

  /// Handle reply to a comment (nested reply)
  Future<void> _handleCommentReply(
    String content,
    List<RichTextFacet> facets,
    ThreadViewComment parentComment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _commentsProvider.createComment(
        content: content,
        contentFacets: facets,
        parentComment: parentComment,
      );

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Reply posted'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to post reply: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
      rethrow; // Let ReplyScreen know submission failed
    }
  }

  /// Open reply screen for replying to a comment
  void _openReplyToComment(ThreadViewComment comment) {
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

    // Navigate to reply screen with comment context
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (context) => ReplyScreen(
              comment: comment,
              onSubmit: (content, facets) => _handleCommentReply(content, facets, comment),
              commentsProvider: _commentsProvider,
            ),
      ),
    );
  }

  /// Navigate to focused thread screen for deep threads
  void _onContinueThread(
    ThreadViewComment thread,
    List<ThreadViewComment> ancestors,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (context) => FocusedThreadScreen(
              thread: thread,
              ancestors: ancestors,
              onReply: _handleCommentReply,
              commentsProvider: _commentsProvider,
            ),
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

        // Content with RefreshIndicator and floating SliverAppBar
        // Wrapped in Stack to add solid status bar background overlay
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.primary,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Pinned app bar that stays visible when scrolling
                  SliverAppBar(
                    backgroundColor: AppColors.background,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: AppColors.textPrimary,
                    title: _buildCommunityTitle(),
                    centerTitle: false,
                    elevation: 0,
                    pinned: true,
                    actions: [
                      IconButton(
                        icon: const ShareIcon(color: AppColors.textPrimary),
                        onPressed: _handleShare,
                        tooltip: 'Share',
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'More options',
                        color: AppColors.backgroundSecondary,
                        onSelected: _handleMenuAction,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'copy_link',
                            child: Row(
                              children: [
                                Icon(Icons.link, size: 20),
                                SizedBox(width: 12),
                                Text('Copy link'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Report'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'hide',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_off_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Hide post'),
                              ],
                            ),
                          ),
                        ],
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
                                // Reuse PostCard (hide comment button in
                                // detail view)
                                // Use ValueListenableBuilder to only rebuild
                                // when time changes
                                _PostHeader(
                                  post: widget.post,
                                  currentTimeNotifier:
                                      commentsProvider.currentTimeNotifier,
                                ),

                                // Visual divider before comments section
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  height: 1,
                                  color: AppColors.border,
                                ),

                                // Comments header with sort dropdown
                                CommentsHeader(
                                  key: _commentsHeaderKey,
                                  commentCount: widget.post.post.stats.commentCount,
                                  currentSort: commentsProvider.sort,
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
                            onCommentTap: _openReplyToComment,
                            collapsedComments:
                                commentsProvider.collapsedComments,
                            onCollapseToggle: commentsProvider.toggleCollapsed,
                            onContinueThread: _onContinueThread,
                            onDelete: (uri) =>
                                commentsProvider.deleteComment(commentUri: uri),
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
            ),
            // Prevents content showing through transparent status bar
            const StatusBarOverlay(),
          ],
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
        return DetailedPostView(
          post: post,
          currentTime: currentTime,
          showSources: true,
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
    this.onCommentTap,
    this.collapsedComments = const {},
    this.onCollapseToggle,
    this.onContinueThread,
    this.onDelete,
  });

  final ThreadViewComment comment;
  final ValueNotifier<DateTime?> currentTimeNotifier;
  final void Function(ThreadViewComment)? onCommentTap;
  final Set<String> collapsedComments;
  final void Function(String uri)? onCollapseToggle;
  final void Function(ThreadViewComment, List<ThreadViewComment>)?
  onContinueThread;
  final Future<void> Function(String commentUri)? onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: currentTimeNotifier,
      builder: (context, currentTime, child) {
        return CommentThread(
          thread: comment,
          currentTime: currentTime,
          maxDepth: 6,
          onCommentTap: onCommentTap,
          collapsedComments: collapsedComments,
          onCollapseToggle: onCollapseToggle,
          onContinueThread: onContinueThread,
          onDelete: onDelete,
        );
      },
    );
  }
}
