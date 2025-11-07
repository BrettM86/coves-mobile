import 'package:coves_flutter/utils/url_launcher.dart';
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

  group('UrlLauncher', () {
    group('Security Validation', () {
      test('blocks javascript: scheme', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'javascript:alert("xss")',
        );
        expect(result, false);
        expect(mockPlatform.launchedUrls, isEmpty);
      });

      test('blocks file: scheme', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'file:///etc/passwd',
        );
        expect(result, false);
        expect(mockPlatform.launchedUrls, isEmpty);
      });

      test('blocks data: scheme', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'data:text/html,<h1>XSS</h1>',
        );
        expect(result, false);
        expect(mockPlatform.launchedUrls, isEmpty);
      });

      test('allows http scheme', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'http://example.com',
        );
        expect(result, true);
        expect(mockPlatform.launchedUrls, contains('http://example.com'));
      });

      test('allows https scheme', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'https://example.com',
        );
        expect(result, true);
        expect(mockPlatform.launchedUrls, contains('https://example.com'));
      });

      test('scheme check is case insensitive', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'HTTPS://example.com',
        );
        expect(result, true);
        // URL gets normalized to lowercase by url_launcher
        expect(mockPlatform.launchedUrls, contains('https://example.com'));
      });
    });

    group('Invalid URL Handling', () {
      test('returns false for malformed URLs', () async {
        final result = await UrlLauncher.launchExternalUrl('not a url');
        expect(result, false);
      });

      test('returns false for empty string', () async {
        final result = await UrlLauncher.launchExternalUrl('');
        expect(result, false);
      });

      test('handles URLs with special characters', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'https://example.com/path?query=value&other=123',
        );
        expect(result, true);
      });
    });

    group('Error Snackbar Display', () {
      testWidgets('shows snackbar when context provided and URL blocked', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      await UrlLauncher.launchExternalUrl(
                        'javascript:alert("xss")',
                        context: context,
                      );
                    },
                    child: const Text('Test'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap button to trigger URL launch
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        // Wait for snackbar animation
        await tester.pumpAndSettle();

        // Verify snackbar is displayed
        expect(find.text('Invalid link format'), findsOneWidget);
      });

      testWidgets('shows snackbar when context provided and URL fails', (
        tester,
      ) async {
        // Configure platform to fail
        mockPlatform.canLaunchResponse = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      await UrlLauncher.launchExternalUrl(
                        'https://example.com',
                        context: context,
                      );
                    },
                    child: const Text('Test'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap button to trigger URL launch
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        // Wait for snackbar animation
        await tester.pumpAndSettle();

        // Verify snackbar is displayed
        expect(find.text('Could not open link'), findsOneWidget);
      });

      test('does not crash when context is null', () async {
        // Should not throw exception
        expect(
          () async => UrlLauncher.launchExternalUrl('javascript:alert("xss")'),
          returnsNormally,
        );
      });
    });

    group('Successful Launches', () {
      test('successfully launches valid https URL', () async {
        final result = await UrlLauncher.launchExternalUrl(
          'https://www.example.com/path',
        );
        expect(result, true);
        expect(
          mockPlatform.launchedUrls,
          contains('https://www.example.com/path'),
        );
      });

      test('uses external application mode', () async {
        await UrlLauncher.launchExternalUrl('https://example.com');
        expect(
          mockPlatform.lastLaunchMode,
          PreferredLaunchMode.externalApplication,
        );
      });
    });
  });
}
