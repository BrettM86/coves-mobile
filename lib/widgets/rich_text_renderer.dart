import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/facet.dart';
import '../utils/facet_detector.dart';
import '../utils/url_launcher.dart';

/// A reusable widget for rendering text with rich text facets (links, mentions, etc.)
///
/// Facets are annotations in the text that specify formatting or special behavior
/// for specific character ranges. This widget converts atProto-style facets into
/// Flutter TextSpan widgets with appropriate styling and interaction handlers.
///
/// Supported facet types:
/// - Links (social.coves.richtext.facet#link): Blue, underlined, tappable
///
/// If no facets are provided, renders plain text.
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
  final int? maxLines;

  /// How to handle text overflow
  final TextOverflow? overflow;

  /// Optional custom style for links (overrides default blue underline)
  final TextStyle? linkStyle;

  @override
  State<RichTextRenderer> createState() => _RichTextRendererState();
}

class _RichTextRendererState extends State<RichTextRenderer> {
  /// Track all gesture recognizers for proper disposal
  final List<GestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If no facets, render plain text
    if (widget.facets == null || widget.facets!.isEmpty || widget.text.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    // Clear previous recognizers before rebuilding spans
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    // Build rich text with facets
    return Text.rich(
      TextSpan(
        children: _buildTextSpans(context),
        style: widget.style,
      ),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }

  /// Builds a list of TextSpan widgets from the text and facets
  ///
  /// This method:
  /// 1. Sorts facets by start position
  /// 2. Iterates through the text, building spans for both plain text and faceted regions
  /// 3. Converts UTF-8 byte indices to Dart character indices using FacetDetector utility
  /// 4. Handles overlapping or invalid facets gracefully
  List<InlineSpan> _buildTextSpans(BuildContext context) {
    final spans = <InlineSpan>[];
    final text = widget.text;

    // Sort facets by start position to process them in order
    final sortedFacets = List<RichTextFacet>.from(widget.facets!)
      ..sort((a, b) => a.index.byteStart.compareTo(b.index.byteStart));

    var currentPosition = 0; // Current position in the text (Dart string index)

    for (final facet in sortedFacets) {
      // Extract byte indices from facet
      final byteStart = facet.index.byteStart;
      final byteEnd = facet.index.byteEnd;

      // Skip invalid facets
      if (byteStart < 0 || byteEnd <= byteStart) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping facet with invalid byte range '
              '[$byteStart, $byteEnd)');
        }
        continue;
      }

      // Convert UTF-8 byte indices to Dart character indices
      final charStart = FacetDetector.byteIndexToCharIndex(text, byteStart);
      final charEnd = FacetDetector.byteIndexToCharIndex(text, byteEnd);

      // Skip if conversion failed or indices are out of bounds
      if (charStart < 0 || charEnd < 0 || charStart >= text.length || charEnd > text.length) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping facet with out-of-bounds char indices '
              '[$charStart, $charEnd) for text length ${text.length}');
        }
        continue;
      }

      // Skip if this facet overlaps with previous content (already processed)
      if (charStart < currentPosition) {
        if (kDebugMode) {
          debugPrint('RichTextRenderer: Skipping overlapping facet at char index '
              '$charStart (current position: $currentPosition)');
        }
        continue;
      }

      // Add plain text before the facet (if any)
      if (charStart > currentPosition) {
        spans.add(TextSpan(text: text.substring(currentPosition, charStart)));
      }

      // Add the faceted text with appropriate styling/behavior
      final facetText = text.substring(charStart, charEnd);
      spans.add(_buildFacetSpan(context, facet, facetText));

      currentPosition = charEnd;
    }

    // Add any remaining plain text after the last facet
    if (currentPosition < text.length) {
      spans.add(TextSpan(text: text.substring(currentPosition)));
    }

    return spans;
  }

  /// Builds a TextSpan for a faceted region of text
  ///
  /// Currently handles link facets. Other facet types can be added here.
  InlineSpan _buildFacetSpan(BuildContext context, RichTextFacet facet, String facetText) {
    if (facet.features.isEmpty) {
      // No features, render as plain text
      return TextSpan(text: facetText);
    }

    // Check for link feature
    for (final feature in facet.features) {
      // Handle link facets
      if (feature is LinkFacetFeature) {
        final uri = feature.uri;

        if (uri.isNotEmpty) {
          // Create tappable link span with tracked recognizer
          final recognizer = TapGestureRecognizer()
            ..onTap = () {
              UrlLauncher.launchExternalUrl(uri, context: context);
            };
          _recognizers.add(recognizer);

          return TextSpan(
            text: facetText,
            style: widget.linkStyle ?? TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          );
        }
      }

    }

    // No recognized features, render as plain text
    return TextSpan(text: facetText);
  }
}
