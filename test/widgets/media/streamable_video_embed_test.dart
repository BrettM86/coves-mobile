// Spec for the shared Streamable embed extracted from post_card.dart's
// `_EmbedCard` and detailed_post_view.dart's `_VideoEmbed`.
//
// Target API — lib/widgets/media/streamable_video_embed.dart:
//
//   enum PlayChipStyle { feed, detail }
//
//   class StreamableVideoEmbed extends StatefulWidget {
//     const StreamableVideoEmbed({
//       required this.embed,                 // ExternalEmbed
//       required this.streamableService,
//       this.height = 180,
//       this.frameDecoration,                // BoxDecoration? (feed border)
//       this.darken = false,                 // detail's scrim
//       this.playChipStyle = PlayChipStyle.feed,
//       super.key,
//     });
//
//     /// Case-INSENSITIVE: `embedType` in {video, video-stream} and
//     /// `provider` == streamable, whatever the casing the AppView sent.
//     static bool isStreamableVideo(ExternalEmbed embed);
//   }
//
// The widget folds the three bugs the two copies disagreed on:
//   1. case-insensitive embedType (was feed-only, case-sensitive)
//   2. `Semantics(enabled: !loading)` (was feed-only)
//   3. one snackbar string, 'Could not load video'
//
// COMPILE-RED until lib/widgets/media/streamable_video_embed.dart exists.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/media/streamable_video_embed.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_helpers/mock_url_launcher_platform.dart';

const _streamableUri = 'https://streamable.com/abc123';
const _streamableApi = 'https://api.streamable.com/videos/abc123';
const _thumb = 'https://cdn.test/video-thumb.jpg';
const _failureCopy = 'Could not load video';

ExternalEmbed embedWith({
  String? embedType = 'video',
  String? provider = 'streamable',
  String? thumb = _thumb,
  String uri = _streamableUri,
}) {
  return ExternalEmbed(
    uri: uri,
    thumb: thumb,
    embedType: embedType,
    provider: provider,
  );
}

/// A service whose single request resolves after a delay with no `files`
/// entry, so `getVideoUrl` yields null and the widget takes the error branch.
StreamableService failingStreamable() {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.streamable.com'));
  DioAdapter(dio: dio).onGet(
    _streamableApi,
    (server) => server.reply(
      200,
      <String, dynamic>{},
      delay: const Duration(milliseconds: 500),
    ),
  );
  return StreamableService(dio: dio);
}

/// A service whose request answers with a `files` field of the wrong shape,
/// so the production cast inside `getVideoUrl` throws a [TypeError] — the
/// non-Dio failure mode that used to escape the widget entirely.
StreamableService malformedStreamable() {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.streamable.com'));
  DioAdapter(dio: dio).onGet(
    _streamableApi,
    (server) => server.reply(200, <String, dynamic>{'files': 'not-a-map'}),
  );
  return StreamableService(dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUrlLauncherPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockPlatform;
  });

  Widget harness(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('isStreamableVideo', () {
    test('accepts the canonical lowercase form', () {
      expect(StreamableVideoEmbed.isStreamableVideo(embedWith()), isTrue);
      expect(
        StreamableVideoEmbed.isStreamableVideo(
          embedWith(embedType: 'video-stream'),
        ),
        isTrue,
      );
    });

    test('ignores embedType casing', () {
      for (final type in <String>[
        'Video',
        'VIDEO',
        'Video-Stream',
        'VIDEO-STREAM',
      ]) {
        expect(
          StreamableVideoEmbed.isStreamableVideo(embedWith(embedType: type)),
          isTrue,
          reason: '$type is the same embed type as its lowercase form',
        );
      }
    });

    test('ignores provider casing', () {
      for (final provider in <String>[
        'streamable',
        'Streamable',
        'STREAMABLE',
      ]) {
        expect(
          StreamableVideoEmbed.isStreamableVideo(embedWith(provider: provider)),
          isTrue,
        );
      }
    });

    test('rejects a non-video embed type', () {
      expect(
        StreamableVideoEmbed.isStreamableVideo(embedWith(embedType: 'article')),
        isFalse,
      );
      expect(
        StreamableVideoEmbed.isStreamableVideo(embedWith(embedType: null)),
        isFalse,
      );
      expect(
        StreamableVideoEmbed.isStreamableVideo(embedWith(embedType: 'videos')),
        isFalse,
        reason: 'the match is exact after lowercasing, not a prefix test',
      );
    });

    test('rejects a video from another provider', () {
      expect(
        StreamableVideoEmbed.isStreamableVideo(embedWith(provider: 'youtube')),
        isFalse,
      );
      expect(
        StreamableVideoEmbed.isStreamableVideo(embedWith(provider: null)),
        isFalse,
        reason: 'only Streamable URLs can be resolved to an MP4 in-app',
      );
    });
  });

  group('rendering', () {
    testWidgets('renders nothing without a thumbnail', (tester) async {
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(thumb: null),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('the feed chip style uses the square play glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('the detail chip style uses the rounded play glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
            playChipStyle: PlayChipStyle.detail,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('applies the caller-supplied frame decoration', (tester) async {
      const decoration = BoxDecoration(color: Color(0xFF00FF00));

      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
            frameDecoration: decoration,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration == decoration,
        ),
        findsOneWidget,
        reason: 'the feed keeps its bordered frame via frameDecoration',
      );
    });

    testWidgets('advertises an enabled play button before any tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        containsSemantics(isButton: true, isEnabled: true),
      );
      handle.dispose();
    });
  });

  group('launch flow', () {
    testWidgets('shows a loading chip and a disabled button while resolving', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('shows the shared failure copy and restores the button', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text(_failureCopy), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byIcon(Icons.play_arrow),
        findsOneWidget,
        reason: 'a failed resolve is retryable',
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('reports an unexpected response shape instead of hanging', (
      tester,
    ) async {
      // A TypeError out of the resolve used to escape the try/finally: the
      // spinner stopped and the user was told nothing.
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: embedWith(),
            streamableService: malformedStreamable(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(_failureCopy), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byIcon(Icons.play_arrow),
        findsOneWidget,
        reason: 'the loading flag is reset so the chip is retryable',
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('non-Streamable video embeds', () {
    // The detail view renders this widget for ANY video-typed embed, so a
    // YouTube/Vimeo link reaches the tap handler with nothing to resolve
    // in-app. The chip is still a live control: it hands off to the browser.
    ExternalEmbed youtubeEmbed() => embedWith(
      provider: 'youtube',
      uri: 'https://www.youtube.com/watch?v=abc123',
    );

    testWidgets('advertises an enabled play button', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: youtubeEmbed(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        containsSemantics(isButton: true, isEnabled: true),
      );
      handle.dispose();
    });

    testWidgets('opens the link externally rather than doing nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          StreamableVideoEmbed(
            embed: youtubeEmbed(),
            streamableService: failingStreamable(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        mockPlatform.launchedUrls,
        contains('https://www.youtube.com/watch?v=abc123'),
      );
      expect(
        find.text(_failureCopy),
        findsNothing,
        reason: 'handing off to the browser is a success, not a failure',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'there is no in-app resolve to wait on',
      );
    });
  });
}
