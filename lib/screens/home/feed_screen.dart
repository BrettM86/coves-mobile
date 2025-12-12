import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feed_provider.dart';
import '../../widgets/icons/bluesky_icons.dart';
import '../../widgets/post_card.dart';

/// Header layout constants
const double _kHeaderHeight = 44;
const double _kTabUnderlineWidth = 28;
const double _kTabUnderlineHeight = 3;
const double _kHeaderContentPadding = _kHeaderHeight;

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.onSearchTap});

  /// Callback when search icon is tapped (to switch to communities tab)
  final VoidCallback? onSearchTap;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Fetch feed after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if widget is still mounted before loading
      if (mounted) {
        _loadFeed();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load feed - business logic is now in FeedProvider
  void _loadFeed() {
    Provider.of<FeedProvider>(context, listen: false).loadFeed(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      Provider.of<FeedProvider>(context, listen: false).loadMore();
    }
  }

  Future<void> _onRefresh() async {
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    await feedProvider.loadFeed(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    // Optimized: Use select to only rebuild when specific fields change
    // This prevents unnecessary rebuilds when unrelated provider fields change
    final isAuthenticated = context.select<AuthProvider, bool>(
      (p) => p.isAuthenticated,
    );
    final isLoading = context.select<FeedProvider, bool>((p) => p.isLoading);
    final error = context.select<FeedProvider, String?>((p) => p.error);
    final feedType = context.select<FeedProvider, FeedType>((p) => p.feedType);

    // IMPORTANT: This relies on FeedProvider creating new list instances
    // (_posts = [..._posts, ...response.feed]) rather than mutating in-place.
    // context.select uses == for comparison, and Lists use reference equality,
    // so in-place mutations (_posts.addAll(...)) would not trigger rebuilds.
    final posts = context.select<FeedProvider, List<FeedViewPost>>(
      (p) => p.posts,
    );
    final isLoadingMore = context.select<FeedProvider, bool>(
      (p) => p.isLoadingMore,
    );
    final currentTime = context.select<FeedProvider, DateTime?>(
      (p) => p.currentTime,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Feed content (behind header)
            _buildBody(
              isLoading: isLoading,
              error: error,
              posts: posts,
              isLoadingMore: isLoadingMore,
              isAuthenticated: isAuthenticated,
              currentTime: currentTime,
            ),
            // Transparent header overlay
            _buildHeader(feedType: feedType, isAuthenticated: isAuthenticated),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required FeedType feedType,
    required bool isAuthenticated,
  }) {
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        // Gradient fade from solid to transparent
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withValues(alpha: 0.8),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Feed type tabs in the center
          Expanded(
            child: _buildFeedTypeTabs(
              feedType: feedType,
              isAuthenticated: isAuthenticated,
            ),
          ),
          // Search/Communities icon on the right
          if (widget.onSearchTap != null)
            Semantics(
              label: 'Navigate to Communities',
              button: true,
              child: InkWell(
                onTap: widget.onSearchTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: AppColors.primary.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: BlueSkyIcon.search(color: AppColors.textPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedTypeTabs({
    required FeedType feedType,
    required bool isAuthenticated,
  }) {
    // If not authenticated, only show Discover
    if (!isAuthenticated) {
      return Center(
        child: _buildFeedTypeTab(
          label: 'Discover',
          isActive: true,
          onTap: null,
        ),
      );
    }

    // Authenticated: show both tabs side by side (TikTok style)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildFeedTypeTab(
          label: 'Discover',
          isActive: feedType == FeedType.discover,
          onTap: () => _switchToFeedType(FeedType.discover),
        ),
        const SizedBox(width: 24),
        _buildFeedTypeTab(
          label: 'For You',
          isActive: feedType == FeedType.forYou,
          onTap: () => _switchToFeedType(FeedType.forYou),
        ),
      ],
    );
  }

  Widget _buildFeedTypeTab({
    required String label,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      label: '$label feed${isActive ? ', selected' : ''}',
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary.withValues(alpha: 0.6),
                fontSize: 16,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            // Underline indicator (TikTok style)
            Container(
              width: _kTabUnderlineWidth,
              height: _kTabUnderlineHeight,
              decoration: BoxDecoration(
                color: isActive ? AppColors.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _switchToFeedType(FeedType type) {
    Provider.of<FeedProvider>(context, listen: false).setFeedType(type);
  }

  Widget _buildBody({
    required bool isLoading,
    required String? error,
    required List<FeedViewPost> posts,
    required bool isLoadingMore,
    required bool isAuthenticated,
    required DateTime? currentTime,
  }) {
    // Loading state (only show full-screen loader for initial load,
    // not refresh)
    if (isLoading && posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // Error state (only show full-screen error when no posts loaded
    // yet). If we have posts but pagination failed, we'll show the error
    // at the bottom
    if (error != null && posts.isEmpty) {
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
                _getUserFriendlyError(error),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Provider.of<FeedProvider>(context, listen: false).retry();
                },
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

    // Empty state
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum, size: 64, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                isAuthenticated ? 'No posts yet' : 'No posts to discover',
                style: const TextStyle(
                  fontSize: 20,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAuthenticated
                    ? 'Subscribe to communities to see posts in your feed'
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
      );
    }

    // Posts list
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        // Add top padding so content isn't hidden behind transparent header
        padding: const EdgeInsets.only(top: _kHeaderContentPadding),
        // Add extra item for loading indicator or pagination error
        itemCount: posts.length + (isLoadingMore || error != null ? 1 : 0),
        itemBuilder: (context, index) {
          // Footer: loading indicator or error message
          if (index == posts.length) {
            // Show loading indicator for pagination
            if (isLoadingMore) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }
            // Show error message for pagination failures
            if (error != null) {
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
                      _getUserFriendlyError(error),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        Provider.of<FeedProvider>(context, listen: false)
                          ..clearError()
                          ..loadMore();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
          }

          final post = posts[index];
          return Semantics(
            label:
                'Feed post in ${post.post.community.name} by '
                '${post.post.author.displayName ?? post.post.author.handle}. '
                '${post.post.title ?? ""}',
            button: true,
            child: PostCard(post: post, currentTime: currentTime),
          );
        },
      ),
    );
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
