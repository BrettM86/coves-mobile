import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/media/gif_codec.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/native_image_embed.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/fake_gif_codec.dart';
import '../../test_helpers/fake_image_cache_manager.dart';
import '../../test_helpers/image_fixtures.dart';
import '../../test_helpers/semantics_helpers.dart';

const _catThumb = 'https://cdn.test/cat-thumb.jpg';
const _catFull = 'https://cdn.test/cat-full.gif';
const _gif = EmbedImage(thumb: _catThumb, fullsize: _catFull, isGif: true);
const _jpeg = EmbedImage(
  thumb: 'https://cdn.test/dog-thumb.jpg',
  fullsize: 'https://cdn.test/dog-full.jpg',
);
const _embedKey = Key('detail-images-embed');

void main() {
  late FakeGifFrames frames;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    frames = await FakeGifFrames.create();
  });

  tearDownAll(() => frames.dispose());

  Widget harness({
    required List<EmbedImage> images,
    FakeGifCodecLoader? loader,
    FakeImageCacheManager? cacheManager,
    List<int>? opened,
    bool tickersEnabled = true,
    int? stackIndex,
  }) {
    Widget gallery = NativeImageGallery(
      images: images,
      // The gallery's default source is fullsize: a GIF must still show
      // its thumb before a tap.
      keyPrefix: 'detail',
      onOpen: (index) => opened?.add(index),
    );
    if (loader != null) {
      gallery = GifCodecScope(loader: loader.load, child: gallery);
    }
    Widget content = ImageCacheScope(
      cacheManager: cacheManager ?? FakeImageCacheManager(),
      child: gallery,
    );
    if (stackIndex != null) {
      // How MainShellScreen keeps its tabs: child 0 is the gallery's tab.
      content = IndexedStack(
        index: stackIndex,
        children: [content, const SizedBox(width: 400, height: 300)],
      );
    }
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            // How an Overlay hides a covered route.
            child: TickerMode(enabled: tickersEnabled, child: content),
          ),
        ),
      ),
    );
  }

  Finder playControl() => find.bySemanticsLabel('Play GIF');
  Finder pauseControl() => find.bySemanticsLabel('Pause GIF');
  Finder networkImage(String url) => find.byWidgetPredicate(
    (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
  );

  Future<void> tapPlay(WidgetTester tester) async {
    expect(playControl(), findsOneWidget, reason: 'a GIF shows Play GIF');
    await tester.tap(playControl());
    await tester.pump();
    await tester.pump();
  }

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(PageView), Offset(dx, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('B2 GIF play/pause in the gallery', () {
    testWidgets('before a tap shows the still thumb, never fullsize', (
      tester,
    ) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(harness(images: [_gif], loader: loader));
      await tester.pump();

      expect(networkImage(_catThumb), findsOneWidget);
      expect(networkImage(_catFull), findsNothing);
      expect(playControl(), findsOneWidget);
      expect(find.byKey(gifFrameKey), findsNothing);
      expect(loader.requests, isEmpty);
    });

    testWidgets('play advances per frame duration, pause freezes, play '
        'resumes from the frozen frame', (tester) async {
      final opened = <int>[];
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(
        harness(images: [_gif], loader: loader, opened: opened),
      );

      await tapPlay(tester);

      expect(loader.requests, [_catFull]);
      expect(shownGifFrameWidth(tester), 10);
      expect(pauseControl(), findsOneWidget);
      expect(playControl(), findsNothing);

      // Frame durations are 100ms, 300ms, 200ms, looping.
      await tester.pump(const Duration(milliseconds: 99));
      expect(shownGifFrameWidth(tester), 10);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(milliseconds: 299));
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shownGifFrameWidth(tester), 12);
      await tester.pump(const Duration(milliseconds: 199));
      expect(shownGifFrameWidth(tester), 12);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shownGifFrameWidth(tester), 10);
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);

      // Pause 100ms into the 300ms frame.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(pauseControl());
      await tester.pump();

      expect(playControl(), findsOneWidget);
      expect(pauseControl(), findsNothing);
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(seconds: 5));
      expect(shownGifFrameWidth(tester), 11);

      // Resume by screen reader; the frame finishes its remaining 200ms.
      activateBySemantics(tester, playControl());
      await tester.pump();

      expect(pauseControl(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 199));
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shownGifFrameWidth(tester), 12);

      expect(opened, isEmpty, reason: 'play and pause never open the viewer');
    });

    final failureRows = <(String, FakeGifCodecLoader Function())>[
      (
        'the loader fails',
        () => FakeGifCodecLoader(error: Exception('GIF download failed')),
      ),
      (
        'a later frame fails to decode',
        () => FakeGifCodecLoader(codec: FakeGifCodec(frames, failOnRequest: 1)),
      ),
    ];

    for (final (name, buildLoader) in failureRows) {
      testWidgets('$name: returns to the still thumb with Play GIF', (
        tester,
      ) async {
        final loader = buildLoader();
        await tester.pumpWidget(harness(images: [_gif], loader: loader));

        await tapPlay(tester);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(loader.requests, [_catFull]);
        expect(playControl(), findsOneWidget);
        expect(find.byKey(gifFrameKey), findsNothing);
        expect(networkImage(_catThumb), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('B3 tap elsewhere on a GIF', () {
    testWidgets('opens the viewer at that page without loading the GIF', (
      tester,
    ) async {
      final opened = <int>[];
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(
        harness(images: [_jpeg, _gif], loader: loader, opened: opened),
      );
      await swipe(tester, -300);
      expect(playControl(), findsOneWidget, reason: 'a GIF shows Play GIF');

      await tester.tapAt(
        tester.getTopLeft(find.byKey(_embedKey)) + const Offset(12, 12),
      );
      await tester.pump();

      expect(opened, [1]);
      expect(loader.requests, isEmpty);
      expect(find.byKey(gifFrameKey), findsNothing);
    });
  });

  group('B4 GIF playback lifecycle', () {
    testWidgets('swiping away from a playing GIF stops it', (tester) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(harness(images: [_gif, _jpeg], loader: loader));
      await tapPlay(tester);
      expect(shownGifFrameWidth(tester), 10);

      await swipe(tester, -300);
      await swipe(tester, 300);

      expect(playControl(), findsOneWidget);
      expect(find.byKey(gifFrameKey), findsNothing);
    });

    testWidgets('a load finishing after the page was swiped away does not '
        'start playback', (tester) async {
      final loader = FakeGifCodecLoader(controlled: true);
      await tester.pumpWidget(harness(images: [_gif, _jpeg], loader: loader));
      await tapPlay(tester);

      await swipe(tester, -300);
      loader.pending!.complete(FakeGifCodec(frames));
      await tester.pump();
      await swipe(tester, 300);

      expect(playControl(), findsOneWidget);
      expect(find.byKey(gifFrameKey), findsNothing);
    });

    testWidgets(
      'a frame finishing decode after pause leaves the frozen frame',
      (tester) async {
        final codec = FakeGifCodec(frames, controlled: true);
        final loader = FakeGifCodecLoader(codec: codec);
        await tester.pumpWidget(harness(images: [_gif], loader: loader));
        await tapPlay(tester);
        codec.completePending();
        await tester.pump();
        expect(shownGifFrameWidth(tester), 10);

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(
          codec.pendingFrames,
          isNotEmpty,
          reason: 'the next frame is mid-decode',
        );
        await tester.tap(pauseControl());
        await tester.pump();
        codec.completePending();
        await tester.pump(const Duration(seconds: 1));

        expect(shownGifFrameWidth(tester), 10);
        expect(playControl(), findsOneWidget);
      },
    );

    testWidgets('unmounting while the GIF loads throws nothing', (
      tester,
    ) async {
      final loader = FakeGifCodecLoader(controlled: true);
      await tester.pumpWidget(harness(images: [_gif], loader: loader));
      await tapPlay(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      loader.pending!.complete(FakeGifCodec(frames));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a reused gallery showing another post resets playback', (
      tester,
    ) async {
      const otherThumb = 'https://cdn.test/bird-thumb.jpg';
      const other = EmbedImage(
        thumb: otherThumb,
        fullsize: 'https://cdn.test/bird-full.gif',
        isGif: true,
      );
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(harness(images: [_gif], loader: loader));
      await tapPlay(tester);
      expect(shownGifFrameWidth(tester), 10);

      await tester.pumpWidget(harness(images: [other], loader: loader));
      await tester.pump();

      expect(networkImage(otherThumb), findsOneWidget);
      expect(playControl(), findsOneWidget);
      expect(find.byKey(gifFrameKey), findsNothing);
      expect(loader.requests, [_catFull]);
    });
  });

  group('B10 hidden GIF playback', () {
    final hidingRows =
        <
          (
            String,
            Future<void> Function(
              WidgetTester,
              FakeGifCodecLoader, {
              required bool hidden,
            }),
          )
        >[
          (
            'an ancestor TickerMode is disabled',
            (tester, loader, {required hidden}) => tester.pumpWidget(
              harness(images: [_gif], loader: loader, tickersEnabled: !hidden),
            ),
          ),
          (
            'the app goes to the background',
            (tester, loader, {required hidden}) async {
              tester.binding.handleAppLifecycleStateChanged(
                hidden ? AppLifecycleState.paused : AppLifecycleState.resumed,
              );
              await tester.pump();
            },
          ),
        ];

    for (final (name, setHidden) in hidingRows) {
      testWidgets('$name: the playing GIF freezes, and is paused with Play GIF '
          'when visible again', (tester) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
        await tester.pumpWidget(harness(images: [_gif], loader: loader));
        await tapPlay(tester);
        await tester.pump(const Duration(milliseconds: 100));
        expect(shownGifFrameWidth(tester), 11);

        // 100ms into the 300ms frame.
        await tester.pump(const Duration(milliseconds: 100));
        await setHidden(tester, loader, hidden: true);
        await tester.pump(const Duration(milliseconds: 200));
        expect(shownGifFrameWidth(tester), 11);
        await tester.pump(const Duration(seconds: 5));
        expect(shownGifFrameWidth(tester), 11);

        await setHidden(tester, loader, hidden: false);
        await tester.pump();

        expect(playControl(), findsOneWidget);
        expect(pauseControl(), findsNothing);
        expect(shownGifFrameWidth(tester), 11);
        await tester.pump(const Duration(seconds: 1));
        expect(shownGifFrameWidth(tester), 11);
      });
    }

    testWidgets('an inactive IndexedStack tab: the playing GIF freezes, and is '
        'paused with Play GIF when its tab is shown again', (tester) async {
      // The hidden tab is offstage to default finders.
      int? hiddenFrameWidth() => tester
          .widget<RawImage>(find.byKey(gifFrameKey, skipOffstage: false))
          .image
          ?.width;
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(
        harness(images: [_gif], loader: loader, stackIndex: 0),
      );
      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);

      // 100ms into the 300ms frame.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        harness(images: [_gif], loader: loader, stackIndex: 1),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(hiddenFrameWidth(), 11);
      await tester.pump(const Duration(seconds: 5));
      expect(hiddenFrameWidth(), 11);

      await tester.pumpWidget(
        harness(images: [_gif], loader: loader, stackIndex: 0),
      );
      await tester.pump();

      expect(playControl(), findsOneWidget);
      expect(pauseControl(), findsNothing);
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(seconds: 1));
      expect(shownGifFrameWidth(tester), 11);
    });
  });

  group('B11 GIF loop count', () {
    testWidgets('a play-once GIF stops on its last frame with Play GIF, and '
        'Play GIF replays from the first frame', (tester) async {
      final loader = FakeGifCodecLoader(
        codec: FakeGifCodec(frames, repetitionCount: 0),
      );
      await tester.pumpWidget(harness(images: [_gif], loader: loader));
      await tapPlay(tester);
      expect(shownGifFrameWidth(tester), 10);

      // Frame durations are 100ms, 300ms, 200ms: the last ends at 600ms.
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);
      await tester.pump(const Duration(milliseconds: 300));
      expect(shownGifFrameWidth(tester), 12);
      await tester.pump(const Duration(milliseconds: 200));
      expect(shownGifFrameWidth(tester), 12);
      expect(playControl(), findsOneWidget);
      expect(pauseControl(), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(shownGifFrameWidth(tester), 12);

      await tapPlay(tester);

      expect(shownGifFrameWidth(tester), 10);
      expect(pauseControl(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);
    });

    for (final repetitionCount in [0, -1]) {
      testWidgets('a single-frame GIF (repetitionCount $repetitionCount) shows '
          'its frame and returns to Play GIF, on every play', (tester) async {
        final loader = FakeGifCodecLoader(
          codec: FakeGifCodec(
            frames,
            frameCount: 1,
            repetitionCount: repetitionCount,
          ),
        );
        await tester.pumpWidget(harness(images: [_gif], loader: loader));

        await tapPlay(tester);
        expect(shownGifFrameWidth(tester), 10);
        // The single frame lasts 100ms.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(shownGifFrameWidth(tester), 10);
        expect(playControl(), findsOneWidget);
        expect(pauseControl(), findsNothing);

        await tapPlay(tester);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(shownGifFrameWidth(tester), 10);
        expect(playControl(), findsOneWidget);
        expect(pauseControl(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('B9 default GIF loader', () {
    testWidgets('reads fullsize through the cache manager and decodes it', (
      tester,
    ) async {
      final file = (await tester.runAsync(() async {
        const fs = LocalFileSystem();
        final dir = await fs.systemTempDirectory.createTemp('gif_playback');
        final file = dir.childFile('cat.gif');
        await file.writeAsBytes(animatedGif3x2);
        return file;
      }))!;
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final cacheManager = FakeImageCacheManager(files: {_catFull: file});
      await tester.pumpWidget(
        harness(images: [_gif], cacheManager: cacheManager),
      );

      await tapPlay(tester);
      for (var i = 0; i < 50 && shownGifFrameWidth(tester) == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(cacheManager.singleFileRequests, [_catFull]);
      expect(shownGifFrameWidth(tester), 3);
    });
  });

  group('B8 a local GIF on the optimistic post', () {
    testWidgets('shows a still first frame from the file with Play GIF, never '
        'an autoplaying Image.file, and plays on tap', (tester) async {
      final local = EmbedImage.local(io.File('/gifs/cat.gif'), isGif: true);
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: GifCodecScope(
                  loader: loader.load,
                  child: NativeImageThumb(
                    images: [local],
                    keyPrefix: 'post',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is FileImage,
        ),
        findsNothing,
      );
      expect(loader.requests, ['file:///gifs/cat.gif']);
      expect(shownGifFrameWidth(tester), 10);
      expect(playControl(), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(
        shownGifFrameWidth(tester),
        10,
        reason: 'the still never advances',
      );

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);
      expect(pauseControl(), findsOneWidget);
    });
  });
}
