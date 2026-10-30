import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../models/facet.dart';
import '../../utils/utf8_offsets.dart';
import 'facet_editing_controller.dart';

/// How many of a record's [maxFacetsPerRecord] facets the composer's
/// formatting uses.
class FormattingBudget {
  const FormattingBudget({required this.used});

  /// The budget [text] and its UTF-16 [inlineRanges], [blockRanges] and
  /// [featureRanges] use, counted by the same rules as [serializeFormatting]
  /// (a range with more than 20 features counts once per facet it splits
  /// into) but never throwing.
  FormattingBudget.of(
    String text, {
    List<InlineRange> inlineRanges = const [],
    List<BlockRange> blockRanges = const [],
    List<FeatureRange> featureRanges = const [],
  }) : used = _facetCount(
         _collectFormatting(
           text,
           inlineRanges: inlineRanges,
           blockRanges: blockRanges,
           featureRanges: featureRanges,
         ).featuresByRange,
       );

  /// The serialized facet count, grouped by range and split at 20 features.
  final int used;

  int get remaining => math.max(0, maxFacetsPerRecord - used);

  bool get isExhausted => used >= maxFacetsPerRecord;

  bool get isOverLimit => used > maxFacetsPerRecord;
}

/// Thrown when formatting would serialize to more than [maxFacetsPerRecord]
/// facets.
class FacetLimitExceededException implements Exception {
  const FacetLimitExceededException({required this.facetCount});

  final int facetCount;

  int get limit => maxFacetsPerRecord;
}

/// The composer's formatting, ready to submit.
class SerializedFormatting {
  const SerializedFormatting({
    required this.content,
    required this.facets,
    required this.codeRanges,
  });

  /// The trimmed text that the facets index into.
  final String content;

  /// Formatting facets with UTF-8 byte offsets into [content], grouped by
  /// identical range and sorted by byte start.
  final List<RichTextFacet> facets;

  /// Inline code and code block ranges in UTF-16 offsets into [content],
  /// sorted by start, for excluding them from link and mention detection.
  final List<TextRange> codeRanges;
}

/// Converts the composer's [text] and its UTF-16 [inlineRanges] and
/// [blockRanges] into trimmed content and byte-offset formatting facets.
///
/// Ranges shift by the leading trim and are clipped to the trimmed content;
/// a range left empty is dropped. A block range loses its leading and
/// trailing empty lines, so a block of only empty lines is dropped. Features
/// over the same byte range share one facet, in lexicon union order with
/// unknown-type features last in the order given. A range with more than
/// 20 features (the lexicon maximum) is written as consecutive facets over
/// that range, each with at most 20 features, in the same order.
///
/// Spoiler reasons, code block languages and quote and heading levels are
/// written from the ranges, and each of [featureRanges] writes its feature
/// unchanged.
///
/// Throws [FacetLimitExceededException] when the facets would number more
/// than [maxFacetsPerRecord]; none are dropped to fit.
SerializedFormatting serializeFormatting(
  String text, {
  List<InlineRange> inlineRanges = const [],
  List<BlockRange> blockRanges = const [],
  List<FeatureRange> featureRanges = const [],
}) {
  final (:content, :featuresByRange, :codeRanges) = _collectFormatting(
    text,
    inlineRanges: inlineRanges,
    blockRanges: blockRanges,
    featureRanges: featureRanges,
  );
  final facetCount = _facetCount(featuresByRange);
  if (facetCount > maxFacetsPerRecord) {
    throw FacetLimitExceededException(facetCount: facetCount);
  }
  final offsets = Utf8Offsets(content);

  // Facets in creation order, so ties in the byte-range sort below keep it:
  // List.sort is not stable.
  final unsorted = [
    for (final MapEntry(key: (start, end), value: features)
        in featuresByRange.entries)
      for (final chunk in _chunked(_inUnionOrder(features)))
        RichTextFacet(
          index: ByteSlice(
            byteStart: offsets.byteOffsetOf(start),
            byteEnd: offsets.byteOffsetOf(end),
          ),
          features: chunk,
        ),
  ];
  final order = List.generate(unsorted.length, (index) => index)
    ..sort((a, b) {
      final first = unsorted[a].index;
      final second = unsorted[b].index;
      if (first.byteStart != second.byteStart) {
        return first.byteStart.compareTo(second.byteStart);
      }
      if (first.byteEnd != second.byteEnd) {
        return first.byteEnd.compareTo(second.byteEnd);
      }
      return a.compareTo(b);
    });
  final facets = [for (final index in order) unsorted[index]];
  codeRanges.sort(
    (a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end),
  );

  return SerializedFormatting(
    content: content,
    facets: facets,
    codeRanges: codeRanges,
  );
}

