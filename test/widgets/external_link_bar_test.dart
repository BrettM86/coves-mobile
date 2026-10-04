import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/mock_url_launcher_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUrlLauncherPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockPlatform;
  });

  /// The bar shows the favicon's generic link glyph and requests no favicon.
  void expectGenericLinkGlyph() {
    final bar = find.byType(ExternalLinkBar);
    expect(
      find.descendant(of: bar, matching: find.byType(CachedNetworkImage)),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.link)),
      findsOneWidget,
    );
  }

  /// The bar's uri is one a tap cannot open, so the bar is plain text: no
  /// tap target, no open-in-new arrow, and a screen reader reads [label]
  /// alone, once, as neither a button nor something to activate. Tapping it
  /// does nothing, not even the launcher's "Invalid link format" snackbar.
  /// Needs semantics enabled.
  Future<void> expectInertBar(WidgetTester tester, String label) async {
    final bar = find.byType(ExternalLinkBar);
    expect(
      find.descendant(of: bar, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTap != null,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.open_in_new)),
      findsNothing,
    );

    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(label))),
      findsOneWidget,
      reason: 'the label is announced once',
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(label: label, isButton: false, hasTapAction: false),
    );
    expect(find.bySemanticsLabel(RegExp('Open link to')), findsNothing);

    await tester.tap(bar);
    await tester.pumpAndSettle();

    expect(mockPlatform.launchedUrls, isEmpty);
    expect(find.text('Invalid link format'), findsNothing);
  }

  group('ExternalLinkBar', () {
    testWidgets('renders with domain and favicon', (tester) async {
      final embed = ExternalEmbed(
        uri: 'https://example.com/article',
        domain: 'example.com',
        title: 'Test Article',
        description: 'A test article',
        thumb: 'https://example.com/thumb.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // Verify domain is displayed
      expect(find.text('example.com'), findsOneWidget);

      // Verify external link icon is present
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('handles missing domain field by extracting from URI', (
      tester,
    ) async {
      final embed = ExternalEmbed(uri: 'https://test.example.com/path');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // Should extract domain from URI
      expect(find.text('test.example.com'), findsOneWidget);
    });

    testWidgets('handles invalid URI gracefully', (tester) async {
      final embed = ExternalEmbed(uri: 'not a valid url');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // A uri with no host is shown as written
      expect(find.text('not a valid url'), findsOneWidget);
    });

    testWidgets('launches URL when tapped', (tester) async {
      final embed = ExternalEmbed(
        uri: 'https://example.com/article',
        domain: 'example.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // Tap the link bar
      await tester.tap(find.byType(ExternalLinkBar));
      await tester.pumpAndSettle();

      // Verify URL was launched
      expect(
        mockPlatform.launchedUrls,
        contains('https://example.com/article'),
      );
    });

    testWidgets('has proper accessibility label', (tester) async {
      final embed = ExternalEmbed(
        uri: 'https://example.com',
        domain: 'example.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // Verify Semantics widget is present
      expect(find.byType(Semantics), findsWidgets);

      // Verify link renders
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('displays favicon from Google service', (tester) async {
      final embed = ExternalEmbed(
        uri: 'https://github.com/user/repo',
        domain: 'github.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );

      // Let images load
      await tester.pumpAndSettle();

      // Verify CachedNetworkImage is present (favicon)
      expect(find.byType(Image), findsOneWidget);
    });

    group('Domain Extraction Edge Cases', () {
      testWidgets('handles empty domain field', (tester) async {
        final embed = ExternalEmbed(uri: 'https://example.com', domain: '');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExternalLinkBar(embed: embed)),
          ),
        );

        // Should extract from URI
        expect(find.text('example.com'), findsOneWidget);
      });

      testWidgets('handles URL with path and query', (tester) async {
        final embed = ExternalEmbed(
          uri: 'https://example.com/path?query=value',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExternalLinkBar(embed: embed)),
          ),
        );

        // Should show just domain
        expect(find.text('example.com'), findsOneWidget);
      });

      testWidgets('handles URL with subdomain', (tester) async {
        final embed = ExternalEmbed(uri: 'https://sub.example.com/article');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExternalLinkBar(embed: embed)),
          ),
        );

        // Should show full host
        expect(find.text('sub.example.com'), findsOneWidget);
      });

      testWidgets('handles URL with port', (tester) async {
        final embed = ExternalEmbed(uri: 'https://example.com:8080/path');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExternalLinkBar(embed: embed)),
          ),
        );

        // Should show host with port
        expect(find.text('example.com'), findsOneWidget);
      });
    });
  });

  // The record's `domain` field is author-declared text, while a tap opens
  // `uri`. The bar must name the host the tap actually opens, or a post can
  // show one site and send the reader to another. A uri a tap cannot open
  // is named by the uri itself, never by its host or the declared domain,
  // and the bar is inert: nothing to tap, no arrow, read as plain text.
  group('ExternalLinkBar shows the host the tap opens', () {
    testWidgets(
      'names, announces, and fetches the favicon for the uri host rather '
      'than a spoofed declared domain',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final embed = ExternalEmbed(
            uri: 'https://evil.example/login',
            domain: 'paypal.com',
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: ExternalLinkBar(embed: embed)),
            ),
          );

          expect(find.text('evil.example'), findsOneWidget);
          expect(find.text('paypal.com'), findsNothing);

          expect(
            find.bySemanticsLabel(
              RegExp(
                RegExp.escape('Open link to evil.example in external browser'),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('paypal.com'))),
            findsNothing,
          );

          final faviconUrl = tester
              .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .imageUrl;
          expect(
            Uri.parse(faviconUrl).queryParameters['domain'],
            'evil.example',
          );

          await tester.tap(find.byType(ExternalLinkBar));
          await tester.pumpAndSettle();

          expect(
            Uri.parse(mockPlatform.launchedUrls.single).host,
            'evil.example',
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'shows a hostless uri as written, with the generic link glyph, never '
      'the declared domain, as an inert bar',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final embed = ExternalEmbed(
            uri: 'https:paypal.com',
            domain: 'paypal.com',
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: ExternalLinkBar(embed: embed)),
            ),
          );

          expect(find.text('https:paypal.com'), findsOneWidget);
          expect(find.text('paypal.com'), findsNothing);

          expectGenericLinkGlyph();
          await expectInertBar(tester, 'https:paypal.com');
        } finally {
          handle.dispose();
        }
      },
    );

    // Uri finds the host paypal.com in each of these, but a tap refuses
    // them, so the bar must not read "paypal.com" or show PayPal's icon.
    for (final uri in <String>[
      'ftp://paypal.com/',
      '//paypal.com/login',
      'javascript://paypal.com/%0Aalert(1)',
    ]) {
      testWidgets(
        'shows the uri a tap cannot open "$uri" as written, not its host, '
        'with the generic link glyph, as an inert bar',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ExternalLinkBar(
                    embed: ExternalEmbed(uri: uri, domain: 'paypal.com'),
                  ),
                ),
              ),
            );

            expect(find.text(uri), findsOneWidget);
            expect(find.text('paypal.com'), findsNothing);

            expectGenericLinkGlyph();
            await expectInertBar(tester, uri);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  });

  group('ExternalLinkBar label edge cases', () {
    Future<void> pumpBar(WidgetTester tester, ExternalEmbed embed) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExternalLinkBar(embed: embed)),
        ),
      );
    }

    testWidgets(
      'names the real host of a uri whose userinfo imitates the declared '
      'domain, dropping the userinfo, port, and uppercase',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await pumpBar(
            tester,
            ExternalEmbed(
              uri: 'https://paypal.com@EVIL.example:8443/login',
              domain: 'paypal.com',
            ),
          );

          expect(find.text('evil.example'), findsOneWidget);
          expect(find.text('paypal.com'), findsNothing);

          expect(
            find.bySemanticsLabel(
              RegExp(
                RegExp.escape('Open link to evil.example in external browser'),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('paypal.com'))),
            findsNothing,
          );
        } finally {
          handle.dispose();
        }
      },
    );

    const blankUris = {'an empty uri': '', 'a whitespace-only uri': '   '};
    for (final MapEntry(key: description, value: blankUri)
        in blankUris.entries) {
      testWidgets(
        'shows $description as "Invalid link", with the generic link glyph, '
        'never the declared domain, as an inert bar',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await pumpBar(
              tester,
              ExternalEmbed(uri: blankUri, domain: 'paypal.com'),
            );

            expect(find.text('Invalid link'), findsOneWidget);
            expect(find.text('paypal.com'), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape('paypal.com'))),
              findsNothing,
            );

            expectGenericLinkGlyph();
            await expectInertBar(tester, 'Invalid link');
          } finally {
            handle.dispose();
          }
        },
      );
    }

    testWidgets(
      'shows a hostless uri trimmed of surrounding whitespace, with the '
      'generic link glyph, never the declared domain, as an inert bar',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await pumpBar(
            tester,
            ExternalEmbed(uri: '  not a valid url  ', domain: 'example.org'),
          );

          expect(find.text('not a valid url'), findsOneWidget);
          expect(find.text('example.org'), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('example.org'))),
            findsNothing,
          );

          expectGenericLinkGlyph();
          await expectInertBar(tester, 'not a valid url');
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'shows an absolute uri with leading whitespace as the whole trimmed '
      'uri, since the untrimmed uri has no host, with the generic link '
      'glyph, as an inert bar',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await pumpBar(
            tester,
            ExternalEmbed(
              uri: '  https://example.com/path',
              domain: 'paypal.com',
            ),
          );

          expect(find.text('https://example.com/path'), findsOneWidget);
          expect(find.text('example.com'), findsNothing);
          expect(find.text('paypal.com'), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape('paypal.com'))),
            findsNothing,
          );

          expectGenericLinkGlyph();
          await expectInertBar(tester, 'https://example.com/path');
        } finally {
          handle.dispose();
        }
      },
    );
  });
}
