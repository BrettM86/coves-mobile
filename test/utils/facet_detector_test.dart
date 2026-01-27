import 'package:coves_flutter/utils/facet_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FacetDetector', () {
    test('detects simple URL', () {
      const text = 'Check out https://example.com for more info';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 1);
      expect(facets[0].hasLink, true);
      expect(facets[0].linkUri, 'https://example.com');
    });

    test('detects domain without protocol', () {
      const text = 'Visit example.com for details';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 1);
      expect(facets[0].hasLink, true);
      expect(facets[0].linkUri, 'https://example.com');
    });

    test('detects multiple URLs', () {
      const text = 'Visit https://example.com and https://test.org today';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 2);
      expect(facets[0].linkUri, 'https://example.com');
      expect(facets[1].linkUri, 'https://test.org');
    });

    test('handles URL with emoji correctly (UTF-8 vs UTF-16)', () {
      const text = 'Hello 👋 check https://example.com world';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 1);
      expect(facets[0].hasLink, true);
      expect(facets[0].linkUri, 'https://example.com');

      // Verify byte indices are correct
      // "Hello 👋 check " = 5 + 1 + 4 (emoji) + 1 + 6 = 17 bytes
      expect(facets[0].index.byteStart, 17);
      // "https://example.com" = 19 bytes
      expect(facets[0].index.byteEnd, 36);
    });

    test('trims trailing punctuation', () {
      const text = 'Check out https://example.com!';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 1);
      expect(facets[0].linkUri, 'https://example.com');
    });

    test('handles empty text', () {
      const text = '';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 0);
    });

    test('handles text with no URLs', () {
      const text = 'This is just plain text';
      final facets = FacetDetector.detectLinks(text);

      expect(facets.length, 0);
    });
  });

  group('FacetDetector.charIndexToByteIndex', () {
    test('handles ASCII text', () {
      const text = 'Hello world';
      expect(FacetDetector.charIndexToByteIndex(text, 0), 0);
      expect(FacetDetector.charIndexToByteIndex(text, 5), 5);
      expect(FacetDetector.charIndexToByteIndex(text, 11), 11);
    });

    test('handles emoji (4-byte UTF-8)', () {
      const text = 'Hi 👋';
      // 'Hi ' = 3 bytes
      expect(FacetDetector.charIndexToByteIndex(text, 3), 3);
      // '👋' is 2 UTF-16 chars but 4 UTF-8 bytes
      expect(FacetDetector.charIndexToByteIndex(text, 5), 7);
    });

    test('handles multiple emoji', () {
      const text = '👋🌍';
      // First emoji: 2 UTF-16 chars, 4 UTF-8 bytes
      expect(FacetDetector.charIndexToByteIndex(text, 2), 4);
      // Second emoji: 2 UTF-16 chars, 4 UTF-8 bytes
      expect(FacetDetector.charIndexToByteIndex(text, 4), 8);
    });
  });

  group('FacetDetector.byteIndexToCharIndex', () {
    test('handles ASCII text', () {
      const text = 'Hello world';
      expect(FacetDetector.byteIndexToCharIndex(text, 0), 0);
      expect(FacetDetector.byteIndexToCharIndex(text, 5), 5);
      expect(FacetDetector.byteIndexToCharIndex(text, 11), 11);
    });

    test('handles emoji (4-byte UTF-8)', () {
      const text = 'Hi 👋';
      // 'Hi ' = 3 bytes = 3 chars
      expect(FacetDetector.byteIndexToCharIndex(text, 3), 3);
      // '👋' is 4 UTF-8 bytes but 2 UTF-16 chars
      expect(FacetDetector.byteIndexToCharIndex(text, 7), 5);
    });
  });
}
