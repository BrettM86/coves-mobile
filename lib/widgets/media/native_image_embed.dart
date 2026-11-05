import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import 'gif_player.dart';
import 'image_error.dart';
import 'media_aspect.dart';
import 'media_page_dots.dart';
import 'media_surface.dart';
import 'play_chip.dart';

/// Which rendering of a hydrated image to fetch: the feed-sized `thumb` or
/// the lightbox-sized `fullsize`.
enum MediaImageSource { thumb, fullsize }

/// A media block that may or may not be activatable.
///
/// When [onTap] is null the button semantics are omitted entirely: a screen
/// reader announcing a button that does nothing is worse than announcing
/// nothing at all. The block keeps its [mediaKey] either way, so the surface
/// stays addressable.
class TappableMedia extends StatelessWidget {
  const TappableMedia({
    required this.mediaKey,
    required this.label,
    required this.child,
    this.onTap,
    super.key,
  });

  final Key mediaKey;
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final block = GestureDetector(key: mediaKey, onTap: onTap, child: child);

    if (onTap == null) {
      return block;
    }

    return Semantics(
      // An explicit container: without it this annotation is absorbed into
      // the subtree's node, swallowing the image's alt-text label.
      container: true,
      explicitChildNodes: true,
      button: true,
      label: label,
      child: block,
    );
  }
}

/// The head image of a native gallery, at full block width.
///
/// The feed card and the detail view use it for a single image; the Bluesky
/// embed card renders its images this way with a "1/N" badge when there are
/// more. [keyPrefix] namespaces the widget keys (`post-`, `detail-`,
/// `bluesky-`).
///
/// [images] must be non-empty: this widget renders `images.first`. Callers
/// get that for free from `ImagesPostEmbed`, whose constructor rejects an
/// empty gallery; the assert catches any other source of the list.
class NativeImageThumb extends StatelessWidget {
  const NativeImageThumb({
    required this.images,
    required this.keyPrefix,
    this.bounds = kFeedRatioBounds,
    this.source = MediaImageSource.thumb,
    this.fill = kFeedMediaFill,
    this.playChipStyle = PlayChipStyle.feed,
    this.onTap,
    super.key,
  });

  final List<EmbedImage> images;
  final String keyPrefix;
  final MediaRatioBounds bounds;
  final MediaImageSource source;
  final MediaFillStyle fill;

  /// The play control's treatment when the image is a GIF.
  final PlayChipStyle playChipStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Asserted here rather than in the (const) constructor, which cannot hold
    // a runtime condition.
    assert(
      images.isNotEmpty,
      'NativeImageThumb renders images.first; ImagesPostEmbed guarantees at '
      'least one image',
    );
    final image = images.first;

