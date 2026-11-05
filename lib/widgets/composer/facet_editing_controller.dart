import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';

import '../../constants/app_colors.dart';
import '../../models/facet.dart';
import '../../theme/rich_text_palette.dart';
import '../../utils/rich_text_composer.dart';
import '../../utils/url_policy.dart';
import '../../utils/utf8_offsets.dart';
import 'facet_serialization.dart';

/// A value with the inline, block and feature ranges that applied to it.
typedef _RangeSnapshot = ({
  TextEditingValue value,
  List<InlineRange> ranges,
  List<BlockRange> blockRanges,
  List<FeatureRange> featureRanges,
});

enum InlineFormat { bold, italic, strikethrough, spoiler, code }

class InlineRange {
  const InlineRange(this.format, this.start, this.end, {this.reason});

  final InlineFormat format;
  final int start;
  final int end;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is InlineRange &&
      other.format == format &&
      other.start == start &&
      other.end == end &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(format, start, end, reason);

  @override
  String toString() =>
      'InlineRange(${format.name}, $start, $end, reason: $reason)';
}

enum BlockFormat { blockquote, heading, codeBlock }

class BlockRange {
  const BlockRange(
    this.format,
    this.start,
    this.end, {
    this.level = 1,
    this.language,
  });

  final BlockFormat format;
  final int start;
  final int end;
  final int level;
  final String? language;

  @override
  bool operator ==(Object other) =>
      other is BlockRange &&
      other.format == format &&
      other.start == start &&
      other.end == end &&
      other.level == level &&
      other.language == language;

  @override
  int get hashCode => Object.hash(format, start, end, level, language);

  @override
  String toString() =>
      'BlockRange(${format.name}, $start, $end, level: $level, '
      'language: $language)';
}

class FeatureRange {
  const FeatureRange(this.feature, this.start, this.end);

  final FacetFeature feature;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is FeatureRange &&
      other.feature == feature &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(feature, start, end);

  @override
  String toString() => 'FeatureRange($feature, $start, $end)';
}

/// Text controller that tracks inline formatting ranges over its text.
class FacetEditingController extends TextEditingController {
  FacetEditingController({super.text});

  /// A controller holding a stored record's [content] verbatim and its
  /// [facets] as ranges, for editing an existing post or comment.
  ///
  /// Each facet's UTF-8 byte range becomes a UTF-16 range, and each of its
  /// features becomes its own range over it: bold, italic, strikethrough,
  /// spoiler (with its reason) and inline code in [inlineRanges]; quote,
  /// heading (with their levels) and code block (with its language) in
  /// [blockRanges], widened to the whole lines they touch; mentions, links
  /// and features of unknown type in [featureRanges], kept with their DID,
  /// uri or raw data. A link whose uri fails [isAllowedWebUrl] and a mention
  /// whose DID fails [isValidDid] are not kept. A facet whose start or end
  /// falls inside a multi-byte character, outside the content, or inside an
  /// extended grapheme cluster is dropped whole; the other facets load.
  ///
  /// The ranges are canonical once loaded: an exact duplicate loads once,
  /// same-format inline ranges with the same reason that touch or overlap
  /// merge, and blocks settle as the editor leaves them (same-kind quotes or
  /// code blocks that overlap or sit on adjacent lines merge, and a quote
  /// crossing a code block widens over its lines). Ranges with different
  /// reasons, levels or languages never merge.
  ///
  /// Saving passes [text] and all three range lists to [serializeFormatting].
  /// The edit flow's update call sends the record's existing embed, langs
  /// and labels unchanged alongside the new content and facets, and an
  /// optimistic local copy replaces content and facets together, never one
  /// without the other.
  FacetEditingController.fromRecord(String content, List<RichTextFacet> facets)
    : super(text: content) {
    final offsets = Utf8Offsets(content);
    final graphemeBoundaries = _GraphemeBoundaries(content);
    final lines = _Lines(content);
    int? charIndexOf(int byteOffset) {
      final charIndex = offsets.charIndexOf(byteOffset);
      return charIndex != null && graphemeBoundaries.contains(charIndex)
          ? charIndex
          : null;
    }

    for (final facet in facets) {
      final start = charIndexOf(facet.index.byteStart);
      final end = charIndexOf(facet.index.byteEnd);
      if (start == null || end == null || end <= start) {
        continue;
      }
      for (final feature in facet.features) {
        void addInline(InlineFormat format, {String? reason}) =>
            _inlineRanges.add(InlineRange(format, start, end, reason: reason));
        void addBlock(BlockFormat format, {int level = 1, String? language}) {
          // Leading and trailing newlines belong to the neighbouring lines;
          // widen from the first and last characters the block covers.
          var blockStart = start;
          var blockEnd = end;
          while (blockStart < blockEnd && content[blockStart] == '\n') {
            blockStart++;
          }
          while (blockEnd > blockStart && content[blockEnd - 1] == '\n') {
            blockEnd--;
          }
          if (blockEnd == blockStart) {
            return;
          }
          final block = BlockRange(
            format,
            lines.startOf(lines.indexOf(blockStart)),
            lines.endOf(lines.indexOf(blockEnd - 1)),
            level: level,
            language: language,
          );
          if (!_blockRanges.contains(block)) {
            _blockRanges.add(block);
          }
        }

        switch (feature) {
          case BoldFacetFeature():
            addInline(InlineFormat.bold);
          case ItalicFacetFeature():
            addInline(InlineFormat.italic);
          case StrikethroughFacetFeature():
            addInline(InlineFormat.strikethrough);
          case SpoilerFacetFeature(:final reason):
            addInline(InlineFormat.spoiler, reason: reason);
          case CodeFacetFeature():
            addInline(InlineFormat.code);
          case BlockquoteFacetFeature(:final level):
            addBlock(BlockFormat.blockquote, level: level);
          case HeadingFacetFeature(:final level):
            addBlock(BlockFormat.heading, level: level);
          case CodeBlockFacetFeature(:final language):
            addBlock(BlockFormat.codeBlock, language: language);
          // A link or mention that fails policy is not kept, so its text is
          // detected and looked up again like typed text.
          case LinkFacetFeature(:final uri) when !isAllowedWebUrl(uri):
            break;
          case MentionFacetFeature(:final did) when !isValidDid(did):
            break;
          // fromJson reads a link or mention without a usable uri or did as
          // an unknown feature; the backend rejects it, so it is not kept.
          case UnknownFacetFeature(:final data)
              when data[r'$type'] == LinkFacetFeature.typeId ||
                  data[r'$type'] == MentionFacetFeature.typeId:
            break;
          // An image placement is kept as is, like a feature this composer
          // doesn't edit, so editing a comment keeps its placed images.
          case MentionFacetFeature() ||
              LinkFacetFeature() ||
              ImageFacetFeature() ||
              UnknownFacetFeature():
            final range = FeatureRange(feature, start, end);
            if (!_featureRanges.contains(range)) {
              _featureRanges.add(range);
            }
        }
      }
    }
    _canonicalizeLoadedRanges(lines);
  }

  /// A controller holding a saved composer draft: [text] verbatim with its
  /// [inlineRanges], [blockRanges] and [featureRanges] as they were taken
  /// from a controller over the same text.
  ///
  /// The ranges load as given, without a formatting budget check, and are
  /// made canonical the way [FacetEditingController.fromRecord] makes them.
  FacetEditingController.withRanges(
    String text, {
    List<InlineRange> inlineRanges = const [],
    List<BlockRange> blockRanges = const [],
    List<FeatureRange> featureRanges = const [],
  }) : super(text: text) {
    _inlineRanges.addAll(inlineRanges);
    _blockRanges.addAll(blockRanges);
    _featureRanges.addAll(featureRanges);
    _canonicalizeLoadedRanges(_Lines(text));
  }

  /// Merges same-format inline ranges with equal attributes that touch or
  /// overlap, as the editor merges them, and settles blocks the editor's way.
  void _canonicalizeLoadedRanges(_Lines lines) {
    final loadedInline = [..._inlineRanges];
    _inlineRanges
      ..clear()
      ..addAll([
        for (final format in InlineFormat.values)
          ..._merge([
            for (final range in loadedInline)
              if (range.format == format) range,
          ]),
      ])
      ..sort(_compareRanges);
    final settledBlocks = {
      for (final block in _settled(_lineBlocks(_blockRanges, lines)))
        block.toRange(lines),
    };
    _blockRanges
      ..clear()
      ..addAll(settledBlocks);
  }

  /// Loaded mention, link and unknown-type features, in load order. They
  /// pass through the same composing gate as [_inlineRanges].
  final List<FeatureRange> _featureRanges = [];

  /// Cached provisional remap of the held feature ranges onto the current
  /// value while composing; cleared together with [_provisionalRanges].
  List<FeatureRange>? _provisionalFeatureRanges;

  final List<InlineRange> _inlineRanges = [];

  /// Formats applied to text inserted at the current collapsed caret.
  final Set<InlineFormat> _armedFormats = {};

  /// The value before the active IME composition began, or null when no
  /// composition is active. While it is set, [_inlineRanges] and
  /// [_armedFormats] are held in this value's coordinates.
  TextEditingValue? _preCompositionValue;

  /// The value and ranges from before the active composition began, kept
  /// only once a selection toggle or caret move has rebased the composition,
  /// so a cancel can still restore the original ranges.
  _RangeSnapshot? _cancelBaseline;

  /// Cached provisional remap of the held ranges onto the current value
  /// while composing; cleared whenever the value or the ranges change.
  List<InlineRange>? _provisionalRanges;

  /// Block ranges, each covering whole lines. They pass through the same
  /// composing gate as [_inlineRanges]: while a composition is active they
  /// are held in the coordinates of [_preCompositionValue].
  final List<BlockRange> _blockRanges = [];

  /// Cached provisional remap of the held block ranges onto the current
  /// value while composing; cleared together with [_provisionalRanges].
  List<BlockRange>? _provisionalBlockRanges;

  /// Where the active composition's text begins, in the coordinates of
  /// [_preCompositionValue]; null when that is unknown. A composition that
  /// re-composes an existing word begins at the word's start.
  int? _composedStart;

  /// Formats flipped at a collapsed caret during the active composition.
  final Set<InlineFormat> _composingToggles = {};

  /// Whether the active composition has changed the text at any point.
  bool _compositionChangedText = false;

  /// The formats armed at a collapsed caret just before the latest update
  /// selected the text ending at that caret without changing it, as the iOS
  /// Korean keyboard does before replacing a syllable; null otherwise.
  Set<InlineFormat>? _armedBeforeSelection;

  /// The selected value and its ranges from before an update that deleted
  /// exactly a selection like [_armedBeforeSelection]'s, kept until the next
  /// update so text inserted in the selection's place replaces it as a whole,
  /// with the formats armed before the selection for any text it adds.
  ({_RangeSnapshot snapshot, Set<InlineFormat> armed})? _deletedSelection;

