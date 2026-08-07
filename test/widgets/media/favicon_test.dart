import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/widgets/media/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `domain` a [Favicon] renders comes straight off an AppView record, so
/// it is attacker-influenced text that must not be able to reach into the
/// favicon-service query string and add or overwrite parameters.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  String imageUrlOf(WidgetTester tester) {
    return tester
        .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .imageUrl;
  }

  group('Favicon url building', () {
    testWidgets('builds the canonical query for an ordinary domain', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Favicon('https://example.com/a', domain: 'example.com')),
      );

      expect(
        imageUrlOf(tester),
        'https://www.google.com/s2/favicons?domain=example.com&sz=32',
      );
    });

    testWidgets('percent-encodes a domain that smuggles a query parameter', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Favicon(
            'https://example.com/a',
            domain: 'evil.com&sz=999',
          ),
        ),
      );

      final url = imageUrlOf(tester);
      expect(
        url,
        'https://www.google.com/s2/favicons?domain=evil.com%26sz%3D999&sz=32',
      );
      expect(
        Uri.parse(url).queryParameters['domain'],
        'evil.com&sz=999',
        reason: 'the hostile text stays one value, not two parameters',
      );
      expect(
        Uri.parse(url).queryParameters['sz'],
        '32',
        reason: 'the caller-controlled sz must not be overridden',
      );
    });

    testWidgets('encodes whitespace and other unsafe characters', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Favicon('https://example.com/a', domain: 'bad domain/#?'),
        ),
      );

      final url = imageUrlOf(tester);
      expect(url.contains(' '), isFalse);
      expect(Uri.parse(url).queryParameters['domain'], 'bad domain/#?');
    });

    testWidgets('falls back to the host parsed out of the url', (tester) async {
      await tester.pumpWidget(
        wrap(const Favicon('https://sub.example.com/path?q=1')),
      );

      expect(
        imageUrlOf(tester),
        'https://www.google.com/s2/favicons?domain=sub.example.com&sz=32',
      );
    });

    testWidgets('renders the link glyph when there is no domain at all', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const Favicon('not a url')));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });
  });
}
