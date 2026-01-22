import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../services/streamable_service.dart';
import '../utils/date_time_utils.dart';
import '../utils/url_launcher.dart';
import 'bluesky_post_card.dart';
import 'external_link_bar.dart';
import 'fullscreen_video_player.dart';
import 'source_link_bar.dart';
import 'tappable_author.dart';

/// Social media style post detail view inspired by Reddit's clean, content-first design.
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
  // Image carousel state
  int _currentImageIndex = 0;
  final PageController _imagePageController = PageController();

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  /// Determines the content type for layout decisions
  _ContentType get _contentType {
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
            widget.post.post.embed?.blueskyPost != null) ...[
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
    const size = 22.0;

    if (author.avatar != null && author.avatar!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: author.avatar!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => _buildAvatarPlaceholder(author, size),
          errorWidget: (context, url, error) =>
              _buildAvatarPlaceholder(author, size),
        ),
      );
    }

    return _buildAvatarPlaceholder(author, size);
  }

  /// Placeholder avatar with initial
  Widget _buildAvatarPlaceholder(AuthorView author, double size) {
    final initial = (author.displayName ?? author.handle).isNotEmpty
        ? (author.displayName ?? author.handle)[0].toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.inter(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w600,
            color: AppColors.coral,
          ),
        ),
      ),
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

  /// Video player with play button overlay
  Widget _buildVideoPlayer() {
    final embed = widget.post.post.embed!.external!;

    return _VideoEmbed(
      embed: embed,
      streamableService: context.read<StreamableService>(),
    );
  }

  /// Image carousel for multi-image posts with attached link bar
  Widget _buildImageCarousel() {
    final embed = widget.post.post.embed!.external!;
    final images = embed.images ?? [];

    if (images.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
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
                onTap: () => UrlLauncher.launchExternalUrl(
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
                      final imageUrl = image['thumb'] as String? ??
                          image['fullsize'] as String? ??
                          '';

                      if (imageUrl.isEmpty) return _buildImagePlaceholder();

                      return CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => _buildImagePlaceholder(),
                        errorWidget: (context, url, error) =>
                            _buildImagePlaceholder(),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Link bar with page indicator (bottom of card)
            GestureDetector(
              onTap: () => UrlLauncher.launchExternalUrl(
                embed.uri,
                context: context,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    _buildFavicon(embed.uri),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatUrlForDisplay(embed.uri),
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

    if (embed.thumb == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => UrlLauncher.launchExternalUrl(
          embed.uri,
          context: context,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
            ),
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
                  placeholder: (context, url) => Container(
                    height: 220,
                    color: AppColors.backgroundSecondary,
                  ),
                  errorWidget: (context, url, error) => Container(
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
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(7),
                    bottomRight: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    _buildFavicon(embed.uri),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatUrlForDisplay(embed.uri),
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
      child: Text(
        widget.post.post.text,
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
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
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
    if (sources == null || sources.isEmpty) return const SizedBox.shrink();

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
        child: Icon(
          Icons.image_outlined,
          color: AppColors.textMuted,
          size: 40,
        ),
      ),
    );
  }

  /// Formats a URL for display (removes protocol, keeps domain + path start)
  String _formatUrlForDisplay(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final path = uri.path;

      // Combine host and path, removing trailing slash if present
      if (path.isEmpty || path == '/') {
        return host;
      }
      return '$host$path';
    } on FormatException {
      return url;
    }
  }

  /// Builds a favicon widget for the given URL
  Widget _buildFavicon(String url) {
    String? domain;
    try {
      final uri = Uri.parse(url);
      domain = uri.host;
    } on FormatException {
      domain = null;
    }

    if (domain == null || domain.isEmpty) {
      return Icon(
        Icons.link,
        size: 18,
        color: AppColors.textPrimary.withValues(alpha: 0.7),
      );
    }

    final faviconUrl =
        'https://www.google.com/s2/favicons?domain=$domain&sz=32';

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: faviconUrl,
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => Icon(
          Icons.link,
          size: 18,
          color: AppColors.textPrimary.withValues(alpha: 0.7),
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.link,
          size: 18,
          color: AppColors.textPrimary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// Video embed with play button overlay
class _VideoEmbed extends StatefulWidget {
  const _VideoEmbed({required this.embed, required this.streamableService});

  final ExternalEmbed embed;
  final StreamableService streamableService;

  @override
  State<_VideoEmbed> createState() => _VideoEmbedState();
}

class _VideoEmbedState extends State<_VideoEmbed> {
  bool _isLoading = false;

  bool get _isStreamable =>
      widget.embed.provider?.toLowerCase() == 'streamable';

  Future<void> _playVideo() async {
    if (!_isStreamable || widget.embed.thumb == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);

    try {
      final videoUrl =
          await widget.streamableService.getVideoUrl(widget.embed.uri);

      if (!mounted) return;

      if (videoUrl == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not load video',
              style: GoogleFonts.inter(color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.backgroundSecondary,
          ),
        );
        return;
      }

      await navigator.push<void>(
        MaterialPageRoute(
          builder: (context) => FullscreenVideoPlayer(videoUrl: videoUrl),
          fullscreenDialog: true,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embed.thumb == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _isLoading ? null : _playVideo,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video thumbnail - full width
          CachedNetworkImage(
            imageUrl: widget.embed.thumb!,
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (context, url) => Container(
              height: 240,
              color: AppColors.backgroundSecondary,
            ),
            errorWidget: (context, url, error) => Container(
              height: 240,
              color: AppColors.backgroundSecondary,
              child: const Center(
                child: Icon(
                  Icons.broken_image,
                  color: AppColors.textMuted,
                  size: 40,
                ),
              ),
            ),
          ),

          // Darkening overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),

          // Play button - simple and clean
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: AppColors.background,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.background,
                    size: 36,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Content type enum for layout decisions
enum _ContentType {
  video,
  singleImage,
  multiImage,
  link,
  textOnly,
}
