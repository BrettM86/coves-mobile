import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import 'media_aspect.dart';
import 'media_surface.dart';

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
/// The feed card renders every images embed this way — one image, plus a
/// "1/N" badge when the gallery holds more — and the detail view uses it for
/// a single-image post. [keyPrefix] namespaces the widget keys (`post-` vs
/// `detail-`).
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
    this.onTap,
    super.key,
  });

  final List<EmbedImage> images;
  final String keyPrefix;
  final MediaRatioBounds bounds;
  final MediaImageSource source;
  final MediaFillStyle fill;
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
              child: _NetworkMediaImage(
                image: image,
                source: source,
                fill: fill,
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

/// A swipeable carousel of fullsize native images with an i/N indicator.
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
    required this.onOpen,
    this.bounds = kDetailRatioBounds,
    this.fill = kDetailMediaFill,
    super.key,
  });

  final List<EmbedImage> images;
  final String keyPrefix;

  /// Called with the page the user is looking at when the gallery is tapped.
  final void Function(int index) onOpen;

  final MediaRatioBounds bounds;
  final MediaFillStyle fill;

  @override
  State<NativeImageGallery> createState() => _NativeImageGalleryState();
}

class _NativeImageGalleryState extends State<NativeImageGallery> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

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

    return TappableMedia(
      mediaKey: Key('${widget.keyPrefix}-images-embed'),
      label: 'View full image',
      onTap: () => widget.onOpen(current),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            AspectRatio(
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
                },
                itemBuilder:
                    (context, index) => _NetworkMediaImage(
                      image: images[index],
                      source: MediaImageSource.fullsize,
                      fill: widget.fill,
                      fit: BoxFit.contain,
                    ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: MediaBadge(
                key: Key('${widget.keyPrefix}-images-page-indicator'),
                label: '${current + 1}/${images.length}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single hydrated image, carrying its alt text into the semantics tree.
class _NetworkMediaImage extends StatelessWidget {
  const _NetworkMediaImage({
    required this.image,
    required this.source,
    required this.fill,
    this.fit = BoxFit.cover,
  });

  final EmbedImage image;
  final MediaImageSource source;
  final MediaFillStyle fill;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final alt = image.alt;

    Widget rendered = CachedNetworkImage(
      imageUrl: switch (source) {
        MediaImageSource.thumb => image.thumb,
        MediaImageSource.fullsize => image.fullsize,
      },
      width: double.infinity,
      fit: fit,
      // Disable fade animation to prevent scroll jitter
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder:
          (context, url) =>
              MediaFill(iconColor: fill.iconColor, iconSize: fill.iconSize),
      errorWidget:
          (context, url, error) => MediaFill(
            icon: Icons.broken_image,
            iconColor: fill.iconColor,
            iconSize: fill.iconSize,
          ),
    );

    if (alt != null && alt.isNotEmpty) {
      rendered = Semantics(image: true, label: alt, child: rendered);
    }

    return rendered;
  }
}
