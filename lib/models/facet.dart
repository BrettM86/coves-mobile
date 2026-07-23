// Rich text facet models for Coves
//
// Facets represent structured metadata about text segments, such as links,
// mentions, or headings. They use byte indices (UTF-8) rather than character
// indices (UTF-16) to ensure cross-platform compatibility with the backend.

import 'package:flutter/foundation.dart';

/// Byte range for a text segment
///
/// Uses UTF-8 byte offsets, not UTF-16 character positions.
/// This is crucial for proper alignment with the backend, especially
/// when text contains emoji or other multi-byte characters.
class ByteSlice {
  const ByteSlice({
    required this.byteStart,
    required this.byteEnd,
  })  : assert(byteStart >= 0, 'byteStart must be non-negative'),
        assert(byteEnd >= byteStart, 'byteEnd must be >= byteStart');

  factory ByteSlice.fromJson(Map<String, dynamic> json) {
    final start = json['byteStart'];
    final end = json['byteEnd'];

    if (start == null || start is! int) {
      throw const FormatException(
        'ByteSlice: Required field "byteStart" is missing or invalid',
      );
    }

    if (end == null || end is! int) {
      throw const FormatException(
        'ByteSlice: Required field "byteEnd" is missing or invalid',
      );
    }

    if (start < 0 || end < 0 || end < start) {
      throw FormatException(
        'ByteSlice: Invalid byte range [$start, $end)',
      );
    }

    return ByteSlice(
      byteStart: start,
      byteEnd: end,
    );
  }

  /// Start byte position (inclusive)
  final int byteStart;

  /// End byte position (exclusive)
  final int byteEnd;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'byteStart': byteStart,
      'byteEnd': byteEnd,
    };
  }

  @override
  String toString() => 'ByteSlice($byteStart, $byteEnd)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ByteSlice &&
          runtimeType == other.runtimeType &&
          byteStart == other.byteStart &&
          byteEnd == other.byteEnd;

  @override
  int get hashCode => Object.hash(byteStart, byteEnd);
}

/// Base class for facet features
///
/// A facet feature describes the semantic meaning of a text segment,
/// such as a link, mention, or a block-level structure (quote, heading, code).
sealed class FacetFeature {
  const FacetFeature();

  /// Create a FacetFeature from JSON
  ///
  /// The feature union is open: unknown `$type`s become [UnknownFacetFeature]
  /// and render as plain text. Known types with missing/invalid attributes
  /// also degrade to [UnknownFacetFeature] rather than throwing, so one bad
  /// feature never strips rich text from the rest of the record.
  factory FacetFeature.fromJson(Map<String, dynamic> json) {
    // Not a cast: a non-string $type (e.g. 42) must degrade gracefully,
    // not throw a TypeError that escapes `on Exception` guards upstream.
    final type = json[r'$type'];

    if (type is! String || type.isEmpty) {
      return UnknownFacetFeature(data: json);
    }

    switch (type) {
      case LinkFacetFeature.typeId:
        final uri = json['uri'];
        if (uri == null || uri is! String || uri.isEmpty) {
          return UnknownFacetFeature(data: json);
        }
        return LinkFacetFeature(uri: uri);

      case MentionFacetFeature.typeId:
        final did = json['did'];
        if (did == null || did is! String || did.isEmpty) {
          return UnknownFacetFeature(data: json);
        }
        return MentionFacetFeature(did: did);

      case BoldFacetFeature.typeId:
        return const BoldFacetFeature();

      case ItalicFacetFeature.typeId:
        return const ItalicFacetFeature();

      case StrikethroughFacetFeature.typeId:
        return const StrikethroughFacetFeature();

      case SpoilerFacetFeature.typeId:
        final reason = json['reason'];
        return SpoilerFacetFeature(reason: reason is String ? reason : null);

      case BlockquoteFacetFeature.typeId:
        // Absent level means 1. The lexicon tells writers to clamp nesting
        // deeper than 6 to level 6; we mirror that leniency on read
        // (clamping <1 up to 1 as well) rather than dropping the facet.
        final level = json['level'];
        if (level == null) {
          return const BlockquoteFacetFeature();
        }
        if (level is! int) {
          return UnknownFacetFeature(data: json);
        }
        return BlockquoteFacetFeature(level: level.clamp(1, 6));

      case HeadingFacetFeature.typeId:
        // Level is required for headings; degrade to plain text without it.
        final level = json['level'];
        if (level is! int) {
          return UnknownFacetFeature(data: json);
        }
        return HeadingFacetFeature(level: level.clamp(1, 6));

      case CodeFacetFeature.typeId:
        return const CodeFacetFeature();

      case CodeBlockFacetFeature.typeId:
        final language = json['language'];
        return CodeBlockFacetFeature(
          language: language is String && language.isNotEmpty ? language : null,
        );

      default:
        // Unknown feature type - preserve for forward compatibility
        return UnknownFacetFeature(data: json);
    }
  }

