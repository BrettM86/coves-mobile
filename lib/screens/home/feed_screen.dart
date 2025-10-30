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
    // Use select to only rebuild when specific fields change
    final isAuthenticated = context.select<AuthProvider, bool>(
      (p) => p.isAuthenticated,
    );
    final feedProvider = Provider.of<FeedProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: Text(isAuthenticated ? 'Feed' : 'Explore'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(child: _buildBody(feedProvider, isAuthenticated)),
    );
  }

  Widget _buildBody(FeedProvider feedProvider, bool isAuthenticated) {
    // Loading state
    if (feedProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      );
    }

    // Error state
    if (feedProvider.error != null) {
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
                feedProvider.error!,
                style: const TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => feedProvider.retry(),
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
    if (feedProvider.posts.isEmpty) {
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
        itemCount:
            feedProvider.posts.length + (feedProvider.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == feedProvider.posts.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
              ),
            );
          }

          final post = feedProvider.posts[index];
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
