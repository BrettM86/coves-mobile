import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feed_provider.dart';

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
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    feedProvider.loadFeed(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      feedProvider.loadMore();
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
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
  }) {
    // Loading state (only show full-screen loader for initial load, not refresh)
    if (isLoading && posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      );
    }

    // Error state (only show full-screen error when no posts loaded yet)
    // If we have posts but pagination failed, we'll show the error at the bottom
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
                color: Color(0xFFFF6B35),
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load feed',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getUserFriendlyError(error),
                style: const TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final feedProvider = Provider.of<FeedProvider>(
                    context,
                    listen: false,
                  );
                  feedProvider.retry();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
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
              const Icon(Icons.forum, size: 64, color: Color(0xFFFF6B35)),
              const SizedBox(height: 24),
              Text(
                isAuthenticated ? 'No posts yet' : 'No posts to discover',
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAuthenticated
                    ? 'Subscribe to communities to see posts in your feed'
                    : 'Check back later for new posts',
                style: const TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
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
      color: const Color(0xFFFF6B35),
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
                  child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                ),
              );
            }
            // Show error message for pagination failures
            if (error != null) {
              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF6B35)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFFF6B35),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getUserFriendlyError(error),
                      style: const TextStyle(
                        color: Color(0xFFB6C2D2),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        final feedProvider = Provider.of<FeedProvider>(
                          context,
                          listen: false,
                        );
                        feedProvider.clearError();
                        feedProvider.loadMore();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B35),
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
                'Feed post in ${post.post.community.name} by ${post.post.author.displayName ?? post.post.author.handle}. ${post.post.title ?? ""}',
            button: true,
            child: _PostCard(post: post),
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

class _PostCard extends StatelessWidget {

  const _PostCard({required this.post});
  final FeedViewPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F26),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2F36))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Community and author info
            Row(
              children: [
                // Community avatar placeholder
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      post.post.community.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'c/${post.post.community.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Posted by ${post.post.author.displayName ?? post.post.author.handle}',
                        style: const TextStyle(
                          color: Color(0xFFB6C2D2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Post title
            if (post.post.title != null) ...[
              Text(
                post.post.title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Embed (link preview)
            if (post.post.embed?.external != null) ...[
              _EmbedCard(embed: post.post.embed!.external!),
              const SizedBox(height: 12),
            ],

            // Stats row
            Row(
              children: [
                Icon(
                  Icons.arrow_upward,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.post.stats.score}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.comment_outlined,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.post.stats.commentCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbedCard extends StatelessWidget {

  const _EmbedCard({required this.embed});
  final ExternalEmbed embed;

  @override
  Widget build(BuildContext context) {
    // Only show image if thumbnail exists
    if (embed.thumb == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2F36)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: embed.thumb!,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Container(
              width: double.infinity,
              height: 180,
              color: const Color(0xFF1A1F26),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF484F58)),
              ),
            ),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('❌ Image load error: $error');
            debugPrint('URL: $url');
          }
          return Container(
            width: double.infinity,
            height: 180,
            color: const Color(0xFF1A1F26),
            child: const Icon(
              Icons.broken_image,
              color: Color(0xFF484F58),
              size: 48,
            ),
          );
        },
      ),
    );
  }
}
