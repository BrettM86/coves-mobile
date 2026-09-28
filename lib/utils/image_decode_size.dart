import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Decode widths are rounded up to a multiple of this, so one URL shown at
/// slightly different sizes (a 20px and a 24px avatar) shares one decoded
/// bitmap in the image cache instead of decoding once per size.
const int _decodeWidthStep = 64;

/// The pixel width to decode a network image at so it stays sharp when drawn
/// [logicalWidth] logical pixels wide on this screen.
///
/// Pass it as `memCacheWidth` (or to [ResizeImage]). Without it an image is
/// decoded at its source resolution: a 1000x1000 avatar costs ~4MB of
/// decoded bitmap to paint a 72px circle, and a feed full of them churns the
/// image cache, re-decoding on scroll-back.
///
/// Only the width is constrained, so the aspect ratio is kept, and images
/// smaller than the result are never upscaled.
int decodeWidthFor(BuildContext context, double logicalWidth) {
  final pixels = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  final steps = math.max(1, (pixels / _decodeWidthStep).ceil());
  return steps * _decodeWidthStep;
}

/// [decodeWidthFor] the full screen width - for media that spans the
/// content column (link thumbnails, banners, video posters).
int fullWidthDecodeWidth(BuildContext context) {
  return decodeWidthFor(context, MediaQuery.sizeOf(context).width);
}
