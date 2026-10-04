import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/widgets/media/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Favicon] stands for the site its url opens, so the url's host decides
/// which icon is fetched, and a url a tap cannot open (`isAllowedWebUrl` is
/// false) shows the generic link glyph, even when it has a host. The url
/// comes straight off an AppView record, so its host is attacker-influenced
/// text: it must not be able to reach into the favicon-service query string
/// and add or overwrite parameters.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  String imageUrlOf(WidgetTester tester) {
    return tester
        .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .imageUrl;
  }

  group('Favicon url building', () {
    testWidgets('builds the canonical query for an ordinary url host', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const Favicon('https://example.com/a')));

      expect(
        imageUrlOf(tester),
        'https://www.google.com/s2/favicons?domain=example.com&sz=32',
      );
    });

    testWidgets('percent-encodes a url host that smuggles a query parameter', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const Favicon('https://evil.com&sz=999/')));

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

    // A url host can carry the sub-delimiters `!$'()*+,;=` raw, and the
    // parsed host keeps a space as the escape `%20`. Both must reach the
    // favicon service as the one `domain` value the host parsed to.
    testWidgets(
      'encodes the sub-delimiters and percent escapes a url host can carry',
      (tester) async {
        await tester.pumpWidget(
          wrap(const Favicon(r"https://a!$'()*+,;=b c/")),
        );

        final url = imageUrlOf(tester);
        expect(
          url,
          'https://www.google.com/s2/favicons'
          '?domain=a%21%24%27%28%29%2A%2B%2C%3B%3Db%2520c&sz=32',
        );
        expect(url.contains(' '), isFalse);
        expect(Uri.parse(url).queryParameters, {
          'domain': r"a!$'()*+,;=b%20c",
          'sz': '32',
        });
      },
    );

    testWidgets(
      'asks for only the host of a url with a subdomain, path, and query',
      (tester) async {
        await tester.pumpWidget(
          wrap(const Favicon('https://sub.example.com/path?q=1')),
        );

        expect(
          imageUrlOf(tester),
          'https://www.google.com/s2/favicons?domain=sub.example.com&sz=32',
        );
      },
    );
  });

  group('Favicon asks only about the url host', () {
    String requestedDomainOf(WidgetTester tester) {
      return Uri.parse(imageUrlOf(tester)).queryParameters['domain']!;
    }

    testWidgets('asks for the host of the url, the site a tap opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Favicon('https://evil.example/login')),
      );

      expect(requestedDomainOf(tester), 'evil.example');
    });

    testWidgets(
      'asks for the lowercased url host, ignoring userinfo and port',
      (tester) async {
        await tester.pumpWidget(
          wrap(const Favicon('https://paypal.com@EVIL.example:8443/login')),
        );

        expect(requestedDomainOf(tester), 'evil.example');
      },
    );

    for (final url in <String>[
      'https:paypal.com',
      'not a url',
      '  https://example.com',
    ]) {
      testWidgets(
        'renders the link glyph and requests no favicon for the hostless '
        'url "$url"',
        (tester) async {
          await tester.pumpWidget(wrap(Favicon(url)));

          expect(find.byType(CachedNetworkImage), findsNothing);
          expect(find.byIcon(Icons.link), findsOneWidget);
        },
      );
    }

    // Uri gives each of these the host paypal.com, but a tap refuses them,
    // so fetching PayPal's icon would dress a dead link as PayPal.
    for (final url in <String>[
      '//paypal.com/login',
      'ftp://paypal.com/',
      'httpx://paypal.com',
      'intent://paypal.com/#Intent;scheme=https;end',
      'javascript://paypal.com/%0Aalert(1)',
      'file://paypal.com/x',
      '',
    ]) {
      testWidgets(
        'renders the link glyph and requests no favicon for the url a tap '
        'cannot open "$url"',
        (tester) async {
          await tester.pumpWidget(wrap(Favicon(url)));

          expect(find.byType(CachedNetworkImage), findsNothing);
          expect(find.byIcon(Icons.link), findsOneWidget);
        },
      );
    }
  });
}