  /// The type identifier for this feature (e.g., "social.coves.richtext.facet#link")
  String get type;

  /// Convert to JSON
  Map<String, dynamic> toJson();
}

/// Link facet feature
class LinkFacetFeature extends FacetFeature {
  const LinkFacetFeature({required this.uri});

  static const typeId = 'social.coves.richtext.facet#link';

  /// The URI/URL this link points to
  final String uri;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() {
    return {
      r'$type': type,
      'uri': uri,
    };
  }

  @override
  String toString() => 'LinkFacetFeature($uri)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkFacetFeature &&
          runtimeType == other.runtimeType &&
          uri == other.uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Mention of a user or community
///
/// The annotated text is usually a handle with '@' (user) or '!' (community)
/// prefix, but the reference is a DID.
class MentionFacetFeature extends FacetFeature {
  const MentionFacetFeature({required this.did});

  static const typeId = 'social.coves.richtext.facet#mention';

  /// DID of the mentioned user or community
  final String did;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type, 'did': did};

  @override
  String toString() => 'MentionFacetFeature($did)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionFacetFeature &&
          runtimeType == other.runtimeType &&
          did == other.did;

  @override
  int get hashCode => did.hashCode;
}

/// Bold text formatting
class BoldFacetFeature extends FacetFeature {
  const BoldFacetFeature();

  static const typeId = 'social.coves.richtext.facet#bold';

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BoldFacetFeature;

  @override
  int get hashCode => typeId.hashCode;
}

/// Italic text formatting
class ItalicFacetFeature extends FacetFeature {
  const ItalicFacetFeature();

  static const typeId = 'social.coves.richtext.facet#italic';

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ItalicFacetFeature;

  @override
  int get hashCode => typeId.hashCode;
}

/// Strikethrough text formatting
class StrikethroughFacetFeature extends FacetFeature {
  const StrikethroughFacetFeature();

  static const typeId = 'social.coves.richtext.facet#strikethrough';

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StrikethroughFacetFeature;

  @override
  int get hashCode => typeId.hashCode;
}

/// Hidden/spoiler text that requires user interaction to reveal
class SpoilerFacetFeature extends FacetFeature {
  const SpoilerFacetFeature({this.reason});

  static const typeId = 'social.coves.richtext.facet#spoiler';

  /// Optional explanation of what's hidden
  final String? reason;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {
        r'$type': type,
        if (reason != null) 'reason': reason,
      };

  @override
  String toString() => 'SpoilerFacetFeature($reason)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpoilerFacetFeature &&
          runtimeType == other.runtimeType &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(typeId, reason);
}

/// Block-level quotation
///
/// The range spans whole lines (excluding the trailing newline). Nested
/// quotes are disjoint ranges with increasing [level], never containment.
class BlockquoteFacetFeature extends FacetFeature {
  const BlockquoteFacetFeature({this.level = 1})
      : assert(level >= 1 && level <= 6, 'level must be 1-6');

  static const typeId = 'social.coves.richtext.facet#blockquote';

  /// Quote nesting depth (1-6). Absent on the wire means 1.
  final int level;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {
        r'$type': type,
        if (level != 1) 'level': level,
      };

  @override
  String toString() => 'BlockquoteFacetFeature(level: $level)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockquoteFacetFeature &&
          runtimeType == other.runtimeType &&
          level == other.level;

  @override
  int get hashCode => Object.hash(typeId, level);
}

/// Section heading spanning a single whole line
class HeadingFacetFeature extends FacetFeature {
  const HeadingFacetFeature({required this.level})
      : assert(level >= 1 && level <= 6, 'level must be 1-6');

  static const typeId = 'social.coves.richtext.facet#heading';

  /// Heading level, 1 (largest) through 6
  final int level;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type, 'level': level};

  @override
  String toString() => 'HeadingFacetFeature(level: $level)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadingFacetFeature &&
          runtimeType == other.runtimeType &&
          level == other.level;

  @override
  int get hashCode => Object.hash(typeId, level);
}

/// Inline code span rendered in monospace
class CodeFacetFeature extends FacetFeature {
  const CodeFacetFeature();

  static const typeId = 'social.coves.richtext.facet#code';

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {r'$type': type};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CodeFacetFeature;

  @override
  int get hashCode => typeId.hashCode;
}

/// Block of preformatted code rendered in monospace, whitespace preserved
class CodeBlockFacetFeature extends FacetFeature {
  const CodeBlockFacetFeature({this.language});

  static const typeId = 'social.coves.richtext.facet#codeBlock';

  /// Optional language hint for syntax highlighting (e.g. 'go', 'python')
  final String? language;

  @override
  String get type => typeId;

  @override
  Map<String, dynamic> toJson() => {
        r'$type': type,
        if (language != null) 'language': language,
      };

  @override
  String toString() => 'CodeBlockFacetFeature($language)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeBlockFacetFeature &&
          runtimeType == other.runtimeType &&
          language == other.language;

