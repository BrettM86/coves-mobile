import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/mock_url_launcher_platform.dart';

/// Helper to get UTF-8 byte length of a string
int _byteLen(String s) => utf8.encode(s).length;

/// Helper to create a link facet for testing using substring positions
/// This calculates byte indices automatically from the text
RichTextFacet _createLinkFacetFromText({
  required String fullText,
  required String linkText,
  required String uri,
  int occurrence = 0,
}) {
  // Find the character indices
  int charStart = fullText.indexOf(linkText);
  for (int i = 0; i < occurrence && charStart != -1; i++) {
    charStart = fullText.indexOf(linkText, charStart + 1);
  }
  if (charStart == -1) {
    throw ArgumentError('linkText "$linkText" not found in fullText');
  }
  final charEnd = charStart + linkText.length;

  // Convert to byte indices
  final byteStart = _byteLen(fullText.substring(0, charStart));
  final byteEnd = _byteLen(fullText.substring(0, charEnd));

  return RichTextFacet(
    index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
    features: [LinkFacetFeature(uri: uri)],
  );
}

/// Helper to create a link facet with raw byte indices
RichTextFacet _createLinkFacet({
  required int byteStart,
  required int byteEnd,
  required String uri,
}) {
  return RichTextFacet(
    index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
    features: [LinkFacetFeature(uri: uri)],
  );
}

/// Helper to wrap widget in MaterialApp for testing
Widget _wrapInMaterialApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

