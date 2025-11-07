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
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
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
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
      );

      // Should extract domain from URI
      expect(find.text('test.example.com'), findsOneWidget);
    });

    testWidgets('handles invalid URI gracefully', (tester) async {
      final embed = ExternalEmbed(uri: 'not a valid url');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
      );

      // Should fallback to showing full URI
      expect(find.text('not a valid url'), findsOneWidget);
    });

    testWidgets('launches URL when tapped', (tester) async {
      final embed = ExternalEmbed(
        uri: 'https://example.com/article',
        domain: 'example.com',
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
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
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
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
        MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
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
          MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
        );

        // Should extract from URI
        expect(find.text('example.com'), findsOneWidget);
      });

      testWidgets('handles URL with path and query', (tester) async {
        final embed = ExternalEmbed(
          uri: 'https://example.com/path?query=value',
        );

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
        );

        // Should show just domain
        expect(find.text('example.com'), findsOneWidget);
      });

      testWidgets('handles URL with subdomain', (tester) async {
        final embed = ExternalEmbed(uri: 'https://sub.example.com/article');

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
        );

        // Should show full host
        expect(find.text('sub.example.com'), findsOneWidget);
      });

      testWidgets('handles URL with port', (tester) async {
        final embed = ExternalEmbed(uri: 'https://example.com:8080/path');

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ExternalLinkBar(embed: embed))),
        );

        // Should show host with port
        expect(find.text('example.com'), findsOneWidget);
      });
    });
  });
}
