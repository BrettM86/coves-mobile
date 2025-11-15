import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../services/streamable_service.dart';
import '../utils/community_handle_utils.dart';
import '../utils/date_time_utils.dart';
import 'external_link_bar.dart';
import 'fullscreen_video_player.dart';
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
  const PostCard({
    required this.post,
    this.currentTime,
    this.showCommentButton = true,
    this.disableNavigation = false,
    this.showActions = true,
    this.showHeader = true,
    this.showBorder = true,
    super.key,
  });

  final FeedViewPost post;
  final DateTime? currentTime;
  final bool showCommentButton;
  final bool disableNavigation;
  final bool showActions;
  final bool showHeader;
  final bool showBorder;

  /// Check if this post should be clickable
  /// Only text posts (no embeds or non-video/link embeds) are
  /// clickable
  bool get _isClickable {
    // If navigation is explicitly disabled (e.g., on detail screen),
    // not clickable
    if (disableNavigation) {
      return false;
    }

    final embed = post.post.embed;

    // If no embed, it's a text-only post - clickable
    if (embed == null) {
      return true;
    }

    // If embed exists, check if it's a video or link type
    final external = embed.external;
    if (external == null) {
      return true; // No external embed, clickable
    }

    final embedType = external.embedType;

    // Video and video-stream posts should NOT be clickable (they have
    // their own tap handling)
    if (embedType == 'video' || embedType == 'video-stream') {
      return false;
    }

    // Link embeds should NOT be clickable (they have their own link handling)
    if (embedType == 'link') {
      return false;
    }

    // All other types are clickable
    return true;
  }

  void _navigateToDetail(BuildContext context) {
    // Navigate to post detail screen
    // Use URI-encoded version of the post URI for the URL path
    // Pass the full post object via extras
    final encodedUri = Uri.encodeComponent(post.post.uri);
    context.push('/post/$encodedUri', extra: post);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: showHeader ? 8 : 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        border:
            showBorder
                ? const Border(bottom: BorderSide(color: AppColors.border))
                : null,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, showHeader ? 4 : 12, 16, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Community and author info
            if (showHeader) ...[
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
            ],

            // Wrap content in InkWell if clickable (text-only posts)
            if (_isClickable)
              InkWell(
                onTap: () => _navigateToDetail(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    // Spacing after title (only if we have text)
                    if (post.post.title != null && post.post.text.isNotEmpty)
                      const SizedBox(height: 8),

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
                  ],
                ),
              )
            else
              // Non-clickable content (video/link posts)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    _EmbedCard(
                      embed: post.post.embed!.external!,
                      streamableService: context.read<StreamableService>(),
                    ),
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
                ],
              ),

            // External link (if present)
            if (post.post.embed?.external != null) ...[
              const SizedBox(height: 8),
              ExternalLinkBar(embed: post.post.embed!.external!),
            ],

            // Reduced spacing before action buttons
            if (showActions) const SizedBox(height: 4),

            // Action buttons row
            if (showActions)
              PostCardActions(post: post, showCommentButton: showCommentButton),
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
/// For video embeds (Streamable), displays a play button overlay and opens
/// a video player dialog when tapped.
class _EmbedCard extends StatefulWidget {
  const _EmbedCard({required this.embed, required this.streamableService});

  final ExternalEmbed embed;
  final StreamableService streamableService;

  @override
  State<_EmbedCard> createState() => _EmbedCardState();
}

class _EmbedCardState extends State<_EmbedCard> {
  bool _isLoadingVideo = false;

  /// Checks if this embed is a video
  bool get _isVideo {
    final embedType = widget.embed.embedType;
    return embedType == 'video' || embedType == 'video-stream';
  }

  /// Checks if this is a Streamable video
  bool get _isStreamableVideo {
    return _isVideo && widget.embed.provider?.toLowerCase() == 'streamable';
  }

  /// Shows the video player in fullscreen with swipe-to-dismiss
  Future<void> _showVideoPlayer(BuildContext context) async {
    // Capture context-dependent objects before async gap
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      // Fetch the MP4 URL from Streamable using the injected service
      final videoUrl = await widget.streamableService.getVideoUrl(
        widget.embed.uri,
      );

      if (!mounted) {
        return;
      }

      if (videoUrl == null) {
        // Show error if we couldn't get the video URL
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load video',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.9),
              ),
            ),
            backgroundColor: AppColors.backgroundSecondary,
          ),
        );
        return;
      }

      // Navigate to fullscreen video player
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (context) => FullscreenVideoPlayer(videoUrl: videoUrl),
          fullscreenDialog: true,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show image if thumbnail exists
    if (widget.embed.thumb == null) {
      return const SizedBox.shrink();
    }

    // Build the thumbnail image
    final thumbnailWidget = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: widget.embed.thumb!,
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

    // If this is a Streamable video, add play button overlay and tap handler
    if (_isStreamableVideo) {
      return GestureDetector(
        onTap: _isLoadingVideo ? null : () => _showVideoPlayer(context),
        child: Stack(
          alignment: Alignment.center,
          children: [
            thumbnailWidget,
            // Semi-transparent play button or loading indicator overlay
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child:
                  _isLoadingVideo
                      ? const CircularProgressIndicator(
                        color: AppColors.loadingIndicator,
                      )
                      : const Icon(
                        Icons.play_arrow,
                        color: AppColors.textPrimary,
                        size: 48,
                      ),
            ),
          ],
        ),
      );
    }

    // For non-video embeds, just return the thumbnail
    return thumbnailWidget;
  }
}
