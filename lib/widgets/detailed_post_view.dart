import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../services/streamable_service.dart';
import '../utils/date_time_utils.dart';
import '../utils/url_display.dart';
import '../utils/url_launcher.dart';
import 'bluesky_post_card.dart';
import 'external_link_bar.dart';
import 'image_viewer.dart';
import 'media/favicon.dart';
import 'media/media_aspect.dart';
import 'media/media_surface.dart';
import 'media/native_image_embed.dart';
import 'media/native_video_embed.dart';
import 'media/streamable_video_embed.dart';
import 'rich_text_renderer.dart';
import 'source_link_bar.dart';
import 'tappable_author.dart';
import 'user_avatar.dart';

/// Social media style post detail view inspired by Reddit's clean,
/// content-first design.
///
/// Features:
/// - Compact author row with avatar, handle, and timestamp
/// - Content-first layout with minimal decoration
/// - Full-width media that fills available space
/// - Clean sans-serif typography throughout
/// - Subtle card backgrounds for embedded content
class DetailedPostView extends StatefulWidget {
  const DetailedPostView({
    required this.post,
    this.currentTime,
    this.showSources = true,
    super.key,
  });

  final FeedViewPost post;
  final DateTime? currentTime;
  final bool showSources;

  @override
  State<DetailedPostView> createState() => _DetailedPostViewState();
}

class _DetailedPostViewState extends State<DetailedPostView> {
  // External-embed carousel state. The native gallery owns its own
  // controller (see NativeImageGallery); this pair belongs to the legacy
  // external#view carousel only.
  int _currentImageIndex = 0;
  final PageController _imagePageController = PageController();

  @override
  void didUpdateWidget(DetailedPostView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // This State is reused when the same slot renders a different post, so
    // carousel position has to be rewound by hand. Resetting the index alone
    // is not enough: the controller would keep the previous post's page on
    // screen while the indicator and the tap target both said page one.
    if (oldWidget.post.post.uri != widget.post.post.uri) {
      _currentImageIndex = 0;
      if (_imagePageController.hasClients) {
        _imagePageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  /// Whether the post carries a native (images/video) embed to render.
  bool get _hasNativeMedia {
    final embed = widget.post.post.embed;
    return embed is ImagesPostEmbed || embed is VideoPostEmbed;
  }

  /// Determines the content type for layout decisions
  _ContentType get _contentType {
    // Native embeds are self-describing, so they short-circuit the
    // heuristics below, which exist only to classify external link cards.
    final nativeEmbed = widget.post.post.embed;
    if (nativeEmbed is ImagesPostEmbed) {
      return nativeEmbed.images.length > 1
          ? _ContentType.nativeGallery
          : _ContentType.nativeSingleImage;
    }
    if (nativeEmbed is VideoPostEmbed) {
      return _ContentType.nativeVideo;
    }

    final embed = widget.post.post.embed?.external;
    if (embed == null) {
      return _ContentType.textOnly;
    }

    final embedType = embed.embedType?.toLowerCase();
    if (embedType == 'video' || embedType == 'video-stream') {
      return _ContentType.video;
    }

    if (embed.images != null && embed.images!.length > 1) {
      return _ContentType.multiImage;
    }

    if (embed.thumb != null) {
      return _ContentType.singleImage;
    }

    return _ContentType.link;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author row - compact Reddit-style
        _buildAuthorRow(),

        // Title - prominent but clean
        if (widget.post.post.title != null) ...[
          const SizedBox(height: 12),
          _buildTitle(),
        ],

        // Media section - full width, content-first
        if (widget.post.post.embed?.external != null ||
            widget.post.post.embed?.blueskyPost != null ||
            _hasNativeMedia) ...[
          const SizedBox(height: 12),
          _buildMediaSection(),
        ],

        // Post text - clean and readable
        if (widget.post.post.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildBodyText(),
        ],

        // External link bar
        if (widget.post.post.embed?.external != null) ...[
          const SizedBox(height: 12),
          _buildExternalLink(),
        ],

        // Bluesky post embed
        if (widget.post.post.embed?.blueskyPost != null) ...[
          const SizedBox(height: 12),
          BlueskyPostCard(
            embed: widget.post.post.embed!.blueskyPost!,
            currentTime: widget.currentTime,
          ),
        ],

        // Sources section
        if (widget.showSources) _buildSourcesSection(),
      ],
    );
  }

  /// Reddit-style author row: avatar • @handle • time
  Widget _buildAuthorRow() {
    final author = widget.post.post.author;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TappableAuthor(
        authorDid: author.did,
        child: Row(
          children: [
            // Small circular avatar
            _buildAvatar(author),
            const SizedBox(width: 8),

            // Handle with @ prefix - always shown in muted grey
            Text(
              '@${author.handle}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),

            // Dot separator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '•',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),

            // Time ago
            Text(
              DateTimeUtils.formatTimeAgo(
                widget.post.post.createdAt,
                currentTime: widget.currentTime,
              ),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small circular avatar
  Widget _buildAvatar(AuthorView author) {
    return UserAvatar(
      name: author.displayName ?? author.handle,
      avatarUrl: author.avatar,
      size: 22,
    );
  }

  /// Title - slightly larger than body, not oversized
  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        widget.post.post.title!,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          height: 1.35,
        ),
      ),
    );
  }

  /// Main media section based on content type
  Widget _buildMediaSection() {
    switch (_contentType) {
      case _ContentType.nativeSingleImage:
        return _buildNativeSingleImage();
      case _ContentType.nativeGallery:
        return _buildNativeGallery();
      case _ContentType.nativeVideo:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NativeVideoEmbed(
            embed: widget.post.post.embed! as VideoPostEmbed,
            keyPrefix: 'detail',
            playChipStyle: PlayChipStyle.detail,
            fill: kDetailMediaFill,
          ),
        );
      case _ContentType.video:
        return _buildVideoPlayer();
      case _ContentType.multiImage:
        return _buildImageCarousel();
      case _ContentType.singleImage:
        return _buildSingleImage();
      case _ContentType.link:
      case _ContentType.textOnly:
        return const SizedBox.shrink();
    }
  }

  /// Native single image: full card width at its own aspect ratio, tapping
  /// opens the zoomable viewer.
  Widget _buildNativeSingleImage() {
    final embed = widget.post.post.embed! as ImagesPostEmbed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: NativeImageThumb(
        images: embed.images,
        keyPrefix: 'detail',
        bounds: kDetailRatioBounds,
        source: MediaImageSource.fullsize,
        fill: kDetailMediaFill,
        onTap: () => ImageViewer.open(context, embed.images),
      ),
    );
  }

  /// Native gallery: a swipeable carousel of fullsize images with an i/N
  /// indicator. No link bar — a native gallery has no uri to open.
  Widget _buildNativeGallery() {
    final embed = widget.post.post.embed! as ImagesPostEmbed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: NativeImageGallery(
        images: embed.images,
        keyPrefix: 'detail',
        onOpen:
            (index) =>
                ImageViewer.open(context, embed.images, initialIndex: index),
      ),
    );
  }