  @override
  int get hashCode => Object.hash(typeId, language);
}

/// Unknown facet feature for forward compatibility
///
/// Preserves unknown feature types so they can be round-tripped
/// through the client without data loss.
class UnknownFacetFeature extends FacetFeature {
  const UnknownFacetFeature({required this.data});

  /// Raw JSON data
  final Map<String, dynamic> data;

  @override
  String get type {
    final rawType = data[r'$type'];
    return rawType is String ? rawType : 'unknown';
  }

  @override
  Map<String, dynamic> toJson() => data;

  @override
  String toString() => 'UnknownFacetFeature($type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownFacetFeature &&
          runtimeType == other.runtimeType &&
          _mapEquals(data, other.data);

  @override
  int get hashCode {
    // MapEntry hashes by identity and `.entries` creates fresh entries per
    // call, so Object.hashAll(data.entries) returned a different value on
    // every invocation. Hash the content instead, XOR-folded so the result
    // is independent of key insertion order (matching _mapEquals).
    var hash = 0;
    for (final entry in data.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

/// A rich text facet - metadata about a text segment
class RichTextFacet {
  const RichTextFacet({
    required this.index,
    required this.features,
  });

  factory RichTextFacet.fromJson(Map<String, dynamic> json) {
    final indexData = json['index'];
    if (indexData == null || indexData is! Map<String, dynamic>) {
      throw const FormatException(
        'RichTextFacet: Required field "index" is missing or invalid',
      );
    }

    final featuresData = json['features'];
    if (featuresData == null || featuresData is! List) {
      throw const FormatException(
        'RichTextFacet: Required field "features" is missing or invalid',
      );
    }

    return RichTextFacet(
      index: ByteSlice.fromJson(indexData),
      features: List.unmodifiable(
        featuresData
            .whereType<Map<String, dynamic>>()
            .map(FacetFeature.fromJson)
            .toList(),
      ),
    );
  }

  /// The byte range this facet applies to
  final ByteSlice index;

  /// The semantic features of this text segment
  final List<FacetFeature> features;

  /// Check if this facet contains a link feature
  bool get hasLink =>
      features.any((feature) => feature is LinkFacetFeature);

  /// The first block-level feature (blockquote, heading, codeBlock), if any
  ///
  /// Block features change layout rather than character style, so renderers
  /// treat a facet carrying one as a block and apply any remaining features
  /// inline within it (code blocks excepted: their text renders literally).
  FacetFeature? get blockFeature {
    for (final feature in features) {
      if (feature is BlockquoteFacetFeature ||
          feature is HeadingFacetFeature ||
          feature is CodeBlockFacetFeature) {
        return feature;
      }
    }
    return null;
  }

  /// Get the link URI if this facet has a link feature
  String? get linkUri {
    for (final feature in features) {
      if (feature is LinkFacetFeature) {
        return feature.uri;
      }
    }
    return null;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'index': index.toJson(),
      'features': features.map((f) => f.toJson()).toList(),
    };
  }

  @override
  String toString() => 'RichTextFacet($index, ${features.length} features)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RichTextFacet &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          _listEquals(features, other.features);

  @override
  int get hashCode => Object.hash(index, Object.hashAll(features));

  static bool _listEquals(List<FacetFeature> a, List<FacetFeature> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Client-side caps mirroring the backend sanitizer's MaxFacets and
/// MaxFeaturesPerFacet. Old pre-sanitizer federated records can exceed the
/// backend caps, so we enforce them here too to keep rendering bounded.
const int _maxFacets = 200;
const int _maxFeaturesPerFacet = 20;

/// Parse facets from a record's 'facets' field
///
/// Backend returns facets inside `record['facets']` rather than at the top level.
/// This helper safely extracts and parses them, returning null if missing/invalid.
///
/// Note: Malformed facets are dropped individually (logged in debug mode) so
/// a single bad entry never strips rich text from the rest of the content.
List<RichTextFacet>? parseFacetsFromRecord(Object? record) {
  if (record == null || record is! Map<String, dynamic>) {
    return null;
  }
  final facets = record['facets'];
  if (facets == null || facets is! List) {
    return null;
  }
  final parsed = <RichTextFacet>[];
  for (final entry in facets.whereType<Map<String, dynamic>>()) {
    if (parsed.length >= _maxFacets) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Truncating facets to first $_maxFacets (backend MaxFacets cap)',
        );
      }
      break;
    }
    final features = entry['features'];
    if (features is List && features.length > _maxFeaturesPerFacet) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Dropping facet with ${features.length} features '
          '(backend MaxFeaturesPerFacet cap: $_maxFeaturesPerFacet)',
        );
      }
      continue;
    }
    try {
      parsed.add(RichTextFacet.fromJson(entry));
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Skipping malformed facet: $e');
      }
    }
  }
  if (parsed.isEmpty) {
    return null;
  }
  return List.unmodifiable(parsed);
}