    return TappableMedia(
      mediaKey: Key('$keyPrefix-images-embed'),
      label: 'View full image',
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: clampMediaRatio(
                image.aspectRatio,
                min: bounds.min,
                max: bounds.max,
              ),
              child: _MediaImage(
                image: image,
                source: source,
                fill: fill,
                playChipStyle: playChipStyle,
              ),
            ),
            if (images.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: MediaBadge(
                  key: Key('$keyPrefix-images-count-badge'),
                  label: '1/${images.length}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A swipeable carousel of native images with page dots overlaid at the
/// bottom centre.
///
/// Owns its [PageController] rather than borrowing one, and rewinds when the
/// embed changes: this State is reused when the same slot renders a
/// different post, and resetting the index alone is not enough — the
/// controller would keep the previous post's page on screen while the
/// indicator and the tap target both said page one.
///
/// [images] must be non-empty: the carousel frame is sized from
/// `images.first`. Callers get that for free from `ImagesPostEmbed`, whose
/// constructor rejects an empty gallery; the assert catches any other source
/// of the list.
class NativeImageGallery extends StatefulWidget {
  const NativeImageGallery({
    required this.images,
    required this.keyPrefix,
    this.onOpen,
    this.bounds = kDetailRatioBounds,
    this.fill = kDetailMediaFill,
    this.source = MediaImageSource.fullsize,
    this.playChipStyle = PlayChipStyle.feed,
    this.initialIndex = 0,
    this.onPageChanged,
    super.key,
  });

  final List<EmbedImage> images;
  final String keyPrefix;

  /// The page shown first. Out of range is a caller bug: it asserts in
  /// debug and shows the first page in release.
  final int initialIndex;

  /// Called with the new page after each swipe.
  final ValueChanged<int>? onPageChanged;
  final MediaImageSource source;

  /// The play control's treatment for the gallery's GIFs.
  final PlayChipStyle playChipStyle;

  /// Called with the page the user is looking at when the gallery is tapped.
  /// Null leaves the gallery swipeable but not activatable.
  final void Function(int index)? onOpen;

  final MediaRatioBounds bounds;
  final MediaFillStyle fill;

  @override
  State<NativeImageGallery> createState() => _NativeImageGalleryState();
}

class _NativeImageGalleryState extends State<NativeImageGallery> {
  @override
  void initState() {
    super.initState();
    assert(
      // An empty list has its own assert, in build.
      widget.images.isEmpty ||
          (widget.initialIndex >= 0 &&
              widget.initialIndex < widget.images.length),
      'initialIndex ${widget.initialIndex} is out of range for '
      '${widget.images.length} images',
    );
  }

  late int _currentIndex =
      widget.initialIndex >= 0 && widget.initialIndex < widget.images.length
      ? widget.initialIndex
      : 0;
  late final PageController _controller = PageController(
    initialPage: _currentIndex,
  );

  @override
  void didUpdateWidget(NativeImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isSameGallery(oldWidget.images, widget.images)) {
      return;
    }

    _currentIndex = 0;
    if (_controller.hasClients) {
      _controller.jumpToPage(0);
    }
    // Reported even before layout, when the jump above can't run, so an
    // owner tracking the page never keeps one the new images lack.
    widget.onPageChanged?.call(0);
  }

  static bool _isSameGallery(List<EmbedImage> a, List<EmbedImage> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].fullsize != b[i].fullsize) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    // Asserted here rather than in the (const) constructor, which cannot hold
    // a runtime condition.
    assert(
      images.isNotEmpty,
      'NativeImageGallery sizes itself from images.first; ImagesPostEmbed '
      'guarantees at least one image',
    );
    // Guard against an index left behind by a longer gallery in the frame
    // before didUpdateWidget rewinds.
    final current = _currentIndex < images.length ? _currentIndex : 0;
    final onOpen = widget.onOpen;

    final frame = TappableMedia(
      mediaKey: Key('${widget.keyPrefix}-images-embed'),
      label: 'View full image',
      onTap: onOpen == null ? null : () => onOpen(current),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          // The gallery frame follows the first image; the rest are
          // contained inside it rather than resizing the carousel.
          aspectRatio: clampMediaRatio(
            images.first.aspectRatio,
            min: widget.bounds.min,
            max: widget.bounds.max,
          ),
          child: PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              widget.onPageChanged?.call(index);
            },
            itemBuilder: (context, index) => _MediaImage(
              image: images[index],
              source: widget.source,
              fill: widget.fill,
              playChipStyle: widget.playChipStyle,
              active: index == current,
            ),
          ),
        ),
      ),
    );

    if (images.length < 2) {
      return frame;
    }

    // The dots sit over the bottom of the image so their dark pill reads
    // against it. They ignore pointers so a tap or swipe on the pill still
    // reaches the gallery.
    return Stack(
      children: [
        frame,
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: IgnorePointer(
            child: Center(
              child: KeyedSubtree(
                key: Key('${widget.keyPrefix}-images-page-indicator'),
                child: MediaPageDots(count: images.length, index: current),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single hydrated image, or the local file of an optimistic post's
/// image, carrying its alt text into the semantics tree.
///
/// A GIF is a [GifPlayer] whatever the [source]: its still is always the
/// thumb, and fullsize is only fetched to play it.
class _MediaImage extends StatelessWidget {
  const _MediaImage({
    required this.image,
    required this.source,
    required this.fill,
    required this.playChipStyle,
    this.active = true,
  });

  final EmbedImage image;
  final MediaImageSource source;
  final MediaFillStyle fill;
  final PlayChipStyle playChipStyle;

  /// Whole image inside its frame, never cropped: the frame's ratio is
  /// clamped, so an image outside the bounds gets bars instead.
  static const BoxFit fit = BoxFit.contain;

  /// Whether this is the gallery page in view; a GIF stops when it is not.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final alt = image.alt;
    final localFile = image.localFile;

    if (image.isGif) {
      return GifPlayer(
        image: image,
        fit: fit,
        playChipStyle: playChipStyle,
        active: active,
        // A local GIF's still is its first frame, decoded by the player;
        // this fill only covers the decode.
        still: localFile != null
            ? MediaFill(iconColor: fill.iconColor, iconSize: fill.iconSize)
            : _networkImage(context, image.thumb),
      );
    }

    var rendered = localFile != null
        ? Image.file(
            localFile,
            width: double.infinity,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => MediaFill(
              icon: Icons.broken_image,
              iconColor: fill.iconColor,
              iconSize: fill.iconSize,
            ),
          )
        : _networkImage(context, switch (source) {
            MediaImageSource.thumb => image.thumb,
            MediaImageSource.fullsize => image.fullsize,
          });

    if (alt != null && alt.isNotEmpty) {
      rendered = Semantics(image: true, label: alt, child: rendered);
    }

    return rendered;
  }

  Widget _networkImage(BuildContext context, String url) {
    final cacheManager = ImageCacheScope.of(context);
    return CachedNetworkImage(
      cacheManager: cacheManager,
      imageUrl: url,
      width: double.infinity,
      fit: fit,
      // Disable fade animation to prevent scroll jitter
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) =>
          MediaFill(iconColor: fill.iconColor, iconSize: fill.iconSize),
      errorWidget: (context, url, error) => ImageLoadError(
        url: url,
        error: error,
        cacheManager: cacheManager,
        fallback: MediaFill(
          icon: Icons.broken_image,
          iconColor: fill.iconColor,
          iconSize: fill.iconSize,
        ),
      ),
    );
  }
}
