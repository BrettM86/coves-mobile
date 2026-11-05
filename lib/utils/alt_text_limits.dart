// Alt text length limits: grapheme clusters and UTF-8 bytes.

import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';

import '../constants/image_upload_limits.dart';

/// Which alt text limit a text is over.
enum AltTextLimit { graphemes, bytes }

/// The measured length of an alt text against its limits.
class AltTextMeasure {
  const AltTextMeasure._({required this.graphemes, required this.bytes});

  factory AltTextMeasure.of(String text) => AltTextMeasure._(
    graphemes: text.characters.length,
    bytes: utf8.encode(text).length,
  );

  /// How close to a limit the counter appears, in what [remaining] counts.
  static const _counterThreshold = 100;

  final int graphemes;
  final int bytes;

  /// The limit the text is over, the grapheme limit first; null when it is
  /// within both.
  AltTextLimit? get exceeded {
    if (graphemes > ImageUploadLimits.altTextMaxGraphemes) {
      return AltTextLimit.graphemes;
    }
    if (bytes > ImageUploadLimits.altTextMaxBytes) {
      return AltTextLimit.bytes;
    }
    return null;
  }

  bool get isValid => exceeded == null;

  /// The room left under the nearer limit: the lesser of graphemes and bytes
  /// left, so it never overstates the room.
  int get remaining => min(
    ImageUploadLimits.altTextMaxGraphemes - graphemes,
    ImageUploadLimits.altTextMaxBytes - bytes,
  );

  /// Whether the text is near enough a limit to show [remaining].
  bool get showCounter => remaining <= _counterThreshold;
}
