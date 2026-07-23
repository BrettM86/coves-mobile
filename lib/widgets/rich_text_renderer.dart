import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../models/facet.dart';
import '../utils/url_launcher.dart';

/// A reusable widget for rendering text with rich text facets.
///
/// Facets are advisory annotations over canonical plaintext: the text must
/// remain readable if every facet is ignored, and unknown feature types
/// degrade to plain text (the union is open).
///
/// Inline features (styled via merged text spans, overlaps compose):
/// - Links: primary color, underlined, tappable
/// - Mentions: primary color, tappable (profile or community by DID)
/// - Bold / italic / strikethrough
/// - Inline code: monospace with subtle background
/// - Spoilers: redacted until tapped
///
/// Block features (rendered as block layout when [maxLines] is null):
/// - Blockquotes: left bar per nesting level
/// - Headings: scaled/bold single line
/// - Code blocks: monospace card, whitespace preserved, horizontal scroll
///
/// When [maxLines] is set (feed previews), everything renders in a single
/// Text.rich so ellipsis works; block features are approximated as character
/// styles instead of layout.
class RichTextRenderer extends StatefulWidget {
  const RichTextRenderer({
    required this.text,
    this.facets,
    this.style,
    this.maxLines,
    this.overflow,
    this.linkStyle,
    super.key,
  });

  /// The text content to render
  final String text;

  /// Optional list of facets (annotations) for the text
  final List<RichTextFacet>? facets;

  /// Base text style (applied to all text)
  final TextStyle? style;

  /// Maximum number of lines to display
  ///
  /// When set, block facets are approximated inline so the line limit and
  /// [overflow] behave like a normal Text widget.
  final int? maxLines;

  /// How to handle text overflow
  final TextOverflow? overflow;

  /// Optional custom style for links
  ///
  /// When null, links get the default treatment: theme primary color plus
  /// underline. When provided, this style REPLACES that whole default
  /// treatment (no underline is added automatically).
  final TextStyle? linkStyle;

  @override
  State<RichTextRenderer> createState() => _RichTextRendererState();
}

/// A facet with its byte range resolved to Dart string (UTF-16) indices
class _ResolvedFacet {
  _ResolvedFacet({
    required this.facet,
    required this.charStart,
    required this.charEnd,
  });

  final RichTextFacet facet;
  final int charStart;
  final int charEnd;
}

/// A block-level facet with its range extended to whole-line boundaries
class _ResolvedBlock {
  _ResolvedBlock({
    required this.feature,
    required this.start,
    required this.end,
  });

  final FacetFeature feature;
  final int start;
  final int end;
}

class _RichTextRendererState extends State<RichTextRenderer> {
  /// Track all gesture recognizers for proper disposal
  final List<GestureRecognizer> _recognizers = [];

  /// Spoiler ranges ("charStart:charEnd") the user has revealed
  final Set<String> _revealedSpoilers = {};

  /// Resolved facets/blocks cached across rebuilds (provider-driven feed
  /// rebuilds must not redo the byte-to-char resolution work)
  List<_ResolvedFacet>? _resolvedFacetsCache;
  List<_ResolvedBlock>? _resolvedBlocksCache;

