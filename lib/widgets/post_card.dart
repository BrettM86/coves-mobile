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
import 'bluesky_post_card.dart';
import 'community_avatar.dart';
import 'external_link_bar.dart';
import 'image_viewer.dart';
import 'media/media_surface.dart';
import 'media/native_image_embed.dart';
import 'media/native_video_embed.dart';
import 'media/streamable_video_embed.dart';
import 'post_card_actions.dart';
import 'rich_text_renderer.dart';
import 'source_link_bar.dart';
import 'tappable_author.dart';
import 'tappable_community.dart';
import 'user_avatar.dart';

/// The feed's bordered frame around an external embed's thumbnail.
const BoxDecoration _embedFrame = BoxDecoration(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
);

/// Post card widget for displaying feed posts
///
/// Displays a post with:
/// - Community and author information
/// - Post title and text content
/// - Native image and video embeds
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
    this.showFullText = false,
    this.showAuthorFooter = false,
    this.showSources = false,
    this.textFontSize = 13,
    this.textLineHeight = 1.4,
    this.embedHeight = 180,
    this.titleFontSize = 16,
    this.titleFontWeight = FontWeight.w400,
    super.key,
  });

  final FeedViewPost post;
  final DateTime? currentTime;
  final bool showCommentButton;
  final bool disableNavigation;
  final bool showActions;
  final bool showHeader;
  final bool showBorder;
  final bool showFullText;
  final bool showAuthorFooter;
  final bool showSources;
  final double textFontSize;
  final double textLineHeight;
  final double embedHeight;
  final double titleFontSize;
  final FontWeight titleFontWeight;

  void _navigateToDetail(BuildContext context) {
    // Navigate to post detail screen
    // Use URI-encoded version of the post URI for the URL path
    // Pass the full post object via extras
    final encodedUri = Uri.encodeComponent(post.post.uri);
    context.push('/post/$encodedUri', extra: post);
  }

  @override
  Widget build(BuildContext context) {
    final media = _buildMediaEmbed(context);
    // Everything that can sit under the title and therefore needs the gap
    // after it: native media, either embed card, or the post text.
    final hasContentBelowTitle =
        media != null ||
        post.post.embed?.external != null ||
        post.post.embed?.blueskyPost != null ||
        post.post.text.isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: showHeader ? 8 : 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        border:
            showBorder
                ? const Border(
                  bottom: BorderSide(color: AppColors.borderWarm, width: 0.5),
                )
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
                  // Community avatar (tappable for community navigation)
                  TappableCommunity(
                    communityDid: post.post.community.did,
                    child: CommunityAvatar(
                      name: post.post.community.name,
                      avatarUrl: post.post.community.avatar,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Community handle with styled parts (tappable)
                        TappableCommunity(
                          communityDid: post.post.community.did,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: _buildCommunityHandle(post.post.community),
                        ),
                        // Author handle (tappable for profile navigation)
                        TappableAuthor(
                          authorDid: post.post.author.did,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '@${post.post.author.handle}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
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

            // Post content - title and text are clickable, embed handles
            // its own taps
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author info (shown in detail view, above title)
                if (showAuthorFooter) _buildAuthorFooter(context),

                // Title and text wrapped in InkWell for navigation
                if (!disableNavigation &&
                    (post.post.title != null || post.post.text.isNotEmpty))
                  InkWell(
                    onTap: () => _navigateToDetail(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Post title
                        if (post.post.title != null) ...[
                          Text(
                            post.post.title!,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],

                        // Spacing after title
                        if (post.post.title != null && hasContentBelowTitle)
                          const SizedBox(height: 12),
                      ],
                    ),
                  )
                else
                // Title when navigation is disabled
                if (post.post.title != null) ...[
                  Text(
                    post.post.title!,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (hasContentBelowTitle) const SizedBox(height: 12),
                ],

                // Native image/video embed
                if (media != null) ...[media, const SizedBox(height: 8)],

                // Embed thumbnail
                if (post.post.embed?.external != null) ...[
                  _buildExternalEmbed(context, post.post.embed!.external!),
                  const SizedBox(height: 8),
                ],

                // Bluesky post embed
                if (post.post.embed?.blueskyPost != null) ...[
                  BlueskyPostCard(
                    embed: post.post.embed!.blueskyPost!,
                    currentTime: currentTime,
                  ),
                  const SizedBox(height: 8),
                ],

                // Post text (clickable for navigation)
                if (post.post.text.isNotEmpty) ...[
                  if (!disableNavigation)
                    InkWell(
                      onTap: () => _navigateToDetail(context),
                      child: _buildTextContent(),
                    )
                  else
                    _buildTextContent(),
                ],
              ],
            ),

            // External link (if present)
            if (post.post.embed?.external != null) ...[
              const SizedBox(height: 8),
              ExternalLinkBar(embed: post.post.embed!.external!),
            ],

            // Sources section (for megathreads, shown in detail view)
            if (showSources &&
                post.post.embed?.external?.sources != null &&
                post.post.embed!.external!.sources!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Sources',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ...post.post.embed!.external!.sources!.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SourceLinkBar(source: source),
                ),
              ),
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

  /// Builds the text content with appropriate styling
  Widget _buildTextContent() {
    if (showFullText) {
      // Detail view: no container, better readability
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: RichTextRenderer(
          text: post.post.text,
          facets: post.post.facets,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: textFontSize,
            height: textLineHeight,
          ),
        ),
      );
    } else {
      // Feed view: compact preview with refined container
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: RichTextRenderer(
          text: post.post.text,
          facets: post.post.facets,
          style: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.85),
            fontSize: textFontSize,
            height: textLineHeight,
          ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
  }

  /// Builds the native media block for image and video embeds.
  ///
  /// Returns null when there is nothing renderable — no embed, an unknown
  /// `$type`, or an unhydrated record shape whose blobs never resolved — so
  /// the card falls back to text rather than showing an empty frame.
  Widget? _buildMediaEmbed(BuildContext context) {
    return switch (post.post.embed) {
      final ImagesPostEmbed images => _buildImagesEmbed(context, images),
      final VideoPostEmbed video => _buildVideoEmbed(context, video),
      _ => null,
    };
  }

  /// Builds the images block: the first image at full card width, with a
  /// "1/N" badge when the gallery holds more. Tapping opens the fullscreen
  /// viewer directly — the rest of the card still navigates to the post.
  Widget _buildImagesEmbed(BuildContext context, ImagesPostEmbed embed) {
    return NativeImageThumb(
      images: embed.images,
      keyPrefix: 'post',
      // With navigation off there is nothing to activate, and the block
      // drops its button semantics along with the handler.
      onTap:
          disableNavigation
              ? null
              : () => ImageViewer.open(context, embed.images),
    );
  }

  /// Builds the video block: thumbnail or dark placeholder, a play overlay,
  /// and the duration when the record carried one.
  ///
  /// Media plays in place even when [disableNavigation] is set — it is
  /// playback, not navigation.
  Widget _buildVideoEmbed(BuildContext context, VideoPostEmbed embed) {
    return NativeVideoEmbed(embed: embed, keyPrefix: 'post');
  }

  /// Builds the external embed block: a Streamable poster the user can play
  /// in place, or a plain link thumbnail that opens the post.
  Widget _buildExternalEmbed(BuildContext context, ExternalEmbed embed) {
    if (StreamableVideoEmbed.isStreamableVideo(embed)) {
      return StreamableVideoEmbed(
        embed: embed,
        streamableService: context.read<StreamableService>(),
        height: embedHeight,
        frameDecoration: _embedFrame,
      );
    }

    return _LinkThumbnail(
      embed: embed,
      height: embedHeight,
      onTap: disableNavigation ? null : () => _navigateToDetail(context),
    );
  }

  /// Builds the community handle with styled parts (name + instance)
  Widget _buildCommunityHandle(CommunityRef community) {
    final displayHandle = CommunityHandleUtils.formatHandleForDisplay(
      community.handle,
    );

    // Fallback to raw handle or name if formatting fails
    if (displayHandle == null || !displayHandle.contains('@')) {
      return Text(
        community.handle ?? community.name,
        style: const TextStyle(color: AppColors.communityName, fontSize: 14),
      );
    }

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

  /// Builds author footer with avatar, handle, and timestamp
  Widget _buildAuthorFooter(BuildContext context) {
    final author = post.post.author;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // Author avatar and handle (tappable for profile navigation)
          TappableAuthor(
            authorDid: author.did,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author avatar (circular, small)
                UserAvatar(
                  name: author.displayName ?? author.handle,
                  avatarUrl: author.avatar,
                  size: 20,
                ),
                const SizedBox(width: 8),

                // Author handle
                Text(
                  '@${author.handle}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Timestamp
          Text(
            DateTimeUtils.formatTimeAgo(
              post.post.createdAt,
              currentTime: currentTime,
            ),
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain external-link preview: the embed's thumbnail in the feed's
/// bordered frame, opening the post when tapped.
///
/// Streamable videos take a different path — see [StreamableVideoEmbed],
/// which plays in place instead of navigating.
class _LinkThumbnail extends StatelessWidget {
  const _LinkThumbnail({required this.embed, required this.height, this.onTap});

  final ExternalEmbed embed;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Hide the embed area when there is no thumbnail to show.
    final thumb = embed.thumb;
    if (thumb == null) {
      return const SizedBox.shrink();
    }

    final thumbnail = Container(
      decoration: _embedFrame,
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: thumb,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter from height changes
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder:
            (context, url) => SizedBox(
              width: double.infinity,
              height: height,
              child: const MediaFill(icon: Icons.image_outlined),
            ),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('❌ Image load error: $error');
            debugPrint('URL: $url');
          }
          return Container(
            width: double.infinity,
            height: height,
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

    if (onTap == null) {
      return thumbnail;
    }

    return GestureDetector(onTap: onTap, child: thumbnail);
  }
}