/// The trimmed content of [text], its formatting features keyed by their
/// UTF-16 range in the content (one entry per facet, in insertion order),
/// and the unsorted code ranges, by the rules of [serializeFormatting].
({
  String content,
  Map<(int, int), List<FacetFeature>> featuresByRange,
  List<TextRange> codeRanges,
})
_collectFormatting(
  String text, {
  required List<InlineRange> inlineRanges,
  required List<BlockRange> blockRanges,
  List<FeatureRange> featureRanges = const [],
}) {
  final content = text.trim();
  final leadingTrim = text.length - text.trimLeft().length;

  final featuresByRange = <(int, int), List<FacetFeature>>{};
  final codeRanges = <TextRange>[];

  void add(int start, int end, FacetFeature feature, {required bool isCode}) {
    final features = featuresByRange.putIfAbsent((start, end), () => []);
    if (!features.contains(feature)) {
      features.add(feature);
    }
    if (isCode) {
      codeRanges.add(TextRange(start: start, end: end));
    }
  }

  (int, int) clipped(int start, int end) => (
    (start - leadingTrim).clamp(0, content.length),
    (end - leadingTrim).clamp(0, content.length),
  );

  for (final range in inlineRanges) {
    final (start, end) = clipped(range.start, range.end);
    if (end <= start) {
      continue;
    }
    add(start, end, switch (range.format) {
      InlineFormat.bold => const BoldFacetFeature(),
      InlineFormat.italic => const ItalicFacetFeature(),
      InlineFormat.strikethrough => const StrikethroughFacetFeature(),
      InlineFormat.spoiler => SpoilerFacetFeature(reason: range.reason),
      InlineFormat.code => const CodeFacetFeature(),
    }, isCode: range.format == InlineFormat.code);
  }

  for (final range in blockRanges) {
    var (start, end) = clipped(range.start, range.end);
    // Empty lines at either end of a block are newlines alone
    while (start < end && content.codeUnitAt(start) == _newline) {
      start++;
    }
    while (end > start && content.codeUnitAt(end - 1) == _newline) {
      end--;
    }
    if (end <= start) {
      continue;
    }
    add(start, end, switch (range.format) {
      BlockFormat.blockquote => BlockquoteFacetFeature(level: range.level),
      BlockFormat.heading => HeadingFacetFeature(level: range.level),
      BlockFormat.codeBlock => CodeBlockFacetFeature(language: range.language),
    }, isCode: range.format == BlockFormat.codeBlock);
  }

  // A feature range passed in with a bound between the halves of a
  // surrogate pair is dropped
  bool splitsSurrogatePair(int index) =>
      index > 0 &&
      index < content.length &&
      _isHighSurrogate(content.codeUnitAt(index - 1)) &&
      _isLowSurrogate(content.codeUnitAt(index));

  for (final range in featureRanges) {
    final (start, end) = clipped(range.start, range.end);
    if (end <= start ||
        splitsSurrogatePair(start) ||
        splitsSurrogatePair(end)) {
      continue;
    }
    add(start, end, range.feature, isCode: false);
  }

  return (
    content: content,
    featuresByRange: featuresByRange,
    codeRanges: codeRanges,
  );
}

const _newline = 0x0A;

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

/// The most features one facet may carry, the lexicon's `features`
/// maxLength.
const _maxFeaturesPerFacet = 20;

/// [features] in lexicon union order, keeping their given order among
/// features of one union position (List.sort is not stable).
List<FacetFeature> _inUnionOrder(List<FacetFeature> features) {
  final order = List.generate(features.length, (index) => index)
    ..sort((a, b) {
      final byUnion = _unionOrder(features[a])
          .compareTo(_unionOrder(features[b]));
      return byUnion != 0 ? byUnion : a.compareTo(b);
    });
  return [for (final index in order) features[index]];
}

/// How many facets [featuresByRange] serializes to: one per range, plus one
/// for each further run of [_maxFeaturesPerFacet] features on it.
int _facetCount(Map<(int, int), List<FacetFeature>> featuresByRange) {
  var count = 0;
  for (final features in featuresByRange.values) {
    count +=
        (features.length + _maxFeaturesPerFacet - 1) ~/ _maxFeaturesPerFacet;
  }
  return count;
}

/// [features] cut into consecutive runs of at most [_maxFeaturesPerFacet].
List<List<FacetFeature>> _chunked(List<FacetFeature> features) => [
  for (var start = 0; start < features.length; start += _maxFeaturesPerFacet)
    features.sublist(
      start,
      math.min(start + _maxFeaturesPerFacet, features.length),
    ),
];

/// The position of [feature]'s type in the lexicon's facet feature union,
/// the order features of one facet are written in
int _unionOrder(FacetFeature feature) => switch (feature) {
  MentionFacetFeature() => 0,
  LinkFacetFeature() => 1,
  BoldFacetFeature() => 2,
  ItalicFacetFeature() => 3,
  StrikethroughFacetFeature() => 4,
  SpoilerFacetFeature() => 5,
  BlockquoteFacetFeature() => 6,
  HeadingFacetFeature() => 7,
  CodeFacetFeature() => 8,
  CodeBlockFacetFeature() => 9,
  UnknownFacetFeature() => 10,
};
