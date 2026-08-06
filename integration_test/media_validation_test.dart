// Live end-to-end validation of native media embeds against the real local
// backend (AppView on :8081, image proxy on :8080, PDS on :3001).
//
// Prerequisites (see docs in the Coves backend repo):
//   - `make dev-up` + `make run` in ~/Code/coves
//   - the media validation posts seeded in the news community (five posts:
//     single image, 3-image gallery, title-less image, hostile pre-stamped
//     #view embed, and a video whose blob is a jpeg so playback fails into
//     the error state by design)
//
// Run on a booted simulator:
//   flutter test integration_test/media_validation_test.dart -d <device-id>
import 'package:coves_flutter/main.dart' as app;
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps until [finder] matches, failing after [timeout].
///
/// pumpAndSettle never settles on this app (feed shimmer/animations), so all
/// waiting is bounded polling instead.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for $finder${reason == null ? '' : ' — $reason'}');
}

Future<void> settleABit(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native media embeds render end-to-end against live backend', (
    tester,
  ) async {
    // Pre-accept the EULA and community guidelines gates so the app boots
    // straight to the landing screen.
    SharedPreferences.setMockInitialValues({
      'eula_accepted_version': 1,
      'community_guidelines_accepted_version': 1,
    });

    // bootstrapCovesApp is main() minus SentryFlutter.init, whose
    // FlutterError.onError override the test binding rejects.
    await tester.pumpWidget(await app.bootstrapCovesApp());
    await settleABit(tester);

    // ── Landing → guest feed.
    if (find.text('Explore communities').evaluate().isNotEmpty) {
      await tester.tap(find.text('Explore communities'));
    }
    await waitFor(
      tester,
      find.byKey(const Key('post-images-embed')),
      timeout: const Duration(seconds: 45),
      reason: 'guest feed should load and show the seeded image posts',
    );

    // ── Feed: single-image post renders with its media block.
    expect(
      find.byKey(const Key('post-images-embed')),
      findsWidgets,
      reason: 'seeded image posts must render media blocks in the feed',
    );

    // Gallery post shows its 1/N count badge.
    await waitFor(tester, find.byKey(const Key('post-images-count-badge')));
    expect(find.text('1/3'), findsWidgets);

    // ── Hostile post: title renders, and its card carries NO media block.
    final hostileTitle = find.textContaining('Hostile embed');
    if (hostileTitle.evaluate().isEmpty) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -600),
        1500,
      );
      await settleABit(tester);
    }
    expect(
      hostileTitle,
      findsWidgets,
      reason:
          'the hostile-embed post must still render as a text post — '
          'if the whole feed is missing, the never-throws contract broke',
    );

    // ── Video post: media block, duration badge, play overlay.
    var videoBlock = find.byKey(const Key('post-video-embed'));
    for (var i = 0; i < 6 && videoBlock.evaluate().isEmpty; i++) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -500),
        1500,
      );
      await settleABit(tester);
      videoBlock = find.byKey(const Key('post-video-embed'));
    }
    expect(videoBlock, findsOneWidget);
    expect(find.byKey(const Key('post-video-play-overlay')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('post-video-duration-badge')),
        matching: find.text('12:34'),
      ),
      findsOneWidget,
    );

    // ── Video tap → fullscreen player → jpeg-as-video fails into the H5
    // error state (visible message + close), never an infinite spinner.
    await tester.ensureVisible(videoBlock);
    await settleABit(tester);
    await tester.tap(videoBlock, warnIfMissed: false);
    await settleABit(tester);
    expect(
      find.byKey(const Key('fullscreen-video-error')).evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
      isTrue,
      reason:
          'tapping the video must push the fullscreen player '
          '(error state or still-initializing spinner)',
    );
    // AVFoundation can take a while to reject image bytes; the contract is
    // that it must END in the error state, never an eternal spinner.
    await waitFor(
      tester,
      find.byKey(const Key('fullscreen-video-error')),
      timeout: const Duration(seconds: 60),
      reason: 'a bad video must land in the error state, not a spinner',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Dismiss the player. The close affordance's 'Close' semantics are
    // asserted by the H5 unit tests; here we just pop the route.
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await settleABit(tester);
    expect(find.byKey(const Key('fullscreen-video-error')), findsNothing);

    // ── Feed: tapping the gallery post's media block opens the fullscreen
    // viewer directly (NOT the detail screen), with the whole gallery
    // swipeable from the feed.
    var galleryBadge = find.byKey(const Key('post-images-count-badge'));
    for (var i = 0; i < 6 && galleryBadge.evaluate().isEmpty; i++) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 500),
        1500,
      );
      await settleABit(tester);
      galleryBadge = find.byKey(const Key('post-images-count-badge'));
    }
    final galleryBlock =
        find
            .ancestor(
              of: galleryBadge,
              matching: find.byKey(const Key('post-images-embed')),
            )
            .first;
    await tester.ensureVisible(galleryBlock);
    await settleABit(tester);
    await tester.tap(galleryBlock, warnIfMissed: false);
    await waitFor(tester, find.byKey(const Key('image-viewer')));
    expect(
      find.descendant(
        of: find.byKey(const Key('image-viewer-page-indicator')),
        matching: find.text('1/3'),
      ),
      findsOneWidget,
      reason: 'the feed tap opens the full gallery, starting at image 1',
    );
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await settleABit(tester);
    expect(find.byKey(const Key('image-viewer')), findsNothing);

    // ── Feed → detail: the media block no longer navigates, so go through
    // the card's comment button, which routes to detail for all post types.
    final galleryCard =
        find.ancestor(of: galleryBadge, matching: find.byType(PostCard)).first;
    final commentButton =
        find
            .descendant(
              of: galleryCard,
              matching: find.byIcon(Icons.chat_bubble_outline),
            )
            .first;
    await tester.ensureVisible(commentButton);
    await settleABit(tester);
    await tester.tap(commentButton, warnIfMissed: false);
    await settleABit(tester);

    // ── Detail: native gallery with page indicator; swipe advances it.
    await waitFor(tester, find.byKey(const Key('detail-images-embed')));
    final indicator = find.byKey(const Key('detail-images-page-indicator'));
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('1/3')),
      findsOneWidget,
    );
    await tester.fling(
      find.descendant(
        of: find.byKey(const Key('detail-images-embed')),
        matching: find.byType(PageView),
      ),
      const Offset(-350, 0),
      1200,
    );
    await settleABit(tester);
    expect(
      find.descendant(of: indicator, matching: find.text('2/3')),
      findsOneWidget,
      reason: 'swiping the gallery must advance the page indicator',
    );

    // ── Tap the gallery → fullscreen zoomable viewer, opened on the page
    // the carousel was showing (2/3 after the swipe above), then dismiss.
    await tester.tap(
      find.byKey(const Key('detail-images-embed')),
      warnIfMissed: false,
    );
    await waitFor(tester, find.byKey(const Key('image-viewer')));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('image-viewer-page-indicator')),
        matching: find.text('2/3'),
      ),
      findsOneWidget,
      reason: 'the viewer opens on the image the carousel was showing',
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    expect(nav.canPop(), isTrue);
    nav.pop();
    await settleABit(tester);
    expect(find.byKey(const Key('image-viewer')), findsNothing);
    expect(find.byKey(const Key('detail-images-embed')), findsOneWidget);
  });
}
