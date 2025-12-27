import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/bluesky_colors.dart';
import '../constants/bluesky_icons.dart';
import '../models/bluesky_post.dart';
import '../models/post.dart';
import '../utils/date_time_utils.dart';
import '../utils/url_launcher.dart';

/// Bluesky post card widget for displaying Bluesky crossposts
///
/// Renders a Bluesky post embed with:
/// - User avatar and profile information (tappable to view on bsky.app)
/// - Post text content with overflow handling
/// - Media indicators for images/videos
/// - Quoted posts (nested cards)
/// - Read-only engagement metrics
/// - "View on Bluesky" footer link
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling periodic updates and deterministic testing.
class BlueskyPostCard extends StatelessWidget {
  const BlueskyPostCard({required this.embed, this.currentTime, super.key});

  static const _blueskyBaseUrl = 'https://bsky.app';

  final BlueskyPostEmbed embed;
  final DateTime? currentTime;

  /// Constructs the Bluesky post URL
  String _getPostUrl() {
    final resolved = embed.resolved;
    if (resolved == null) {
      return _blueskyBaseUrl;
    }

    // Use resolved.uri (the actual post URI) instead of embed.uri
    return BlueskyPostEmbed.getPostWebUrl(resolved, resolved.uri) ??
        BlueskyPostEmbed.getProfileUrl(resolved.author.handle);
  }

  /// Constructs the Bluesky profile URL
  String _getProfileUrl() {
    final handle = embed.resolved?.author.handle;
    if (handle == null || handle.isEmpty) {
      return _blueskyBaseUrl;
    }
    return BlueskyPostEmbed.getProfileUrl(handle);
  }

