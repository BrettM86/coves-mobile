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
import 'external_link_bar.dart';
import 'fullscreen_video_player.dart';
import 'image_viewer.dart';
import 'post_card_actions.dart';
import 'rich_text_renderer.dart';
import 'source_link_bar.dart';
import 'tappable_author.dart';
import 'tappable_community.dart';

/// Widest and tallest aspect ratios (width/height) the feed will render media
/// at. Clamping keeps a panorama from becoming a sliver and a tall portrait
/// shot from swallowing the whole viewport. The 3:4 floor lets a standard
/// phone-camera portrait through uncropped; only taller shots (9:16
/// screenshots, stories) get center-cropped.
const double _widestMediaRatio = 16 / 9;
const double _tallestMediaRatio = 3 / 4;

/// Resolves the display aspect ratio for an image, clamped to the feed range.
/// Media with no declared ratio renders at the 16:9 ceiling.
double _mediaAspectRatio(EmbedAspectRatio? ratio) {
  if (ratio == null) {
    return _widestMediaRatio;
  }
  return (ratio.width / ratio.height).clamp(
    _tallestMediaRatio,
    _widestMediaRatio,
  );
}

/// Formats a video duration as `m:ss`, switching to `h:mm:ss` from one hour.
///
/// Total function: a negative duration reads as `0:00` rather than throwing,
/// since the value comes from an untrusted record.
String formatVideoDuration(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final paddedSeconds = (total % 60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }
  return '$minutes:$paddedSeconds';
}

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
                    child: _buildCommunityAvatar(post.post.community),
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
                  _EmbedCard(
                    embed: post.post.embed!.external!,
                    streamableService: context.read<StreamableService>(),
                    height: embedHeight,
                    onImageTap:
                        disableNavigation
                            ? null
                            : () => _navigateToDetail(context),
                  ),
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
    final image = embed.images.first;
    final alt = image.alt;

    Widget thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: _mediaAspectRatio(image.aspectRatio),
        child: CachedNetworkImage(
          imageUrl: image.thumb,
          width: double.infinity,
          fit: BoxFit.cover,
          // Disable fade animation to prevent scroll jitter
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => const _MediaPlaceholder(),
          errorWidget:
              (context, url, error) =>
                  const _MediaPlaceholder(icon: Icons.broken_image),
        ),
      ),
    );

    if (alt != null && alt.isNotEmpty) {
      thumbnail = Semantics(image: true, label: alt, child: thumbnail);
    }

    final block = GestureDetector(
      key: const Key('post-images-embed'),
      onTap:
          disableNavigation
              ? null
              : () => ImageViewer.open(context, embed.images),
      child: Stack(
        children: [
          thumbnail,
          if (embed.images.length > 1)
            Positioned(
              top: 8,
              right: 8,
              child: _MediaBadge(
                key: const Key('post-images-count-badge'),
                label: '1/${embed.images.length}',
              ),
            ),
        ],
      ),
    );

    // With navigation off there is nothing to activate, and announcing a
    // button a screen reader cannot use is worse than announcing nothing.
    if (disableNavigation) {
      return block;
    }

    return Semantics(
      // An explicit container: without it this annotation is absorbed into
      // the subtree's node, swallowing the image's alt-text label.
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'View full image',
      child: block,
    );
  }

  /// Builds the video block: thumbnail or dark placeholder, a play overlay,
  /// and the duration when the record carried one.
  Widget _buildVideoEmbed(BuildContext context, VideoPostEmbed embed) {
    final thumbnail = embed.thumbnail;
    final duration = embed.duration;
    final alt = embed.alt;

    Widget surface = AspectRatio(
      aspectRatio: _widestMediaRatio,
      child:
          thumbnail != null
              ? CachedNetworkImage(
                imageUrl: thumbnail,
                width: double.infinity,
                fit: BoxFit.cover,
                // Disable fade animation to prevent scroll jitter
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (context, url) => const _MediaPlaceholder(),
                errorWidget:
                    (context, url, error) =>
                        const _MediaPlaceholder(icon: Icons.broken_image),
              )
              : const _MediaPlaceholder(),
    );

    if (alt != null && alt.isNotEmpty) {
      surface = Semantics(image: true, label: alt, child: surface);
    }

    return Semantics(
      // An explicit container: without it this annotation is absorbed into
      // the subtree's node, and the duration badge's text displaces the
      // label. Any future overlay (mute, GIF chip) would do the same.
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Play video',
      child: GestureDetector(
        key: const Key('post-video-embed'),
        onTap: () => _playVideo(context, embed),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              surface,
              Container(
                key: const Key('post-video-play-overlay'),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: AppColors.textPrimary,
                  size: 48,
                ),
              ),
              if (duration != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _MediaBadge(
                    key: const Key('post-video-duration-badge'),
                    label: formatVideoDuration(duration),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the fullscreen player for a native video embed.
  ///
  /// Pushed synchronously: the embed already carries a playable URL, unlike
  /// the Streamable flow which has to resolve one first. Media plays in place
  /// even when [disableNavigation] is set — it is playback, not navigation.
  void _playVideo(BuildContext context, VideoPostEmbed embed) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => FullscreenVideoPlayer(videoUrl: embed.video),
        fullscreenDialog: true,
      ),
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

  /// Builds the community avatar widget
  Widget _buildCommunityAvatar(CommunityRef community) {
    if (community.avatar != null && community.avatar!.isNotEmpty) {
      // Show real community avatar
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: community.avatar!,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          // Disable fade animation to prevent scroll jitter
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
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
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
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
                if (author.avatar != null && author.avatar!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: author.avatar!,
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      // Disable fade animation to prevent scroll jitter
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder:
                          (context, url) => _buildAuthorFallbackAvatar(author),
                      errorWidget:
                          (context, url, error) =>
                              _buildAuthorFallbackAvatar(author),
                    ),
                  )
                else
                  _buildAuthorFallbackAvatar(author),
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

  /// Builds a fallback avatar for the author
  Widget _buildAuthorFallbackAvatar(AuthorView author) {
    final firstLetter =
        (author.displayName ?? author.handle).isNotEmpty
            ? (author.displayName ?? author.handle)[0]
            : '?';
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          firstLetter.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Neutral dark fill behind feed media: shown while a thumbnail loads, when
/// it fails, and for videos the AppView gave us no thumbnail for.
class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({this.icon});

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundSecondary,
      child:
          icon == null
              ? null
              : Center(
                child: Icon(icon, color: AppColors.textSecondary, size: 32),
              ),
    );
  }
}

/// Small translucent pill overlaying media — the image count and the video
/// duration both use it.
class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
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
  const _EmbedCard({
    required this.embed,
    required this.streamableService,
    this.height = 180,
    this.onImageTap,
  });

  final ExternalEmbed embed;
  final StreamableService streamableService;
  final double height;
  final VoidCallback? onImageTap;

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
    // Hide embed area when no thumbnail available
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
        height: widget.height,
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter from height changes
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder:
            (context, url) => Container(
              width: double.infinity,
              height: widget.height,
              color: AppColors.backgroundSecondary,
              child: const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: AppColors.textSecondary,
                  size: 32,
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
            height: widget.height,
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
      return Semantics(
        button: true,
        // Reflect the disabled tap handler while the video is loading so
        // assistive tech doesn't advertise a dead button
        enabled: !_isLoadingVideo,
        label: 'Play video',
        child: GestureDetector(
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
        ),
      );
    }

    // For non-video embeds (images, link previews), make them tappable
    // to navigate to post detail
    if (widget.onImageTap != null) {
      return GestureDetector(onTap: widget.onImageTap, child: thumbnailWidget);
    }

    // No tap handler provided, just return the thumbnail
    return thumbnailWidget;
  }
}