  @override
  void didUpdateWidget(RichTextRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        !listEquals(oldWidget.facets, widget.facets)) {
      _resolvedFacetsCache = null;
      _resolvedBlocksCache = null;
      // Char-range keys are only valid relative to this text/facets pair
      _revealedSpoilers.clear();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Clear previous recognizers before rebuilding spans (must run before
    // the plain-text early return, or recognizers from a prior faceted
    // build would leak when the widget updates to a facet-less state)
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    // If no facets, render plain text
    if (widget.facets == null ||
        widget.facets!.isEmpty ||
        widget.text.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final resolved = _resolvedFacetsCache ??= _resolveFacets();

    // Compact mode: a single Text.rich so maxLines/ellipsis work
    if (widget.maxLines != null) {
      return Text.rich(
        TextSpan(
          children: _inlineSpans(
            context,
            0,
            widget.text.length,
            resolved,
            approximateBlocks: true,
          ),
          style: widget.style,
        ),
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final blocks = _resolvedBlocksCache ??= _resolveBlocks(resolved);

    // No block structure: keep the single-Text.rich shape
    if (blocks.isEmpty) {
      return Text.rich(
        TextSpan(
          children: _inlineSpans(context, 0, widget.text.length, resolved),
          style: widget.style,
        ),
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final children = _blockWidgets(
      context,
      0,
      widget.text.length,
      blocks,
      resolved,
      widget.style,
    );

    if (children.length == 1) {
      return children.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }

  /// Converts facet byte ranges to char ranges, dropping invalid facets
  ///
  /// The text is UTF-8 encoded once and every needed byte offset is resolved
  /// in a single cumulative walk over the bytes (instead of re-encoding the
  /// whole text per facet endpoint, which was O(facets x textLength)).
  List<_ResolvedFacet> _resolveFacets() {
    final text = widget.text;
    final bytes = utf8.encode(text);

    // Collect the byte offsets we need (sorted, deduplicated), skipping
    // facets that are trivially invalid.
    final offsets = SplayTreeSet<int>();
    for (final facet in widget.facets!) {
      final byteStart = facet.index.byteStart;
      final byteEnd = facet.index.byteEnd;
      if (byteStart < 0 || byteEnd <= byteStart || byteEnd > bytes.length) {
        continue; // logged in the resolution loop below
      }
      offsets
        ..add(byteStart)
        ..add(byteEnd);
    }

    final charIndexAt =
        _charIndexForByteOffsets(bytes, offsets.toList(), text.length);

    final resolved = <_ResolvedFacet>[];
    for (final facet in widget.facets!) {
      final byteStart = facet.index.byteStart;
      final byteEnd = facet.index.byteEnd;

      if (byteStart < 0 || byteEnd <= byteStart) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping facet with invalid byte '
              'range [$byteStart, $byteEnd)');
        }
        continue;
      }

      // Strict: a facet extending past the text's UTF-8 length is malformed
      // and is dropped, not clamped to the text end.
      if (byteEnd > bytes.length) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping facet with byte range '
              '[$byteStart, $byteEnd) past text byte length ${bytes.length}');
        }
        continue;
      }

      // -1 means the offset splits a multi-byte UTF-8 sequence
      final charStart = charIndexAt[byteStart] ?? -1;
      final charEnd = charIndexAt[byteEnd] ?? -1;

      if (charStart < 0 ||
          charEnd < 0 ||
          charStart >= text.length ||
          charEnd <= charStart) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping facet with out-of-bounds '
              'char indices [$charStart, $charEnd) for text length '
              '${text.length}');
        }
        continue;
      }