  /// Remaps the inline ranges and the armed formats to [newValue] before
  /// listeners are notified, so they always see text and ranges that agree.
  ///
  /// While an IME composition is active the ranges are held, and they are
  /// remapped once from the pre-composition value when it ends. A caret move
  /// during a composition rebases it onto the current text and re-arms the
  /// formats at the new caret.
  @override
  set value(TextEditingValue newValue) {
    final oldValue = super.value;
    _provisionalRanges = null;
    _provisionalBlockRanges = null;
    _provisionalFeatureRanges = null;
    if (_isComposing(newValue)) {
      if (_preCompositionValue == null) {
        _forgetKeyboardReplacement();
        _preCompositionValue = oldValue;
        _composedStart = _unchangedPrefixOffset(
          oldValue.text,
          newValue.text,
          newValue.composing.start,
        );
      }
      if (newValue.text != oldValue.text) {
        _compositionChangedText = true;
      }
      if (newValue.text == oldValue.text &&
          newValue.selection != oldValue.selection) {
        _rebaseComposition(oldValue.copyWith(selection: newValue.selection));
        _resetArmedFormats(newValue.selection);
      }
    } else {
      final preCompositionValue = _preCompositionValue;
      final cancelBaseline = _cancelBaseline;
      final composedStart = _composedStart;
      final composingToggles = {..._composingToggles};
      final compositionChangedText = _compositionChangedText;
      _preCompositionValue = null;
      _cancelBaseline = null;
      _composedStart = null;
      _composingToggles.clear();
      _compositionChangedText = false;
      // Only a composition that changed the text and then returned to the
      // original is a cancel; committing text it never changed is not.
      if (cancelBaseline != null &&
          compositionChangedText &&
          newValue.text == cancelBaseline.value.text) {
        // A cancelled rebased composition: restore the original ranges.
        _inlineRanges
          ..clear()
          ..addAll(cancelBaseline.ranges);
        _blockRanges
          ..clear()
          ..addAll(cancelBaseline.blockRanges);
        _featureRanges
          ..clear()
          ..addAll(cancelBaseline.featureRanges);
        _resetArmedFormats(newValue.selection);
        super.value = newValue;
        return;
      }
      final baseValue = preCompositionValue ?? oldValue;
      final repeated = preCompositionValue == null && newValue == oldValue;
      // Keyboards repeat updates; a repeat leaves this state as it is.
      final armedBeforeSelection = repeated ? null : _armedBeforeSelection;
      final deletedSelection = repeated ? null : _deletedSelection;
      if (!repeated) {
        _armedBeforeSelection = null;
        _deletedSelection = null;
      }
      if (newValue.text != baseValue.text) {
        final rewritten = preCompositionValue == null
            ? _rewriteBeforeCaret(oldValue, newValue)
            : null;
        final deletesSelection =
            preCompositionValue == null &&
            armedBeforeSelection != null &&
            _deletesSelection(oldValue, newValue);
        if (deletesSelection) {
          _deletedSelection = (
            snapshot: (
              value: oldValue,
              ranges: [..._inlineRanges],
              blockRanges: [..._blockRanges],
              featureRanges: [..._featureRanges],
            ),
            armed: armedBeforeSelection,
          );
        }
        final replacesDeletedSelection =
            preCompositionValue == null &&
            deletedSelection != null &&
            _insertsAtCaret(oldValue, newValue);
        if (rewritten != null) {
          // The rewrite keeps its text's formats and the insertion at the
          // caret takes the formats armed there
          _applyEdit(oldValue, rewritten);
          _applyEdit(rewritten, newValue);
        } else if (replacesDeletedSelection) {
          final rest = _replaceDeletedSelection(
            deletedSelection.snapshot,
            newValue,
            deletedSelection.armed,
          );
          if (rest != null) {
            _deletedSelection = (snapshot: rest, armed: deletedSelection.armed);
          }
        } else {
          _applyEdit(
            baseValue,
            newValue,
            composedStart: preCompositionValue == null ? null : composedStart,
            composingToggles: composingToggles,
          );
        }
        if (replacesDeletedSelection) {
          // A keyboard replacing what it selected keeps the formats armed
          // before the selection.
          _armedFormats
            ..clear()
            ..addAll(deletedSelection.armed);
        } else {
          _resetArmedFormats(newValue.selection);
        }
      } else if (preCompositionValue == null &&
          newValue.selection != oldValue.selection &&
          _selectsBeforeCaret(oldValue, newValue)) {
        _armedBeforeSelection = {..._armedFormats};
        _resetArmedFormats(newValue.selection);
      } else if (preCompositionValue != null
          ? newValue.selection != preCompositionValue.selection
          : newValue.selection != oldValue.selection) {
        // A commit of unchanged text keeps formats armed during the
        // composition unless the caret moved.
        _resetArmedFormats(newValue.selection);
      }
    }
    super.value = newValue;
  }

