import '../models/facet.dart';
import '../models/post.dart';
import 'block_lines.dart';
import 'utf8_offsets.dart';

/// An image placed in the body by an accepted `#image` facet
class PlacedImage {
  const PlacedImage({
    required this.index,
    required this.image,
    required this.range,
    this.spoilered = false,
  });

  /// Index into the embed's main images list
  final int index;

  final EmbedImage image;

  /// Byte range of the placement in the text
  final ByteSlice range;

  /// Whether a spoiler facet overlaps the placement, hiding it until the
  /// reader reveals that spoiler
  final bool spoilered;
}

/// The split of a post's images into body placements and the gallery
class ImageLayout {
  const ImageLayout({required this.gallery, required this.placed});

  /// Unplaced images in index order
  final List<EmbedImage> gallery;

  /// Accepted placements in body order
  final List<PlacedImage> placed;

  /// Placements outside every spoiler, which always show in the body
  List<PlacedImage> get openPlaced => [
    for (final placement in placed)
      if (!placement.spoilered) placement,
  ];

  /// The lightbox sequence in screen order: the [shown] placements in body
  /// order, then the gallery; or, with [galleryFirst] for a surface that
  /// draws its gallery above the body, the gallery then the placements
  List<EmbedImage> lightboxImages(
    List<PlacedImage> shown, {
    bool galleryFirst = false,
  }) => [
    if (galleryFirst) ...gallery,
    for (final placement in shown) placement.image,
    if (!galleryFirst) ...gallery,
  ];
}

/// Splits [embed]'s main images into body placements and the gallery
///
/// The server already strips rule-breaking placements; these guards keep a
/// bad record from breaking the render. A rejected placement leaves its image
/// in the gallery and its covered text as plain text. Every accepted
/// placement is one the renderer can draw as a block where its facet sits.
ImageLayout imageLayout(
  PostEmbed? embed,
  String text,
  List<RichTextFacet>? facets,
) {
  final images = switch (embed) {
    ImagesPostEmbed(:final images) => images,
    ImagesWithAttachmentPostEmbed(:final images) => images,
    _ => const <EmbedImage>[],
  };
  if (images.isEmpty) {
    return const ImageLayout(gallery: [], placed: []);
  }
  if (facets == null || facets.isEmpty) {
    return ImageLayout(gallery: List.unmodifiable(images), placed: const []);
  }

  final offsets = Utf8Offsets(text);

  // Char range of a facet the renderer keeps (it drops the rest)
  (int, int)? charRange(ByteSlice range) {
    if (range.byteStart < 0 ||
        range.byteEnd <= range.byteStart ||
        range.byteEnd > offsets.byteLength) {
      return null;
    }
    final start = offsets.charIndexOf(range.byteStart);
    final end = offsets.charIndexOf(range.byteEnd);
    return start == null || end == null ? null : (start, end);
  }

  bool overlaps((int, int) a, (int, int) b) => a.$1 < b.$2 && b.$1 < a.$2;

  final codeRanges = <(int, int)>[];
  final spoilerRanges = <(int, int)>[];
  // Block facets as the renderer lays them out: extended to whole lines
  final quoteLines = <(int, int)>[];
  final otherBlockLines = <(int, int)>[];
  for (final facet in facets) {
    final range = charRange(facet.index);
    if (range == null) {
      continue;
    }
    final features = facet.features;
    if (features.any(
      (feature) =>
          feature is CodeFacetFeature || feature is CodeBlockFacetFeature,
    )) {
      codeRanges.add(range);
    }
    if (features.any((feature) => feature is SpoilerFacetFeature)) {
      spoilerRanges.add(range);
    }
    // Every block the renderer draws from this facet: a quote can share
    // one with a heading or code block over the same lines
    final blocks = facet.blockFeatures;
    final lines = blocks.isEmpty
        ? null
        : lineExtendedRange(text, range.$1, range.$2);
    if (lines != null) {
      for (final block in blocks) {
        (block is BlockquoteFacetFeature ? quoteLines : otherBlockLines).add(
          lines,
        );
      }
    }
  }

  final candidates = <(PlacedImage, (int, int))>[];
  for (final facet in facets) {
    if (facet.features.length != 1) {
      continue;
    }
    final feature = facet.features.single;
    if (feature is! ImageFacetFeature || feature.index >= images.length) {
      continue;
    }
    final range = charRange(facet.index);
    if (range == null ||
        codeRanges.any((code) => overlaps(range, code)) ||
        // A heading or code block owns its whole line
        otherBlockLines.any((lines) => overlaps(range, lines)) ||
        // Inside a quote is fine; across its edge the quote would drop it
        quoteLines.any(
          (lines) =>
              overlaps(range, lines) &&
              (range.$1 < lines.$1 || range.$2 > lines.$2),
        )) {
      continue;
    }
    candidates.add((
      PlacedImage(
        index: feature.index,
        image: images[feature.index],
        range: facet.index,
        spoilered: spoilerRanges.any((spoiler) => overlaps(range, spoiler)),
      ),
      range,
    ));
  }

  // Body order decides which of two clashing placements wins
  candidates.sort((a, b) => a.$2.$1.compareTo(b.$2.$1));
  final blockEnds = {for (final lines in quoteLines) lines.$2}
    ..addAll([for (final lines in otherBlockLines) lines.$2]);
  final placedIndices = <int>{};
  final placed = <PlacedImage>[];
  final placedRanges = <(int, int)>[];
  for (final (candidate, range) in candidates) {
    if (placedIndices.contains(candidate.index) ||
        placedRanges.any((other) => overlaps(range, other)) ||
        // The renderer skips the newline after a block, so a placement
        // starting on it would be skipped too
        (text[range.$1] == '\n' &&
            (blockEnds.contains(range.$1) ||
                placedRanges.any((other) => other.$2 == range.$1)))) {
      continue;
    }
    placedIndices.add(candidate.index);
    placed.add(candidate);
    placedRanges.add(range);
  }

  return ImageLayout(
    gallery: List.unmodifiable([
      for (var index = 0; index < images.length; index++)
        if (!placedIndices.contains(index)) images[index],
    ]),
    placed: List.unmodifiable(placed),
  );
}

