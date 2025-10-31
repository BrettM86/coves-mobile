import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feed_provider.dart';
import '../../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(isAuthenticated ? 'Feed' : 'Explore'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _buildBody(
          isLoading: isLoading,
          error: error,
          posts: posts,
          isLoadingMore: isLoadingMore,
          isAuthenticated: isAuthenticated,
          currentTime: currentTime,
        ),
      ),
    );
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
