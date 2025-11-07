import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/community_handle_utils.dart';
import '../utils/date_time_utils.dart';
import 'external_link_bar.dart';
import 'post_card_actions.dart';

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
                // Community avatar
                _buildCommunityAvatar(post.post.community),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Community handle with styled parts
                      _buildCommunityHandle(post.post.community),
                      // Author handle
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

            // External link (if present)
            if (post.post.embed?.external != null) ...[
              const SizedBox(height: 8),
              ExternalLinkBar(embed: post.post.embed!.external!),
            ],

            // Reduced spacing before action buttons
            const SizedBox(height: 4),

            // Action buttons row
            PostCardActions(post: post),
          ],
        ),
      ),
    );
  }

  /// Builds the community handle with styled parts (name + instance)
  Widget _buildCommunityHandle(CommunityRef community) {
    final displayHandle =
        CommunityHandleUtils.formatHandleForDisplay(community.handle)!;

    // Split the handle into community name and instance
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
              fontSize: 14,
            ),
          ),
          TextSpan(
            text: instancePart,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the community avatar widget
  Widget _buildCommunityAvatar(CommunityRef community) {
    if (community.avatar != null && community.avatar!.isNotEmpty) {
      // Show real community avatar
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: community.avatar!,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallbackAvatar(community),
          errorWidget: (context, url, error) => _buildFallbackAvatar(community),
        ),
      );
    }

    // Fallback to letter placeholder
    return _buildFallbackAvatar(community);
  }

  /// Builds a fallback avatar with the first letter of community name
  Widget _buildFallbackAvatar(CommunityRef community) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          community.name[0].toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
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