      resolved.add(
        _ResolvedFacet(facet: facet, charStart: charStart, charEnd: charEnd),
      );
    }

    resolved.sort((a, b) => a.charStart.compareTo(b.charStart));
    return resolved;
  }

  /// Resolves each byte offset in [offsets] (sorted ascending, all within
  /// `0..bytes.length`) to its UTF-16 char index, in one walk over [bytes].
  ///
  /// Offsets landing mid-way through a multi-byte UTF-8 sequence map to -1
  /// (matching FacetDetector.byteIndexToCharIndex's failure result); an
  /// offset equal to `bytes.length` maps to [textLength].
  static Map<int, int> _charIndexForByteOffsets(
    List<int> bytes,
    List<int> offsets,
    int textLength,
  ) {
    final map = <int, int>{};
    var oi = 0;
    var byteIndex = 0;
    var charIndex = 0;

    while (oi < offsets.length && byteIndex < bytes.length) {
      while (oi < offsets.length && offsets[oi] == byteIndex) {
        map[offsets[oi]] = charIndex;
        oi++;
      }
      if (oi >= offsets.length) {
        break;
      }

      // Advance one code point using the UTF-8 lead byte
      final lead = bytes[byteIndex];
      final seqLen = lead < 0x80
          ? 1
          : lead < 0xE0
              ? 2
              : lead < 0xF0
                  ? 3
                  : 4;
      final next = byteIndex + seqLen;

      // Offsets inside the sequence would split a code point: unresolvable
      while (oi < offsets.length && offsets[oi] < next) {
        map[offsets[oi]] = -1;
        oi++;
      }

      // Code points >= U+10000 (4-byte sequences) are surrogate pairs in
      // UTF-16 and count as 2 code units
      charIndex += seqLen == 4 ? 2 : 1;
      byteIndex = next;
    }

    for (; oi < offsets.length; oi++) {
      map[offsets[oi]] = offsets[oi] == bytes.length ? textLength : -1;
    }
    return map;
  }

  /// Extracts block-level facets with ranges extended to line boundaries
  ///
  /// Per the lexicon, block ranges must span whole lines excluding the
  /// trailing newline; readers extend malformed mid-line ranges outward.
  List<_ResolvedBlock> _resolveBlocks(List<_ResolvedFacet> resolved) {
    final text = widget.text;
    final blocks = <_ResolvedBlock>[];

    for (final rf in resolved) {
      final feature = rf.facet.blockFeature;
      if (feature == null) {
        continue;
      }

      // A sloppy writer may start the range on a newline; advance past
      // leading newlines before snapping to line start so we don't swallow
      // the previous line (symmetric with the trailing back-off below).
      var rangeStart = rf.charStart;
      while (rangeStart < rf.charEnd && text[rangeStart] == '\n') {
        rangeStart++;
      }

      final start =
          rangeStart == 0 ? 0 : text.lastIndexOf('\n', rangeStart - 1) + 1;

      // A sloppy writer may include the trailing newline; back off before
      // extending forward so we don't swallow the next line.
      var end = rf.charEnd;
      while (end > start && text[end - 1] == '\n') {
        end--;
      }
      if (end < text.length && text[end] != '\n') {
        final nl = text.indexOf('\n', end);
        end = nl == -1 ? text.length : nl;
      }

      if (end > start) {
        blocks.add(_ResolvedBlock(feature: feature, start: start, end: end));
      }
    }

    blocks.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      // Longer (containing) block first so containment recursion sees it
      return cmp != 0 ? cmp : b.end.compareTo(a.end);
    });
    return blocks;
  }

  /// Lays out a range as a list of block widgets (paragraphs and blocks)
  List<Widget> _blockWidgets(
    BuildContext context,
    int rangeStart,
    int rangeEnd,
    List<_ResolvedBlock> blocks,
    List<_ResolvedFacet> inlineFacets,
    TextStyle? baseStyle,
  ) {
    final text = widget.text;
    final widgets = <Widget>[];
    var pos = rangeStart;
    var i = 0;

    while (i < blocks.length) {
      final block = blocks[i];
      if (block.start < pos || block.end > rangeEnd) {
        // Overlaps already-rendered content (or leaks out of this range)
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping overlapping block facet at '
              'char index ${block.start}');
        }
        i++;
        continue;
      }

      if (block.start > pos) {
        _addParagraph(
            context, widgets, pos, block.start, inlineFacets, baseStyle);
      }

      final feature = block.feature;
      if (feature is BlockquoteFacetFeature) {
        // Consume blocks contained in this quote (cross-type nesting);
        // quote-in-quote containment is disallowed by the lexicon and will
        // simply render inside the outer quote's bars.
        final inner = <_ResolvedBlock>[];
        var j = i + 1;
        while (j < blocks.length && blocks[j].start < block.end) {
          if (blocks[j].end <= block.end) {
            inner.add(blocks[j]);
          } else if (kDebugMode) {
            // Straddles the quote boundary: dropped, same as other overlaps
            debugPrint('RichTextRenderer: Skipping overlapping block facet '
                'at char index ${blocks[j].start}');
          }
          j++;
        }
        widgets.add(
          _blockquoteWidget(context, block, inner, inlineFacets, baseStyle),
        );
        i = j;
      } else if (feature is HeadingFacetFeature) {
        widgets.add(
          _headingWidget(context, block, feature, inlineFacets, baseStyle),
        );
        i++;
      } else {
        widgets.add(
          _codeBlockWidget(context, block, feature as CodeBlockFacetFeature,
              inlineFacets, baseStyle),
        );
        i++;
      }

      pos = block.end;
      // Skip the newline separating this block from what follows
      if (pos < rangeEnd && text[pos] == '\n') {
        pos++;
      }
    }

    if (pos < rangeEnd) {
      _addParagraph(context, widgets, pos, rangeEnd, inlineFacets, baseStyle);
    }

    return widgets;
  }

  /// Adds a paragraph widget for a gap between blocks (if non-empty)
  void _addParagraph(
    BuildContext context,
    List<Widget> widgets,
    int start,
    int end,
    List<_ResolvedFacet> inlineFacets,
    TextStyle? baseStyle,
  ) {
    final text = widget.text;
    var s = start;
    var e = end;
    while (s < e && text[s] == '\n') {
      s++;
    }
    while (e > s && text[e - 1] == '\n') {
      e--;
    }
    if (s >= e) {
      return;
    }

    widgets.add(
      Text.rich(
        TextSpan(
          children: _inlineSpans(context, s, e, inlineFacets),
          style: baseStyle,
        ),
      ),
    );
  }

  Widget _blockquoteWidget(
    BuildContext context,
    _ResolvedBlock block,
    List<_ResolvedBlock> inner,
    List<_ResolvedFacet> inlineFacets,
    TextStyle? baseStyle,
  ) {
    final level = (block.feature as BlockquoteFacetFeature).level;
    final quoteStyle = (baseStyle ?? const TextStyle())
        .merge(const TextStyle(color: AppColors.textSecondary));

    final children = _blockWidgets(
      context,
      block.start,
      block.end,
      inner,
      inlineFacets,
      quoteStyle,
    );

    var child = children.length == 1
        ? children.first
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          );

    // One bar per nesting level, innermost closest to the text
    for (var i = 0; i < level; i++) {
      child = Container(
        padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.teal.withValues(alpha: 0.6),
              width: 3,
            ),
          ),
        ),
        child: child,
      );
    }

    return child;
  }

  static const _headingScales = [1.55, 1.4, 1.25, 1.15, 1.05, 1.0];

  Widget _headingWidget(
    BuildContext context,
    _ResolvedBlock block,
    HeadingFacetFeature feature,
    List<_ResolvedFacet> inlineFacets,
    TextStyle? baseStyle,
  ) {
    final base = baseStyle ?? const TextStyle();
    final baseSize = base.fontSize ?? 14.0;
    final headingStyle = base.copyWith(
      fontSize: baseSize * _headingScales[feature.level - 1],
      fontWeight: feature.level <= 2 ? FontWeight.w700 : FontWeight.w600,
      height: 1.3,
    );

    return Text.rich(
      TextSpan(
        children: _inlineSpans(context, block.start, block.end, inlineFacets),
        style: headingStyle,
      ),
    );
  }

  Widget _codeBlockWidget(
    BuildContext context,
    _ResolvedBlock block,
    CodeBlockFacetFeature feature,
    List<_ResolvedFacet> inlineFacets,
    TextStyle? baseStyle,
  ) {
    final codeStyle = _monospace(baseStyle ?? const TextStyle());
    final language = feature.language;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.backgroundTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (language != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                language,
                style: _monospace(const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                )),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text.rich(
              // Code is literal (no inline facet styling), except spoilers:
              // concealment beats literalness, so spoiler ranges are
              // redacted here too instead of leaking in plain sight
              TextSpan(children: _codeBlockSpans(block, inlineFacets)),
              style: codeStyle,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  /// Splits a code block's raw text into spans, redacting spoiler ranges
  ///
  /// Spoilers get the same treatment as inline runs (invisible glyphs,
  /// solid background, screen-reader label, tap to reveal/hide), keyed by
  /// the spoiler's full char range so reveal state is shared with any
  /// inline rendering of the same facet.
  List<InlineSpan> _codeBlockSpans(
    _ResolvedBlock block,
    List<_ResolvedFacet> inlineFacets,
  ) {
    final text = widget.text;
    final spoilers = inlineFacets
        .where((rf) =>
            rf.charStart < block.end &&
            rf.charEnd > block.start &&
            rf.facet.features.any((f) => f is SpoilerFacetFeature))
        .toList();

    if (spoilers.isEmpty) {
      return [TextSpan(text: text.substring(block.start, block.end))];
    }

    final spans = <InlineSpan>[];
    var pos = block.start;

    for (final rf in spoilers) {
      final segStart = rf.charStart.clamp(pos, block.end);
      final segEnd = rf.charEnd.clamp(pos, block.end);
      if (segEnd <= segStart) {
        continue; // fully consumed by an earlier overlapping spoiler
      }

      if (segStart > pos) {
        spans.add(TextSpan(text: text.substring(pos, segStart)));
      }

      final key = '${rf.charStart}:${rf.charEnd}';
      final revealed = _revealedSpoilers.contains(key);
      final tapRecognizer = TapGestureRecognizer()
        ..onTap = () => setState(() {
              if (!_revealedSpoilers.remove(key)) {
                _revealedSpoilers.add(key);
              }
            });
      _recognizers.add(tapRecognizer);

      if (revealed) {
        spans.add(TextSpan(
          text: text.substring(segStart, segEnd),
          style: TextStyle(
            backgroundColor:
                AppColors.backgroundTertiary.withValues(alpha: 0.5),
          ),
          recognizer: tapRecognizer,
        ));
      } else {
        final reason = rf.facet.features
            .whereType<SpoilerFacetFeature>()
            .first
            .reason;
        spans.add(TextSpan(
          text: text.substring(segStart, segEnd),
          style: const TextStyle(
            color: Colors.transparent,
            backgroundColor: AppColors.backgroundTertiary,
          ),
          recognizer: tapRecognizer,
          semanticsLabel: reason != null
              ? 'Spoiler: $reason. Tap to reveal.'
              : 'Spoiler. Tap to reveal.',
        ));
      }

      pos = segEnd;
    }

    if (pos < block.end) {
      spans.add(TextSpan(text: text.substring(pos, block.end)));
    }
    return spans;
  }

  static TextStyle _monospace(TextStyle base) {
    return base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier New', 'Courier'],
    );
  }

  /// Builds inline spans for [start, end), merging styles of overlapping
  /// facets by splitting the range into runs at facet boundaries.
  ///
  /// When [approximateBlocks] is true (compact previews), block features are
  /// rendered as character styles instead of layout.
  List<InlineSpan> _inlineSpans(
    BuildContext context,
    int start,
    int end,
    List<_ResolvedFacet> facets, {
    bool approximateBlocks = false,
  }) {
    final text = widget.text;

    // Facets that intersect this range and carry renderable features
    final active = facets.where((rf) {
      if (rf.charEnd <= start || rf.charStart >= end) {
        return false;
      }
      if (approximateBlocks) {
        return rf.facet.features.isNotEmpty;
      }
      return rf.facet.features.any(_isInlineFeature);
    }).toList();

    if (active.isEmpty) {
      return [TextSpan(text: text.substring(start, end))];
    }

    final boundaries = SplayTreeSet<int>()
      ..add(start)
      ..add(end);
    for (final rf in active) {
      boundaries
        ..add(rf.charStart.clamp(start, end))
        ..add(rf.charEnd.clamp(start, end));
    }

    final points = boundaries.toList();
    final spans = <InlineSpan>[];

    for (var i = 0; i < points.length - 1; i++) {
      final runStart = points[i];
      final runEnd = points[i + 1];
      final covering = active
          .where((rf) => rf.charStart <= runStart && rf.charEnd >= runEnd)
          .toList();
      spans.add(
        _runSpan(context, runStart, runEnd, covering, approximateBlocks),
      );
    }

    return spans;
  }

  static bool _isInlineFeature(FacetFeature feature) {
    return feature is LinkFacetFeature ||
        feature is MentionFacetFeature ||
        feature is BoldFacetFeature ||
        feature is ItalicFacetFeature ||
        feature is StrikethroughFacetFeature ||
        feature is CodeFacetFeature ||
        feature is SpoilerFacetFeature;
  }

  /// Builds the span for one run, merging all covering facets' features
  InlineSpan _runSpan(
    BuildContext context,
    int runStart,
    int runEnd,
    List<_ResolvedFacet> covering,
    bool approximateBlocks,
  ) {
    final runText = widget.text.substring(runStart, runEnd);
    if (covering.isEmpty) {
      return TextSpan(text: runText);
    }

    var style = const TextStyle();
    final decorations = <TextDecoration>[];
    VoidCallback? onTap;
    _ResolvedFacet? spoiler;
    SpoilerFacetFeature? spoilerFeature;

    for (final rf in covering) {
      for (final feature in rf.facet.features) {
        switch (feature) {
          case BoldFacetFeature():
            style = style.copyWith(fontWeight: FontWeight.w700);
          case ItalicFacetFeature():
            style = style.copyWith(fontStyle: FontStyle.italic);
          case StrikethroughFacetFeature():
            decorations.add(TextDecoration.lineThrough);
          case CodeFacetFeature():
            style = _monospace(style).copyWith(
              backgroundColor: AppColors.backgroundTertiary,
            );
          case LinkFacetFeature(uri: final uri):
            if (uri.isNotEmpty) {
              if (widget.linkStyle != null) {
                style = style.merge(widget.linkStyle);
              } else {
                style = style.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                );
                decorations.add(TextDecoration.underline);
              }
              onTap ??= () {
                UrlLauncher.launchExternalUrl(uri, context: context);
              };
            }
          case MentionFacetFeature(did: final did):
            style = style.copyWith(
              color: Theme.of(context).colorScheme.primary,
              // Only set a weight when none is set yet, so an already-merged
              // bold (w700) isn't clobbered down to w600
              fontWeight: style.fontWeight ?? FontWeight.w600,
            );
            // Federation-supplied DID goes into a router path: only wire
            // navigation for structurally valid DIDs (a value like
            // "../login" would otherwise normalize into another route).
            // Invalid DIDs render styled but not tappable.
            if (_didPattern.hasMatch(did)) {
              final mentionText =
                  widget.text.substring(rf.charStart, rf.charEnd);
              onTap ??= () => _openMention(context, did, mentionText);
            }
          case SpoilerFacetFeature():
            if (spoiler == null) {
              spoiler = rf;
              spoilerFeature = feature;
            }
          case BlockquoteFacetFeature():
            if (approximateBlocks) {
              style = style.copyWith(
                fontStyle: FontStyle.italic,
                // Muted color only when no earlier feature (link/mention)
                // already set one
                color: style.color ?? AppColors.textSecondary,
              );
            }
          case HeadingFacetFeature():
            if (approximateBlocks) {
              style = style.copyWith(fontWeight: FontWeight.w700);
            }
          case CodeBlockFacetFeature():
            if (approximateBlocks) {
              style = _monospace(style).copyWith(
                backgroundColor: AppColors.backgroundTertiary,
              );
            }
          case UnknownFacetFeature():
            break; // Open union: unknown features render as plain text
        }
      }
    }

    if (decorations.isNotEmpty) {
      style = style.copyWith(decoration: TextDecoration.combine(decorations));
    }

    String? semanticsLabel;
    if (spoiler != null) {
      final key = '${spoiler.charStart}:${spoiler.charEnd}';
      if (_revealedSpoilers.contains(key)) {
        style = style.copyWith(
          backgroundColor: AppColors.backgroundTertiary.withValues(alpha: 0.5),
        );
        // Revealed: onTap YIELDS to link/mention, so a revealed spoilered
        // link launches (and consequently cannot be re-hidden) — deliberate
        onTap ??= () => setState(() => _revealedSpoilers.remove(key));
      } else {
        // Redacted: glyphs invisible, background solid; tap to reveal
        style = style.copyWith(
          color: Colors.transparent,
          backgroundColor: AppColors.backgroundTertiary,
          decoration: TextDecoration.none,
        );
        // Screen readers must not speak the concealed text
        final reason = spoilerFeature?.reason;
        semanticsLabel = reason != null
            ? 'Spoiler: $reason. Tap to reveal.'
            : 'Spoiler. Tap to reveal.';
        // Hidden: onTap HARD-overrides link/mention so a concealed URL
        // can't launch before the reader chooses to reveal it — deliberate
        onTap = () => setState(() => _revealedSpoilers.add(key));
      }
    }

    GestureRecognizer? recognizer;
    if (onTap != null) {
      final tapRecognizer = TapGestureRecognizer()..onTap = onTap;
      _recognizers.add(tapRecognizer);
      recognizer = tapRecognizer;
    }

    return TextSpan(
      text: runText,
      style: style,
      recognizer: recognizer,
      semanticsLabel: semanticsLabel,
    );
  }

  /// Structural DID shape (method + method-specific id); mentions with DIDs
  /// that don't match are rendered styled but never made tappable, since the
  /// DID is interpolated into a router path.
  static final _didPattern = RegExp(r'^did:[a-z0-9]+:[A-Za-z0-9._:%-]+$');

  /// Navigates to the mentioned user or community
  ///
  /// The facet only carries a DID; the text prefix distinguishes users ('@')
  /// from communities ('!'). Known limitation: a malformed facet range that
  /// excludes the prefix character makes the heuristic misroute (community
  /// mentions would open as profiles) — the facet itself carries no
  /// user-vs-community discriminator to check against.
  void _openMention(BuildContext context, String did, String mentionText) {
    final route =
        mentionText.startsWith('!') ? '/community/$did' : '/profile/$did';
    context.push(route);
  }
}
