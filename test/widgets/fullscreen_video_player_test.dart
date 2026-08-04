import 'package:coves_flutter/widgets/fullscreen_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Root of the failure UI shown when the player cannot initialise.
const _errorKey = Key('fullscreen-video-error');

const _videoUrl = 'https://cdn.test/video.mp4';

void main() {
  // Under flutter_test the video_player platform interface is never
  // registered, so `VideoPlayerController.initialize()` throws
  // `UnimplementedError: init() has not been implemented`. That is an
  // Error, not an Exception — which is precisely the H5 bug: the widget's
  // `on Exception catch` misses it, `_isInitializing` stays true, and the
  // user watches a spinner forever. These tests lean on that same failure
  // to drive the error state.
  //
  // Note the deliberate absence of pumpAndSettle: while the bug is live the
  // spinner animates forever and pumpAndSettle only reports a timeout,
  // which says nothing about what is actually wrong. Bounded pumps give the
  // real assertion failure both before and after the fix.
  Future<void> settleInit(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpPlayer(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FullscreenVideoPlayer(videoUrl: _videoUrl)),
    );
    await settleInit(tester);
  }

  group('H5 FullscreenVideoPlayer initialisation failure', () {
    testWidgets('does not let the failure escape as an uncaught error', (
      tester,
    ) async {
      await pumpPlayer(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the catch must cover Errors, not just Exceptions',
      );
    });

    testWidgets('stops spinning and shows an error state', (tester) async {
      await pumpPlayer(tester);

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'an infinite spinner is the failure mode H5 removes',
      );
      expect(find.byKey(_errorKey), findsOneWidget);
    });

    testWidgets('the error state explains itself with an icon and text', (
      tester,
    ) async {
      await pumpPlayer(tester);

      final errorBlock = find.byKey(_errorKey);
      expect(
        find.descendant(of: errorBlock, matching: find.byType(Icon)),
        findsWidgets,
      );

      final messages = tester
          .widgetList<Text>(
            find.descendant(of: errorBlock, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .where((data) => data.trim().isNotEmpty);
      expect(
        messages,
        isNotEmpty,
        reason: 'an icon with no words leaves the user guessing',
      );
    });

    testWidgets('shows no scrubber when initialisation failed', (tester) async {
      await pumpPlayer(tester);

      expect(find.byKey(_errorKey), findsOneWidget);
      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'scrubbing a video that never loaded is meaningless',
      );
    });

    testWidgets('offers a labelled close affordance that pops the route', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => ElevatedButton(
                    onPressed:
                        () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const FullscreenVideoPlayer(
                                  videoUrl: _videoUrl,
                                ),
                            fullscreenDialog: true,
                          ),
                        ),
                    child: const Text('OPEN'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await settleInit(tester);

      expect(find.byKey(_errorKey), findsOneWidget);

      final closeButton = find.bySemanticsLabel('Close');
      expect(
        closeButton,
        findsWidgets,
        reason: 'the error state needs a labelled way out',
      );
      expect(
        tester.getSemantics(closeButton.first),
        containsSemantics(isButton: true, label: 'Close'),
      );

      await tester.tap(closeButton.first);
      await settleInit(tester);

      expect(find.byKey(_errorKey), findsNothing);
      expect(find.text('OPEN'), findsOneWidget);
      handle.dispose();
    });
  });
}
