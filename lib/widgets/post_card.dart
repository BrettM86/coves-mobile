import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/reply_icon.dart';
import 'icons/share_icon.dart';

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
class PostCard extends StatefulWidget {
  const PostCard({required this.post, this.currentTime, super.key});

  final FeedViewPost post;
  final DateTime? currentTime;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isLiked = false;

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
                      widget.post.post.community.name[0].toUpperCase(),
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
                        'c/${widget.post.post.community.name}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@${widget.post.post.author.handle}',
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
                    widget.post.post.createdAt,
                    currentTime: widget.currentTime,
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
            if (widget.post.post.title != null) ...[
              Text(
                widget.post.post.title!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],

            // Spacing after title (only if we have content below)
            if (widget.post.post.title != null &&
                (widget.post.post.embed?.external != null ||
                    widget.post.post.text.isNotEmpty))
              const SizedBox(height: 8),

            // Embed (link preview)
            if (widget.post.post.embed?.external != null) ...[
              _EmbedCard(embed: widget.post.post.embed!.external!),
              const SizedBox(height: 8),
            ],

            // Post text body preview
            if (widget.post.post.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.post.post.text,
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
                    child: ShareIcon(
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
                        ReplyIcon(
                          size: 18,
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateTimeUtils.formatCount(
                            widget.post.post.stats.commentCount,
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
                    setState(() {
                      _isLiked = !_isLiked;
                    });
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
                        AnimatedHeartIcon(
                          isLiked: _isLiked,
                          size: 18,
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                          likedColor: const Color(0xFFFF0033), // Bright red
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateTimeUtils.formatCount(widget.post.post.stats.score),
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
