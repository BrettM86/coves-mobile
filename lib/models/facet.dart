// Rich text facet models for Coves
//
// Facets represent structured metadata about text segments, such as links,
// mentions, or hashtags. They use byte indices (UTF-8) rather than character
// indices (UTF-16) to ensure cross-platform compatibility with the backend.

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
/// such as a link, mention, or hashtag.
sealed class FacetFeature {
  const FacetFeature();

  /// The type identifier for this feature (e.g., "social.coves.richtext.facet#link")
  String get type;

  /// Convert to JSON
  Map<String, dynamic> toJson();

  /// Create a FacetFeature from JSON
  factory FacetFeature.fromJson(Map<String, dynamic> json) {
    final type = json[r'$type'] as String?;

    if (type == null || type.isEmpty) {
      return UnknownFacetFeature(data: json);
    }

    switch (type) {
      case 'social.coves.richtext.facet#link':
        final uri = json['uri'];
        if (uri == null || uri is! String || uri.isEmpty) {
          throw const FormatException(
            'LinkFacetFeature: Required field "uri" is missing or invalid',
          );
        }
        return LinkFacetFeature(uri: uri);

      default:
        // Unknown feature type - preserve for forward compatibility
        return UnknownFacetFeature(data: json);
    }
  }
}

/// Link facet feature
class LinkFacetFeature extends FacetFeature {
  const LinkFacetFeature({required this.uri});

  /// The URI/URL this link points to
  final String uri;

  @override
  String get type => 'social.coves.richtext.facet#link';

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

/// Unknown facet feature for forward compatibility
///
/// Preserves unknown feature types so they can be round-tripped
/// through the client without data loss.
class UnknownFacetFeature extends FacetFeature {
  const UnknownFacetFeature({required this.data});

  /// Raw JSON data
  final Map<String, dynamic> data;

  @override
  String get type => data[r'$type'] as String? ?? 'unknown';

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
  int get hashCode => Object.hashAll(data.entries);

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

/// Parse facets from a record's 'facets' field
///
/// Backend returns facets inside `record['facets']` rather than at the top level.
/// This helper safely extracts and parses them, returning null if missing/invalid.
List<RichTextFacet>? parseFacetsFromRecord(Object? record) {
  if (record == null || record is! Map<String, dynamic>) {
    return null;
  }
  final facets = record['facets'];
  if (facets == null || facets is! List) {
    return null;
  }
  try {
    return List.unmodifiable(
      facets
          .whereType<Map<String, dynamic>>()
          .map(RichTextFacet.fromJson)
          .toList(),
    );
  } on Exception {
    return null;
  }
}