  /// Moves the stored ranges through the edit from [oldValue] to [newValue],
  /// as [_remapped], [_remappedBlocks] and [_remappedFeatures] describe;
  /// the armed formats are left as they are. [armedFormats] stands in for
  /// them when given.
  void _applyEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue, {
    int? composedStart,
    Set<InlineFormat> composingToggles = const {},
    Set<InlineFormat>? armedFormats,
  }) {
    final remapped = _remapped(
      oldValue,
      newValue,
      composedStart: composedStart,
      composingToggles: composingToggles,
      armedFormats: armedFormats,
    );
    final remappedBlocks = _remappedBlocks(oldValue, newValue);
    final remappedFeatures = _remappedFeatures(oldValue, newValue);
    _inlineRanges
      ..clear()
      ..addAll(
        _outsideCodeBlocks(
          remapped,
          remappedBlocks,
          within: _editedLines(oldValue, newValue),
        ),
      );
    _blockRanges
      ..clear()
      ..addAll(remappedBlocks);
    _featureRanges
      ..clear()
      ..addAll(remappedFeatures);
  }

  /// The value between the two parts of an update that changes only the
  /// letter case of text before [oldValue]'s collapsed caret and inserts
  /// text at the caret, such as a key-event keyboard capitalising a line's
  /// first word together with the next character; null for any other
  /// update, including an autocorrection, or when the formats armed at the
  /// caret are the ones before it, so no toggle there is pending.
  TextEditingValue? _rewriteBeforeCaret(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final caret = _collapsedCaret(oldValue);
    final oldText = oldValue.text;
    final newText = newValue.text;
    final insertedLength = newText.length - oldText.length;
    if (caret == null ||
        insertedLength <= 0 ||
        setEquals(_armedFormats, _formatsBefore(_inlineRanges, caret))) {
      return null;
    }
    final rewrittenPrefix = newText.substring(0, caret);
    final oldPrefix = oldText.substring(0, caret);
    if (rewrittenPrefix == oldPrefix ||
        rewrittenPrefix.toLowerCase() != oldPrefix.toLowerCase() ||
        newText.substring(caret + insertedLength) != oldText.substring(caret)) {
      return null;
    }
    return TextEditingValue(
      text: rewrittenPrefix + oldText.substring(caret),
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// Forgets a keyboard replacement in progress, for edits made outside the
  /// value setter.
  void _forgetKeyboardReplacement() {
    _armedBeforeSelection = null;
    _deletedSelection = null;
  }

  /// Whether [newValue] selects text ending at [oldValue]'s collapsed caret.
  bool _selectsBeforeCaret(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final caret = _collapsedCaret(oldValue);
    final selection = newValue.selection;
    return caret != null &&
        selection.isValid &&
        !selection.isCollapsed &&
        selection.end == caret;
  }

  /// Whether [newValue] deletes exactly [oldValue]'s selection and leaves
  /// the caret where it began.
  bool _deletesSelection(TextEditingValue oldValue, TextEditingValue newValue) {
    final selection = oldValue.selection;
    final oldText = oldValue.text;
    return selection.isValid &&
        !selection.isCollapsed &&
        _collapsedCaret(newValue) == selection.start &&
        newValue.text ==
            oldText.substring(0, selection.start) +
                oldText.substring(selection.end);
  }

  /// Whether [newValue] only inserts text at [oldValue]'s collapsed caret
  /// and leaves the caret after it.
  bool _insertsAtCaret(TextEditingValue oldValue, TextEditingValue newValue) {
    final caret = _collapsedCaret(oldValue);
    final oldText = oldValue.text;
    final newText = newValue.text;
    final insertedLength = newText.length - oldText.length;
    return caret != null &&
        insertedLength > 0 &&
        _collapsedCaret(newValue) == caret + insertedLength &&
        newText.startsWith(oldText.substring(0, caret)) &&
        newText.endsWith(oldText.substring(caret));
  }

  /// Restores the ranges from before [deleted]'s selection was deleted and
  /// moves them onto [newValue], whose text puts an insertion in the
  /// selection's place. The insertion replaces the selection character by
  /// character: each replaced character passes its formats to the one now in
  /// its place, and characters beyond the selection's length take the
  /// formats armed before the selection, [armed]. With a surrogate pair on
  /// either side it is one replacement.
  ///
  /// Returns the replaced characters not yet put back, as a selection like
  /// [deleted]'s, when the insertion is shorter than the selection: keyboards
  /// put a replacement back over several updates. Returns null otherwise.
  _RangeSnapshot? _replaceDeletedSelection(
    _RangeSnapshot deleted,
    TextEditingValue newValue,
    Set<InlineFormat> armed,
  ) {
    _inlineRanges
      ..clear()
      ..addAll(deleted.ranges);
    _blockRanges
      ..clear()
      ..addAll(deleted.blockRanges);
    _featureRanges
      ..clear()
      ..addAll(deleted.featureRanges);
    final text = deleted.value.text;
    final start = deleted.value.selection.start;
    final end = deleted.value.selection.end;
    final replaced = text.substring(start, end);
    final inserted = newValue.text.substring(
      start,
      newValue.text.length - (text.length - end),
    );
    bool hasSurrogate(String part) =>
        part.codeUnits.any((unit) => unit >= 0xD800 && unit <= 0xDFFF);
    if (hasSurrogate(replaced) || hasSurrogate(inserted)) {
      _applyEdit(deleted.value, newValue);
      return null;
    }
    var current = deleted.value.copyWith(
      selection: TextSelection.collapsed(offset: end),
    );
    void step(String nextText, int caret, {Set<InlineFormat>? armed}) {
      final next = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: caret),
      );
      _applyEdit(current, next, armedFormats: armed);
      current = next;
    }

    final kept = math.min(replaced.length, inserted.length);
    for (var i = 0; i < kept; i++) {
      if (replaced[i] != inserted[i]) {
        final at = start + i;
        current = current.copyWith(
          selection: TextSelection.collapsed(offset: at + 1),
        );
        // With the old caret after the replaced character, the replacement
        // takes that character's formats and not the armed ones.
        step(current.text.replaceRange(at, at + 1, inserted[i]), at + 1);
      }
    }
    final at = start + kept;
    current = current.copyWith(selection: TextSelection.collapsed(offset: at));
    if (inserted.length > kept) {
      step(
        current.text.replaceRange(at, at, inserted.substring(kept)),
        start + inserted.length,
        armed: armed,
      );
    } else if (replaced.length > kept) {
      final rest = (
        value: current.copyWith(
          selection: TextSelection(
            baseOffset: at,
            extentOffset: start + replaced.length,
          ),
        ),
        ranges: [..._inlineRanges],
        blockRanges: [..._blockRanges],
        featureRanges: [..._featureRanges],
      );
      step(current.text.replaceRange(at, start + replaced.length, ''), at);
      return rest;
    }
    return null;
  }

  /// Arms the formats of the ranges that cover the character before a
  /// collapsed [newSelection]; arms nothing otherwise, or in a code block.
  void _resetArmedFormats(TextSelection newSelection) {
    _armedFormats.clear();
    if (newSelection.isValid &&
        newSelection.isCollapsed &&
        !_touchesCodeBlock(
          _blockRanges,
          newSelection.baseOffset,
          newSelection.baseOffset,
        )) {
      _armedFormats.addAll(
        _formatsBefore(_inlineRanges, newSelection.baseOffset),
      );
    }
  }

  /// The ranges as they apply to the current text: while composing, the held
  /// ranges provisionally remapped onto the composing text, without the parts
  /// on code-block lines; otherwise the stored ranges.
  List<InlineRange> get _displayRanges {
    final preCompositionValue = _preCompositionValue;
    if (preCompositionValue == null || preCompositionValue.text == value.text) {
      return _inlineRanges;
    }
    return _provisionalRanges ??= _outsideCodeBlocks(
      _remapped(
        preCompositionValue,
        value,
        composedStart: _composedStart,
        composingToggles: _composingToggles,
      ),
      _displayBlockRanges,
      within: _editedLines(preCompositionValue, value),
    );
  }

  /// Moves the stored ranges onto [current] (a value with the current text)
  /// while composing, so the composition continues from it; the original
  /// pre-composition value and ranges are kept for a cancel.
  void _rebaseComposition(TextEditingValue current) {
    final preCompositionValue = _preCompositionValue;
    if (preCompositionValue == null) {
      return;
    }
    _cancelBaseline ??= (
      value: preCompositionValue,
      ranges: [..._inlineRanges],
      blockRanges: [..._blockRanges],
      featureRanges: [..._featureRanges],
    );
    final displayed = [..._displayRanges];
    final displayedBlocks = [..._displayBlockRanges];
    final displayedFeatures = [..._displayFeatureRanges];
    _inlineRanges
      ..clear()
      ..addAll(displayed);
    _blockRanges
      ..clear()
      ..addAll(displayedBlocks);
    _featureRanges
      ..clear()
      ..addAll(displayedFeatures);
    _provisionalBlockRanges = null;
    _provisionalFeatureRanges = null;
    _preCompositionValue = current;
    _composedStart = current.composing.isValid ? current.composing.start : null;
    _composingToggles.clear();
    _provisionalRanges = null;
  }

  /// The stored ranges moved through the single replaced region that turns
  /// [oldValue]'s text into [newValue]'s text, sorted by [_compareRanges].
  ///
  /// When [oldValue] is the value before a composition, [composedStart] is
  /// where the composition's text begins and [composingToggles] are the
  /// formats flipped at the caret during it. The composed insertion runs from
  /// [composedStart] (or the replaced region's start, if earlier) to the end
  /// of the replaced region's new text, and each toggled format is applied to
  /// or removed from all of it. [armedFormats] stands in for the armed
  /// formats when given.
  List<InlineRange> _remapped(
    TextEditingValue oldValue,
    TextEditingValue newValue, {
    int? composedStart,
    Set<InlineFormat> composingToggles = const {},
    Set<InlineFormat>? armedFormats,
  }) {
    final armed = armedFormats ?? _armedFormats;
    final oldText = oldValue.text;
    final newText = newValue.text;
    final replaced = _replacedRegion(
      oldText,
      newText,
      newValue.selection.isValid && newValue.selection.isCollapsed
          ? newValue.selection.baseOffset
          : null,
    );
    final start = replaced.start;
    final deletedLength = replaced.oldEnd - start;
    final insertedLength = replaced.newEnd - start;

    int afterDeletion(int position) {
      if (position <= start) {
        return position;
      }
      if (position >= replaced.oldEnd) {
        return position - deletedLength;
      }
      return start;
    }

    final remaining = [
      for (final range in _inlineRanges)
        InlineRange(
          range.format,
          afterDeletion(range.start),
          afterDeletion(range.end),
          reason: range.reason,
        ),
    ].where((range) => range.start < range.end).toList();

    final oldSelection = oldValue.selection;
    // The armed formats apply only to text inserted at the caret; formats
    // toggled during a composition are applied below through
    // [composingToggles].
    final armedApplies =
        oldSelection.isValid &&
        oldSelection.isCollapsed &&
        oldSelection.baseOffset == start;
    final armedForInsertion = armedApplies
        ? {...armed}
        : deletedLength > 0
        ? <InlineFormat>{}
        : _formatsBefore(remaining, start);
    // Replacement text takes the formats of the first character it replaces,
    // with their reasons, not those of the character before it.
    final replacedReasons = <InlineFormat, String?>{};
    if (deletedLength > 0) {
      for (final range in _inlineRanges) {
        if (range.start <= start && start < range.end) {
          replacedReasons.putIfAbsent(range.format, () => range.reason);
        }
      }
      armedForInsertion.addAll(replacedReasons.keys);
    }

    final inserted = <InlineRange>[];
    // Armed formats whose existing range grows over the insertion; such a
    // range keeps its attributes and no new range is added for the format.
    final extendedFormats = <InlineFormat>{};
    for (final range in remaining) {
      if (range.start >= start) {
        inserted.add(
          InlineRange(
            range.format,
            range.start + insertedLength,
            range.end + insertedLength,
            reason: range.reason,
          ),
        );
      } else if (range.end < start) {
        inserted.add(range);
      } else if (armedForInsertion.contains(range.format) &&
          (!replacedReasons.containsKey(range.format) ||
              replacedReasons[range.format] == range.reason)) {
        extendedFormats.add(range.format);
        inserted.add(
          InlineRange(
            range.format,
            range.start,
            range.end + insertedLength,
            reason: range.reason,
          ),
        );
      } else {
        inserted
          ..add(
            InlineRange(range.format, range.start, start, reason: range.reason),
          )
          ..add(
            InlineRange(
              range.format,
              start + insertedLength,
              range.end + insertedLength,
              reason: range.reason,
            ),
          );
      }
    }
    // Replacement text carries the reason of the range it inherits from, so
    // the merge below joins it to that range when it was shifted, not
    // extended (a replacement starting at the range's start).
    if (insertedLength > 0) {
      for (final format in armedForInsertion.difference(extendedFormats)) {
        inserted.add(
          InlineRange(
            format,
            start,
            start + insertedLength,
            reason: replacedReasons[format],
          ),
        );
      }
    }
    // Each format toggled during the composition is applied to or removed
    // from the whole composed insertion, overriding what it inherited.
    if (composingToggles.isNotEmpty) {
      final composedFrom = composedStart != null && composedStart < start
          ? composedStart
          : start;
      final composed = TextRange(
        start: composedFrom,
        end: start + insertedLength,
      );
      for (final format in composingToggles) {
        if (armed.contains(format)) {
          if (!composed.isCollapsed) {
            inserted.add(InlineRange(format, composed.start, composed.end));
          }
        } else {
          final kept = [
            for (final range in inserted)
              if (range.format != format)
                range
              else
                ..._subtract(range, composed),
          ];
          inserted
            ..clear()
            ..addAll(kept);
        }
      }
    }

    // Every range is snapped, not only those near the edit: a regional
    // indicator insertion can re-pair flags anywhere after it.
    final clusterBoundaries = _GraphemeBoundaries(newText);
    final snapped = <InlineRange>[];
    for (final range in inserted) {
      if (range.start >= range.end) {
        continue;
      }
      final boundaries = clusterBoundaries.snap(
        TextRange(start: range.start, end: range.end),
      );
      if (boundaries.start < boundaries.end) {
        snapped.add(
          InlineRange(
            range.format,
            boundaries.start,
            boundaries.end,
            reason: range.reason,
          ),
        );
      }
    }

    return [
      for (final format in InlineFormat.values)
        ..._merge([
          for (final range in snapped)
            if (range.format == format) range,
        ]),
    ]..sort(_compareRanges);
  }

  /// All inline ranges in the current text's coordinates, sorted by start,
  /// then end, then format index. While an IME composition is active these
  /// are the held ranges provisionally remapped onto the composing text.
  List<InlineRange> get inlineRanges => List.unmodifiable(_displayRanges);

  /// The stored ranges, which while an IME composition is active are held in
  /// the coordinates of the value before the composition began.
  @visibleForTesting
  List<InlineRange> get heldInlineRanges => List.unmodifiable(_inlineRanges);

  /// All block ranges in the current text's coordinates, in no particular
  /// order. While an IME composition is active these are the held block
  /// ranges provisionally remapped onto the composing text.
  ///
  /// The quote is always outer: a code block or heading never strictly
  /// contains a quote, and a quote and a code block over the same lines
  /// render as the quote containing the code block.
  List<BlockRange> get blockRanges => List.unmodifiable(_displayBlockRanges);

  /// The loaded mention, link and unknown-type feature ranges in the current
  /// text's coordinates, in load order. While an IME composition is active
  /// these are the held ranges provisionally remapped onto the composing
  /// text.
  ///
  /// Edits move them without looking at their content: an insertion strictly
  /// inside a range extends it, one at or before its start shifts it, one at
  /// or after its end leaves it, and a range whose text is all deleted is
  /// removed. A mention or link range is instead removed by any edit that
  /// changes its own text, including one that regroups its first or last
  /// grapheme cluster.
  List<FeatureRange> get featureRanges =>
      List.unmodifiable(_displayFeatureRanges);

  /// The feature ranges as they apply to the current text: while composing,
  /// the held ranges provisionally remapped onto the composing text;
  /// otherwise the stored ranges.
  List<FeatureRange> get _displayFeatureRanges {
    final preCompositionValue = _preCompositionValue;
    if (preCompositionValue == null || preCompositionValue.text == value.text) {
      return _featureRanges;
    }
    return _provisionalFeatureRanges ??= _remappedFeatures(
      preCompositionValue,
      value,
    );
  }

  /// The stored feature ranges moved through the single replaced region that
  /// turns [oldValue]'s text into [newValue]'s text, in load order, by the
  /// rule on [featureRanges]; a replacement that starts strictly inside a
  /// range extends it over the replacement text. Each range is widened to
  /// grapheme-cluster boundaries, except a mention or link range, which is
  /// dropped when it no longer lies on them.
  List<FeatureRange> _remappedFeatures(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_featureRanges.isEmpty) {
      return [];
    }
    final newText = newValue.text;
    final replaced = _replacedRegion(
      oldValue.text,
      newText,
      _collapsedCaret(newValue),
    );
    final start = replaced.start;
    final deletedLength = replaced.oldEnd - start;
    final insertedLength = replaced.newEnd - start;
    int afterDeletion(int position) {
      if (position <= start) {
        return position;
      }
      if (position >= replaced.oldEnd) {
        return position - deletedLength;
      }
      return start;
    }

    final clusterBoundaries = _GraphemeBoundaries(newText);
    final remapped = <FeatureRange>[];
    for (final range in _featureRanges) {
      if (_isLinkOrMention(range.feature) ||
          range.feature is ImageFacetFeature) {
        // A mention or link covers exactly its own text: an edit that
        // changes that text drops it, so the text is detected again. An
        // image placement's covered text stands in for the image; text
        // typed into it would vanish under the image, so the placement goes
        // and the image falls back to the gallery.
        final changesOwnText = deletedLength > 0
            ? start < range.end && range.start < replaced.oldEnd
            : range.start < start && start < range.end;
        if (changesOwnText) {
          continue;
        }
        final shift = range.start >= replaced.oldEnd
            ? insertedLength - deletedLength
            : 0;
        final moved = TextRange(
          start: range.start + shift,
          end: range.end + shift,
        );
        // An edit beside it that regroups its first or last grapheme
        // (a combining mark appended at its end) changes its text too.
        if (clusterBoundaries.snap(moved) == moved) {
          remapped.add(FeatureRange(range.feature, moved.start, moved.end));
        }
        continue;
      }
      var rangeStart = afterDeletion(range.start);
      var rangeEnd = afterDeletion(range.end);
      if (range.start >= start) {
        rangeStart += insertedLength;
        rangeEnd += insertedLength;
      } else if (range.end > start) {
        rangeEnd += insertedLength;
      }
      if (rangeStart >= rangeEnd) {
        continue;
      }
      final boundaries = clusterBoundaries.snap(
        TextRange(start: rangeStart, end: rangeEnd),
      );
      remapped.add(
        FeatureRange(range.feature, boundaries.start, boundaries.end),
      );
    }
    return remapped;
  }

  /// The block ranges as they apply to the current text: while composing,
  /// the held ranges provisionally remapped onto the composing text;
  /// otherwise the stored ranges.
  List<BlockRange> get _displayBlockRanges {
    final preCompositionValue = _preCompositionValue;
    if (preCompositionValue == null || preCompositionValue.text == value.text) {
      return _blockRanges;
    }
    return _provisionalBlockRanges ??= _remappedBlocks(
      preCompositionValue,
      value,
    );
  }

  /// Drops every block range, including a zero-length range on an empty
  /// document, where the value setter sees no text change.
  @override
  set text(String newText) {
    if (newText.isEmpty) {
      _droppingBlockRanges(() => super.text = newText);
    } else {
      super.text = newText;
    }
  }

  @override
  void clear() => _droppingBlockRanges(super.clear);

  /// Drops every block range, runs [reset], then disarms every format armed
  /// or toggled at the caret. Notifies listeners when a range or format was
  /// dropped but [reset] left the value unchanged, which happens on an empty
  /// document with an activated block or an armed format.
  void _droppingBlockRanges(void Function() reset) {
    _forgetKeyboardReplacement();
    final valueBefore = value;
    final droppedBlocks = _dropBlockRanges();
    reset();
    final droppedFormats =
        _armedFormats.isNotEmpty || _composingToggles.isNotEmpty;
    _armedFormats.clear();
    _composingToggles.clear();
    if ((droppedBlocks || droppedFormats) && value == valueBefore) {
      notifyListeners();
    }
  }

  /// Drops every block and feature range and returns whether any block
  /// range was dropped.
  bool _dropBlockRanges() {
    final dropped = _blockRanges.isNotEmpty;
    _blockRanges.clear();
    _featureRanges.clear();
    _provisionalBlockRanges = null;
    _provisionalFeatureRanges = null;
    final cancelBaseline = _cancelBaseline;
    if (cancelBaseline != null) {
      _cancelBaseline = (
        value: cancelBaseline.value,
        ranges: cancelBaseline.ranges,
        blockRanges: const [],
        featureRanges: const [],
      );
    }
    return dropped;
  }

  /// The stored block ranges moved through the single replaced region that
  /// turns [oldValue]'s text into [newValue]'s text, in whole lines of the
  /// new text.
  ///
  /// The edit replaces the old lines from the line where it starts (the
  /// upper line) to the line where its deleted text ends with the new lines
  /// from the upper line to the line where its inserted text ends. Lines
  /// outside the edit keep their blocks. The edited lines take the upper
  /// line's blocks: a quote or code block covers every edited line, and a
  /// heading stays on the upper line. A block that starts below the upper
  /// line keeps only the lines below the edit, and is removed when the edit
  /// joined all of its lines into the upper line.
  ///
  /// Enter (one inserted newline, nothing deleted) has two exceptions:
  ///
  /// * On an empty line, a block ends there instead of continuing: the
  ///   emptied line and the new line lose it, the lines above keep it, the
  ///   lines below keep it as a separate block, and a block that was only
  ///   that line is removed. A code block ends only when the line is its
  ///   last line; on any other code-block line every block continues. A
  ///   quote or heading ends only when no code block covers the line, so
  ///   on the last line of a quoted code block only the code block ends and
  ///   the quote covers both lines.
  /// * At the start of a non-empty heading line, the heading moves down with
  ///   the text and the new upper line is plain; a quote covers both lines.
  ///
  /// When the edit adds or removes lines, the result is settled by
  /// [_settled].
  List<BlockRange> _remappedBlocks(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_blockRanges.isEmpty) {
      return [];
    }
    final oldText = oldValue.text;
    final newText = newValue.text;
    final replaced = _replacedRegion(
      oldText,
      newText,
      newValue.selection.isValid && newValue.selection.isCollapsed
          ? newValue.selection.baseOffset
          : null,
    );
    final oldLines = _Lines(oldText);
    final newLines = _Lines(newText);
    final upperLine = oldLines.indexOf(replaced.start);
    final lastOldLine = oldLines.indexOf(replaced.oldEnd);
    final lastNewLine = newLines.indexOf(replaced.newEnd);
    final lineShift = lastNewLine - lastOldLine;
    final enter =
        replaced.oldEnd == replaced.start &&
        replaced.newEnd == replaced.start + 1 &&
        lastNewLine > upperLine;
    final upperLineEmpty =
        oldLines.startOf(upperLine) == oldLines.endOf(upperLine);
    final enterOnEmptyLine = enter && upperLineEmpty;
    final enterAtLineStart =
        enter &&
        !upperLineEmpty &&
        replaced.start == oldLines.startOf(upperLine);
    // Only Enter on an empty line asks whether a code block covers it.
    final codeBlockOnUpperLine =
        enterOnEmptyLine &&
        _blockRanges.any(
          (range) =>
              range.format == BlockFormat.codeBlock &&
              oldLines.indexOf(range.start) <= upperLine &&
              upperLine <= oldLines.indexOf(range.end),
        );

    final moved = <_LineBlock>[];
    for (final range in _blockRanges) {
      void addSpan(int first, int last) {
        if (first <= last) {
          moved.add(
            _LineBlock(
              range.format,
              range.level,
              _LineSpan(first, last),
              language: range.language,
            ),
          );
        }
      }

      final first = oldLines.indexOf(range.start);
      final last = oldLines.indexOf(range.end);
      if (last < upperLine) {
        addSpan(first, last);
      } else if (first > lastOldLine) {
        addSpan(first + lineShift, last + lineShift);
      } else if (first > upperLine) {
        addSpan(lastNewLine + 1, last + lineShift);
      } else if (enterOnEmptyLine &&
          (range.format == BlockFormat.codeBlock
              ? last == upperLine
              : !codeBlockOnUpperLine)) {
        addSpan(first, upperLine - 1);
        addSpan(upperLine + 2, last + 1);
      } else if (enterAtLineStart && range.format == BlockFormat.heading) {
        addSpan(upperLine + 1, last + lineShift);
      } else if (last > lastOldLine) {
        addSpan(first, last + lineShift);
      } else {
        addSpan(
          first,
          range.format == BlockFormat.heading ? upperLine : lastNewLine,
        );
      }
    }

    final linesChanged = lastOldLine != upperLine || lastNewLine != upperLine;
    return {
      for (final block in linesChanged ? _settled(moved) : moved)
        block.toRange(newLines),
    }.toList();
  }

  /// How many of a record's facets the current text and ranges use once
  /// serialized; it can exceed the limit, since edits are never blocked.
  FormattingBudget get formattingBudget => FormattingBudget.of(
    text,
    inlineRanges: _displayRanges,
    blockRanges: _displayBlockRanges,
    featureRanges: _displayFeatureRanges,
  );

  /// The change in the serialized facet count that [toggleBlock] with these
  /// arguments would cause, without changing anything.
  int toggleBlockCost(BlockFormat format, {int level = 1}) {
    final toggled = _blockToggled(format, level);
    if (toggled == null) {
      return 0;
    }
    return _costOf(toggled.inlineRanges, toggled.blockRanges);
  }

  /// The change in the serialized facet count that [toggleInline] with
  /// [format] would cause, without changing anything.
  int toggleInlineCost(InlineFormat format) {
    final toggled = _inlineToggled(format);
    if (toggled == null) {
      return 0;
    }
    return _costOf(toggled.inlineRanges, _displayBlockRanges);
  }

  /// Whether [toggleBlock] with these arguments may run: always when it
  /// removes the format, otherwise when its cost fits the remaining budget.
  bool canToggleBlock(BlockFormat format, {int level = 1}) {
    final toggled = _blockToggled(format, level);
    return toggled == null ||
        toggled.removing ||
        _fitsBudget(toggled.inlineRanges, toggled.blockRanges);
  }

  /// Whether [toggleInline] with [format] may run: always when it removes
  /// the format, otherwise when its cost fits the remaining budget.
  bool canToggleInline(InlineFormat format) {
    final toggled = _inlineToggled(format);
    return toggled == null ||
        toggled.removing ||
        _fitsBudget(toggled.inlineRanges, _displayBlockRanges);
  }

  /// The serialized facet count of [inlineRanges] and [blockRanges] over the
  /// current text, less the count the current ranges serialize to.
  int _costOf(List<InlineRange> inlineRanges, List<BlockRange> blockRanges) =>
      _usedBy(inlineRanges, blockRanges) - formattingBudget.used;

  /// Whether [inlineRanges] and [blockRanges] over the current text cost no
  /// more than the remaining budget.
  bool _fitsBudget(
    List<InlineRange> inlineRanges,
    List<BlockRange> blockRanges,
  ) {
    final budget = formattingBudget;
    return _usedBy(inlineRanges, blockRanges) - budget.used <= budget.remaining;
  }

  /// The serialized facet count of [inlineRanges] and [blockRanges], with
  /// the current feature ranges, over the current text.
  int _usedBy(List<InlineRange> inlineRanges, List<BlockRange> blockRanges) =>
      FormattingBudget.of(
        text,
        inlineRanges: inlineRanges,
        blockRanges: blockRanges,
        featureRanges: _displayFeatureRanges,
      ).used;

  /// The ranges [toggleBlock] would leave and whether it removes [format],
  /// computed from the ranges as they apply to the current text; null for
  /// an invalid selection.
  ({
    List<InlineRange> inlineRanges,
    List<BlockRange> blockRanges,
    bool removing,
  })?
  _blockToggled(BlockFormat format, int level) {
    if (!selection.isValid) {
      return null;
    }
    final lines = _Lines(text);
    final touched = _touchedLines(lines);
    final blocks = _lineBlocks(_displayBlockRanges, lines);

    final List<_LineBlock> updated;
    final bool removing;
    if (format == BlockFormat.heading) {
      removing = _allLinesCovered(
        blocks,
        touched,
        BlockFormat.heading,
        level: level,
      );
      updated = _toggledHeading(blocks, touched, level);
    } else {
      removing = _allLinesCovered(blocks, touched, format);
      updated = removing
          ? _withBlockCut(blocks, format, touched)
          : _withBlockAdded(blocks, format, touched);
    }

    final settled = _settled(updated);
    final blockRanges = {for (final block in settled) block.toRange(lines)}
        .toList();
    final addedCodeBlock = format == BlockFormat.codeBlock && !removing;
    return (
      inlineRanges: addedCodeBlock
          ? _outsideNewlyCodedLines(_displayRanges, blocks, settled, lines)
          : _displayRanges,
      blockRanges: blockRanges,
      removing: removing,
    );
  }

  /// The inline ranges [toggleInline] would leave and whether it removes
  /// [format], computed from the ranges as they apply to the current text;
  /// null when the toggle changes no range (in a code block, at a collapsed
  /// caret outside a composition that changed the text, or without a
  /// selection to format). At a caret during such a composition, the flip
  /// applies to or removes [format] from the composed insertion.
  ({List<InlineRange> inlineRanges, bool removing})? _inlineToggled(
    InlineFormat format,
  ) {
    if (isSelectionInCodeBlock()) {
      return null;
    }
    if (selection.isValid && selection.isCollapsed) {
      final preCompositionValue = _preCompositionValue;
      if (preCompositionValue == null ||
          preCompositionValue.text == value.text) {
        return null;
      }
      final removing = _armedFormats.contains(format);
      final armedFormats = {..._armedFormats};
      final composingToggles = {..._composingToggles};
      if (!armedFormats.remove(format)) {
        armedFormats.add(format);
      }
      if (!composingToggles.remove(format)) {
        composingToggles.add(format);
      }
      return (
        inlineRanges: _outsideCodeBlocks(
          _remapped(
            preCompositionValue,
            value,
            composedStart: _composedStart,
            composingToggles: composingToggles,
            armedFormats: armedFormats,
          ),
          _displayBlockRanges,
          within: _editedLines(preCompositionValue, value),
        ),
        removing: removing,
      );
    }
    final selected = _snappedSelection();
    if (selected == null) {
      return null;
    }
    final ranges = _displayRanges;
    final formatRanges = [
      for (final range in ranges)
        if (range.format == format) range,
    ];
    final removing = _covers(formatRanges, selected);
    final updatedFormatRanges = removing
        ? [for (final range in formatRanges) ..._subtract(range, selected)]
        : _merge([
            ...formatRanges,
            InlineRange(format, selected.start, selected.end),
          ]);
    return (
      inlineRanges: [
        for (final range in ranges)
          if (range.format != format) range,
        ...updatedFormatRanges,
      ]..sort(_compareRanges),
      removing: removing,
    );
  }

  /// Toggles [format] over every line the selection touches.
  ///
  /// A quote or code block is removed from the touched lines when all of
  /// them already have it, and added to all of them otherwise, merging with
  /// same-format blocks it overlaps or sits next to (a block next to it
  /// stays separate when the merge would cross another block's edge or put
  /// a quote strictly inside a code block). A quote that a code block would
  /// strictly contain widens to the code block's lines, and removing a quote
  /// from part of a code block's lines removes it from all of them. A
  /// heading at [level]
  /// (1–3) is removed when every touched line has it, and otherwise gives
  /// each touched line its own heading at that level. Headings and code
  /// blocks never share a line. An addition that would cross another
  /// block's edge widens to that block's edges; a removal widens over an
  /// inner block of the other format it would otherwise cut through.
  /// During a composition the toggle applies to the lines of the current
  /// text. Does nothing when [canToggleBlock] is false.
  void toggleBlock(BlockFormat format, {int level = 1}) {
    final toggled = _blockToggled(format, level);
    if (toggled == null ||
        !(toggled.removing ||
            _fitsBudget(toggled.inlineRanges, toggled.blockRanges))) {
      return;
    }
    _forgetKeyboardReplacement();
    _rebaseComposition(value);

    _blockRanges
      ..clear()
      ..addAll(toggled.blockRanges);
    _provisionalBlockRanges = null;
    if (format == BlockFormat.codeBlock && !toggled.removing) {
      // The rebase above stored the display ranges the toggle was computed
      // from, so its inline ranges apply as they are.
      _inlineRanges
        ..clear()
        ..addAll(toggled.inlineRanges);
      _armedFormats.clear();
      _composingToggles.clear();
    }
    notifyListeners();
  }

  /// Whether any line the selection touches has a heading; a selection
  /// ending at a line start does not touch that line.
  bool touchesHeading() => _headingsRemoved() != null;

  /// Removes the heading from every line the selection touches, whatever
  /// its level, and adds none. Does nothing when no touched line has one.
  void removeHeadings() {
    final blockRanges = _headingsRemoved();
    if (blockRanges == null) {
      return;
    }
    _forgetKeyboardReplacement();
    _rebaseComposition(value);

    _blockRanges
      ..clear()
      ..addAll(blockRanges);
    _provisionalBlockRanges = null;
    notifyListeners();
  }

  /// The block ranges [removeHeadings] would leave, computed from the ranges
  /// as they apply to the current text; null when it would change nothing.
  List<BlockRange>? _headingsRemoved() {
    if (!selection.isValid) {
      return null;
    }
    final lines = _Lines(text);
    final touched = _touchedLines(lines);
    final blocks = _lineBlocks(_displayBlockRanges, lines);
    final kept = [
      for (final block in blocks)
        if (block.format != BlockFormat.heading ||
            !touched.overlaps(block.span))
          block,
    ];
    if (kept.length == blocks.length) {
      return null;
    }
    return {for (final block in _settled(kept)) block.toRange(lines)}.toList();
  }

  /// The lines of [lines] the selection touches; a selection ending at a
  /// line start does not touch that line.
  _LineSpan _touchedLines(_Lines lines) {
    final touched = _touchedOffsets();
    return _LineSpan(lines.indexOf(touched.start), lines.indexOf(touched.end));
  }

  /// The selection clamped to the text, with an end at a line start moved
  /// back onto the line before, so it covers only the lines it touches.
  ({int start, int end}) _touchedOffsets() {
    final text = this.text;
    final start = selection.start.clamp(0, text.length);
    var end = selection.end.clamp(0, text.length);
    if (end > start && text[end - 1] == '\n') {
      end--;
    }
    return (start: start, end: end);
  }

  /// Toggles [format] over the current non-collapsed selection.
  ///
  /// Removes the format when it already covers the whole selection,
  /// otherwise applies it and merges touching ranges of the same format.
  /// At a collapsed caret, flips [format] in the formats armed for the text
  /// typed next instead; during a composition that applies to the whole
  /// composed insertion when it commits. Does nothing when
  /// [canToggleInline] is false.
  void toggleInline(InlineFormat format) {
    if (isSelectionInCodeBlock()) {
      return;
    }
    _forgetKeyboardReplacement();
    if (selection.isValid && selection.isCollapsed) {
      final toggled = _inlineToggled(format);
      if (toggled != null &&
          !toggled.removing &&
          !_fitsBudget(toggled.inlineRanges, _displayBlockRanges)) {
        return;
      }
      if (!_armedFormats.remove(format)) {
        _armedFormats.add(format);
      }
      if (_preCompositionValue != null && !_composingToggles.remove(format)) {
        _composingToggles.add(format);
      }
      _provisionalRanges = null;
      notifyListeners();
      return;
    }
    final toggled = _inlineToggled(format);
    if (toggled == null ||
        !(toggled.removing ||
            _fitsBudget(toggled.inlineRanges, _displayBlockRanges))) {
      return;
    }
    _rebaseComposition(value);

    _inlineRanges
      ..clear()
      ..addAll(toggled.inlineRanges);
    notifyListeners();
  }

  /// Renders the text with each inline format over its range, heading lines
  /// at their heading size and weight, code-block lines in monospace, and
  /// the stock composing underline over the composing region when
  /// [withComposing] is true and the region is valid. A block's style covers
  /// its line's trailing newline too. Only [TextSpan]s are produced.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final length = text.length;
    final ranges = _displayRanges;
    final styledBlocks = [
      for (final block in _displayBlockRanges)
        if (block.format != BlockFormat.blockquote) block,
    ];
    final composing = value.composing;
    final showComposing =
        withComposing && value.isComposingRangeValid && !composing.isCollapsed;

    int clamped(int offset) => offset.clamp(0, length);
    int blockEnd(BlockRange block) => clamped(block.end + 1);

    // Loaded mentions and links are colored over exactly their text
    final loaded = [
      for (final range in _displayFeatureRanges)
        if (_isLinkOrMention(range.feature)) range,
    ];
    // Mentions and links are colored as typed, by the submit-time rules,
    // except inside code or over a loaded mention or link, which submit
    // keeps instead
    final detected = detectRichTextSpans(
      text,
      excludedRanges: [
        for (final range in ranges)
          if (range.format == InlineFormat.code)
            TextRange(start: range.start, end: range.end),
        for (final block in styledBlocks)
          if (block.format == BlockFormat.codeBlock)
            TextRange(start: block.start, end: blockEnd(block)),
        for (final range in loaded)
          TextRange(start: range.start, end: range.end),
      ],
    );
    if (ranges.isEmpty &&
        styledBlocks.isEmpty &&
        !showComposing &&
        detected.isEmpty &&
        loaded.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final boundaries = <int>{0, length};
    for (final range in ranges) {
      boundaries
        ..add(clamped(range.start))
        ..add(clamped(range.end));
    }
    for (final block in styledBlocks) {
      boundaries
        ..add(clamped(block.start))
        ..add(blockEnd(block));
    }
    if (showComposing) {
      boundaries
        ..add(composing.start)
        ..add(composing.end);
    }
    for (final span in detected) {
      boundaries
        ..add(span.start)
        ..add(span.end);
    }
    for (final range in loaded) {
      boundaries
        ..add(clamped(range.start))
        ..add(clamped(range.end));
    }
    final sortedBoundaries = boundaries.toList()..sort();
    final baseFontSize = style?.fontSize ?? 14.0;

    // Every range starts and ends on a boundary, so each covers a run of
    // whole segments: segment i runs from sortedBoundaries[i] to the next.
    final segmentCount = sortedBoundaries.length - 1;
    ({int first, int end}) segmentsOf(int start, int end) => (
      first: _firstIndexWhere(sortedBoundaries, (b) => b >= clamped(start)),
      end: _firstIndexWhere(sortedBoundaries, (b) => b >= clamped(end)),
    );
    final formatBits = List.filled(segmentCount, 0);
    for (final range in ranges) {
      final covered = segmentsOf(range.start, range.end);
      for (var index = covered.first; index < covered.end; index++) {
        formatBits[index] |= 1 << range.format.index;
      }
    }
    // The last block covering a segment styles it
    final segmentBlocks = List<BlockRange?>.filled(segmentCount, null);
    for (final block in styledBlocks) {
      final covered = segmentsOf(block.start, block.end + 1);
      for (var index = covered.first; index < covered.end; index++) {
        segmentBlocks[index] = block;
      }
    }
    // The first loaded mention or link covering a segment colors it
    final segmentFeatures = List<FacetFeature?>.filled(segmentCount, null);
    for (final range in loaded) {
      final covered = segmentsOf(range.start, range.end);
      for (var index = covered.first; index < covered.end; index++) {
        segmentFeatures[index] ??= range.feature;
      }
    }

    final children = <TextSpan>[];
    // Detected spans are in text order and never overlap, so one pass finds
    // the span, if any, covering each segment
    var detectedIndex = 0;
    for (var index = 0; index < segmentCount; index++) {
      final start = sortedBoundaries[index];
      final end = sortedBoundaries[index + 1];
      while (detectedIndex < detected.length &&
          detected[detectedIndex].end <= start) {
        detectedIndex++;
      }
      final loadedFeature = segmentFeatures[index];
      final color = loadedFeature != null
          ? loadedFeature is MentionFacetFeature
                ? RichTextPalette.mention
                : RichTextPalette.link
          : detectedIndex < detected.length &&
                detected[detectedIndex].start <= start
          ? switch (detected[detectedIndex].kind) {
              RichTextSpanKind.mention => RichTextPalette.mention,
              RichTextSpanKind.link => RichTextPalette.link,
            }
          : null;
      final bits = formatBits[index];
      final formats = {
        for (final format in InlineFormat.values)
          if (bits & (1 << format.index) != 0) format,
      };
      final underlined =
          showComposing && composing.start <= start && end <= composing.end;
      final block = segmentBlocks[index];
      final blockStyle = block == null
          ? null
          : _blockStyle(block, baseFontSize);
      final inlineStyle = _segmentStyle(formats, underlined: underlined);
      final segmentStyle = blockStyle == null
          ? inlineStyle
          : blockStyle.merge(inlineStyle);
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: color == null
              ? segmentStyle
              : (segmentStyle ?? const TextStyle()).copyWith(color: color),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// Inline formats whose ranges cover every character of the current
  /// non-collapsed selection, or the formats armed for the text typed next
  /// at a collapsed caret.
  Set<InlineFormat> activeInlineFormats() {
    if (selection.isCollapsed) {
      return Set.unmodifiable(_armedFormats);
    }
    final selected = _snappedSelection();
    if (selected == null) {
      return const {};
    }
    final ranges = _displayRanges;
    return {
      for (final format in InlineFormat.values)
        if (_covers([
          for (final range in ranges)
            if (range.format == format) range,
        ], selected))
          format,
    };
  }

  /// The block formats that cover every line the selection touches; a
  /// selection ending at a line start does not touch that line. During a
  /// composition this reads the blocks as they apply to the composing text.
  Set<BlockFormat> activeBlockFormats() {
    if (!selection.isValid) {
      return const {};
    }
    final lines = _Lines(text);
    final touched = _touchedLines(lines);
    final blocks = _lineBlocks(_displayBlockRanges, lines);
    return {
      for (final format in BlockFormat.values)
        if (_allLinesCovered(blocks, touched, format)) format,
    };
  }

  /// The heading level when every line the selection touches has a heading
  /// of that one level; null otherwise.
  int? activeHeadingLevel() {
    if (!selection.isValid) {
      return null;
    }
    final lines = _Lines(text);
    final touched = _touchedLines(lines);
    final blocks = _lineBlocks(_displayBlockRanges, lines);
    for (final block in blocks) {
      if (block.format == BlockFormat.heading &&
          block.span.contains(_LineSpan(touched.first, touched.first))) {
        return _allLinesCovered(
              blocks,
              touched,
              BlockFormat.heading,
              level: block.level,
            )
            ? block.level
            : null;
      }
    }
    return null;
  }

  /// Whether any line the selection or caret touches is in a code block; a
  /// selection ending at a line start does not touch that line. Inline
  /// formatting is not applied there.
  bool isSelectionInCodeBlock() {
    if (!selection.isValid) {
      return false;
    }
    final touched = _touchedOffsets();
    return _touchesCodeBlock(_displayBlockRanges, touched.start, touched.end);
  }

  /// Replaces the selection with [text] as unformatted pasted text, leaving
  /// a collapsed caret after it; does nothing for an invalid selection.
  ///
  /// The paste behaves like deleting the selection and then typing [text]:
  /// the deletion joins lines with the upper line's blocks, pasted text on a
  /// line takes that line's blocks, and each pasted newline follows the
  /// Enter rule; "\r\n", "\r", U+2028 and U+2029 paste as newlines. Pasted
  /// characters carry no inline format, so a range strictly containing the
  /// paste point splits around it. An active
  /// composition is committed as it stands first. Listeners are notified
  /// once, with the final text and ranges.
  void pasteUnformatted(String text) {
    if (!selection.isValid) {
      return;
    }
    _forgetKeyboardReplacement();
    if (_preCompositionValue != null) {
      _rebaseComposition(value);
    }
    _preCompositionValue = null;
    _cancelBaseline = null;
    _composedStart = null;
    _composingToggles.clear();
    _compositionChangedText = false;
    _provisionalRanges = null;
    _provisionalBlockRanges = null;
    _provisionalFeatureRanges = null;

    final currentText = this.text;
    final selected = snapToGraphemeBoundaries(
      currentText,
      TextRange(start: selection.start, end: selection.end),
    );
    // A caret inside a grapheme cluster moves to the cluster's start.
    final start = selected.start;
    final end = selection.isCollapsed ? start : selected.end;

    var current = TextEditingValue(
      text: currentText,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
    if (start < end) {
      current = _applyPlainEdit(
        current,
        currentText.replaceRange(start, end, ''),
        start,
      );
    }
    // Every line separator becomes '\n' so the block model sees each line
    // break the text field renders.
    final segments = text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[\r\u2028\u2029]'), '\n')
        .split('\n');
    for (var index = 0; index < segments.length; index++) {
      // Each newline is a separate edit so it follows the Enter rule.
      if (index > 0) {
        current = _insertPlain(current, '\n');
      }
      if (segments[index].isNotEmpty) {
        current = _insertPlain(current, segments[index]);
      }
    }
    _resetArmedFormats(current.selection);
    if (current == value) {
      // Same text and caret, but the ranges may have changed.
      notifyListeners();
    } else {
      super.value = current;
    }
  }

  /// Inserts [inserted] as plain text at [current]'s collapsed caret,
  /// remapping the stored ranges as typing it would with nothing armed.
  TextEditingValue _insertPlain(TextEditingValue current, String inserted) {
    final caret = current.selection.baseOffset;
    return _applyPlainEdit(
      current,
      current.text.replaceRange(caret, caret, inserted),
      caret + inserted.length,
    );
  }

  /// Remaps the stored ranges from [current] onto [newText] with a collapsed
  /// caret at [caret], without notifying listeners, and returns the new
  /// value. Nothing is armed, so inserted text carries no inline format.
  TextEditingValue _applyPlainEdit(
    TextEditingValue current,
    String newText,
    int caret,
  ) {
    final newValue = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _armedFormats.clear();
    final remapped = _remapped(current, newValue);
    final remappedBlocks = _remappedBlocks(current, newValue);
    final remappedFeatures = _remappedFeatures(current, newValue);
    _inlineRanges
      ..clear()
      ..addAll(
        _outsideCodeBlocks(
          remapped,
          remappedBlocks,
          within: _editedLines(current, newValue),
        ),
      );
    _blockRanges
      ..clear()
      ..addAll(remappedBlocks);
    _featureRanges
      ..clear()
      ..addAll(remappedFeatures);
    return newValue;
  }

  /// The normalized selection snapped to grapheme boundaries, or null when
  /// the selection is collapsed, invalid, or snaps to an empty range (such as
  /// a stale selection past the end of the text).
  TextRange? _snappedSelection() {
    if (!selection.isValid || selection.isCollapsed) {
      return null;
    }
    final snapped = snapToGraphemeBoundaries(
      text,
      TextRange(start: selection.start, end: selection.end),
    );
    return snapped.isCollapsed ? null : snapped;
  }
}

/// [offset] when [oldText] and [newText] share their first [offset]
/// characters, so it means the same position in both; null otherwise.
int? _unchangedPrefixOffset(String oldText, String newText, int offset) {
  if (offset < 0 || offset > oldText.length || offset > newText.length) {
    return null;
  }
  return oldText.substring(0, offset) == newText.substring(0, offset)
      ? offset
      : null;
}

/// Whether [value] has an active IME composition: a valid, non-collapsed
/// composing region.
bool _isComposing(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;

/// The style of a run carrying [formats], with the composing underline when
/// [underlined]; null when the run is plain.
TextStyle? _segmentStyle(
  Set<InlineFormat> formats, {
  required bool underlined,
}) {
  if (formats.isEmpty && !underlined) {
    return null;
  }
  final decorations = [
    if (formats.contains(InlineFormat.strikethrough))
      TextDecoration.lineThrough,
    if (underlined) TextDecoration.underline,
  ];
  final isCode = formats.contains(InlineFormat.code);
  return TextStyle(
    fontWeight: formats.contains(InlineFormat.bold) ? FontWeight.w700 : null,
    fontStyle: formats.contains(InlineFormat.italic) ? FontStyle.italic : null,
    decoration: decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations),
    fontFamily: isCode ? 'monospace' : null,
    fontFamilyFallback: isCode
        ? const ['Menlo', 'Courier New', 'Courier']
        : null,
    backgroundColor: formats.contains(InlineFormat.spoiler)
        ? AppColors.backgroundTertiary.withValues(alpha: 0.5)
        : null,
  );
}

/// Heading scale and weight by level, starting at level 1, matching the
/// rendered post; a level past the table takes its last row.
const _headingStyles = [
  (scale: 1.55, weight: FontWeight.w700),
  (scale: 1.4, weight: FontWeight.w700),
  (scale: 1.25, weight: FontWeight.w600),
  (scale: 1.15, weight: FontWeight.w600),
  (scale: 1.05, weight: FontWeight.w600),
  (scale: 1.0, weight: FontWeight.w600),
];

/// The style of the text on [block]'s lines: a heading's size, weight and
/// line height over [baseFontSize], or monospace for a code block.
TextStyle _blockStyle(BlockRange block, double baseFontSize) {
  if (block.format == BlockFormat.codeBlock) {
    return const TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
    );
  }
  final heading =
      _headingStyles[(block.level - 1).clamp(0, _headingStyles.length - 1)];
  return TextStyle(
    fontSize: baseFontSize * heading.scale,
    fontWeight: heading.weight,
    height: 1.3,
  );
}

/// Formats of [ranges] that cover the character before [position].
Set<InlineFormat> _formatsBefore(List<InlineRange> ranges, int position) => {
  for (final range in ranges)
    if (range.start < position && position <= range.end) range.format,
};

/// The single region replaced to turn [oldText] into [newText]: old
/// [start, oldEnd) became new [start, newEnd).
///
/// When repeated characters make the split ambiguous, the region is placed so
/// the inserted text ends at [caret] where possible.
({int start, int oldEnd, int newEnd}) _replacedRegion(
  String oldText,
  String newText,
  int? caret,
) {
  final shorterLength = oldText.length < newText.length
      ? oldText.length
      : newText.length;
  var prefixLength = 0;
  while (prefixLength < shorterLength &&
      oldText.codeUnitAt(prefixLength) == newText.codeUnitAt(prefixLength)) {
    prefixLength++;
  }
  var suffixLength = 0;
  while (suffixLength < shorterLength &&
      oldText.codeUnitAt(oldText.length - 1 - suffixLength) ==
          newText.codeUnitAt(newText.length - 1 - suffixLength)) {
    suffixLength++;
  }

  var start = prefixLength;
  final lowestStart = shorterLength - suffixLength;
  if (caret != null && lowestStart < prefixLength) {
    final growth = newText.length > oldText.length
        ? newText.length - oldText.length
        : 0;
    start = (caret - growth).clamp(lowestStart, prefixLength);
  }
  final chosenSuffixLength = suffixLength < shorterLength - start
      ? suffixLength
      : shorterLength - start;
  return (
    start: start,
    oldEnd: oldText.length - chosenSuffixLength,
    newEnd: newText.length - chosenSuffixLength,
  );
}

/// Whether [ranges] (all one format) together cover every position of
/// [target].
bool _covers(List<InlineRange> ranges, TextRange target) {
  final sorted = [...ranges]..sort(_compareRanges);
  var coveredUntil = target.start;
  for (final range in sorted) {
    if (range.start > coveredUntil) {
      break;
    }
    if (range.end > coveredUntil) {
      coveredUntil = range.end;
    }
    if (coveredUntil >= target.end) {
      return true;
    }
  }
  return coveredUntil >= target.end;
}

/// The parts of [range] that lie outside [removed].
List<InlineRange> _subtract(InlineRange range, TextRange removed) {
  if (range.end <= removed.start || range.start >= removed.end) {
    return [range];
  }
  return [
    if (range.start < removed.start)
      InlineRange(
        range.format,
        range.start,
        removed.start,
        reason: range.reason,
      ),
    if (range.end > removed.end)
      InlineRange(range.format, removed.end, range.end, reason: range.reason),
  ];
}

/// Merges touching or overlapping ranges of a single format that carry the
/// same reason; ranges with different reasons stay apart.
List<InlineRange> _merge(List<InlineRange> ranges) {
  final sorted = [...ranges]..sort(_compareRanges);
  final merged = <InlineRange>[];
  // The index in [merged] of the latest range for each reason.
  final latestByReason = <String?, int>{};
  for (final range in sorted) {
    final index = latestByReason[range.reason];
    if (index != null && range.start <= merged[index].end) {
      final last = merged[index];
      if (range.end > last.end) {
        merged[index] = InlineRange(
          last.format,
          last.start,
          range.end,
          reason: last.reason,
        );
      }
    } else {
      latestByReason[range.reason] = merged.length;
      merged.add(range);
    }
  }
  return merged;
}

int _compareRanges(InlineRange a, InlineRange b) {
  if (a.start != b.start) {
    return a.start.compareTo(b.start);
  }
  if (a.end != b.end) {
    return a.end.compareTo(b.end);
  }
  if (a.format != b.format) {
    return a.format.index.compareTo(b.format.index);
  }
  final aReason = a.reason;
  final bReason = b.reason;
  if (aReason == bReason) {
    return 0;
  }
  if (aReason == null) {
    return -1;
  }
  if (bReason == null) {
    return 1;
  }
  return aReason.compareTo(bReason);
}

/// Whether [feature] is a mention or a link, whose range covers exactly its
/// own text.
bool _isLinkOrMention(FacetFeature feature) =>
    feature is MentionFacetFeature || feature is LinkFacetFeature;

/// Widens [range] to the nearest extended-grapheme-cluster boundaries of
/// [text], clamped to the text length.
TextRange snapToGraphemeBoundaries(String text, TextRange range) {
  return _GraphemeBoundaries(text).snap(range);
}

/// The extended-grapheme-cluster boundaries of a text, found on demand.
///
/// An offset between two code units below U+0300, other than inside CR LF, is
/// always a boundary: no code unit in that range extends, joins or prepends
/// to a cluster. A query segments only the stretch between the nearest such
/// offsets around it, and keeps the stretch for later queries, so a keystroke
/// in a long mostly-Latin text never segments the whole text. A run of
/// other scripts or emoji is one stretch, segmented whole as before.
class _GraphemeBoundaries {
  _GraphemeBoundaries(this._text);

  final String _text;

  /// Segmented stretches, sorted by start; each holds its boundaries from its
  /// start to its end, both included.
  final List<List<int>> _stretches = [];

  /// Whether [offset] is a boundary whatever the code units around it.
  bool _isPlainBoundary(int offset) {
    if (offset <= 0 || offset >= _text.length) {
      return true;
    }
    final before = _text.codeUnitAt(offset - 1);
    final after = _text.codeUnitAt(offset);
    return before < 0x300 &&
        after < 0x300 &&
        !(before == 0x0D && after == 0x0A);
  }

  /// The boundaries of the stretch holding [offset], from the nearest plain
  /// boundary at or before it to the nearest one at or after it.
  List<int> _stretchAround(int offset) {
    // First stretch ending at or after offset.
    var index = 0;
    var high = _stretches.length;
    while (index < high) {
      final middle = (index + high) >> 1;
      if (_stretches[middle].last >= offset) {
        high = middle;
      } else {
        index = middle + 1;
      }
    }
    if (index < _stretches.length && _stretches[index].first <= offset) {
      return _stretches[index];
    }
    var from = offset;
    while (!_isPlainBoundary(from)) {
      from--;
    }
    var to = offset;
    while (!_isPlainBoundary(to)) {
      to++;
    }
    final boundaries = [from];
    var position = from;
    for (final cluster in _text.substring(from, to).characters) {
      position += cluster.length;
      boundaries.add(position);
    }
    _stretches.insert(index, boundaries);
    return boundaries;
  }

  /// Whether [offset] is a cluster boundary.
  bool contains(int offset) {
    if (_isPlainBoundary(offset)) {
      return true;
    }
    final stretch = _stretchAround(offset);
    final index = _firstIndexWhere(stretch, (b) => b >= offset);
    return index < stretch.length && stretch[index] == offset;
  }

  /// Widens [range]: the start moves down to the nearest boundary at or
  /// before it, the end up to the nearest boundary at or after it, both
  /// clamped to the text length.
  TextRange snap(TextRange range) {
    final length = _text.length;
    final start = range.start.clamp(0, length);
    final end = range.end.clamp(0, length);
    return TextRange(start: _floor(start), end: _ceiling(end));
  }

  int _floor(int offset) {
    if (_isPlainBoundary(offset)) {
      return offset;
    }
    final stretch = _stretchAround(offset);
    // First index whose boundary is > offset, minus one: the last <= offset.
    return stretch[_firstIndexWhere(stretch, (b) => b > offset) - 1];
  }

  int _ceiling(int offset) {
    if (_isPlainBoundary(offset)) {
      return offset;
    }
    final stretch = _stretchAround(offset);
    return stretch[_firstIndexWhere(stretch, (b) => b >= offset)];
  }
}

/// Binary search for the first index in sorted [values] satisfying the
/// monotone [test], or `values.length` when none does.
int _firstIndexWhere(List<int> values, bool Function(int) test) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (test(values[middle])) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

/// [ranges] without their parts on the code-block lines of [blocks], each
/// line with its trailing newline; inline formatting never applies there.
/// With [within], only the code-block lines inside it lose their ranges, so
/// a loaded range on a code-block line an edit did not touch is kept.
List<InlineRange> _outsideCodeBlocks(
  List<InlineRange> ranges,
  List<BlockRange> blocks, {
  TextRange? within,
}) {
  var kept = [...ranges];
  for (final block in blocks) {
    if (block.format == BlockFormat.codeBlock) {
      var start = block.start;
      var end = block.end + 1;
      if (within != null) {
        start = start > within.start ? start : within.start;
        end = end < within.end ? end : within.end;
      }
      if (start < end) {
        final removed = TextRange(start: start, end: end);
        kept = [for (final range in kept) ..._subtract(range, removed)];
      }
    }
  }
  return kept;
}

/// [ranges] without their parts on lines that are code-block lines in
/// [after] but not in [before] (both in the line indexes of [lines]), each
/// line with its trailing newline. Ranges on lines that were already code
/// lines, such as a loaded range, are kept.
List<InlineRange> _outsideNewlyCodedLines(
  List<InlineRange> ranges,
  List<_LineBlock> before,
  List<_LineBlock> after,
  _Lines lines,
) {
  bool wasCoded(int line) => before.any(
    (block) =>
        block.format == BlockFormat.codeBlock &&
        block.span.contains(_LineSpan(line, line)),
  );
  var kept = [...ranges];
  for (final block in after) {
    if (block.format != BlockFormat.codeBlock) {
      continue;
    }
    for (var line = block.span.first; line <= block.span.last; line++) {
      if (!wasCoded(line)) {
        final removed = TextRange(
          start: lines.startOf(line),
          end: lines.endOf(line) + 1,
        );
        kept = [for (final range in kept) ..._subtract(range, removed)];
      }
    }
  }
  return kept;
}

/// The whole lines of [newValue]'s text that the replaced region turning
/// [oldValue]'s text into it touches, the last with its trailing newline.
TextRange _editedLines(TextEditingValue oldValue, TextEditingValue newValue) {
  final newText = newValue.text;
  final replaced = _replacedRegion(
    oldValue.text,
    newText,
    _collapsedCaret(newValue),
  );
  final lines = _Lines(newText);
  return TextRange(
    start: lines.startOf(lines.indexOf(replaced.start)),
    end: lines.endOf(lines.indexOf(replaced.newEnd)) + 1,
  );
}

/// [value]'s caret offset when its selection is a valid collapsed caret;
/// null otherwise.
int? _collapsedCaret(TextEditingValue value) =>
    value.selection.isValid && value.selection.isCollapsed
    ? value.selection.baseOffset
    : null;

/// Whether a code block in [blocks] covers a line holding any offset from
/// [start] to [end]. Blocks cover whole lines, so a block shares a line with
/// those offsets exactly when it overlaps them.
bool _touchesCodeBlock(List<BlockRange> blocks, int start, int end) =>
    blocks.any(
      (block) =>
          block.format == BlockFormat.codeBlock &&
          block.start <= end &&
          start <= block.end,
    );

/// [ranges] in the line indexes of [lines].
List<_LineBlock> _lineBlocks(List<BlockRange> ranges, _Lines lines) => [
  for (final range in ranges)
    _LineBlock(
      range.format,
      range.level,
      _LineSpan(lines.indexOf(range.start), lines.indexOf(range.end)),
      language: range.language,
    ),
];

/// The line starts of a text, computed once, for mapping offsets to lines.
class _Lines {
  _Lines(String text) : _length = text.length {
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 0x0A) {
        _starts.add(index + 1);
      }
    }
  }

  final int _length;
  final List<int> _starts = [0];

  /// The index of the line holding [offset]; a newline belongs to the line
  /// it ends.
  int indexOf(int offset) =>
      _firstIndexWhere(_starts, (start) => start > offset) - 1;

  int startOf(int line) => _starts[line];

  /// The end of [line], excluding its trailing newline.
  int endOf(int line) =>
      line + 1 < _starts.length ? _starts[line + 1] - 1 : _length;
}