  @override
  Widget build(BuildContext context) {
    // Handle unavailable posts
    if (embed.resolved == null) {
      return _buildUnavailableCard();
    }

    final post = embed.resolved!;
    final author = post.author;

    // Card matching Bluesky's dim theme
    return GestureDetector(
      onTap: () {
        UrlLauncher.launchExternalUrl(_getPostUrl(), context: context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: BlueskyColors.cardBackground,
          borderRadius: BorderRadius.circular(BlueskyColors.innerBorderRadius),
          border: Border.all(color: BlueskyColors.cardBorder),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Avatar, display name, handle
            _buildHeader(context, author),
            const SizedBox(height: 8),

            // Post text content (no truncation - Bluesky posts are max 300 chars)
            if (post.text.isNotEmpty) ...[
              Text(
                post.text,
                style: const TextStyle(
                  color: BlueskyColors.textPrimary,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Media placeholder
            if (post.hasMedia) ...[
              _buildMediaPlaceholder(context, post.mediaCount),
              const SizedBox(height: 8),
            ],

            // External link embed (link card)
            if (post.embed != null) ...[
              _buildExternalEmbed(context, post.embed!),
              const SizedBox(height: 8),
            ],

            // Quoted post
            if (post.quotedPost != null) ...[
              _buildQuotedPost(context, post.quotedPost!),
              const SizedBox(height: 8),
            ],

            // Timestamp row
            const SizedBox(height: 4),
            _buildTimestampRow(context, post),

            // Likes count (if any)
            if (post.likeCount > 0) ...[
              const SizedBox(height: 12),
              _buildLikesCount(post.likeCount),
            ],

            // Action bar
            const SizedBox(height: 12),
            _buildActionBar(post),
          ],
        ),
      ),
    );
  }

  /// Builds the timestamp row with date/time
  Widget _buildTimestampRow(BuildContext context, BlueskyPostResult post) {
    return Text(
      DateTimeUtils.formatFullDateTime(post.createdAt),
      style: const TextStyle(
        color: BlueskyColors.textSecondary,
        fontSize: 13,
      ),
    );
  }

  /// Builds the likes count display (e.g., "3 likes")
  Widget _buildLikesCount(int likeCount) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: BlueskyColors.cardBorder),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$likeCount',
            style: const TextStyle(
              color: BlueskyColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'likes',
            style: TextStyle(
              color: BlueskyColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the action bar with Bluesky icons
  Widget _buildActionBar(BlueskyPostResult post) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: BlueskyColors.cardBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Reply
          _buildActionWithSvg(
            BlueskyIcons.reply(size: 18, color: BlueskyColors.actionColor),
            post.replyCount,
          ),
          // Repost
          _buildActionWithSvg(
            BlueskyIcons.repost(size: 18, color: BlueskyColors.actionColor),
            post.repostCount,
          ),
          // Like
          _buildActionWithSvg(
            BlueskyIcons.like(size: 18, color: BlueskyColors.actionColor),
            post.likeCount,
          ),
          // Bookmark (keep Material icon for now)
          _buildActionIcon(Icons.bookmark_border, null),
          // Share/More (keep Material icon for now)
          _buildActionIcon(Icons.more_horiz, null),
        ],
      ),
    );
  }

  /// Builds an action item with SVG icon and optional count
  Widget _buildActionWithSvg(Widget icon, int? count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        if (count != null && count > 0) ...[
          const SizedBox(width: 4),
          Text(
            DateTimeUtils.formatCount(count),
            style: const TextStyle(
              color: BlueskyColors.actionColor,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  /// Builds a single action icon with optional count (for Material icons)
  Widget _buildActionIcon(IconData icon, int? count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: BlueskyColors.actionColor),
        if (count != null && count > 0) ...[
          const SizedBox(width: 4),
          Text(
            DateTimeUtils.formatCount(count),
            style: const TextStyle(
              color: BlueskyColors.actionColor,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  /// Builds the header row with avatar, name, handle, and Bluesky logo
  Widget _buildHeader(BuildContext context, AuthorView author) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar and author info (tappable to profile)
        Expanded(
          child: GestureDetector(
            onTap: () {
              UrlLauncher.launchExternalUrl(_getProfileUrl(), context: context);
            },
            child: Row(
              children: [
                _buildAvatar(author),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.displayName?.trim() ?? author.handle,
                        style: const TextStyle(
                          color: BlueskyColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${author.handle}',
                        style: const TextStyle(
                          color: BlueskyColors.textSecondary,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bluesky logo
        const SizedBox(width: 8),
        BlueskyIcons.logo(size: 24, color: BlueskyColors.blueskyBlue),
      ],
    );
  }

  /// Builds the avatar widget with fallback
  Widget _buildAvatar(AuthorView author) {
    final avatarUrl = author.avatar;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallbackAvatar(author),
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              debugPrint('Failed to load avatar from $url: $error');
            }
            return _buildFallbackAvatar(author);
          },
        ),
      );
    }

    return _buildFallbackAvatar(author);
  }

  /// Builds a fallback avatar with the first letter of display name or handle
  Widget _buildFallbackAvatar(AuthorView author) {
    final text = author.displayName ?? author.handle;
    final firstLetter = text.isNotEmpty ? text[0].toUpperCase() : '?';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: BlueskyColors.avatarFallback,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: BlueskyColors.textSecondary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Builds the media placeholder for images
  Widget _buildMediaPlaceholder(BuildContext context, int mediaCount) {
    final mediaText =
        mediaCount == 1 ? 'Contains 1 image' : 'Contains $mediaCount images';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BlueskyColors.cardBorder.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BlueskyColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.image_outlined,
            size: 18,
            color: BlueskyColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mediaText,
              style: const TextStyle(
                color: BlueskyColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const Icon(
            Icons.open_in_new,
            size: 14,
            color: BlueskyColors.textSecondary,
          ),
        ],
      ),
    );
  }

  /// Builds the external link embed card (link preview)
  Widget _buildExternalEmbed(BuildContext context, BlueskyExternalEmbed embed) {
    return GestureDetector(
      onTap: () {
        UrlLauncher.launchExternalUrl(embed.uri, context: context);
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BlueskyColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (if available)
            if (embed.thumb != null && embed.thumb!.isNotEmpty)
              AspectRatio(
                aspectRatio: 1200 / 630, // Standard OG image ratio
                child: CachedNetworkImage(
                  imageUrl: embed.thumb!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: BlueskyColors.cardBorder.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: BlueskyColors.textSecondary,
                        size: 32,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: BlueskyColors.cardBorder.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: BlueskyColors.textSecondary,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Domain
                  Text(
                    embed.domain,
                    style: const TextStyle(
                      color: BlueskyColors.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Title
                  if (embed.title != null && embed.title!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      embed.title!,
                      style: const TextStyle(
                        color: BlueskyColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Description
                  if (embed.description != null &&
                      embed.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      embed.description!,
                      style: const TextStyle(
                        color: BlueskyColors.textSecondary,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the quoted post card (nested)
  Widget _buildQuotedPost(BuildContext context, BlueskyPostResult quotedPost) {
    // Handle unavailable quoted posts (blocked, deleted, detached)
    if (quotedPost.unavailable) {
      return _buildUnavailableQuotedPost(quotedPost);
    }

    final timeAgo = DateTimeUtils.formatTimeAgo(
      quotedPost.createdAt,
      currentTime: currentTime,
    );

    return GestureDetector(
      onTap: () {
        // Open the quoted post on Bluesky
        final url =
            BlueskyPostEmbed.getPostWebUrl(quotedPost, quotedPost.uri) ??
            BlueskyPostEmbed.getProfileUrl(quotedPost.author.handle);
        UrlLauncher.launchExternalUrl(url, context: context);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BlueskyColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSmallAvatar(quotedPost.author),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    quotedPost.author.displayName?.trim() ??
                        quotedPost.author.handle,
                    style: const TextStyle(
                      color: BlueskyColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '@${quotedPost.author.handle}',
                    style: const TextStyle(
                      color: BlueskyColors.textSecondary,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '· $timeAgo',
                  style: const TextStyle(
                    color: BlueskyColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Quoted post text (no truncation - Bluesky posts are max 300 chars)
            if (quotedPost.text.isNotEmpty) ...[
              Text(
                quotedPost.text,
                style: const TextStyle(
                  color: BlueskyColors.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (quotedPost.hasMedia || quotedPost.embed != null)
                const SizedBox(height: 8),
            ],

            // Media placeholder in quoted post
            if (quotedPost.hasMedia) ...[
              _buildMediaPlaceholder(context, quotedPost.mediaCount),
              if (quotedPost.embed != null) const SizedBox(height: 8),
            ],

            // External link embed in quoted post
            if (quotedPost.embed != null)
              _buildExternalEmbed(context, quotedPost.embed!),
          ],
        ),
      ),
    );
  }

  /// Builds an unavailable quoted post card (blocked, deleted, detached)
  Widget _buildUnavailableQuotedPost(BlueskyPostResult quotedPost) {
    final message =
        quotedPost.message ?? 'Post not found, it may have been deleted.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BlueskyColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.block,
            size: 16,
            color: BlueskyColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: BlueskyColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a small avatar widget with fallback for quoted posts
  Widget _buildSmallAvatar(AuthorView author) {
    final avatarUrl = author.avatar;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildSmallFallbackAvatar(author),
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              debugPrint('Failed to load avatar from $url: $error');
            }
            return _buildSmallFallbackAvatar(author);
          },
        ),
      );
    }

    return _buildSmallFallbackAvatar(author);
  }

  /// Builds a small fallback avatar for quoted posts
  Widget _buildSmallFallbackAvatar(AuthorView author) {
    final text = author.displayName ?? author.handle;
    final firstLetter = text.isNotEmpty ? text[0].toUpperCase() : '?';

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: BlueskyColors.avatarFallback,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: BlueskyColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Builds the unavailable post card
  Widget _buildUnavailableCard() {
    // Use specific message from resolved embed if available, otherwise generic
    final message =
        embed.resolved?.message ?? 'Post not found, it may have been deleted.';

    return Container(
      decoration: BoxDecoration(
        color: BlueskyColors.cardBackground,
        borderRadius: BorderRadius.circular(BlueskyColors.innerBorderRadius),
        border: Border.all(color: BlueskyColors.cardBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bluesky logo row (matching regular post header alignment)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BlueskyIcons.logo(size: 24, color: BlueskyColors.blueskyBlue),
            ],
          ),
          // Centered message
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              message,
              style: const TextStyle(
                color: BlueskyColors.textSecondary,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
