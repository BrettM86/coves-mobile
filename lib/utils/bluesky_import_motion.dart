import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Size;

/// How far a drag of [delta] has carried the Bluesky card from its centre
/// [start] towards the Coves card's centre [target]: 0 at the start, 1 over
/// the target centre, negative when dragged away.
double dragProgress({
  required Offset start,
  required Offset target,
  required Offset delta,
}) {
  final towards = target - start;
  final lengthSquared = towards.distanceSquared;
  if (lengthSquared == 0) {
    return 0;
  }
  return (delta.dx * towards.dx + delta.dy * towards.dy) / lengthSquared;
}

/// The colour blend amount `p` for a drag [progress].
double blendAmount(double progress) {
  final t = progress.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 1 once the blend amount [p] reaches the midpoint, otherwise 0.
int blendStep(double p) => p >= 0.5 ? 1 : 0;

/// The Bluesky share of the card surface at blend amount [p].
double surfaceShare(double p) => 1 - 0.4 * p - 0.6 * blendStep(p);

/// Whether a released drag drops the card into the Coves slot.
bool shouldDrop({
  required bool releaseOverTarget,
  required double progress,
  required bool anySelected,
}) => anySelected && (releaseOverTarget || progress >= 0.5);

final _blankLineRun = RegExp(r'\n(?:[ \t]*\n)+');
final _edgeBlankLines = RegExp(r'^(?:[ \t]*\n)+|(?:\n[ \t]*)+$');

/// [bio] as the card previews it.
String bioPreview(String bio) {
  final normalised = bio.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalised
      .replaceAll(_blankLineRun, '\n')
      .replaceAll(_edgeBlankLines, '');
}

/// How many particles fire from each of the top and bottom edges of a card
/// of [cardSize].
int seatBurstEdgeCount(Size cardSize) {
  if (cardSize.height <= 0) {
    return 4;
  }
  final spacing = 0.6 * cardSize.height / 8;
  return (0.6 * cardSize.width / spacing).round().clamp(4, 24);
}

/// How many particles the seat burst fires around a card of [cardSize].
int seatBurstParticleCount(Size cardSize) =>
    8 * 2 + 4 + 2 * seatBurstEdgeCount(cardSize);

/// Interpolates between [a] and [b] in the oklab colour space.
Color lerpOklab(Color a, Color b, double t) {
  if (t <= 0) {
    return a;
  }
  if (t >= 1) {
    return b;
  }
  final labA = _toOklab(a);
  final labB = _toOklab(b);
  final mixed = List<double>.generate(
    3,
    (i) => labA[i] + (labB[i] - labA[i]) * t,
  );
  return _fromOklab(a, mixed, a.a + (b.a - a.a) * t);
}

double _toLinear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _toGamma(double channel) {
  final value = channel <= 0.0031308
      ? channel * 12.92
      : 1.055 * math.pow(channel, 1 / 2.4) - 0.055;
  return value.clamp(0.0, 1.0);
}

double _cbrt(double value) => value < 0
    ? -math.pow(-value, 1 / 3).toDouble()
    : math.pow(value, 1 / 3).toDouble();

List<double> _toOklab(Color color) {
  final r = _toLinear(color.r);
  final g = _toLinear(color.g);
  final b = _toLinear(color.b);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

/// [lab] as an sRGB colour, built from [base] so no raw colour literal
/// appears outside the palette.
Color _fromOklab(Color base, List<double> lab, double alpha) {
  final l = math.pow(lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2], 3);
  final m = math.pow(lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2], 3);
  final s = math.pow(lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2], 3);
  return base.withValues(
    alpha: alpha.clamp(0.0, 1.0),
    red: _toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    green: _toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    blue: _toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
  );
}
