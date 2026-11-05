// Device-tier check that a removed post's images show "Image removed".
//
// Requires the real local stack (coves dfc8d0be or later) and a local admin
// account. On Android, configure adb reverse through `make mobile-setup` in
// coves.
//
// Manual steps around the run:
// 1. In the dev app on the local stack, open a post with images and note its
//    image URLs (the `thumb` and `fullsize` URLs of each image).
// 2. Have a local admin remove that post.
// 3. Run, passing the noted URLs comma-separated:
//    flutter test integration_test/image_removed_test.dart -d <device> \
//      --flavor dev --dart-define=ENVIRONMENT=local \
//      --dart-define=REMOVED_IMAGE_URLS=<comma-separated URLs>
//
// The test empties the image caches first, so every URL is fetched again and
// must come back 404. Two things are recorded separately by the device
// checker, not by this test: the refetched post shows the moderation
// tombstone, and an already-cached copy may keep showing in the app until
// its next fetch fails (PRD §5.4).
import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/media/native_image_embed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _removedImageUrls = String.fromEnvironment('REMOVED_IMAGE_URLS');

const _loadTimeout = Duration(seconds: 30);
const _pollInterval = Duration(milliseconds: 250);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a removed post\'s image URLs show "Image removed"', (
    tester,
  ) async {
    expect(
      EnvironmentConfig.current.isLocal,
      isTrue,
      reason: 'Run with --flavor dev --dart-define=ENVIRONMENT=local.',
    );

    final urls = [
      for (final url in _removedImageUrls.split(','))
        if (url.trim().isNotEmpty) url.trim(),
    ];
    expect(
      urls,
      isNotEmpty,
      reason:
          'Pass the removed post\'s image URLs with '
          '--dart-define=REMOVED_IMAGE_URLS=<comma-separated URLs>.',
    );

    final localHosts = {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      Uri.parse(EnvironmentConfig.current.apiUrl).host,
    };
    for (final url in urls) {
      expect(
        localHosts,
        contains(Uri.tryParse(url)?.host),
        reason: '$url is not served by the local stack.',
      );
    }

    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    for (final url in urls) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NativeImageThumb(
              // A fresh element per URL, so no state carries over.
              key: ValueKey(url),
              images: [EmbedImage(thumb: url, fullsize: url)],
              keyPrefix: 'removed',
              source: MediaImageSource.fullsize,
            ),
          ),
        ),
      );

      final removed = find.text('Image removed');
      final deadline = DateTime.now().add(_loadTimeout);
      while (removed.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(_pollInterval);
      }

      expect(
        removed,
        findsOneWidget,
        reason: '$url did not show "Image removed" within $_loadTimeout.',
      );
    }
  });
}
