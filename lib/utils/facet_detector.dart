// Link detection and facet generation for rich text
//
// This utility detects URLs in plain text and generates facets with proper
// UTF-8 byte indices for cross-platform compatibility with the backend.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/facet.dart';

class FacetDetector {
  // Private constructor to prevent instantiation
  FacetDetector._();

  /// URL detection regex
  ///
  /// Matches:
  /// - Full URLs with protocol (https://example.com)
  /// - Domain-only URLs without protocol (example.com/path)
  /// - URLs in various contexts (start of line, after space, after parenthesis)
  ///
  /// This regex is adapted from the atproto reference implementation.
  static final _urlRegex = RegExp(
    r'(^|\s|\()((?:https?:\/\/[\S]+)|(?:[a-z][a-z0-9]*(?:\.[a-z0-9]+)+[\S]*))',
    caseSensitive: false,
    multiLine: true,
  );

  /// Trailing punctuation that should be excluded from URLs
  static const _trailingPunctuation = {'.', ',', '!', '?', ')', ';', ':'};

  /// Detect links in text and generate facets
  ///
  /// Returns a list of RichTextFacet objects with proper UTF-8 byte indices.
  /// Each facet contains a LinkFacetFeature with the normalized URL.
  static List<RichTextFacet> detectLinks(String text) {
    if (text.isEmpty) {
      return [];
    }

    final facets = <RichTextFacet>[];

    for (final match in _urlRegex.allMatches(text)) {
      // Group 2 contains the actual URL (group 1 is the prefix)
      final urlMatch = match.group(2);
      if (urlMatch == null || urlMatch.isEmpty) {
        continue;
      }

      // Calculate the start position of the URL (skip the prefix)
      final prefixLength = match.group(1)?.length ?? 0;
      final urlStart = match.start + prefixLength;

      // Trim trailing punctuation from the URL
      final trimmed = _trimTrailingPunctuation(urlMatch);
      if (trimmed.isEmpty) {
        continue;
      }

      final urlEnd = urlStart + trimmed.length;

      // Normalize the URL (add https:// if missing)
      final normalizedUrl = _normalizeUrl(trimmed);

      // Validate the normalized URL
      if (!_isValidUrl(normalizedUrl)) {
        continue;
      }

      // Convert character indices to UTF-8 byte indices
      final byteStart = charIndexToByteIndex(text, urlStart);
      final byteEnd = charIndexToByteIndex(text, urlEnd);

      // Create the facet
      facets.add(
        RichTextFacet(
          index: ByteSlice(
            byteStart: byteStart,
            byteEnd: byteEnd,
          ),
          features: [
            LinkFacetFeature(uri: normalizedUrl),
          ],
        ),
      );
    }

    return facets;
  }

  /// Convert a character index (UTF-16) to a byte index (UTF-8)
  ///
  /// Dart strings use UTF-16 encoding internally, but the backend expects
  /// UTF-8 byte indices. This is critical for proper alignment when text
  /// contains emoji or other multi-byte characters.
  ///
  /// Example:
  /// - Text: "Hello 👋 world"
  /// - Character index of "world": 9
  /// - Byte index of "world": 11 (6 bytes for "Hello " + 4 byte emoji + 1 space)
  static int charIndexToByteIndex(String text, int charIndex) {
    if (charIndex < 0) {
      return 0;
    }

    if (charIndex >= text.length) {
      return utf8.encode(text).length;
    }

    // Extract substring up to the character index
    final substring = text.substring(0, charIndex);

    // Encode to UTF-8 and get the byte length
    return utf8.encode(substring).length;
  }

  /// Convert a byte index (UTF-8) to a character index (UTF-16)
  ///
  /// This is the inverse of charIndexToByteIndex. It's useful for converting
  /// backend byte indices back to Dart string indices for display.
  ///
  /// Example:
  /// - Text: "Hello 👋 world"
  /// - Byte index: 10
  /// - Character index: 9
  static int byteIndexToCharIndex(String text, int byteIndex) {
    if (byteIndex <= 0) {
      return 0;
    }

    final bytes = utf8.encode(text);
    if (byteIndex >= bytes.length) {
      return text.length;
    }

    // Decode the substring of bytes up to the byte index
    try {
      final substring = utf8.decode(bytes.sublist(0, byteIndex));
      return substring.length;
    } on FormatException catch (e) {
      // Byte index falls in the middle of a multi-byte character
      if (kDebugMode) {
        debugPrint(
          'FacetDetector: byteIndexToCharIndex failed at byte $byteIndex: $e',
        );
      }
      return -1;
    }
  }

  /// Trim trailing punctuation from a URL
  ///
  /// URLs in natural text often have punctuation at the end that shouldn't
  /// be part of the link (e.g., "Check out example.com!" -> "example.com")
  static String _trimTrailingPunctuation(String url) {
    var trimmed = url;

    while (trimmed.isNotEmpty &&
        _trailingPunctuation.contains(trimmed[trimmed.length - 1])) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }

  /// Normalize a URL by adding https:// if no protocol is present
  ///
  /// Examples:
  /// - "example.com" -> "https://example.com"
  /// - "http://example.com" -> "http://example.com" (unchanged)
  /// - "https://example.com" -> "https://example.com" (unchanged)
  static String _normalizeUrl(String url) {
    final trimmed = url.trim();

    if (trimmed.isEmpty) {
      return trimmed;
    }

    // Check if URL already has a protocol
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    // Add https:// as default protocol
    return 'https://$trimmed';
  }

  /// Validate that a string is a valid URL
  ///
  /// Basic validation to ensure the URL has a valid scheme and host.
  static bool _isValidUrl(String url) {
    if (url.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    // Must have a scheme (http or https)
    if (!uri.hasScheme) {
      return false;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }

    // Must have a host
    if (!uri.hasAuthority || uri.host.isEmpty) {
      return false;
    }

    return true;
  }
}