  /// Video player with play button overlay
  Widget _buildVideoPlayer() {
    final embed = widget.post.post.embed!.external!;

    return StreamableVideoEmbed(
      embed: embed,
      streamableService: context.read<StreamableService>(),
      height: 240,
      darken: true,
      playChipStyle: PlayChipStyle.detail,
    );
  }

  /// Image carousel for multi-image posts with attached link bar
  Widget _buildImageCarousel() {
    final embed = widget.post.post.embed!.external!;
    final images = embed.images ?? [];

    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            // Images carousel (top of card)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              child: GestureDetector(
                onTap:
                    () => UrlLauncher.launchExternalUrl(
                      embed.uri,
                      context: context,
                    ),
                child: SizedBox(
                  height: 300,
                  child: PageView.builder(
                    controller: _imagePageController,
                    onPageChanged: (index) {
                      setState(() => _currentImageIndex = index);
                    },
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final image = images[index];
                      final imageUrl =
                          image['thumb'] as String? ??
                          image['fullsize'] as String? ??
                          '';

                      if (imageUrl.isEmpty) {
                        return _buildImagePlaceholder();
                      }

                      return CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => _buildImagePlaceholder(),
                        errorWidget:
                            (context, url, error) => _buildImagePlaceholder(),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Link bar with page indicator (bottom of card)
            GestureDetector(
              onTap:
                  () => UrlLauncher.launchExternalUrl(
                    embed.uri,
                    context: context,
                  ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    Favicon(embed.uri, domain: embed.domain),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hostAndPath(embed.uri),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textPrimary.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Page counter (if multiple images)
                    if (images.length > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_currentImageIndex + 1}/${images.length}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: AppColors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Single full-width image with attached link bar
  Widget _buildSingleImage() {
    final embed = widget.post.post.embed!.external!;

    if (embed.thumb == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => UrlLauncher.launchExternalUrl(embed.uri, context: context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image (top of card)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
                child: CachedNetworkImage(
                  imageUrl: embed.thumb!,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder:
                      (context, url) => Container(
                        height: 220,
                        color: AppColors.backgroundSecondary,
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        height: 220,
                        color: AppColors.backgroundSecondary,
                        child: const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textMuted,
                            size: 40,
                          ),
                        ),
                      ),
                ),
              ),

              // Link bar (bottom of card)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    Favicon(embed.uri, domain: embed.domain),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hostAndPath(embed.uri),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textPrimary.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: AppColors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clean body text
  Widget _buildBodyText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RichTextRenderer(
        text: widget.post.post.text,
        facets: widget.post.post.facets,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary.withValues(alpha: 0.95),
          height: 1.5,
        ),
      ),
    );
  }

  /// External link bar in a subtle card
  Widget _buildExternalLink() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ExternalLinkBar(embed: widget.post.post.embed!.external!),
        ),
      ),
    );
  }

  /// Sources section for megathreads
  Widget _buildSourcesSection() {
    final sources = widget.post.post.embed?.external?.sources;
    if (sources == null || sources.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Sources',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Source links
          ...sources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SourceLinkBar(source: source),
            ),
          ),
        ],
      ),
    );
  }

  /// Image placeholder
  Widget _buildImagePlaceholder() {
    return Container(
      height: 280,
      color: AppColors.backgroundSecondary,
      child: const Center(
        child: Icon(Icons.image_outlined, color: AppColors.textMuted, size: 40),
      ),
    );
  }
}

/// Content type enum for layout decisions
enum _ContentType {
  nativeSingleImage,
  nativeGallery,
  nativeVideo,
  video,
  singleImage,
  multiImage,
  link,
  textOnly,
}
