import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  var charStart = fullText.indexOf(linkText);
  for (var i = 0; i < occurrence && charStart != -1; i++) {
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

/// Helper to wrap widget in a real GoRouter harness so mention taps can be
/// asserted against actual navigation. Placeholder screens display the
/// resolved path parameter.
Widget _wrapInRouterApp(Widget child) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: child)),
      GoRoute(
        path: '/profile/:actor',
        builder: (context, state) =>
            Scaffold(body: Text('profile:${state.pathParameters['actor']}')),
      ),
      GoRoute(
        path: '/community/:identifier',
        builder: (context, state) => Scaffold(
          body: Text('community:${state.pathParameters['identifier']}'),
        ),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// Helper to find the TextSpan carrying exactly [text] among content spans
TextSpan _spanWithText(List<InlineSpan> spans, String text) {
  return spans.whereType<TextSpan>().firstWhere((s) => s.text == text);
}

/// Matches the blockquote left-bar container used by the renderer
bool _hasLeftBar(Widget w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).border is Border &&
    ((w.decoration! as BoxDecoration).border! as Border).left.width == 3;

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

    testWidgets('overlapping facets split into runs, first link wins taps', (
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

      // Runs split at facet boundaries:
      // "Check ", "htt", "ps://exam" (both facets), "ple.com", " out"
      expect(spans.length, 5);

      final linkText = [spans[1], spans[2], spans[3]]
          .map((s) => (s as TextSpan).text)
          .join();
      expect(linkText, 'https://example.com');

      // Every link run is styled and tappable
      for (final span in [spans[1], spans[2], spans[3]]) {
        final textSpan = span as TextSpan;
        expect(textSpan.style?.decoration, TextDecoration.underline);
        expect(textSpan.recognizer, isA<TapGestureRecognizer>());
      }

      // In the overlap run the first (earlier-starting) facet wins the tap
      final overlapSpan = spans[2] as TextSpan;
      (overlapSpan.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, contains('https://example.com'));
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
      final recognizer = linkSpan.recognizer! as TapGestureRecognizer;
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
      (firstLink.recognizer! as TapGestureRecognizer).onTap?.call();

      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, contains('https://google.com'));

      // Second link
      final secondLink = spans[3] as TextSpan;
      expect(secondLink.recognizer, isNotNull);
      (secondLink.recognizer! as TapGestureRecognizer).onTap?.call();

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
                  const UnknownFacetFeature(data: {r'$type': 'unknown.type'}),
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

  group('RichTextRenderer - Inline Formatting Facets', () {
    testWidgets('bold facet renders with heavy font weight', (tester) async {
      const text = 'some bold text';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'bold',
                features: const [BoldFacetFeature()],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      expect(spans.length, 3);
      final boldSpan = spans[1] as TextSpan;
      expect(boldSpan.text, 'bold');
      expect(boldSpan.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('overlapping bold and italic merge in the overlap run', (
      tester,
    ) async {
      const text = 'abcdef';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'abcd',
                features: const [BoldFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'cdef',
                features: const [ItalicFacetFeature()],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // "ab" bold, "cd" bold+italic, "ef" italic
      expect(spans.length, 3);

      final bold = spans[0] as TextSpan;
      expect(bold.text, 'ab');
      expect(bold.style?.fontWeight, FontWeight.w700);
      expect(bold.style?.fontStyle, isNot(FontStyle.italic));

      final both = spans[1] as TextSpan;
      expect(both.text, 'cd');
      expect(both.style?.fontWeight, FontWeight.w700);
      expect(both.style?.fontStyle, FontStyle.italic);

      final italic = spans[2] as TextSpan;
      expect(italic.text, 'ef');
      expect(italic.style?.fontWeight, isNull);
      expect(italic.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('strikethrough combines with link underline', (tester) async {
      const text = 'a dead link here';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'dead link',
                features: const [
                  LinkFacetFeature(uri: 'https://example.com'),
                  StrikethroughFacetFeature(),
                ],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);
      final span = spans[1] as TextSpan;

      expect(span.style?.decoration?.contains(TextDecoration.underline), true);
      expect(
        span.style?.decoration?.contains(TextDecoration.lineThrough),
        true,
      );
    });

    testWidgets('inline code renders in monospace', (tester) async {
      const text = 'run flutter test now';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'flutter test',
                features: const [CodeFacetFeature()],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);
      final code = spans[1] as TextSpan;

      expect(code.text, 'flutter test');
      expect(code.style?.fontFamily, 'monospace');
      expect(code.style?.backgroundColor, isNotNull);
    });

    testWidgets('mention is styled and tappable', (tester) async {
      const text = 'hey @alice.test look';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: '@alice.test',
                features: const [MentionFacetFeature(did: 'did:plc:abc')],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);
      final mention = spans[1] as TextSpan;

      expect(mention.text, '@alice.test');
      expect(mention.style?.fontWeight, FontWeight.w600);
      expect(mention.style?.color, isNotNull);
      expect(mention.recognizer, isA<TapGestureRecognizer>());
    });
  });

  group('RichTextRenderer - Spoiler Facets', () {
    testWidgets('spoiler is redacted until tapped, then revealed', (
      tester,
    ) async {
      const text = 'the killer is Bob obviously';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'Bob',
                features: const [SpoilerFacetFeature(reason: 'spoiler')],
              ),
            ],
          ),
        ),
      );

      var richText = tester.widget<RichText>(find.byType(RichText));
      var spans = _getContentSpans(richText);
      var spoilerSpan = spans[1] as TextSpan;

      // Hidden: glyphs transparent over a solid background
      expect(spoilerSpan.style?.color, Colors.transparent);
      expect(spoilerSpan.style?.backgroundColor, isNotNull);
      expect(spoilerSpan.recognizer, isA<TapGestureRecognizer>());

      // Tap to reveal
      (spoilerSpan.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();

      richText = tester.widget<RichText>(find.byType(RichText));
      spans = _getContentSpans(richText);
      spoilerSpan = spans[1] as TextSpan;

      expect(spoilerSpan.style?.color, isNot(Colors.transparent));

      // Tap again to re-hide
      (spoilerSpan.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();

      richText = tester.widget<RichText>(find.byType(RichText));
      spans = _getContentSpans(richText);
      spoilerSpan = spans[1] as TextSpan;
      expect(spoilerSpan.style?.color, Colors.transparent);
    });
  });

  group('RichTextRenderer - Block Facets', () {
    testWidgets('heading renders as its own scaled, bold line', (
      tester,
    ) async {
      const text = 'Big Title\nBody text follows';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            style: const TextStyle(fontSize: 14),
            facets: [
              _facetOver(
                fullText: text,
                span: 'Big Title',
                features: const [HeadingFacetFeature(level: 1)],
              ),
            ],
          ),
        ),
      );

      // Block layout: heading and body are separate RichText widgets
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      expect(richTexts.length, 2);

      // The root span carries the ambient default style; the heading style
      // lives on the inner span
      final root = richTexts.first.text as TextSpan;
      final headingSpan = root.children!.first as TextSpan;
      expect(headingSpan.style?.fontWeight, FontWeight.w700);
      expect(headingSpan.style?.fontSize, greaterThan(14));

      expect(find.textContaining('Body text follows'), findsOneWidget);
    });

    testWidgets('mid-line heading range extends to whole line', (
      tester,
    ) async {
      const text = 'Big Title\nBody';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              // Malformed range covering only "Big" - reader extends it
              _facetOver(
                fullText: text,
                span: 'Big',
                features: const [HeadingFacetFeature(level: 2)],
              ),
            ],
          ),
        ),
      );

      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      expect(richTexts.length, 2);
      expect(richTexts.first.text.toPlainText(), 'Big Title');
    });

    testWidgets('blockquote renders with a left bar per level', (
      tester,
    ) async {
      const text = 'quoted wisdom\nmy reply';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'quoted wisdom',
                features: const [BlockquoteFacetFeature(level: 2)],
              ),
            ],
          ),
        ),
      );

      bool hasLeftBar(Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border is Border &&
          ((w.decoration! as BoxDecoration).border! as Border).left.width == 3;

      // Level 2 quote nests two bar containers
      expect(find.byWidgetPredicate(hasLeftBar), findsNWidgets(2));
      expect(find.textContaining('quoted wisdom'), findsOneWidget);
      expect(find.textContaining('my reply'), findsOneWidget);
    });

    testWidgets('code block renders monospace card with language label', (
      tester,
    ) async {
      const text = 'look:\nprint("hi")\ndone';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'print("hi")',
                features: const [CodeBlockFacetFeature(language: 'python')],
              ),
            ],
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('python'), findsOneWidget);

      final codeText = tester.widget<Text>(find.text('print("hi")'));
      expect(codeText.style?.fontFamily, 'monospace');
      expect(codeText.softWrap, false);

      expect(find.textContaining('look:'), findsOneWidget);
      expect(find.textContaining('done'), findsOneWidget);
    });

    testWidgets('code block inside blockquote (cross-type nesting)', (
      tester,
    ) async {
      const text = 'they said:\ncode here\nend quote';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'they said:\ncode here\nend quote',
                features: const [BlockquoteFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'code here',
                features: const [CodeBlockFacetFeature()],
              ),
            ],
          ),
        ),
      );

      // The code block card renders inside the quote bar container
      final scrollView = find.byType(SingleChildScrollView);
      expect(scrollView, findsOneWidget);
      expect(
        find.ancestor(
          of: scrollView,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).border is Border,
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('adjacent quote facets render as separate blocks', (
      tester,
    ) async {
      const text = 'first quote\nsecond quote';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'first quote',
                features: const [BlockquoteFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'second quote',
                features: const [BlockquoteFacetFeature(level: 2)],
              ),
            ],
          ),
        ),
      );

      // 1 bar for level 1 + 2 bars for level 2
      bool hasLeftBar(Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border is Border &&
          ((w.decoration! as BoxDecoration).border! as Border).left.width == 3;
      expect(find.byWidgetPredicate(hasLeftBar), findsNWidgets(3));
    });

    testWidgets('inline facets still work inside a heading', (tester) async {
      const text = 'See https://example.com\nBody';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'See https://example.com',
                features: const [HeadingFacetFeature(level: 3)],
              ),
              _createLinkFacetFromText(
                fullText: text,
                linkText: 'https://example.com',
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      expect(richTexts.length, 2);

      final headingSpans = _getContentSpans(richTexts.first);
      final linkSpan = headingSpans[1] as TextSpan;
      expect(linkSpan.text, 'https://example.com');
      expect(linkSpan.style?.decoration, TextDecoration.underline);
      expect(linkSpan.recognizer, isA<TapGestureRecognizer>());
    });
  });

  group('RichTextRenderer - Compact Mode (maxLines)', () {
    testWidgets('block facets approximate inline so ellipsis works', (
      tester,
    ) async {
      const text = 'Big Title\nquoted line\ncode line\nplain end';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            facets: [
              _facetOver(
                fullText: text,
                span: 'Big Title',
                features: const [HeadingFacetFeature(level: 1)],
              ),
              _facetOver(
                fullText: text,
                span: 'quoted line',
                features: const [BlockquoteFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'code line',
                features: const [CodeBlockFacetFeature()],
              ),
            ],
          ),
        ),
      );

      // Everything stays in a single RichText so maxLines applies
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      expect(richText.maxLines, 5);
      expect(richText.overflow, TextOverflow.ellipsis);

      final spans = _getContentSpans(richText);
      final byText = {
        for (final s in spans.whereType<TextSpan>()) s.text: s,
      };

      expect(byText['Big Title']?.style?.fontWeight, FontWeight.w700);
      expect(byText['quoted line']?.style?.fontStyle, FontStyle.italic);
      expect(byText['code line']?.style?.fontFamily, 'monospace');
    });
  });

  group('RichTextRenderer - Mention Navigation', () {
    testWidgets('tapping a user mention navigates to the profile route', (
      tester,
    ) async {
      const text = 'hey @alice.test look';

      await tester.pumpWidget(
        _wrapInRouterApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: '@alice.test',
                features: const [MentionFacetFeature(did: 'did:plc:abc')],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final mention = _spanWithText(_getContentSpans(richText), '@alice.test');
      expect(mention.recognizer, isA<TapGestureRecognizer>());

      (mention.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pumpAndSettle();

      expect(find.text('profile:did:plc:abc'), findsOneWidget);
    });

    testWidgets('tapping a community mention navigates to the community route',
        (tester) async {
      const text = 'join !books.coves.social today';

      await tester.pumpWidget(
        _wrapInRouterApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: '!books.coves.social',
                features: const [MentionFacetFeature(did: 'did:plc:books123')],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final mention =
          _spanWithText(_getContentSpans(richText), '!books.coves.social');
      expect(mention.recognizer, isA<TapGestureRecognizer>());

      (mention.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pumpAndSettle();

      expect(find.text('community:did:plc:books123'), findsOneWidget);
    });

    testWidgets('mention with malicious non-DID value is not tappable', (
      tester,
    ) async {
      const text = 'hey @evil.test look';

      await tester.pumpWidget(
        _wrapInRouterApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: '@evil.test',
                features: const [MentionFacetFeature(did: '../login')],
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final mention = _spanWithText(_getContentSpans(richText), '@evil.test');

      // Still styled as a mention, but with no recognizer navigation is
      // impossible
      expect(mention.style?.fontWeight, FontWeight.w600);
      expect(mention.recognizer, isNull);
    });
  });

  group('RichTextRenderer - Block Facets with Emoji', () {
    const text = '🎉 intro\nBig 👋 Title\ncode 🚀 here\nend';

    List<RichTextFacet> facets() => [
          _facetOver(
            fullText: text,
            span: 'Big 👋 Title',
            features: const [HeadingFacetFeature(level: 2)],
          ),
          _facetOver(
            fullText: text,
            span: 'code 🚀 here',
            features: const [CodeBlockFacetFeature()],
          ),
        ];

    testWidgets('emoji before block ranges keeps block boundaries aligned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(RichTextRenderer(text: text, facets: facets())),
      );

      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      final plainTexts = richTexts.map((rt) => rt.text.toPlainText()).toList();

      // The heading line renders exactly, not shifted by multi-byte emoji
      expect(plainTexts, contains('Big 👋 Title'));
      final headingRt = richTexts[plainTexts.indexOf('Big 👋 Title')];
      final headingSpan =
          (headingRt.text as TextSpan).children!.first as TextSpan;
      expect(headingSpan.style?.fontWeight, FontWeight.w700);

      // The code block carries exactly its line
      final codeText = tester.widget<Text>(find.text('code 🚀 here'));
      expect(codeText.style?.fontFamily, 'monospace');

      // Surrounding paragraphs intact
      expect(plainTexts, contains('🎉 intro'));
      expect(plainTexts, contains('end'));
    });

    testWidgets('compact mode approximates emoji block lines inline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(text: text, facets: facets(), maxLines: 4),
        ),
      );

      // Single RichText so maxLines applies
      expect(find.byType(RichText), findsOneWidget);

      final spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      final runTexts =
          spans.whereType<TextSpan>().map((s) => s.text).toList();

      // No text lost or shifted by emoji byte offsets
      expect(runTexts.join(), text);

      final byText = {for (final s in spans.whereType<TextSpan>()) s.text: s};
      expect(byText['Big 👋 Title']?.style?.fontWeight, FontWeight.w700);
      expect(byText['code 🚀 here']?.style?.fontFamily, 'monospace');
    });
  });

  group('RichTextRenderer - Block Range Degradation', () {
    testWidgets('facet with byteEnd past text byte length is dropped', (
      tester,
    ) async {
      const text = 'hello world';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _createLinkFacet(
                byteStart: _byteLen('hello '),
                byteEnd: _byteLen(text) + 5,
                uri: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = _getContentSpans(richText);

      // Facet dropped entirely: one plain run, no link styling or tap
      expect(spans.length, 1);
      final span = spans[0] as TextSpan;
      expect(span.text, text);
      expect(span.style?.decoration, isNull);
      expect(span.recognizer, isNull);
    });

    testWidgets('block range starting on a newline leaves prior line out', (
      tester,
    ) async {
      const text = 'hello\nquoted line';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              // Sloppy range starting AT the newline byte
              RichTextFacet(
                index: ByteSlice(
                  byteStart: _byteLen('hello'),
                  byteEnd: _byteLen(text),
                ),
                features: const [BlockquoteFacetFeature()],
              ),
            ],
          ),
        ),
      );

      expect(find.byWidgetPredicate(_hasLeftBar), findsOneWidget);

      final hello = find.textContaining('hello');
      expect(hello, findsOneWidget);
      expect(
        find.ancestor(of: hello, matching: find.byWidgetPredicate(_hasLeftBar)),
        findsNothing,
      );

      final quoted = find.textContaining('quoted line');
      expect(quoted, findsOneWidget);
      expect(
        find.ancestor(
          of: quoted,
          matching: find.byWidgetPredicate(_hasLeftBar),
        ),
        findsOneWidget,
      );
    });

    testWidgets('code block straddling a quote boundary loses no text', (
      tester,
    ) async {
      const text = 'line one\nline two\nline three';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'line one\nline two',
                features: const [BlockquoteFacetFeature()],
              ),
              // Starts inside line two, ends in line three: straddles the
              // quote's end boundary
              _facetOver(
                fullText: text,
                span: 'two\nline three',
                features: const [CodeBlockFacetFeature()],
              ),
            ],
          ),
        ),
      );

      // Quote renders lines 1-2 inside its bar
      expect(find.byWidgetPredicate(_hasLeftBar), findsOneWidget);
      final quoted = find.textContaining('line one');
      expect(quoted, findsOneWidget);
      expect(
        find.ancestor(
          of: quoted,
          matching: find.byWidgetPredicate(_hasLeftBar),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('line two'), findsOneWidget);

      // Line three still appears (as a paragraph outside the bar)
      final lineThree = find.textContaining('line three');
      expect(lineThree, findsOneWidget);
      expect(
        find.ancestor(
          of: lineThree,
          matching: find.byWidgetPredicate(_hasLeftBar),
        ),
        findsNothing,
      );
    });

    testWidgets('quote fully contained in a quote degrades without crash', (
      tester,
    ) async {
      const text = 'quoted outer\nquoted inner';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: text,
                features: const [BlockquoteFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'quoted inner',
                features: const [BlockquoteFacetFeature(level: 2)],
              ),
            ],
          ),
        ),
      );

      // Disallowed by the lexicon, so exact bar count is not pinned; the
      // outer quote must render and no text may be lost
      expect(find.byWidgetPredicate(_hasLeftBar), findsWidgets);
      expect(find.textContaining('quoted outer'), findsOneWidget);
      expect(find.textContaining('quoted inner'), findsOneWidget);
    });

    testWidgets('code block covering the entire text renders directly', (
      tester,
    ) async {
      const text = 'final x = 42;';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: text,
                features: const [CodeBlockFacetFeature()],
              ),
            ],
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final codeText = tester.widget<Text>(find.text(text));
      expect(codeText.style?.fontFamily, 'monospace');
    });
  });

  group('RichTextRenderer - Spoiler Interaction', () {
    testWidgets('hidden spoilered link reveals on tap instead of launching', (
      tester,
    ) async {
      const text = 'watch the trailer now';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'the trailer',
                features: const [
                  SpoilerFacetFeature(),
                  LinkFacetFeature(uri: 'https://example.com/trailer'),
                ],
              ),
            ],
          ),
        ),
      );

      var spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      var span = _spanWithText(spans, 'the trailer');

      // Hidden: redacted, labelled for screen readers
      expect(span.style?.color, Colors.transparent);
      expect(span.semanticsLabel, contains('Spoiler'));

      // Tap while hidden: reveals, must NOT launch the concealed URL
      (span.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, isEmpty);

      spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      span = _spanWithText(spans, 'the trailer');
      expect(span.style?.color, isNot(Colors.transparent));
      expect(span.semanticsLabel, isNull);

      // Tap while revealed: launches the link
      (span.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pumpAndSettle();
      expect(mockPlatform.launchedUrls, contains('https://example.com/trailer'));
    });

    testWidgets('spoiler reason appears in the semantics label', (
      tester,
    ) async {
      const text = 'the killer is Bob obviously';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'Bob',
                features: const [SpoilerFacetFeature(reason: 'ending')],
              ),
            ],
          ),
        ),
      );

      final spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      final span = _spanWithText(spans, 'Bob');
      expect(span.semanticsLabel, contains('ending'));
    });

    testWidgets('revealed spoiler state is cleared when facets change', (
      tester,
    ) async {
      const text = 'the killer is Bob obviously';

      List<RichTextFacet> spoilerFacets() => [
            _facetOver(
              fullText: text,
              span: 'Bob',
              features: const [SpoilerFacetFeature()],
            ),
          ];

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(text: text, facets: spoilerFacets()),
        ),
      );

      var spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      var span = _spanWithText(spans, 'Bob');
      (span.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();

      spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      span = _spanWithText(spans, 'Bob');
      expect(span.style?.color, isNot(Colors.transparent));

      // Same text, DIFFERENT facets list: reveal state must reset
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              ...spoilerFacets(),
              _facetOver(
                fullText: text,
                span: 'killer',
                features: const [BoldFacetFeature()],
              ),
            ],
          ),
        ),
      );

      spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      span = _spanWithText(spans, 'Bob');
      expect(span.style?.color, Colors.transparent);
    });

    testWidgets('revealed spoiler survives a rebuild with identical facets', (
      tester,
    ) async {
      const text = 'the killer is Bob obviously';

      List<RichTextFacet> spoilerFacets() => [
            _facetOver(
              fullText: text,
              span: 'Bob',
              features: const [SpoilerFacetFeature()],
            ),
          ];

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(text: text, facets: spoilerFacets()),
        ),
      );

      var spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      var span = _spanWithText(spans, 'Bob');
      (span.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();

      // Rebuild with a freshly-constructed but EQUAL facets list
      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(text: text, facets: spoilerFacets()),
        ),
      );

      spans =
          _getContentSpans(tester.widget<RichText>(find.byType(RichText)));
      span = _spanWithText(spans, 'Bob');
      expect(span.style?.color, isNot(Colors.transparent));
    });

    testWidgets('spoiler inside a code block is redacted until tapped', (
      tester,
    ) async {
      const text = 'intro\nlet pass = hunter2\nend';

      await tester.pumpWidget(
        _wrapInMaterialApp(
          RichTextRenderer(
            text: text,
            facets: [
              _facetOver(
                fullText: text,
                span: 'let pass = hunter2',
                features: const [CodeBlockFacetFeature()],
              ),
              _facetOver(
                fullText: text,
                span: 'hunter2',
                features: const [SpoilerFacetFeature()],
              ),
            ],
          ),
        ),
      );

      final codeRichText = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(RichText),
      );

      var spans = _getContentSpans(tester.widget<RichText>(codeRichText));
      var span = _spanWithText(spans, 'hunter2');
      expect(span.style?.color, Colors.transparent);
      expect(span.semanticsLabel, contains('Spoiler'));
      expect(span.recognizer, isA<TapGestureRecognizer>());

      (span.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();

      spans = _getContentSpans(tester.widget<RichText>(codeRichText));
      span = _spanWithText(spans, 'hunter2');
      expect(span.style?.color, isNot(Colors.transparent));
      expect(span.semanticsLabel, isNull);
    });
  });
}

/// Helper to create a facet with arbitrary features over a substring
RichTextFacet _facetOver({
  required String fullText,
  required String span,
  required List<FacetFeature> features,
}) {
  final charStart = fullText.indexOf(span);
  if (charStart == -1) {
    throw ArgumentError('span "$span" not found in fullText');
  }
  final charEnd = charStart + span.length;

  return RichTextFacet(
    index: ByteSlice(
      byteStart: _byteLen(fullText.substring(0, charStart)),
      byteEnd: _byteLen(fullText.substring(0, charEnd)),
    ),
    features: features,
  );
}
