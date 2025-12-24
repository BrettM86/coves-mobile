import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/bluesky_colors.dart';
import '../models/bluesky_post.dart';
import '../models/post.dart';
import '../utils/date_time_utils.dart';
import '../utils/url_launcher.dart';
import 'bluesky_action_bar.dart';

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

    return BlueskyPostEmbed.getPostWebUrl(resolved, embed.uri) ??
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

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BlueskyColors.cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Avatar, display name, handle, timestamp
            _buildHeader(context, author),
            const SizedBox(height: 8),

            // Post text content
            if (post.text.isNotEmpty) ...[
              Text(
                post.text,
                style: const TextStyle(
                  color: BlueskyColors.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],

            // Media placeholder
            if (post.hasMedia) ...[
              _buildMediaPlaceholder(context, post.mediaCount),
              const SizedBox(height: 8),
            ],

            // Quoted post
            if (post.quotedPost != null) ...[
              _buildQuotedPost(context, post.quotedPost!),
              const SizedBox(height: 8),
            ],

            // Action bar (disabled)
            BlueskyActionBar(
              replyCount: post.replyCount,
              repostCount: post.repostCount,
              likeCount: post.likeCount,
            ),

            const SizedBox(height: 8),

            // "View on Bluesky" footer
            _buildFooterLink(context),
          ],
        ),
      ),
    );
  }

  /// Builds the header row with avatar, name, handle, and timestamp
  Widget _buildHeader(BuildContext context, AuthorView author) {
    return GestureDetector(
      onTap: () {
        UrlLauncher.launchExternalUrl(_getProfileUrl(), context: context);
      },
      child: Row(
        children: [
          _buildAvatar(author),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.displayName ?? author.handle,
                  style: const TextStyle(
                    color: BlueskyColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '@${author.handle}',
                  style: const TextStyle(
                    color: BlueskyColors.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            DateTimeUtils.formatTimeAgo(
              embed.resolved!.createdAt,
              currentTime: currentTime,
            ),
            style: const TextStyle(
              color: BlueskyColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the avatar widget with fallback
  Widget _buildAvatar(AuthorView author) {
    final avatarUrl = author.avatar;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallbackAvatar(author),
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              debugPrint('Bluesky avatar load error: $error');
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: BlueskyColors.blueskyBlue,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: BlueskyColors.textPrimary,
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

    return GestureDetector(
      onTap: () {
        UrlLauncher.launchExternalUrl(_getPostUrl(), context: context);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: BlueskyColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BlueskyColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.image_outlined,
              size: 16,
              color: BlueskyColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mediaText,
                style: const TextStyle(
                  color: BlueskyColors.textSecondary,
                  fontSize: 13,
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
      ),
    );
  }

  /// Builds the quoted post card (nested)
  Widget _buildQuotedPost(BuildContext context, BlueskyPostResult quotedPost) {
    return GestureDetector(
      onTap: () {
        // Open the quoted post on Bluesky
        final url =
            BlueskyPostEmbed.getPostWebUrl(quotedPost, quotedPost.uri) ??
            BlueskyPostEmbed.getProfileUrl(quotedPost.author.handle);
        UrlLauncher.launchExternalUrl(url, context: context);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: BlueskyColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BlueskyColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSmallAvatar(quotedPost.author),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quotedPost.author.displayName ?? quotedPost.author.handle,
                    style: const TextStyle(
                      color: BlueskyColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Quoted post text
            if (quotedPost.text.isNotEmpty)
              Text(
                quotedPost.text,
                style: const TextStyle(
                  color: BlueskyColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
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
              debugPrint('Bluesky quoted post avatar load error: $error');
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
        color: BlueskyColors.blueskyBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: BlueskyColors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Builds the "View on Bluesky" footer link
  Widget _buildFooterLink(BuildContext context) {
    return GestureDetector(
      onTap: () {
        UrlLauncher.launchExternalUrl(_getPostUrl(), context: context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: BlueskyColors.background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 14, color: BlueskyColors.blueskyBlue),
            SizedBox(width: 4),
            Text(
              'View on Bluesky',
              style: TextStyle(
                color: BlueskyColors.blueskyBlue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the unavailable post card
  Widget _buildUnavailableCard() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BlueskyColors.cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'This post is no longer available',
            style: TextStyle(
              color: BlueskyColors.textSecondary,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}