/// An inclusive run of line indexes.
class _LineSpan {
  const _LineSpan(this.first, this.last);

  final int first;
  final int last;

  bool overlaps(_LineSpan other) => first <= other.last && other.first <= last;

  bool contains(_LineSpan other) => first <= other.first && other.last <= last;

  /// Whether this span and [other] overlap or sit on adjacent lines.
  bool touches(_LineSpan other) =>
      first <= other.last + 1 && other.first <= last + 1;

  _LineSpan union(_LineSpan other) => _LineSpan(
    first < other.first ? first : other.first,
    last > other.last ? last : other.last,
  );

  @override
  bool operator ==(Object other) =>
      other is _LineSpan && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

/// A block range in line indexes.
class _LineBlock {
  const _LineBlock(this.format, this.level, this.span, {this.language});

  final BlockFormat format;
  final int level;
  final _LineSpan span;
  final String? language;

  /// This block's format and attributes over [span].
  _LineBlock over(_LineSpan span) =>
      _LineBlock(format, level, span, language: language);

  /// Whether [other] has this block's format, level and language, so the
  /// two may merge.
  bool sameKind(_LineBlock other) =>
      other.format == format &&
      other.level == level &&
      other.language == language;

  /// This block as a [BlockRange] over the whole lines of [lines].
  BlockRange toRange(_Lines lines) => BlockRange(
    format,
    lines.startOf(span.first),
    lines.endOf(span.last),
    level: level,
    language: language,
  );
}

/// Whether every line of [touched] lies inside a [format] block.
bool _allLinesCovered(
  List<_LineBlock> blocks,
  _LineSpan touched,
  BlockFormat format, {
  int? level,
}) {
  for (var line = touched.first; line <= touched.last; line++) {
    final lineSpan = _LineSpan(line, line);
    final covered = blocks.any(
      (block) =>
          block.format == format &&
          (level == null || block.level == level) &&
          block.span.contains(lineSpan),
    );
    if (!covered) {
      return false;
    }
  }
  return true;
}

/// Removes headings at [level] from every touched line when all of them
/// have one; otherwise gives each touched line a heading at [level],
/// replacing other levels and cutting code blocks from those lines.
List<_LineBlock> _toggledHeading(
  List<_LineBlock> blocks,
  _LineSpan touched,
  int level,
) {
  final removing = _allLinesCovered(
    blocks,
    touched,
    BlockFormat.heading,
    level: level,
  );
  final kept = [
    for (final block in blocks)
      if (block.format != BlockFormat.heading || !touched.overlaps(block.span))
        block,
  ];
  if (removing) {
    return kept;
  }
  return [
    ..._withBlockCut(kept, BlockFormat.codeBlock, touched),
    for (var line = touched.first; line <= touched.last; line++)
      _LineBlock(BlockFormat.heading, level, _LineSpan(line, line)),
  ];
}

/// The other block format a quote or code block can conflict with.
BlockFormat _conflictingFormat(BlockFormat format) =>
    format == BlockFormat.blockquote
    ? BlockFormat.codeBlock
    : BlockFormat.blockquote;

/// Removes [format] (a quote or code block) from the lines of [cut].
///
/// The cut widens over a block of the other format that lies inside a
/// [format] block being cut and that the cut only partly covers, so the
/// remaining pieces never cross it. Such a block must lie strictly inside,
/// except when cutting a quote: a code block with the quote's lines widens
/// the cut too, so no code block is left strictly containing a quote piece.
/// It never widens over a block that strictly contains the [format] block
/// being cut.
List<_LineBlock> _withBlockCut(
  List<_LineBlock> blocks,
  BlockFormat format,
  _LineSpan cut,
) {
  final conflicting = _conflictingFormat(format);
  var span = cut;
  var widened = true;
  while (widened) {
    widened = false;
    for (final cutBlock in blocks) {
      if (cutBlock.format != format || !cutBlock.span.overlaps(span)) {
        continue;
      }
      for (final inner in blocks) {
        if (inner.format == conflicting &&
            (inner.span != cutBlock.span || format == BlockFormat.blockquote) &&
            cutBlock.span.contains(inner.span) &&
            inner.span.overlaps(span) &&
            !span.contains(inner.span)) {
          span = span.union(inner.span);
          widened = true;
        }
      }
    }
  }
  return [
    for (final block in blocks)
      if (block.format != format || !block.span.overlaps(span))
        block
      else ...[
        if (block.span.first < span.first)
          block.over(_LineSpan(block.span.first, span.first - 1)),
        if (block.span.last > span.last)
          block.over(_LineSpan(span.last + 1, block.span.last)),
      ],
  ];
}

/// Adds [format] (a quote or code block, at level 1 and without a language)
/// to the lines of [added], merged with the same-format blocks of that level
/// and language it overlaps. Lines already in a same-format block with
/// another level or language keep that block and do not get the new one, so
/// the new block covers only the other lines, split into disjoint runs.
/// [_settled] merges same-kind blocks on adjacent lines afterwards.
///
/// A quote widens over every code block it overlaps without containing; a
/// code block widens over every quote whose edge it crosses. Widening repeats
/// until nothing changes. A code block then removes the headings on its
/// lines, and splits where one quote it contains ends and a quote of another
/// level begins (the lines between get their own code block), so each quote
/// widens only over its own part and quotes of different levels stay
/// disjoint.
List<_LineBlock> _withBlockAdded(
  List<_LineBlock> blocks,
  BlockFormat format,
  _LineSpan added,
) {
  final conflicting = _conflictingFormat(format);
  final addedBlock = _LineBlock(format, 1, added);
  var span = added;
  var widened = true;
  while (widened) {
    widened = false;
    for (final block in blocks) {
      if (span.contains(block.span)) {
        continue;
      }
      final merges = block.sameKind(addedBlock) && span.overlaps(block.span);
      final conflicts =
          block.format == conflicting &&
          span.overlaps(block.span) &&
          (format == BlockFormat.blockquote || !block.span.contains(span));
      if (merges || conflicts) {
        span = span.union(block.span);
        widened = true;
      }
    }
  }
  final excluded = [
    for (final block in blocks)
      if (block.format == format &&
          !block.sameKind(addedBlock) &&
          block.span.overlaps(span))
        block.span,
  ]..sort((a, b) => a.first.compareTo(b.first));
  final runs = <_LineSpan>[];
  var next = span.first;
  for (final other in excluded) {
    if (other.first > next) {
      runs.add(_LineSpan(next, other.first - 1));
    }
    if (other.last + 1 > next) {
      next = other.last + 1;
    }
  }
  if (next <= span.last) {
    runs.add(_LineSpan(next, span.last));
  }
  final splits = <int>[];
  if (format == BlockFormat.codeBlock) {
    final quotesInside = [
      for (final block in blocks)
        if (block.format == BlockFormat.blockquote && span.contains(block.span))
          block,
    ]..sort((a, b) => a.span.first.compareTo(b.span.first));
    for (var index = 1; index < quotesInside.length; index++) {
      final previous = quotesInside[index - 1].span;
      final quote = quotesInside[index];
      if (quote.level != quotesInside[index - 1].level &&
          quote.span.first > previous.last) {
        splits
          ..add(previous.last + 1)
          ..add(quote.span.first);
      }
    }
    splits.sort();
  }
  final pieces = <_LineSpan>[];
  for (final run in runs) {
    var start = run.first;
    for (final split in splits) {
      if (split > start && split <= run.last) {
        pieces.add(_LineSpan(start, split - 1));
        start = split;
      }
    }
    pieces.add(_LineSpan(start, run.last));
  }
  return [
    for (final block in blocks)
      if (!span.contains(block.span) ||
          (block.format == format
              ? !block.sameKind(addedBlock)
              : !(format == BlockFormat.codeBlock &&
                    block.format == BlockFormat.heading)))
        block,
    for (final piece in pieces) addedBlock.over(piece),
  ];
}

/// [blocks] with the quote kept outermost and same-format quotes and code
/// blocks of the same level and language merged.
///
/// A quote that a code block strictly contains or whose edge it crosses
/// widens over the code block's lines, keeping its level. Quotes or code
/// blocks of one format, level and language that overlap merge; on adjacent
/// lines they merge unless the merged span would cross the edge of a block
/// of the other format or put a quote strictly inside a code block, in which
/// case they stay separate.
/// Blocks of one format with different levels or languages never merge.
/// Headings never merge. Repeats until nothing changes.
///
/// Each round widens quotes in one sorted pass over the code blocks, then
/// merges each format's blocks in one sorted sweep per level or language.
List<_LineBlock> _settled(List<_LineBlock> blocks) {
  final headings = [
    for (final block in blocks)
      if (block.format == BlockFormat.heading) block,
  ];
  var quotes = [
    for (final block in blocks)
      if (block.format == BlockFormat.blockquote) block,
  ];
  var codes = [
    for (final block in blocks)
      if (block.format == BlockFormat.codeBlock) block,
  ];
  var merging = true;
  while (merging) {
    quotes = _widenedOverCode(quotes, codes);
    final mergedQuotes = _mergedSameKind(quotes, codes);
    final mergedCodes = _mergedSameKind(codes, mergedQuotes);
    merging =
        mergedQuotes.length != quotes.length ||
        mergedCodes.length != codes.length;
    quotes = mergedQuotes;
    codes = mergedCodes;
  }
  return [...headings, ...quotes, ...codes];
}

/// [quotes] each widened over the code blocks it overlaps without
/// containing, until no quote overlaps a code block it does not contain.
///
/// That closure is the quote plus every group of overlapping [codes] it
/// overlaps: the groups are disjoint, so the widened quote cannot reach a
/// group it did not already overlap. Sorting the groups once lets each quote
/// find them by binary search instead of repeated sweeps.
List<_LineBlock> _widenedOverCode(
  List<_LineBlock> quotes,
  List<_LineBlock> codes,
) {
  final sorted = [for (final code in codes) code.span]
    ..sort((a, b) => a.first.compareTo(b.first));
  final groups = <_LineSpan>[];
  for (final span in sorted) {
    if (groups.isNotEmpty && groups.last.overlaps(span)) {
      groups.last = groups.last.union(span);
    } else {
      groups.add(span);
    }
  }
  final groupEnds = [for (final group in groups) group.last];
  final widenedQuotes = <_LineBlock>[];
  for (final quote in quotes) {
    var widened = quote.span;
    var index = _firstIndexWhere(groupEnds, (end) => end >= quote.span.first);
    while (index < groups.length && groups[index].first <= quote.span.last) {
      widened = widened.union(groups[index]);
      index++;
    }
    widenedQuotes.add(widened == quote.span ? quote : quote.over(widened));
  }
  return widenedQuotes;
}

/// [blocks] (quotes, or code blocks) with the overlapping blocks of each
/// level and language merged, and the adjacent ones merged when
/// [_canMergeAdjacent] allows it against [conflicting], the blocks of the
/// other format.
List<_LineBlock> _mergedSameKind(
  List<_LineBlock> blocks,
  List<_LineBlock> conflicting,
) {
  final byKind = <(int, String?), List<_LineBlock>>{};
  for (final block in blocks) {
    (byKind[(block.level, block.language)] ??= []).add(block);
  }
  final merged = <_LineBlock>[];
  for (final kind in byKind.values) {
    kind.sort(
      (a, b) => a.span.first != b.span.first
          ? a.span.first.compareTo(b.span.first)
          : a.span.last.compareTo(b.span.last),
    );
    var current = kind.first;
    for (final block in kind.skip(1)) {
      if (current.span.touches(block.span)) {
        final joined = current.over(current.span.union(block.span));
        if (current.span.overlaps(block.span) ||
            _canMergeAdjacent(conflicting, joined)) {
          current = joined;
          continue;
        }
      }
      merged.add(current);
      current = block;
    }
    merged.add(current);
  }
  return merged;
}

/// Whether [merged], two adjacent same-format blocks joined, neither
/// crosses the edge of a block of the other quote-or-code format nor leaves
/// a code block strictly containing a quote.
bool _canMergeAdjacent(List<_LineBlock> blocks, _LineBlock merged) {
  final other = _conflictingFormat(merged.format);
  for (final block in blocks) {
    if (block.format != other || !block.span.overlaps(merged.span)) {
      continue;
    }
    final mergedContains = merged.span.contains(block.span);
    final blockContains = block.span.contains(merged.span);
    if (!mergedContains && !blockContains) {
      return false;
    }
    final strictlyNested = block.span != merged.span;
    final quoteInsideCode = merged.format == BlockFormat.codeBlock
        ? mergedContains && strictlyNested
        : blockContains && strictlyNested;
    if (quoteInsideCode) {
      return false;
    }
  }
  return true;
}