/// The char ranges of [text] a compact preview keeps once [layout]'s
/// placements are left out
///
/// A placement filling whole lines also drops the line breaks after it, so
/// a run of placements between two paragraphs leaves the one paragraph break
/// before the run. Breaks left at either end of the preview are trimmed.
List<(int, int)> previewTextRanges(String text, ImageLayout? layout) {
  final placed = layout?.placed ?? const <PlacedImage>[];
  if (placed.isEmpty) {
    return [(0, text.length)];
  }

  final offsets = Utf8Offsets(text);
  final removed = <(int, int)>[];
  for (final placement in placed) {
    final start = offsets.charIndexOf(placement.range.byteStart);
    final charEnd = offsets.charIndexOf(placement.range.byteEnd);
    if (start == null || charEnd == null || charEnd <= start) {
      continue;
    }
    var end = charEnd;
    final fillsLines =
        (start == 0 || text[start - 1] == '\n') &&
        (end == text.length || text[end] == '\n');
    if (fillsLines) {
      while (end < text.length && text[end] == '\n') {
        end++;
      }
    }
    if (removed.isNotEmpty && start <= removed.last.$2) {
      final last = removed.removeLast();
      removed.add((last.$1, end > last.$2 ? end : last.$2));
    } else {
      removed.add((start, end));
    }
  }

  final kept = <(int, int)>[];
  var keptStart = 0;
  for (final (start, end) in removed) {
    if (start > keptStart) {
      kept.add((keptStart, start));
    }
    keptStart = end;
  }
  if (keptStart < text.length) {
    kept.add((keptStart, text.length));
  }

  bool blank(int index) => text[index].trim().isEmpty;
  bool blankRange((int, int) range) =>
      text.substring(range.$1, range.$2).trim().isEmpty;

  while (kept.isNotEmpty && blankRange(kept.first)) {
    kept.removeAt(0);
  }
  while (kept.isNotEmpty && blankRange(kept.last)) {
    kept.removeLast();
  }
  if (kept.isEmpty) {
    return kept;
  }
  var (firstStart, firstEnd) = kept.first;
  while (blank(firstStart)) {
    firstStart++;
  }
  kept[0] = (firstStart, firstEnd);
  var (lastStart, lastEnd) = kept.last;
  while (blank(lastEnd - 1)) {
    lastEnd--;
  }
  kept[kept.length - 1] = (lastStart, lastEnd);
  return kept;
}

/// Whether the compact preview of [text] under [layout] has any text left
bool previewHasText(String text, ImageLayout? layout) => previewTextRanges(
  text,
  layout,
).any((range) => text.substring(range.$1, range.$2).trim().isNotEmpty);
