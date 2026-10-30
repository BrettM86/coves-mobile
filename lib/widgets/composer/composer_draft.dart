import 'facet_editing_controller.dart';

/// A composer's saved text and formatting ranges.
///
/// It owns unmodifiable copies of the lists it is given, so later changes
/// to those lists do not reach a stored draft.
class ComposerDraft {
  ComposerDraft({
    required this.text,
    List<InlineRange> inlineRanges = const [],
    List<BlockRange> blockRanges = const [],
    List<FeatureRange> featureRanges = const [],
  }) : inlineRanges = List.unmodifiable(inlineRanges),
       blockRanges = List.unmodifiable(blockRanges),
       featureRanges = List.unmodifiable(featureRanges);

  final String text;
  final List<InlineRange> inlineRanges;
  final List<BlockRange> blockRanges;
  final List<FeatureRange> featureRanges;
}
