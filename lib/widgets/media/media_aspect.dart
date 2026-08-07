import '../../models/post.dart';

/// Widest and tallest display ratios (width/height) a media surface accepts.
typedef MediaRatioBounds = ({double min, double max});

/// The feed card's bounds: 3:4 through 16:9.
///
/// Clamping keeps a panorama from becoming a sliver and a tall portrait from
/// swallowing the viewport. The 3:4 floor lets a standard phone-camera
/// portrait through uncropped; only taller shots (9:16 screenshots, stories)
/// get center-cropped.
const MediaRatioBounds kFeedRatioBounds = (min: 3 / 4, max: 16 / 9);

/// The detail view's bounds: 1:3 through 3:1.
///
/// The detail view keeps far more of the true proportions than the feed card
/// does — every legitimate shape survives untouched. These bounds exist
/// purely as a safety rail: the backend never validates `aspectRatio`, so a
/// hostile record can declare 1:1000000 and, unclamped, lay out a media block
/// hundreds of millions of pixels tall.
const MediaRatioBounds kDetailRatioBounds = (min: 1 / 3, max: 3);

/// Resolves the display ratio (width/height) for a piece of media.
///
/// A declared [ratio] is clamped into [min]..[max]. Media with no declared
/// ratio renders at [fallback], returned as given: the fallback is a display
/// choice rather than record data, so a caller may pick a shape outside its
/// own rails.
double clampMediaRatio(
  EmbedAspectRatio? ratio, {
  required double min,
  required double max,
  double fallback = 16 / 9,
}) {
  if (ratio == null) {
    return fallback;
  }
  return (ratio.width / ratio.height).clamp(min, max);
}