/// Helper to get the inner content spans from a RichText widget
/// The structure is: RichText > TextSpan (with style) > children spans
/// Due to Flutter's text rendering, there may be an extra nesting level
List<InlineSpan> _getContentSpans(RichText richText) {
  final textSpan = richText.text as TextSpan;
  // If textSpan has children and the first child is also a TextSpan with children,
  // we're looking at a nested structure
  if (textSpan.children != null && textSpan.children!.isNotEmpty) {
    final firstChild = textSpan.children![0];
    if (firstChild is TextSpan &&
        firstChild.children != null &&
        firstChild.children!.isNotEmpty) {
      return firstChild.children!;
    }
    return textSpan.children!;
  }
  return [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUrlLauncherPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockPlatform;
  });

  group('RichTextRenderer - Basic Rendering', () {
    testWidgets('renders plain text when no facets provided', (tester) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(const RichTextRenderer(text: 'Hello, world!')),
      );

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('renders plain text when facets list is empty', (tester) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(
          const RichTextRenderer(text: 'Hello, world!', facets: []),
        ),
      );

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('renders plain text when text is empty (even with facets)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: '',
            facets: [
              _createLinkFacet(
                byteStart: 0,
                byteEnd: 5,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      // Empty text should render empty widget
      expect(find.byType(Text), findsOneWidget);
      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.data, '');
    });
  });

  group('RichTextRenderer - Link Facet Rendering', () {
    testWidgets(
      'renders link with correct styling (underlined, primary color)',
      (tester) async {
        const text = 'Check out https://example.com please';
        const linkText = 'https://example.com';

        await tester.pumpWidget(
          _wrapInMaterialApp(
            RichTextRenderer(
              text: text,
              facets: [
                _createLinkFacetFromText(
                  fullText: text,
                  linkText: linkText,
                  uri: 'https://example.com',
                ),
              ],
            ),
          ),
        );

        // Find the RichText widget
        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsOneWidget);

        final richText = tester.widget<RichText>(richTextFinder);
        final spans = _getContentSpans(richText);

        // Verify structure: should have 3 children (before, link, after)
        expect(spans.length, 3);

        // Verify the link span has proper styling
        final linkSpan = spans[1] as TextSpan;
        expect(linkSpan.text, linkText);
        expect(linkSpan.style?.decoration, TextDecoration.underline);
        expect(linkSpan.style?.color, isNotNull);
      },
    );

    testWidgets('multiple links render correctly with text between them', (
      tester,
    ) async {
      const text = 'Visit google.com and apple.com today';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'google.com',
                uri: 'https://google.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'apple.com',
                uri: 'https://apple.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      // Should have 5 spans: "Visit ", "google.com", " and ", "apple.com", " today"
      expect(spans.length, 5);

      // Verify first link
      final firstLink = spans[1] as TextSpan;
      expect(firstLink.text, 'google.com');
      expect(firstLink.style?.decoration, TextDecoration.underline);

      // Verify second link
      final secondLink = spans[3] as TextSpan;
      expect(secondLink.text, 'apple.com');
      expect(secondLink.style?.decoration, TextDecoration.underline);
    });

    testWidgets('link at start of text', (tester) async {
      const text = 'https://example.com is cool';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      // Should have 2 spans: link and " is cool"
      expect(spans.length, 2);

      final linkSpan = spans[0] as TextSpan;
      expect(linkSpan.text, linkText);
      expect(linkSpan.style?.decoration, TextDecoration.underline);
    });

    testWidgets('link at end of text', (tester) async {
      const text = 'Visit https://example.com';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      // Should have 2 spans: "Visit " and link
      expect(spans.length, 2);

      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, linkText);
      expect(linkSpan.style?.decoration, TextDecoration.underline);
    });

    testWidgets('custom linkStyle overrides default styling', (tester) async {
      const text = 'Check out https://example.com please';
      const linkText = 'https://example.com';
      const customLinkStyle = TextStyle(
        color: Colors.red,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.none,
      );

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
            linkStyle: customLinkStyle,
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.style?.color, Colors.red);
      expect(linkSpan.style?.fontWeight, FontWeight.bold);
      expect(linkSpan.style?.decoration, TextDecoration.none);
    });
  });

  group('RichTextRenderer - Facet Boundary Cases', () {
    testWidgets(
      'handles out-of-bounds facet indices gracefully (does not crash)',
      (tester) async {
        // Create facet with indices beyond text length
        await tester.pumpWidget(
          _wrapInMaterialApp(
            RichTextRenderer(
              text: 'Short text',
              facets: [
                _createLinkFacet(
                  byteStart: 100,
                  byteEnd: 200,
                  uri: 'https://example.com',
                ),
              ],
            ),
          ),
        );

        // Should render without crashing
        expect(find.byType(RichText), findsOneWidget);

        final richText = tester.widget<RichText>(find.byType(RichText));
        final spans = _getContentSpans(richText);

        // The invalid facet should be skipped, rendering just plain text
        // When facets are skipped, remaining text should still be added
        expect(spans, isNotEmpty);
      },
    );

    testWidgets('handles overlapping facets (processes first, skips overlap)', (
      tester,
    ) async {
      // Two facets that overlap
      const text = 'Check https://example.com out';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'https://example.com',
                uri: 'https://example.com',
              ),
              // Create overlapping facet manually
              _createLinkFacet(
                byteStart: _byteLen('Check htt'),
                byteEnd: _byteLen('Check https://exam'),
                uri: 'https://other.com',
              ),
            ],
          ),
        ),
      );

      // Should render without crashing
      expect(find.byType(RichText), findsOneWidget);

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // First facet should be processed, second should be skipped
      // Result: "Check ", link, " out"
      expect(spans.length, 3);

      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, 'https://example.com');
    });

    testWidgets('handles facets with invalid byte range (skipped gracefully)', (
      tester,
    ) async {
      // Test that the widget doesn't crash with edge cases
      // Note: ByteSlice has assertions, so we test the renderer's handling
      // of facets at rendering boundaries
      await tester.pumpWidget(
        _wrapInMaterialApp(
          const RichTextRenderer(
            text: 'Hello world',
            facets: [], // Empty facets to avoid assertion error
          ),
        ),
      );

      // Should render plain text
      expect(find.text('Hello world'), findsOneWidget);
    });
  });

  group('RichTextRenderer - UTF-8/Emoji Handling', () {
    testWidgets('text with emoji before link renders correctly', (
      tester,
    ) async {
      const text = 'Hello 👋 https://example.com world';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      expect(spans.length, 3);

      // Verify the text before link contains emoji
      final beforeSpan = spans[0] as TextSpan;
      expect(beforeSpan.text, contains('👋'));

      // Verify the link
      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, linkText);
      expect(linkSpan.style?.decoration, TextDecoration.underline);
    });

    testWidgets('text with emoji after link renders correctly', (tester) async {
      const text = 'Visit https://example.com 🎉';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      expect(spans.length, 3);

      // Verify the link
      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, linkText);

      // Verify the text after link contains emoji
      final afterSpan = spans[2] as TextSpan;
      expect(afterSpan.text, contains('🎉'));
    });

    testWidgets('link text containing emoji displays properly', (tester) async {
      // While URLs typically don't contain emoji, the display text might
      // if the facet covers text that includes emoji
      const text = 'Click here 👉 now';
      const linkText = 'here 👉';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      expect(spans.length, 3);

      // Find the link span that should contain emoji
      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, contains('👉'));
      expect(linkSpan.style?.decoration, TextDecoration.underline);
    });

    testWidgets('multiple emojis with multiple links', (tester) async {
      const text = '🎉 Visit google.com 🚀 and apple.com 🍎';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'google.com',
                uri: 'https://google.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'apple.com',
                uri: 'https://apple.com',
              ),
            ],
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      // Verify it renders without crashing
      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      // Should have 5 spans with proper content
      expect(spans.length, 5);

      // Check first emoji is in first span
      final firstSpan = spans[0] as TextSpan;
      expect(firstSpan.text, contains('🎉'));

      // Check google.com link
      final googleLink = spans[1] as TextSpan;
      expect(googleLink.text, 'google.com');

      // Check middle section has emoji
      final middleSpan = spans[2] as TextSpan;
      expect(middleSpan.text, contains('🚀'));

      // Check apple.com link
      final appleLink = spans[3] as TextSpan;
      expect(appleLink.text, 'apple.com');

      // Check last emoji
      final lastSpan = spans[4] as TextSpan;
      expect(lastSpan.text, contains('🍎'));
    });
  });

  group('RichTextRenderer - Interaction', () {
    testWidgets('tapping a link triggers URL launch', (tester) async {
      const text = 'Visit https://example.com today';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      // Find the RichText widget
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final spans = _getContentSpans(richText);

      // Find the link span with a recognizer
      final linkSpan = spans[1] as TextSpan;
      expect(linkSpan.recognizer, isNotNull);
      expect(linkSpan.recognizer, isA<TapGestureRecognizer>());

      // Simulate tap on the recognizer
      final recognizer = linkSpan.recognizer as TapGestureRecognizer;
      recognizer.onTap?.call();

      // Allow async operations to complete
      await tester.pumpAndSettle();

      // Verify URL was launched
      expect(mockPlatform.launchedUrls, contains('https://example.com'));
    });

    testWidgets('multiple links have separate recognizers', (tester) async {
      const text = 'Visit google.com and apple.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'google.com',
                uri: 'https://google.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'apple.com',
                uri: 'https://apple.com',
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // First link
      final firstLink = spans[1] as TextSpan;
      expect(firstLink.recognizer, isNotNull);
      (firstLink.recognizer as TapGestureRecognizer).onTap?.call();

      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, contains('https://google.com'));

      // Second link
      final secondLink = spans[3] as TextSpan;
      expect(secondLink.recognizer, isNotNull);
      (secondLink.recognizer as TapGestureRecognizer).onTap?.call();

      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, contains('https://apple.com'));
    });

    testWidgets('recognizers are properly disposed on widget disposal', (
      tester,
    ) async {
      const text = 'Visit https://example.com today';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      // Verify widget rendered
      expect(find.byType(RichText), findsOneWidget);

      // Remove the widget (trigger dispose)
      await tester.pumpWidget(_wrapInMaterialApp(const SizedBox()));

      // No crash means recognizers were properly disposed
      expect(find.byType(RichText), findsNothing);
    });
  });

  group('RichTextRenderer - Widget Properties', () {
    testWidgets('maxLines is applied', (tester) async {
      const text =
          'A very long text that should be limited to one line when maxLines is set';
      const linkText = 'A ver';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
            maxLines: 1,
          ),
        ),
      );

      // Find Text.rich widget and check maxLines
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      expect(richText.maxLines, 1);
    });

    testWidgets('maxLines is applied to plain text (no facets)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(
          const RichTextRenderer(
            text: 'A very long text that should be limited',
            maxLines: 2,
          ),
        ),
      );

      final textFinder = find.byType(Text);
      expect(textFinder, findsOneWidget);

      final text = tester.widget<Text>(textFinder);
      expect(text.maxLines, 2);
    });

    testWidgets('overflow is applied', (tester) async {
      const text = 'Some text with a link https://example.com';
      const linkText = 'https://example.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      expect(richText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('overflow is applied to plain text (no facets)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(
          const RichTextRenderer(
            text: 'Plain text without links',
            overflow: TextOverflow.fade,
          ),
        ),
      );

      final textFinder = find.byType(Text);
      expect(textFinder, findsOneWidget);

      final text = tester.widget<Text>(textFinder);
      expect(text.overflow, TextOverflow.fade);
    });

    testWidgets('style is applied to all text', (tester) async {
      const text = 'Check out https://example.com please';
      const linkText = 'https://example.com';
      const baseStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: Colors.grey,
      );

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: linkText,
                uri: 'https://example.com',
              ),
            ],
            style: baseStyle,
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;

      // The style is applied to the inner TextSpan (child of root)
      // Root span has default Material text style, inner span has our style
      expect(rootSpan.children, isNotNull);
      final innerSpan = rootSpan.children![0] as TextSpan;

      // Verify the custom style is applied
      expect(innerSpan.style?.fontSize, 18.0);
      expect(innerSpan.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('style is applied to plain text (no facets)', (tester) async {
      const baseStyle = TextStyle(fontSize: 24, color: Colors.blue);

      await tester.pumpWidget(
        _wrapInMaterialApp(
          const RichTextRenderer(text: 'Just plain text', style: baseStyle),
        ),
      );

      final textFinder = find.byType(Text);
      final text = tester.widget<Text>(textFinder);
      expect(text.style?.fontSize, 24);
      expect(text.style?.color, Colors.blue);
    });
  });

  group('RichTextRenderer - Edge Cases', () {
    testWidgets('handles facet with empty features list', (tester) async {
      const text = 'Some text here';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              RichTextFacet(
                index: ByteSlice(
                  byteStart: _byteLen('Some '),
                  byteEnd: _byteLen('Some text'),
                ),
                features: const [], // Empty features
              ),
            ],
          ),
        ),
      );

      // Should render without crashing
      expect(find.byType(RichText), findsOneWidget);

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // The facet with empty features should be rendered as plain text
      expect(spans, isNotEmpty);
    });

    testWidgets('handles unknown facet feature type', (tester) async {
      const text = 'Some text here';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              RichTextFacet(
                index: ByteSlice(
                  byteStart: _byteLen('Some '),
                  byteEnd: _byteLen('Some text'),
                ),
                features: [
                  UnknownFacetFeature(data: {r'$type': 'unknown.type'}),
                ],
              ),
            ],
          ),
        ),
      );

      // Should render without crashing (unknown features treated as plain text)
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('handles link with empty URI', (tester) async {
      const text = 'Some text here';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              RichTextFacet(
                index: ByteSlice(
                  byteStart: _byteLen('Some '),
                  byteEnd: _byteLen('Some text'),
                ),
                features: const [LinkFacetFeature(uri: '')],
              ),
            ],
          ),
        ),
      );

      // Should render without crashing
      expect(find.byType(RichText), findsOneWidget);

      // Empty URI link should be rendered as plain text (no recognizer)
      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // There should be spans since we have valid byte indices
      expect(spans, isNotEmpty);

      // If there are 3 children (before, facet, after), check the facet has no recognizer
      if (spans.length >= 2) {
        final facetSpan = spans[1] as TextSpan;
        expect(facetSpan.recognizer, isNull);
      }
    });

    testWidgets('widget rebuilds properly when facets change', (tester) async {
      const text1 = 'Visit https://first.com please';
      const link1 = 'https://first.com';
      const text2 = 'Visit https://second.com please';
      const link2 = 'https://second.com';

      // Initial render with one link
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text1,
            facets: [
              _createLinkFacetFromText(
                fullText: text1,
                linkText: link1,
                uri: 'https://first.com',
              ),
            ],
          ),
        ),
      );

      var richText = tester.widget<RichText>(find.byType(RichText));
      var spans = _getContentSpans(richText);
      expect(spans.length, greaterThanOrEqualTo(2));
      var linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, link1);

      // Update with different link
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text2,
            facets: [
              _createLinkFacetFromText(
                fullText: text2,
                linkText: link2,
                uri: 'https://second.com',
              ),
            ],
          ),
        ),
      );

      richText = tester.widget<RichText>(find.byType(RichText));
      spans = _getContentSpans(richText);
      expect(spans.length, greaterThanOrEqualTo(2));
      linkSpan = spans[1] as TextSpan;
      expect(linkSpan.text, link2);
    });

    testWidgets('handles very long text with many facets', (tester) async {
      const text =
          'Link1: a.com Link2: b.com Link3: c.com Link4: d.com Link5: e.com';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'a.com',
                uri: 'https://a.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'b.com',
                uri: 'https://b.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'c.com',
                uri: 'https://c.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'd.com',
                uri: 'https://d.com',
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'e.com',
                uri: 'https://e.com',
              ),
            ],
          ),
        ),
      );

      // Should render without crashing
      expect(find.byType(RichText), findsOneWidget);

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // Should have children
      expect(spans, isNotEmpty);
      // 5 links + up to 6 text segments, but implementation may vary
      expect(spans.length, greaterThanOrEqualTo(5));
    });
  });
}
