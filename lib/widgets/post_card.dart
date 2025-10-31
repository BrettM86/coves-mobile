import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/date_time_utils.dart';

/// Post card widget for displaying feed posts
///
/// Displays a post with:
/// - Community and author information
/// - Post title and text content
/// - External embed (link preview with image)
/// - Action buttons (share, comment, like)
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling:
/// - Periodic updates of time strings
/// - Deterministic testing without DateTime.now()
class PostCard extends StatelessWidget {
  const PostCard({required this.post, this.currentTime, super.key});

  final FeedViewPost post;
  final DateTime? currentTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 1),
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
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      post.post.community.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
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
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@${post.post.author.handle}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Time ago
                Text(
                  DateTimeUtils.formatTimeAgo(
                    post.post.createdAt,
                    currentTime: currentTime,
                  ),
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Post title
            if (post.post.title != null) ...[
              Text(
                post.post.title!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],

            // Spacing after title (only if we have content below)
            if (post.post.title != null &&
                (post.post.embed?.external != null ||
                    post.post.text.isNotEmpty))
              const SizedBox(height: 8),

            // Embed (link preview)
            if (post.post.embed?.external != null) ...[
              _EmbedCard(embed: post.post.embed!.external!),
              const SizedBox(height: 8),
            ],

            // Post text body preview
            if (post.post.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  post.post.text,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            // Reduced spacing before action buttons
            const SizedBox(height: 4),

            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Share button
                InkWell(
                  onTap: () {
                    // TODO: Handle share interaction with backend
                    if (kDebugMode) {
                      debugPrint('Share button tapped for post');
                    }
                  },
                  child: Padding(
                    // Increased padding for better touch targets
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Icon(
                      Icons.ios_share,
                      size: 18,
                      color: AppColors.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Comment button
                InkWell(
                  onTap: () {
                    // TODO: Navigate to post detail/comments screen
                    if (kDebugMode) {
                      debugPrint('Comment button tapped for post');
                    }
                  },
                  child: Padding(
                    // Increased padding for better touch targets
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateTimeUtils.formatCount(
                            post.post.stats.commentCount,
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Heart button
                InkWell(
                  onTap: () {
                    // TODO: Handle upvote/like interaction with backend
                    if (kDebugMode) {
                      debugPrint('Heart button tapped for post');
                    }
                  },
                  child: Padding(
                    // Increased padding for better touch targets
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 18,
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateTimeUtils.formatCount(post.post.stats.score),
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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

/// Embed card widget for displaying link previews
///
/// Shows a thumbnail image for external embeds with loading and error states.
class _EmbedCard extends StatelessWidget {
  const _EmbedCard({required this.embed});

  final ExternalEmbed embed;

  @override
  Widget build(BuildContext context) {
    // Only show image if thumbnail exists
    if (embed.thumb == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
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
              color: AppColors.background,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.loadingIndicator,
                ),
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
            color: AppColors.background,
            child: const Icon(
              Icons.broken_image,
              color: AppColors.loadingIndicator,
              size: 48,
            ),
          );
        },
      ),
    );
  }
}
