import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/multi_feed_provider.dart';
import 'post_card.dart';

/// FeedPage widget for rendering a single feed's content
///
/// Displays a feed with:
/// - Loading state (spinner when loading initial posts)
/// - Error state (error message with retry button)
/// - Empty state (no posts message)
/// - Posts list (RefreshIndicator + ListView.builder with PostCard widgets)
/// - Pagination footer (loading indicator or error retry at bottom)
///
/// This widget is used within a PageView to render individual feeds
/// (Discover, For You) in the feed screen.
///
/// Uses AutomaticKeepAliveClientMixin to keep the page alive when swiping
/// between feeds, preventing scroll position jumps during transitions.
class FeedPage extends StatefulWidget {
  const FeedPage({
    required this.feedType,
    required this.posts,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.scrollController,
    required this.onRefresh,
    required this.onRetry,
    required this.onClearErrorAndLoadMore,
    required this.isAuthenticated,
    required this.currentTime,
    super.key,
  });

  final FeedType feedType;
  final List<FeedViewPost> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onClearErrorAndLoadMore;
  final bool isAuthenticated;
  final DateTime? currentTime;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Always show a footer slot to maintain stable itemCount during pagination.
  /// Without this, itemCount fluctuates when loading spinner appears/disappears,
  /// causing small scroll position jumps (~100px).
  bool get _shouldShowFooter => widget.posts.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Required call for AutomaticKeepAliveClientMixin
    super.build(context);

    // Loading state (only show full-screen loader for initial load,
    // not refresh)
    if (widget.isLoading && widget.posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // Error state (only show full-screen error when no posts loaded
    // yet). If we have posts but pagination failed, we'll show the error
    // at the bottom
    if (widget.error != null && widget.posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load feed',
                style: TextStyle(
                  fontSize: 20,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getUserFriendlyError(widget.error!),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: widget.onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state - wrapped in RefreshIndicator so users can pull to refresh
    if (widget.posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.forum,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.isAuthenticated
                            ? 'No posts yet'
                            : 'No posts to discover',
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isAuthenticated
                            ? 'Subscribe to communities to see '
                                'posts in your feed'
                            : 'Check back later for new posts',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Posts list - use ListView.custom with findChildIndexCallback for
    // scroll position stability during pagination. This tells Flutter how to
    // map item keys to indices, preventing scroll jumps when new items are
    // appended.
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: AppColors.primary,
      child: ListView.custom(
        controller: widget.scrollController,
        // Default platform physics (matches Thunder)
        // Android: ClampingScrollPhysics, iOS: BouncingScrollPhysics
        physics: const AlwaysScrollableScrollPhysics(),
        // Pre-render items 5000px in each direction (10000px total cache).
        // Builds items before they're visible, reducing layout shift jitter
        // from lazy height calculation.
        cacheExtent: 5000,
        // Add top padding so content isn't hidden behind transparent header
        padding: const EdgeInsets.only(top: 44),
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) {
          // Footer: loading indicator, error message, or end of feed
          // Use consistent key so Flutter can track this item across rebuilds
          if (index == widget.posts.length) {
            return KeyedSubtree(
              key: const ValueKey('feed_footer'),
              child: _buildFooter(),
            );
          }

          final post = widget.posts[index];

          // RepaintBoundary isolates each post card to prevent unnecessary
          // repaints of other items during scrolling.
          // ValueKey on RepaintBoundary ensures Flutter correctly identifies
          // and reuses the entire isolated subtree during list updates,
          // preserving both identity and paint optimization.
          return RepaintBoundary(
            key: ValueKey(post.post.uri),
            child: Semantics(
              label:
                  'Feed post in ${post.post.community.name} by '
                  '${post.post.author.displayName ?? post.post.author.handle}. '
                  '${post.post.title ?? ""}',
              button: true,
              child: PostCard(post: post, currentTime: widget.currentTime),
            ),
          );
          },
          childCount: widget.posts.length + (_shouldShowFooter ? 1 : 0),
          // findChildIndexCallback enables Flutter to track items by key
          // during list updates. When pagination adds items, Flutter uses
          // this to map existing keys to indices, maintaining scroll position.
          findChildIndexCallback: (Key key) {
            if (key is ValueKey<String>) {
              final keyValue = key.value;
              // Footer is always at the last index
              if (keyValue == 'feed_footer') {
                return widget.posts.length;
              }
              // Find post by URI
              final index = widget.posts.indexWhere(
                (p) => p.post.uri == keyValue,
              );
              return index != -1 ? index : null;
            }
            return null;
          },
        ),
      ),
    );
  }

  /// Build the footer widget (loading, error, or end of feed)
  Widget _buildFooter() {
    // Show loading indicator for pagination
    if (widget.isLoadingMore) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Show error message for pagination failures
    if (widget.error != null) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.primary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _getUserFriendlyError(widget.error!),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onClearErrorAndLoadMore,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Show end of feed message when no more posts available
    if (!widget.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.textSecondary,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              "You're all caught up!",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Idle state: invisible placeholder with same height as loading spinner
    // to prevent scroll jumps when transitioning between loading/idle states.
    // Height matches: padding (16) + spinner (~48) + padding (16) = 80
    return const SizedBox(height: 80);
  }

  /// Transform technical error messages into user-friendly ones
  String _getUserFriendlyError(String error) {
    final lowerError = error.toLowerCase();

    if (lowerError.contains('socketexception') ||
        lowerError.contains('network') ||
        lowerError.contains('connection refused')) {
      return 'Please check your internet connection';
    } else if (lowerError.contains('timeoutexception') ||
        lowerError.contains('timeout')) {
      return 'Request timed out. Please try again';
    } else if (lowerError.contains('401') ||
        lowerError.contains('unauthorized')) {
      return 'Authentication failed. Please sign in again';
    } else if (lowerError.contains('404') || lowerError.contains('not found')) {
      return 'Content not found';
    } else if (lowerError.contains('500') ||
        lowerError.contains('internal server')) {
      return 'Server error. Please try again later';
    }

    // Fallback to generic message for unknown errors
    return 'Something went wrong. Please try again';
  }
}
