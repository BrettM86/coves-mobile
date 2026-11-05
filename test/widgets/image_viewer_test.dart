import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/media_saver.dart';
import 'package:coves_flutter/utils/app_route_observer.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:coves_flutter/widgets/media/gif_codec.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_gif_codec.dart';
import '../test_helpers/fake_image_cache_manager.dart';

const _viewerKey = Key('image-viewer');

const _twoImageGallery = [
  EmbedImage(
    thumb: 'https://cdn.test/thumb-1.jpg',
    fullsize: 'https://cdn.test/fullsize-1.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/thumb-2.jpg',
    fullsize: 'https://cdn.test/fullsize-2.jpg',
  ),
];

/// Records every requested URL and completes each save immediately.
class _RecordingMediaSaver implements MediaSaver {
  final List<String> savedUrls = [];

  @override
  Future<void> saveImage(String url) async {
    savedUrls.add(url);
  }
}

const _threeImageGallery = [
  EmbedImage(
    thumb: 'https://cdn.test/thumb-1.jpg',
    fullsize: 'https://cdn.test/fullsize-1.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/thumb-2.jpg',
    fullsize: 'https://cdn.test/fullsize-2.jpg',
  ),
  EmbedImage(
    thumb: 'https://cdn.test/thumb-3.jpg',
    fullsize: 'https://cdn.test/fullsize-3.jpg',
  ),
];

/// Records every requested URL and leaves each save pending until the test
/// completes its [Completer].
class _PendingMediaSaver implements MediaSaver {
  final List<String> savedUrls = [];
  final List<Completer<void>> pendingSaves = [];

  @override
  Future<void> saveImage(String url) {
    savedUrls.add(url);
    final save = Completer<void>();
    pendingSaves.add(save);
    return save.future;
  }
}

/// Pumps the viewer directly as the app's home under a [MediaSaver]. With
/// [gifLoader], GIFs load through it and images through a cache manager
/// that never resolves.
Future<void> _pumpViewerWithSaver(
  WidgetTester tester, {
  required MediaSaver saver,
  required List<EmbedImage> images,
  int initialIndex = 0,
  FakeGifCodecLoader? gifLoader,
}) async {
  Widget app = MaterialApp(
    theme: AppTheme.dark,
    home: ImageViewer(images: images, initialIndex: initialIndex),
  );
  if (gifLoader != null) {
    app = GifCodecScope(
      loader: gifLoader.load,
      child: ImageCacheScope(cacheManager: FakeImageCacheManager(), child: app),
    );
  }
  await tester.pumpWidget(Provider<MediaSaver>.value(value: saver, child: app));
  await tester.pumpAndSettle();
}

Finder _saveButton() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byTooltip('Save image'),
);

Finder _downloadGlyph() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is LucideGlyph && identical(widget.paths, LucidePaths.download),
  ),
);

Finder _saveIconButton() =>
    find.ancestor(of: _saveButton(), matching: find.byType(IconButton));

Finder _progressIndicator() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byWidgetPredicate((widget) => widget is ProgressIndicator),
);

Widget _harness({
  List<EmbedImage> images = const [
    EmbedImage(
      thumb: 'https://cdn.test/thumb.jpg',
      fullsize: 'https://cdn.test/fullsize.jpg',
    ),
  ],
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    navigatorObservers: navigatorObservers,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => ImageViewer.open(context, images),
            child: const Text('Open image'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openViewer(
  WidgetTester tester, {
  List<EmbedImage> images = const [
    EmbedImage(
      thumb: 'https://cdn.test/thumb.jpg',
      fullsize: 'https://cdn.test/fullsize.jpg',
    ),
  ],
  List<NavigatorObserver> navigatorObservers = const [],
}) async {
  await tester.pumpWidget(
    _harness(images: images, navigatorObservers: navigatorObservers),
  );
  await tester.tap(find.text('Open image'));
  await tester.pumpAndSettle();
}

Finder _interactiveViewer() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byType(InteractiveViewer),
);

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

const _imageSlotKey = Key('image-viewer-image-slot');

Finder _closeButton() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byTooltip('Close'),
);

Finder _pageIndicator() => find.descendant(
  of: find.byKey(_viewerKey),
  matching: find.byKey(const Key('image-viewer-page-indicator')),
);

/// The viewer's page dots, showing page [index] (zero-based) of [count].
Finder _pageDots({required int index, required int count}) => find.descendant(
  of: _pageIndicator(),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is MediaPageDots &&
        widget.index == index &&
        widget.count == count,
  ),
);

/// The opacity [finder]'s widget is painted with: the product of every
/// opacity between its render object and the root.
double _paintedOpacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  RenderObject? node = tester.renderObject(finder);
  while (node != null) {
    if (node is RenderOpacity) {
      opacity *= node.opacity;
    }
    if (node is RenderAnimatedOpacityMixin) {
      opacity *= node.opacity.value;
    }
    node = node.parent;
  }
  return opacity;
}

/// Expects every control in [controls] to be fully visible and hit-testable
/// when [shown], or invisible and not hit-testable otherwise.
void _expectControls(
  WidgetTester tester,
  List<Finder> controls, {
  required bool shown,
  required String reason,
}) {
  for (final control in controls) {
    expect(
      control.hitTestable(),
      shown ? findsOneWidget : findsNothing,
      reason: '$reason (hit-testable: $control)',
    );
    if (shown || control.evaluate().isNotEmpty) {
      expect(
        _paintedOpacity(tester, control),
        shown ? 1.0 : 0.0,
        reason: '$reason (opacity: $control)',
      );
    }
  }
}

/// A single tap that resolves as a tap rather than the start of a double tap.
Future<void> _singleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

/// Pinches two pointers from [start] to [end] pixels either side of
/// [center], then lifts both. The first pointer alone steps 20 pixels past
/// the tap slop so the scale gesture wins the arena; the span at that moment
/// is the scale baseline.
Future<void> _pinchAt(
  WidgetTester tester,
  Offset center, {
  required double start,
  required double end,
}) async {
  final first = await tester.startGesture(
    center.translate(-start, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center.translate(start, 0),
    pointer: 2,
  );
  final slopStep = end > start ? 20.0 : -20.0;
  await first.moveBy(Offset(-slopStep, 0));
  await tester.pump();
  await first.moveBy(Offset(-(end - start - slopStep), 0));
  await second.moveBy(Offset(end - start, 0));
  await tester.pump();
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

/// Records the viewer's system-UI mode calls as 'method arguments' strings,
/// answering every platform call so nothing reaches a missing plugin.
List<String> _recordSystemUiModeCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays' ||
          call.method == 'SystemChrome.setEnabledSystemUIMode') {
        calls.add('${call.method} ${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

const _statusBarHidden =
    'SystemChrome.setEnabledSystemUIOverlays [SystemUiOverlay.bottom]';
const _edgeToEdge =
    'SystemChrome.setEnabledSystemUIMode SystemUiMode.edgeToEdge';

Future<void> _popViewer(WidgetTester tester, Offset center) async {
  Navigator.of(tester.element(_interactiveViewer())).pop();
  await tester.pumpAndSettle();
}

/// Whether primary focus sits inside the IconButton holding [control].
bool _focusIsInside(Finder control) {
  final focused = FocusManager.instance.primaryFocus?.context;
  final buttons = find
      .ancestor(of: control, matching: find.byType(IconButton))
      .evaluate();
  if (focused == null || buttons.isEmpty) {
    return false;
  }
  final button = buttons.single;
  var inside = focused == button;
  focused.visitAncestorElements((ancestor) {
    inside = inside || ancestor == button;
    return !inside;
  });
  return inside;
}

/// Presses Tab [presses] times and returns the names of [controls] that held
/// primary focus after any press.
Future<Set<String>> _tabCycle(
  WidgetTester tester,
  Map<String, Finder> controls, {
  int presses = 6,
}) async {
  final reached = <String>{};
  for (var press = 0; press < presses; press++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (final MapEntry(:key, :value) in controls.entries) {
      if (_focusIsInside(value)) {
        reached.add(key);
      }
    }
  }
  return reached;
}

void main() {
  testWidgets(
    'image fits inside the safe area at rest and can zoom under the bars',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 30);
      tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 30);
      addTearDown(tester.view.reset);

      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb.jpg',
            fullsize: 'https://cdn.test/fullsize.jpg',
          ),
        ],
      );

      expect(
        tester.getRect(find.byKey(_viewerKey)),
        const Rect.fromLTRB(0, 0, 400, 800),
        reason: 'the backdrop must cover the full screen',
      );
      expect(
        tester.getRect(_interactiveViewer()),
        const Rect.fromLTRB(0, 0, 400, 800),
        reason: 'the zoom surface must cover the full screen',
      );
      final slot = find.descendant(
        of: find.byKey(_viewerKey),
        matching: find.byKey(_imageSlotKey),
      );
      expect(
        tester.getRect(slot),
        const Rect.fromLTRB(0, 40, 400, 770),
        reason: 'at rest the image fits between the status and nav bars',
      );

      await _doubleTapAt(tester, const Offset(200, 60));
      expect(
        tester.getRect(slot).top,
        lessThan(40),
        reason: 'a zoomed image must be able to move under the status bar',
      );
    },
  );

  testWidgets('B3 a gallery shows page dots, not a counter, that follow a '
      'swipe', (tester) async {
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: const [
        EmbedImage(
          thumb: 'https://cdn.test/thumb-1.jpg',
          fullsize: 'https://cdn.test/fullsize-1.jpg',
        ),
        EmbedImage(
          thumb: 'https://cdn.test/thumb-2.jpg',
          fullsize: 'https://cdn.test/fullsize-2.jpg',
        ),
        EmbedImage(
          thumb: 'https://cdn.test/thumb-3.jpg',
          fullsize: 'https://cdn.test/fullsize-3.jpg',
        ),
      ],
    );

    expect(_pageDots(index: 0, count: 3), findsOneWidget);
    expect(
      find.descendant(of: _pageIndicator(), matching: find.text('1/3')),
      findsNothing,
    );

    await tester.fling(
      find.descendant(
        of: find.byKey(_viewerKey),
        matching: find.byType(PageView),
      ),
      const Offset(-500, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(_pageDots(index: 1, count: 3), findsOneWidget);
  });

  group('single tap toggles the controls', () {
    final rows = <(String, List<EmbedImage>, List<Finder> Function())>[
      (
        'single image',
        _twoImageGallery.sublist(0, 1),
        () => [_closeButton(), _saveButton()],
      ),
      (
        'gallery',
        _twoImageGallery,
        () => [_closeButton(), _saveButton(), _pageIndicator()],
      ),
    ];
    for (final (description, images, controls) in rows) {
      testWidgets('$description: tap hides, tap shows, double tap waits', (
        tester,
      ) async {
        await _pumpViewerWithSaver(
          tester,
          saver: _RecordingMediaSaver(),
          images: images,
        );
        final center = tester.getCenter(_interactiveViewer());
        _expectControls(
          tester,
          controls(),
          shown: true,
          reason: 'controls start shown',
        );

        await _singleTapAt(tester, center);
        _expectControls(
          tester,
          controls(),
          shown: false,
          reason: 'a single tap hides the controls',
        );

        await _singleTapAt(tester, center);
        _expectControls(
          tester,
          controls(),
          shown: true,
          reason: 'a second single tap brings the controls back',
        );

        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();
        _expectControls(
          tester,
          controls(),
          shown: true,
          reason: 'the first tap of a double tap must not toggle the controls',
        );
        await tester.tapAt(center);
        await tester.pumpAndSettle();
      });
    }
  });

  testWidgets(
    "hiding controls slide 30px to their edge on Bluesky's lightbox spring",
    (tester) async {
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: _twoImageGallery,
      );
      final center = tester.getCenter(_interactiveViewer());
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final closeAtRest = top(_closeButton());
      final saveAtRest = top(_saveButton());
      final indicatorAtRest = top(_pageIndicator());

      await tester.tapAt(center);
      await tester.pump(kDoubleTapTimeout);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(top(_closeButton()), lessThan(closeAtRest));
      expect(top(_closeButton()), greaterThan(closeAtRest - 30));
      expect(top(_saveButton()), lessThan(saveAtRest));
      expect(top(_pageIndicator()), greaterThan(indicatorAtRest));
      expect(top(_pageIndicator()), lessThan(indicatorAtRest + 30));
      expect(
        _closeButton().hitTestable(),
        findsNothing,
        reason: 'fading controls stop taking taps at once',
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _paintedOpacity(tester, _closeButton()),
        greaterThan(0.1),
        reason: 'the spring is still easing out 300ms in',
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        _paintedOpacity(tester, _closeButton()),
        lessThan(0.02),
        reason: 'the spring is all but settled 800ms in',
      );

      await tester.pumpAndSettle();
      expect(top(_closeButton()), closeAtRest - 30);
      expect(top(_saveButton()), saveAtRest - 30);
      expect(top(_pageIndicator()), indicatorAtRest + 30);
      _expectControls(
        tester,
        [_closeButton(), _saveButton(), _pageIndicator()],
        shown: false,
        reason: 'the spring settles fully hidden',
      );

      await tester.tapAt(center);
      await tester.pump(kDoubleTapTimeout);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(top(_closeButton()), greaterThan(closeAtRest - 30));
      expect(top(_closeButton()), lessThan(closeAtRest));

      await tester.pumpAndSettle();
      expect(top(_closeButton()), closeAtRest);
      expect(top(_saveButton()), saveAtRest);
      expect(top(_pageIndicator()), indicatorAtRest);
      _expectControls(
        tester,
        [_closeButton(), _saveButton(), _pageIndicator()],
        shown: true,
        reason: 'the spring settles fully shown',
      );
    },
  );

  group('zooming hides the controls until a single tap', () {
    final rows =
        <
          (
            String,
            Future<void> Function(WidgetTester, Offset),
            Future<void> Function(WidgetTester, Offset),
          )
        >[
          ('double tap', _doubleTapAt, _doubleTapAt),
          (
            'pinch',
            (tester, center) => _pinchAt(tester, center, start: 40, end: 100),
            (tester, center) => _pinchAt(tester, center, start: 100, end: 45),
          ),
        ];
    for (final (description, zoomIn, zoomOut) in rows) {
      testWidgets(description, (tester) async {
        await _openViewer(tester);
        final controller = tester
            .widget<InteractiveViewer>(_interactiveViewer())
            .transformationController!;
        final center = tester.getCenter(_interactiveViewer());
        final controls = [_closeButton(), _saveButton()];

        await zoomIn(tester, center);
        expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.9));
        _expectControls(
          tester,
          controls,
          shown: false,
          reason: 'zooming in hides the controls',
        );

        await zoomOut(tester, center);
        expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
        _expectControls(
          tester,
          controls,
          shown: false,
          reason: 'returning to scale 1 leaves the controls hidden',
        );

        await _singleTapAt(tester, center);
        _expectControls(
          tester,
          controls,
          shown: true,
          reason: 'a single tap after zooming out shows the controls',
        );
      });
    }
  });

  group('zooming makes the navigation bar transparent', () {
    const seededStyle = SystemUiOverlayStyle(
      statusBarColor: Color(0x33000000),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF123456),
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
    final rows = <(String, Future<void> Function(WidgetTester, Offset))>[
      ('double tap back to scale 1', _doubleTapAt),
      (
        'popping the viewer while zoomed',
        (tester, center) async {
          Navigator.of(tester.element(_interactiveViewer())).pop();
          await tester.pumpAndSettle();
        },
      ),
    ];
    for (final (description, endZoom) in rows) {
      testWidgets('$description restores the app navigation bar', (
        tester,
      ) async {
        final previousStyle = SystemChrome.latestStyle;
        addTearDown(() {
          if (previousStyle != null) {
            SystemChrome.setSystemUIOverlayStyle(previousStyle);
          }
        });
        // Seeded after the viewer opens: MaterialApp applies its own
        // theme-derived style when it first builds.
        await _openViewer(tester);
        SystemChrome.setSystemUIOverlayStyle(seededStyle);
        await tester.pump();
        expect(SystemChrome.latestStyle, seededStyle);

        final center = tester.getCenter(_interactiveViewer());
        await _doubleTapAt(tester, center);
        await tester.pump();

        final zoomed = SystemChrome.latestStyle!;
        expect(zoomed.systemNavigationBarColor, const Color(0x00000000));
        expect(zoomed.systemNavigationBarContrastEnforced, false);
        // Null status fields tell the platform to leave the status bar as is.
        expect(zoomed.statusBarColor, isNull);
        expect(zoomed.statusBarIconBrightness, isNull);
        expect(zoomed.statusBarBrightness, isNull);

        await endZoom(tester, center);
        await tester.pump();

        final restored = SystemChrome.latestStyle!;
        expect(restored.systemNavigationBarColor, const Color(0xFF0B0F14));
        expect(restored.systemNavigationBarIconBrightness, Brightness.light);
        expect(restored.systemNavigationBarContrastEnforced, true);
        expect(restored.statusBarColor, isNull);
      });
    }
  });

  group('the status bar follows the controls', () {
    Future<void> tapWhileZoomed(WidgetTester tester, Offset center) async {
      await _singleTapAt(tester, center);
      final scale = tester
          .widget<InteractiveViewer>(_interactiveViewer())
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      expect(scale, greaterThan(1.01), reason: 'the tap must not unzoom');
      _expectControls(
        tester,
        [_closeButton(), _saveButton()],
        shown: true,
        reason: 'a single tap while zoomed shows the controls',
      );
    }

    final rows =
        <(String, List<(Future<void> Function(WidgetTester, Offset), String)>)>[
          (
            'tap hides it, tap shows it',
            [(_singleTapAt, _statusBarHidden), (_singleTapAt, _edgeToEdge)],
          ),
          (
            'zoom hides it, zooming out keeps it hidden, tap shows it',
            [
              (_doubleTapAt, _statusBarHidden),
              (_doubleTapAt, _statusBarHidden),
              (_singleTapAt, _edgeToEdge),
            ],
          ),
          (
            'tap while zoomed shows it',
            [(_doubleTapAt, _statusBarHidden), (tapWhileZoomed, _edgeToEdge)],
          ),
          (
            'popping with hidden controls at rest restores it',
            [(_singleTapAt, _statusBarHidden), (_popViewer, _edgeToEdge)],
          ),
          (
            'popping while zoomed restores it',
            [(_doubleTapAt, _statusBarHidden), (_popViewer, _edgeToEdge)],
          ),
        ];
    for (final (description, steps) in rows) {
      testWidgets(description, (tester) async {
        final calls = _recordSystemUiModeCalls(tester);
        await _openViewer(tester);
        final center = tester.getCenter(_interactiveViewer());

        for (final (index, (step, expectedLast)) in steps.indexed) {
          await step(tester, center);
          await tester.pump();
          expect(
            calls.lastOrNull,
            expectedLast,
            reason: 'last system UI call after step ${index + 1}',
          );
        }
      });
    }
  });

  testWidgets('hiding the status bar leaves the image where it was', (
    tester,
  ) async {
    void setTopInset(double top) {
      tester.view.padding = FakeViewPadding(top: top, bottom: 30);
      tester.view.viewPadding = FakeViewPadding(top: top, bottom: 30);
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    setTopInset(40);
    addTearDown(tester.view.reset);
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: _twoImageGallery.sublist(0, 1),
    );
    final slot = find.descendant(
      of: find.byKey(_viewerKey),
      matching: find.byKey(_imageSlotKey),
    );
    final center = tester.getCenter(_interactiveViewer());

    final steps = <(String, Future<void> Function(), Rect)>[
      (
        'tap hides the controls and the status bar goes away',
        () async {
          await _singleTapAt(tester, center);
          setTopInset(0);
          await tester.pump();
        },
        const Rect.fromLTRB(0, 40, 400, 770),
      ),
      (
        'tap shows the controls before the status bar returns',
        () => _singleTapAt(tester, center),
        const Rect.fromLTRB(0, 40, 400, 770),
      ),
      (
        'the status bar returns',
        () async {
          setTopInset(40);
          await tester.pump();
        },
        const Rect.fromLTRB(0, 40, 400, 770),
      ),
      (
        'the status bar inset changes while the controls are shown',
        () async {
          setTopInset(24);
          await tester.pump();
        },
        const Rect.fromLTRB(0, 24, 400, 770),
      ),
    ];
    for (final (description, step, expectedSlot) in steps) {
      await step();
      expect(tester.getRect(slot), expectedSlot, reason: description);
    }
  });

  testWidgets('controls keep their inset while the status bar hides', (
    tester,
  ) async {
    void setTopInset(double top) {
      tester.view.padding = FakeViewPadding(top: top, bottom: 30);
      tester.view.viewPadding = FakeViewPadding(top: top, bottom: 30);
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    setTopInset(40);
    addTearDown(tester.view.reset);
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: _twoImageGallery,
    );
    final center = tester.getCenter(_interactiveViewer());
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    final closeAtRest = top(_closeButton());
    final indicatorAtRest = top(_pageIndicator());

    await _singleTapAt(tester, center);
    setTopInset(0);
    await tester.pumpAndSettle();
    expect(top(_closeButton()), closeAtRest - 30, reason: 'hidden');
    expect(top(_pageIndicator()), indicatorAtRest + 30, reason: 'hidden');

    await _singleTapAt(tester, center);
    expect(top(_closeButton()), closeAtRest, reason: 'shown, bar not back');

    setTopInset(40);
    await tester.pumpAndSettle();
    expect(top(_closeButton()), closeAtRest, reason: 'the status bar returns');
  });

  testWidgets('with animations turned off the controls hide and show at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: _twoImageGallery,
    );
    final center = tester.getCenter(_interactiveViewer());
    final controls = [_closeButton(), _saveButton(), _pageIndicator()];

    await tester.tapAt(center);
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    _expectControls(tester, controls, shown: false, reason: 'tap hides');
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tapAt(center);
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    _expectControls(tester, controls, shown: true, reason: 'tap shows');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('a screen reader keeps the controls', () {
    void enableAccessibleNavigation(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
    }

    final rows = <(String, Future<void> Function(WidgetTester, Offset), bool)>[
      ('single tap', _singleTapAt, false),
      ('double tap', _doubleTapAt, true),
    ];
    for (final (description, gesture, zooms) in rows) {
      testWidgets('$description leaves the controls shown', (tester) async {
        final calls = _recordSystemUiModeCalls(tester);
        final semantics = tester.ensureSemantics();
        enableAccessibleNavigation(tester);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _openViewer(tester);
        final center = tester.getCenter(_interactiveViewer());

        await gesture(tester, center);
        if (zooms) {
          final scale = tester
              .widget<InteractiveViewer>(_interactiveViewer())
              .transformationController!
              .value
              .getMaxScaleOnAxis();
          expect(scale, greaterThan(1.01), reason: 'the double tap zooms');
        }
        _expectControls(
          tester,
          [_closeButton(), _saveButton()],
          shown: true,
          reason: 'screen reader users keep the controls after a $description',
        );
        for (final (label, control) in [
          ('Close', _closeButton()),
          ('Save image', _saveButton()),
        ]) {
          expect(
            tester.getSemantics(control),
            // An IconButton exposes its tooltip as the spoken label.
            isSemantics(tooltip: label, isButton: true, hasTapAction: true),
          );
        }
        expect(calls, isNot(contains(_statusBarHidden)));
        semantics.dispose();
      });
    }

    testWidgets('turning a screen reader on brings hidden controls back', (
      tester,
    ) async {
      final calls = _recordSystemUiModeCalls(tester);
      final semantics = tester.ensureSemantics();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openViewer(
        tester,
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb.jpg',
            fullsize: 'https://cdn.test/fullsize.jpg',
            alt: 'A heron standing on a rock',
          ),
        ],
      );

      await _singleTapAt(tester, tester.getCenter(_interactiveViewer()));
      expect(
        find.bySemanticsLabel('A heron standing on a rock'),
        findsOneWidget,
        reason: 'alt text stays in semantics while the controls are hidden',
      );

      enableAccessibleNavigation(tester);
      await tester.pumpAndSettle();
      _expectControls(
        tester,
        [_closeButton(), _saveButton()],
        shown: true,
        reason: 'a screen reader turning on shows the controls',
      );
      expect(calls.lastOrNull, _edgeToEdge);
      semantics.dispose();
    });
  });

  testWidgets('hidden controls cannot hold or take keyboard focus', (
    tester,
  ) async {
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: _twoImageGallery.sublist(0, 1),
    );
    final controls = {'Close': _closeButton(), 'Save image': _saveButton()};

    expect(await _tabCycle(tester, controls), {
      'Close',
      'Save image',
    }, reason: 'Tab reaches both shown controls');
    for (var press = 0; press < 6 && !_focusIsInside(_closeButton()); press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(_focusIsInside(_closeButton()), isTrue, reason: 'Close is focused');

    await _singleTapAt(tester, tester.getCenter(_interactiveViewer()));
    expect(
      controls.keys.where((name) => _focusIsInside(controls[name]!)),
      isEmpty,
      reason: 'hiding the controls moves focus out of them',
    );
    expect(
      await _tabCycle(tester, controls),
      isEmpty,
      reason: 'Tab never lands on hidden controls',
    );
  });

  group('closing the viewer restores the system bars as the pop starts', () {
    Future<void> tapCloseWhileZoomed(WidgetTester tester, Offset center) async {
      await _singleTapAt(tester, center);
      await tester.tap(_closeButton());
    }

    Future<void> navigatorPop(WidgetTester tester, Offset center) async {
      Navigator.of(tester.element(_interactiveViewer())).pop();
    }

    final rows =
        <
          (
            String,
            Future<void> Function(WidgetTester, Offset),
            Future<void> Function(WidgetTester, Offset),
            bool,
          )
        >[
          ('hidden controls, Navigator.pop', _singleTapAt, navigatorPop, false),
          ('zoomed, Navigator.pop', _doubleTapAt, navigatorPop, true),
          ('zoomed, Close button', _doubleTapAt, tapCloseWhileZoomed, true),
        ];
    for (final (description, setUpState, close, zoomed) in rows) {
      testWidgets(description, (tester) async {
        final previousStyle = SystemChrome.latestStyle;
        addTearDown(() {
          if (previousStyle != null) {
            SystemChrome.setSystemUIOverlayStyle(previousStyle);
          }
        });
        final calls = _recordSystemUiModeCalls(tester);
        await _openViewer(tester);
        final center = tester.getCenter(_interactiveViewer());
        await setUpState(tester, center);

        final callsBeforeClose = calls.length;
        await close(tester, center);
        await tester.pump();
        expect(
          calls.lastOrNull,
          _edgeToEdge,
          reason: 'the status bar returns on the first frame of the pop',
        );
        if (zoomed) {
          final style = SystemChrome.latestStyle!;
          expect(style.systemNavigationBarColor, const Color(0xFF0B0F14));
          expect(style.systemNavigationBarIconBrightness, Brightness.light);
          expect(style.systemNavigationBarContrastEnforced, true);
        }

        await tester.pumpAndSettle();
        expect(
          calls.sublist(callsBeforeClose),
          isNot(contains(_statusBarHidden)),
          reason: 'the closing viewer never hides the status bar again',
        );
        expect(find.byKey(_viewerKey), findsNothing, reason: 'it closed');
      });
    }
  });

  group('a route pushed over the viewer gets the app system bars', () {
    final rows = <(String, Future<void> Function(WidgetTester, Offset), bool)>[
      ('hidden controls', _singleTapAt, false),
      ('zoomed', _doubleTapAt, true),
    ];
    for (final (description, setUpState, zoomed) in rows) {
      testWidgets('$description: push releases, pop back re-applies', (
        tester,
      ) async {
        final previousStyle = SystemChrome.latestStyle;
        addTearDown(() {
          if (previousStyle != null) {
            SystemChrome.setSystemUIOverlayStyle(previousStyle);
          }
        });
        final calls = _recordSystemUiModeCalls(tester);
        await _openViewer(tester, navigatorObservers: [appRouteObserver]);
        await setUpState(tester, tester.getCenter(_interactiveViewer()));
        final navigator = Navigator.of(tester.element(_interactiveViewer()));

        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covering route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls.lastOrNull, _edgeToEdge, reason: 'after the push');
        if (zoomed) {
          final style = SystemChrome.latestStyle!;
          expect(style.systemNavigationBarColor, const Color(0xFF0B0F14));
          expect(style.systemNavigationBarIconBrightness, Brightness.light);
          expect(style.systemNavigationBarContrastEnforced, true);
        }

        navigator.pop();
        await tester.pumpAndSettle();
        expect(
          calls.lastOrNull,
          _statusBarHidden,
          reason: 'back on the viewer the controls are still hidden',
        );
        if (zoomed) {
          final style = SystemChrome.latestStyle!;
          expect(style.systemNavigationBarColor, const Color(0x00000000));
          expect(style.systemNavigationBarContrastEnforced, false);
        }
      });
    }
  });

  testWidgets('a screen size change drops the held image inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 30);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 30);
    addTearDown(tester.view.reset);
    await _pumpViewerWithSaver(
      tester,
      saver: _RecordingMediaSaver(),
      images: _twoImageGallery.sublist(0, 1),
    );

    await _singleTapAt(tester, tester.getCenter(_interactiveViewer()));
    tester.view.physicalSize = const Size(800, 400);
    tester.view.padding = const FakeViewPadding(left: 40, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(left: 40, bottom: 24);
    await tester.pump();

    expect(
      tester.getRect(
        find.descendant(
          of: find.byKey(_viewerKey),
          matching: find.byKey(_imageSlotKey),
        ),
      ),
      const Rect.fromLTRB(40, 0, 800, 376),
      reason: 'rotating applies the new real insets even with hidden controls',
    );
  });

  testWidgets('double-tap smoothly animates focal zoom and reset', (
    tester,
  ) async {
    await _openViewer(tester);
    final viewer = _interactiveViewer();
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final position = tester.getTopLeft(viewer) + const Offset(200, 180);
    Future<void> doubleTap() async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(position);
      await tester.pump();
    }

    await doubleTap();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    await tester.pump(const Duration(milliseconds: 100));
    final scale = controller.value.getMaxScaleOnAxis();
    expect(scale, greaterThan(1));
    expect(scale, lessThan(2.5));
    expect(controller.value.storage[12], closeTo(200 * (1 - scale), 0.001));
    expect(controller.value.storage[13], closeTo(180 * (1 - scale), 0.001));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));

    await doubleTap();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.getMaxScaleOnAxis(), inExclusiveRange(1, 2.5));
    await tester.pumpAndSettle();
    expect(controller.value.storage, orderedEquals(Matrix4.identity().storage));
  });

  testWidgets(
    'touch interrupts zoom animation and viewer can close mid-animation',
    (tester) async {
      await _openViewer(tester);
      final viewer = _interactiveViewer();
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final center = tester.getCenter(viewer);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final interrupted = controller.value.clone();
      expect(interrupted.getMaxScaleOnAxis(), inExclusiveRange(1, 2.5));
      final contact = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.value.storage, orderedEquals(interrupted.storage));
      await contact.cancel();
      await tester.pumpAndSettle();
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      Navigator.of(tester.element(viewer)).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_viewerKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pinch zoom takes over after a vertical dismissal drag has started',
    (tester) async {
      await _openViewer(tester);

      final viewerFinder = find.byKey(_viewerKey);
      final interactiveViewerFinder = _interactiveViewer();
      final center = tester.getCenter(interactiveViewerFinder);

      final firstPointer = await tester.startGesture(center, pointer: 1);
      await firstPointer.moveBy(const Offset(0, 30));
      await tester.pump();
      await firstPointer.moveBy(const Offset(0, 120));
      await tester.pump();

      final dismissalContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: viewerFinder,
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        dismissalContainer.transform!.storage[13],
        greaterThan(100),
        reason: 'the first pointer must have started a dismissing drag',
      );

      final secondPointer = await tester.startGesture(
        center.translate(20, 150),
        pointer: 2,
      );
      await firstPointer.moveBy(const Offset(-80, 0));
      await secondPointer.moveBy(const Offset(80, 0));
      await tester.pump();

      final interactiveViewer = tester.widget<InteractiveViewer>(
        interactiveViewerFinder,
      );
      final scaleAfterSpread = interactiveViewer.transformationController!.value
          .getMaxScaleOnAxis();

      await firstPointer.up();
      await secondPointer.up();
      await tester.pumpAndSettle();

      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'a completed pinch must leave the fullscreen viewer open',
      );
      expect(
        scaleAfterSpread,
        greaterThan(1.01),
        reason: 'the second pointer must turn the dismissal drag into a pinch',
      );
    },
  );

  testWidgets('pinch contact cannot dismiss after returning to minimum scale', (
    tester,
  ) async {
    await _openViewer(tester);

    final viewerFinder = find.byKey(_viewerKey);
    final interactiveViewerFinder = _interactiveViewer();
    final controller = tester
        .widget<InteractiveViewer>(interactiveViewerFinder)
        .transformationController!;
    final center = tester.getCenter(interactiveViewerFinder);

    final firstPointer = await tester.startGesture(
      center.translate(-40, 0),
      pointer: 1,
    );
    final secondPointer = await tester.startGesture(
      center.translate(40, 0),
      pointer: 2,
    );
    await firstPointer.moveBy(const Offset(-80, 0));
    await secondPointer.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(
      controller.value.getMaxScaleOnAxis(),
      greaterThan(1.01),
      reason: 'both pointers must establish a genuine pinch zoom',
    );

    await firstPointer.moveBy(const Offset(115, 0));
    await secondPointer.moveBy(const Offset(-115, 0));
    await tester.pump();

    expect(
      controller.value.getMaxScaleOnAxis(),
      closeTo(1.0, 0.001),
      reason: 'the pinch must return to minimum scale before either lift',
    );

    await secondPointer.up();
    await firstPointer.moveBy(const Offset(0, 140));
    await tester.pump();
    await firstPointer.up();
    await tester.pumpAndSettle();

    expect(
      viewerFinder,
      findsOneWidget,
      reason: 'a contact sequence containing a pinch must not dismiss',
    );
    final dismissalTransform = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: viewerFinder,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .transform!;
    expect(
      dismissalTransform.storage[12],
      0.0,
      reason: 'release must clear horizontal dismissal translation',
    );
    expect(
      dismissalTransform.storage[13],
      0.0,
      reason: 'release must clear vertical dismissal translation',
    );
  });

  testWidgets(
    'gallery pinch takes over after a vertical dismissal drag has started',
    (tester) async {
      await _openViewer(
        tester,
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-2.jpg',
            fullsize: 'https://cdn.test/fullsize-2.jpg',
          ),
        ],
      );

      final viewerFinder = find.byKey(_viewerKey);
      final currentInteractiveViewerFinder = _interactiveViewer().first;
      final controller = tester
          .widget<InteractiveViewer>(currentInteractiveViewerFinder)
          .transformationController!;
      final center = tester.getCenter(currentInteractiveViewerFinder);

      final firstPointer = await tester.startGesture(center, pointer: 1);
      await firstPointer.moveBy(const Offset(0, 30));
      await tester.pump();
      await firstPointer.moveBy(const Offset(0, 120));
      await tester.pump();

      final secondPointer = await tester.startGesture(
        center.translate(20, 150),
        pointer: 2,
      );
      await firstPointer.moveBy(const Offset(-80, 0));
      await secondPointer.moveBy(const Offset(80, 0));
      await tester.pump();

      expect(
        controller.value.getMaxScaleOnAxis(),
        greaterThan(1.01),
        reason:
            'the second pointer must turn the gallery dismissal into a pinch',
      );

      await firstPointer.up();
      await secondPointer.up();
      await tester.pumpAndSettle();

      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'the gallery pinch must leave the fullscreen route open',
      );
      expect(
        _pageDots(index: 0, count: 2),
        findsOneWidget,
        reason: 'the pinch must not page away from the first gallery image',
      );
    },
  );

  testWidgets(
    'unzoomed gallery diagonal drag follows the finger and dismisses',
    (tester) async {
      await _openViewer(
        tester,
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-2.jpg',
            fullsize: 'https://cdn.test/fullsize-2.jpg',
          ),
        ],
      );

      final viewerFinder = find.byKey(_viewerKey);
      final currentInteractiveViewerFinder = _interactiveViewer().first;
      final controller = tester
          .widget<InteractiveViewer>(currentInteractiveViewerFinder)
          .transformationController!;
      expect(
        controller.value.storage,
        orderedEquals(Matrix4.identity().storage),
        reason: 'the gallery image must start unzoomed',
      );

      final drag = await tester.startGesture(
        tester.getCenter(currentInteractiveViewerFinder),
      );
      await drag.moveBy(const Offset(20, 30));
      await tester.pump();
      await drag.moveBy(const Offset(50, 120));
      await tester.pump();

      final dismissalTransform = tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: viewerFinder,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .transform!;
      expect(
        dismissalTransform.storage[12],
        70.0,
        reason: 'a steep gallery drag follows the finger sideways too',
      );
      expect(
        dismissalTransform.storage[13],
        greaterThan(100),
        reason: 'the outer viewer must follow the vertical dismissal drag',
      );

      await drag.up();
      await tester.pumpAndSettle();

      expect(
        viewerFinder,
        findsNothing,
        reason: 'more than 100px of vertical movement must dismiss the gallery',
      );
    },
  );

  testWidgets(
    'gallery restores paging after zoomed image pan and double-tap reset',
    (tester) async {
      await _openViewer(
        tester,
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-2.jpg',
            fullsize: 'https://cdn.test/fullsize-2.jpg',
          ),
        ],
      );

      final viewerFinder = find.byKey(_viewerKey);
      final currentInteractiveViewerFinder = _interactiveViewer().first;
      final controller = tester
          .widget<InteractiveViewer>(currentInteractiveViewerFinder)
          .transformationController!;
      final center = tester.getCenter(currentInteractiveViewerFinder);

      await _doubleTapAt(tester, center);
      final zoomedMatrix = controller.value.clone();

      final pan = await tester.startGesture(center);
      await pan.moveBy(const Offset(20, 20));
      await tester.pump();
      await pan.moveBy(const Offset(80, 70));
      await tester.pump();
      await pan.up();
      await tester.pumpAndSettle();
      final pannedMatrix = controller.value.clone();

      expect(
        zoomedMatrix.getMaxScaleOnAxis(),
        closeTo(2.5, 0.001),
        reason: 'the current gallery image must enter the zoomed state',
      );
      expect(
        (pannedMatrix.storage[12] - zoomedMatrix.storage[12]).abs(),
        greaterThan(40),
        reason: 'a zoomed gallery image must pan substantially on X',
      );
      expect(
        (pannedMatrix.storage[13] - zoomedMatrix.storage[13]).abs(),
        greaterThan(40),
        reason: 'the same pan must move the zoomed gallery image on Y',
      );
      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'panning a zoomed image must leave the fullscreen route open',
      );
      expect(
        _pageDots(index: 0, count: 2),
        findsOneWidget,
        reason: 'panning the zoomed image must not change gallery pages',
      );

      await _doubleTapAt(tester, center);

      expect(
        controller.value.storage,
        orderedEquals(Matrix4.identity().storage),
        reason: 'the second double-tap must fully restore the paging state',
      );

      await tester.fling(
        find.descendant(of: viewerFinder, matching: find.byType(PageView)),
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'a normal gallery page swipe must keep the route open',
      );
      expect(
        _pageDots(index: 1, count: 2),
        findsOneWidget,
        reason: 'paging must resume after the zoom and pan state is reset',
      );
    },
  );

  testWidgets('double-tap zooms around the tap and double-tap resets', (
    tester,
  ) async {
    await _openViewer(tester);

    final interactiveViewerFinder = _interactiveViewer();
    final interactiveViewer = tester.widget<InteractiveViewer>(
      interactiveViewerFinder,
    );
    final controller = interactiveViewer.transformationController!;
    expect(
      controller.value.storage,
      orderedEquals(Matrix4.identity().storage),
      reason: 'the single image starts at identity',
    );

    final topLeft = tester.getTopLeft(interactiveViewerFinder);
    final size = tester.getSize(interactiveViewerFinder);
    final tapPosition = topLeft + Offset(size.width * 0.25, size.height * 0.3);

    await _doubleTapAt(tester, tapPosition);
    final zoomedMatrix = controller.value.clone();

    await _doubleTapAt(tester, tapPosition);
    final restoredMatrix = controller.value.clone();

    expect(
      zoomedMatrix.getMaxScaleOnAxis(),
      closeTo(2.5, 0.001),
      reason: 'the first double-tap must zoom to 2.5x',
    );
    expect(
      zoomedMatrix.storage[12],
      isNot(0.0),
      reason: 'zooming around an off-center tap must translate horizontally',
    );
    expect(
      zoomedMatrix.storage[13],
      isNot(0.0),
      reason: 'zooming around an off-center tap must translate vertically',
    );
    expect(
      restoredMatrix.storage,
      orderedEquals(Matrix4.identity().storage),
      reason: 'the second double-tap must clear scale and translation',
    );
  });

  testWidgets(
    'zoomed single-image vertical pan never becomes a dismissal drag',
    (tester) async {
      await _openViewer(tester);

      final viewerFinder = find.byKey(_viewerKey);
      final interactiveViewerFinder = _interactiveViewer();
      final controller = tester
          .widget<InteractiveViewer>(interactiveViewerFinder)
          .transformationController!;
      final center = tester.getCenter(interactiveViewerFinder);

      await _doubleTapAt(tester, center);
      final beforePan = controller.value.clone();
      expect(
        beforePan.getMaxScaleOnAxis(),
        greaterThan(1.01),
        reason: 'the image must be zoomed before the vertical pan',
      );

      final pan = await tester.startGesture(center);
      await pan.moveBy(const Offset(0, 20));
      await tester.pump();
      await pan.moveBy(const Offset(0, 140));
      await tester.pump();

      final duringPan = controller.value.clone();
      final dismissalTransform = tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: viewerFinder,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .transform!;
      expect(
        (duringPan.storage[13] - beforePan.storage[13]).abs(),
        greaterThan(100),
        reason: 'the zoomed image must absorb the above-threshold vertical pan',
      );
      expect(
        dismissalTransform.storage[12],
        0.0,
        reason: 'zoomed-image panning must not translate the outer viewer on X',
      );
      expect(
        dismissalTransform.storage[13],
        0.0,
        reason: 'zoomed-image panning must not translate the outer viewer on Y',
      );

      await pan.up();
      await tester.pumpAndSettle();

      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'releasing a zoomed-image pan must leave the route open',
      );
    },
  );

  testWidgets('single unzoomed image dismisses on a strongly diagonal throw', (
    tester,
  ) async {
    await _openViewer(tester);

    final viewerFinder = find.byKey(_viewerKey);
    final interactiveViewerFinder = _interactiveViewer();
    final controller = tester
        .widget<InteractiveViewer>(interactiveViewerFinder)
        .transformationController!;
    expect(
      controller.value.storage,
      orderedEquals(Matrix4.identity().storage),
      reason: 'the single image must start unzoomed',
    );

    await tester.fling(interactiveViewerFinder, const Offset(320, 140), 1200);
    await tester.pumpAndSettle();

    expect(
      viewerFinder,
      findsNothing,
      reason:
          'more than 100px of vertical movement must dismiss even when '
          'horizontal movement is larger',
    );
  });

  testWidgets(
    'single image free-drags on both axes without a PageView and snaps back',
    (tester) async {
      await _openViewer(tester);

      final viewerFinder = find.byKey(_viewerKey);
      final interactiveViewerFinder = _interactiveViewer();
      final interactiveViewer = tester.widget<InteractiveViewer>(
        interactiveViewerFinder,
      );
      expect(
        interactiveViewer.transformationController!.value.storage,
        orderedEquals(Matrix4.identity().storage),
        reason: 'the drag starts with the image unzoomed at identity',
      );
      final pageViewCount = find
          .descendant(of: viewerFinder, matching: find.byType(PageView))
          .evaluate()
          .length;

      final gesture = await tester.startGesture(
        tester.getCenter(interactiveViewerFinder),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(70, 60));
      await tester.pump();

      final draggedTransform = tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: viewerFinder,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .transform!
          .clone();

      await gesture.up();
      await tester.pumpAndSettle();

      final restoredTransform = tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: viewerFinder,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .transform!;

      expect(
        pageViewCount,
        0,
        reason: 'a one-image viewer must not retain horizontal paging',
      );
      expect(
        draggedTransform.storage[12].abs(),
        greaterThan(50),
        reason: 'a mostly-horizontal drag must visibly move the image on X',
      );
      expect(
        draggedTransform.storage[13].abs(),
        greaterThan(40),
        reason: 'the same drag must visibly move the image on Y',
      );
      expect(
        viewerFinder,
        findsOneWidget,
        reason: '60px of vertical movement is below the dismissal threshold',
      );
      expect(
        restoredTransform.storage[12],
        0.0,
        reason: 'release must restore horizontal translation',
      );
      expect(
        restoredTransform.storage[13],
        0.0,
        reason: 'release must restore vertical translation',
      );
    },
  );

  testWidgets('cancelled above-threshold single-image drag snaps back', (
    tester,
  ) async {
    await _openViewer(tester);

    final viewerFinder = find.byKey(_viewerKey);
    final interactiveViewerFinder = _interactiveViewer();
    final gesture = await tester.startGesture(
      tester.getCenter(interactiveViewerFinder),
    );
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 120));
    await tester.pump();

    final draggedTransform = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: viewerFinder,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .transform!
        .clone();
    expect(
      draggedTransform.storage[12].abs(),
      greaterThan(50),
      reason: 'the drag must visibly displace the viewer on X before cancel',
    );
    expect(
      draggedTransform.storage[13].abs(),
      greaterThan(100),
      reason: 'the drag must cross the dismissal threshold before cancel',
    );

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(
      viewerFinder,
      findsOneWidget,
      reason: 'cancelling must not complete an above-threshold dismissal',
    );
    final restoredTransform = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: viewerFinder,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .transform!;
    expect(
      restoredTransform.storage[12],
      0.0,
      reason: 'cancellation must restore horizontal translation',
    );
    expect(
      restoredTransform.storage[13],
      0.0,
      reason: 'cancellation must restore vertical translation',
    );
  });

  group('save image', () {
    testWidgets(
      'saves the currently visible gallery image and keeps the viewer open',
      (tester) async {
        final saver = _RecordingMediaSaver();
        // The saver wraps MaterialApp so the root-navigator viewer route
        // can read it, the same way the app root provides it.
        await tester.pumpWidget(
          Provider<MediaSaver>.value(
            value: saver,
            child: _harness(images: _twoImageGallery),
          ),
        );
        await tester.tap(find.text('Open image'));
        await tester.pumpAndSettle();

        final viewerFinder = find.byKey(_viewerKey);
        await tester.fling(
          find.descendant(of: viewerFinder, matching: find.byType(PageView)),
          const Offset(-500, 0),
          1200,
        );
        await tester.pumpAndSettle();
        expect(
          _pageDots(index: 1, count: 2),
          findsOneWidget,
          reason: 'the swipe must bring the second image into view',
        );

        await tester.tap(
          find.descendant(
            of: viewerFinder,
            matching: find.byTooltip('Save image'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(saver.savedUrls, [
          'https://cdn.test/fullsize-2.jpg',
        ], reason: 'one tap must save the visible image at full size, once');
        expect(find.text('Saved to Photos'), findsOneWidget);
        expect(
          viewerFinder,
          findsOneWidget,
          reason: 'saving must not close the viewer',
        );
      },
    );

    testWidgets(
      'save button sits top-left inside the safe area and saves on tap',
      (tester) async {
        const safeAreaPadding = EdgeInsets.only(top: 40, left: 24);
        final saver = _RecordingMediaSaver();
        await tester.pumpWidget(
          Provider<MediaSaver>.value(
            value: saver,
            child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(padding: safeAreaPadding),
                child: child!,
              ),
              home: ImageViewer(
                images: const [
                  EmbedImage(
                    thumb: 'https://cdn.test/thumb.jpg',
                    fullsize: 'https://cdn.test/fullsize.jpg',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewerFinder = find.byKey(_viewerKey);
        final saveButton = find.descendant(
          of: viewerFinder,
          matching: find.byTooltip('Save image'),
        );
        expect(saveButton, findsOneWidget);

        final screen = tester.getSize(viewerFinder);
        final buttonRect = tester.getRect(saveButton);
        expect(
          buttonRect.top,
          greaterThanOrEqualTo(safeAreaPadding.top),
          reason: 'the button must clear the top inset',
        );
        expect(
          buttonRect.left,
          greaterThanOrEqualTo(safeAreaPadding.left),
          reason: 'the button must clear the left inset',
        );
        expect(
          buttonRect.right,
          lessThanOrEqualTo(screen.width / 2),
          reason: 'the button belongs on the left, opposite the close button',
        );
        expect(
          buttonRect.bottom,
          lessThanOrEqualTo(screen.height / 2),
          reason: 'the button belongs at the top of the viewer',
        );

        final imageTopLeftBeforeTap = tester.getTopLeft(_interactiveViewer());
        await tester.tap(saveButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(saver.savedUrls, ['https://cdn.test/fullsize.jpg']);
        expect(find.text('Saved to Photos'), findsOneWidget);
        expect(
          viewerFinder,
          findsOneWidget,
          reason: 'saving must not close the viewer',
        );
        expect(
          tester.getTopLeft(_interactiveViewer()),
          imageTopLeftBeforeTap,
          reason: 'tapping save must not start a dismissal drag on the image',
        );
      },
    );

    testWidgets('gallery opened on its last image saves that image', (
      tester,
    ) async {
      final saver = _RecordingMediaSaver();
      await _pumpViewerWithSaver(
        tester,
        saver: saver,
        images: _threeImageGallery,
        initialIndex: 2,
      );

      await tester.tap(_saveButton());
      await tester.pump();

      expect(saver.savedUrls, ['https://cdn.test/fullsize-3.jpg']);
    });

    testWidgets(
      'ignores taps while a save is pending, then saves the visible page',
      (tester) async {
        final saver = _PendingMediaSaver();
        await _pumpViewerWithSaver(
          tester,
          saver: saver,
          images: _threeImageGallery,
        );
        final viewerFinder = find.byKey(_viewerKey);
        final buttonCenter = tester.getCenter(_saveButton());

        // Both taps land before any rebuild could swap the button out.
        await tester.tap(_saveButton());
        await tester.tap(_saveButton());
        await tester.pump();
        await tester.tapAt(buttonCenter);
        await tester.pump();

        expect(saver.savedUrls, [
          'https://cdn.test/fullsize-1.jpg',
        ], reason: 'repeat taps while saving must not start another save');
        expect(
          _progressIndicator(),
          findsOneWidget,
          reason: 'a pending save must show progress',
        );
        expect(
          _downloadGlyph(),
          findsNothing,
          reason: 'the progress indicator replaces the download glyph',
        );

        await tester.fling(
          find.descendant(of: viewerFinder, matching: find.byType(PageView)),
          const Offset(-500, 0),
          1200,
        );
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          _pageDots(index: 1, count: 3),
          findsOneWidget,
          reason: 'paging must still work while a save is pending',
        );
        expect(saver.savedUrls, [
          'https://cdn.test/fullsize-1.jpg',
        ], reason: 'paging must not change the save already in flight');

        saver.pendingSaves.single.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          _progressIndicator(),
          findsNothing,
          reason: 'a finished save must clear the progress indicator',
        );
        expect(
          _downloadGlyph(),
          findsOneWidget,
          reason: 'a finished save must restore the download glyph',
        );

        await tester.tap(_saveButton());
        await tester.pump();

        expect(saver.savedUrls, [
          'https://cdn.test/fullsize-1.jpg',
          'https://cdn.test/fullsize-2.jpg',
        ], reason: 'after the first save, a tap saves the newly visible page');
      },
    );

    testWidgets(
      'save button is disabled for accessibility while a save is pending',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final saver = _PendingMediaSaver();
        await _pumpViewerWithSaver(
          tester,
          saver: saver,
          images: _twoImageGallery,
        );

        expect(
          tester.widget<IconButton>(_saveIconButton()).onPressed,
          isNotNull,
        );
        expect(
          tester.getSemantics(_saveIconButton()),
          isSemantics(isButton: true, isEnabled: true),
        );

        await tester.tap(_saveButton());
        await tester.pump();

        expect(
          tester.widget<IconButton>(_saveIconButton()).onPressed,
          isNull,
          reason:
              'a pending save must disable the button, not just ignore taps',
        );
        expect(
          tester.getSemantics(_saveIconButton()),
          isSemantics(isButton: true, isEnabled: false),
          reason:
              'screen readers must hear the button as disabled while saving',
        );

        saver.pendingSaves.single.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.widget<IconButton>(_saveIconButton()).onPressed,
          isNotNull,
          reason: 'a finished save must re-enable the button',
        );
        expect(
          tester.getSemantics(_saveIconButton()),
          isSemantics(isButton: true, isEnabled: true),
        );
        // Disposed in the body: testWidgets checks for live semantics
        // handles before tear-downs run.
        semantics.dispose();
      },
    );

    testWidgets(
      'without a MediaSaver provider the tap fails loudly, leaving no spinner',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: ImageViewer(images: _twoImageGallery),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(_saveButton());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.takeException(),
          isA<ProviderNotFoundException>(),
          reason: 'a missing provider is a wiring bug and must not be hidden',
        );
        expect(
          _progressIndicator(),
          findsNothing,
          reason: 'the failed tap must not leave a stuck spinner',
        );
        expect(
          _downloadGlyph(),
          findsOneWidget,
          reason: 'the download glyph must come back after the failed tap',
        );
      },
    );

    testWidgets(
      'outcomes finishing during a snackbar exit show only the newest one',
      (tester) async {
        const savedMessage = 'Saved to Photos';
        const saveFailedMessage = "Couldn't save image";
        const accessMessage = 'Allow photo access in Settings to save images';
        final saver = _PendingMediaSaver();
        await _pumpViewerWithSaver(
          tester,
          saver: saver,
          images: _twoImageGallery,
        );

        // Outcome A is fully on screen.
        await tester.tap(_saveButton());
        await tester.pump();
        saver.pendingSaves.last.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(savedMessage), findsOneWidget);

        // Outcome B starts A's exit animation.
        await tester.tap(_saveButton());
        await tester.pump();
        saver.pendingSaves.last.completeError(
          const MediaSaveException(MediaSaveFailure.saveFailed),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // Outcome C lands while A is still animating out.
        await tester.tap(_saveButton());
        await tester.pump();
        saver.pendingSaves.last.completeError(
          const MediaSaveException(MediaSaveFailure.accessDenied),
        );
        await tester.pump();
        expect(saver.savedUrls, hasLength(3));

        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text(accessMessage),
          findsOneWidget,
          reason: 'the newest outcome must show once the old snackbar exits',
        );
        expect(
          find.text(saveFailedMessage),
          findsNothing,
          reason: 'a superseded outcome must never be shown',
        );

        for (var step = 0; step < 60; step++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.text(saveFailedMessage),
            findsNothing,
            reason: 'a superseded outcome must not appear after the newest',
          );
        }
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('a newer save outcome replaces the current snackbar at once', (
      tester,
    ) async {
      final saver = _PendingMediaSaver();
      await _pumpViewerWithSaver(
        tester,
        saver: saver,
        images: _twoImageGallery,
      );

      await tester.tap(_saveButton());
      await tester.pump();
      saver.pendingSaves.single.completeError(
        const MediaSaveException(MediaSaveFailure.saveFailed),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text("Couldn't save image"), findsOneWidget);

      await tester.tap(_saveButton());
      await tester.pump();
      saver.pendingSaves.last.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Saved to Photos'),
        findsOneWidget,
        reason: 'the newest outcome must show within a second, not queue',
      );
      expect(
        find.text("Couldn't save image"),
        findsNothing,
        reason: 'the older outcome must be replaced, not left on screen',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('two back-to-back saves leave no queued snackbar behind', (
      tester,
    ) async {
      final saver = _RecordingMediaSaver();
      await _pumpViewerWithSaver(
        tester,
        saver: saver,
        images: _twoImageGallery,
      );

      await tester.tap(_saveButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Saved to Photos'), findsOneWidget);

      await tester.tap(_saveButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(saver.savedUrls, hasLength(2));
      expect(find.byType(SnackBar), findsOneWidget);

      // The second snackbar's 4-second display plus its exit animation fit
      // well inside 6 seconds; a queued one would still be on screen.
      for (var step = 0; step < 60; step++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byType(SnackBar),
        findsNothing,
        reason:
            'the second save must replace the first snackbar, not queue '
            'behind it',
      );
    });

    const accessMessage = 'Allow photo access in Settings to save images';
    const genericFailureMessage = "Couldn't save image";
    const downloadFailureMessage =
        "Couldn't download image. Check your connection and try again.";
    final failureCases = <(String, Object, String)>[
      (
        'access denied',
        const MediaSaveException(MediaSaveFailure.accessDenied),
        accessMessage,
      ),
      (
        'download failed',
        const MediaSaveException(MediaSaveFailure.downloadFailed),
        downloadFailureMessage,
      ),
      (
        'save failed',
        const MediaSaveException(MediaSaveFailure.saveFailed),
        genericFailureMessage,
      ),
      (
        'an unexpected error',
        StateError('unexpected platform failure'),
        genericFailureMessage,
      ),
    ];

    for (final (description, error, message) in failureCases) {
      testWidgets('$description shows "$message" and re-enables the button', (
        tester,
      ) async {
        final saver = _PendingMediaSaver();
        await _pumpViewerWithSaver(
          tester,
          saver: saver,
          images: _twoImageGallery,
        );

        await tester.tap(_saveButton());
        await tester.pump();
        saver.pendingSaves.single.completeError(error);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Saved to Photos'), findsNothing);
        expect(
          find.byKey(_viewerKey),
          findsOneWidget,
          reason: 'a failed save must not close the viewer',
        );
        expect(
          _progressIndicator(),
          findsNothing,
          reason: 'a failed save must clear the progress indicator',
        );

        await tester.tap(_saveButton());
        await tester.pump();

        expect(saver.savedUrls, [
          'https://cdn.test/fullsize-1.jpg',
          'https://cdn.test/fullsize-1.jpg',
        ], reason: 'after a failure, the next tap must start a new save');

        saver.pendingSaves.last.complete();
        await tester.pump();
      });
    }

    final closingCases = <(String, Object?, String)>[
      ('success', null, 'Saved to Photos'),
      (
        'access denied',
        const MediaSaveException(MediaSaveFailure.accessDenied),
        accessMessage,
      ),
    ];

    for (final (outcome, error, message) in closingCases) {
      void finishSave(_PendingMediaSaver saver) {
        final save = saver.pendingSaves.single;
        if (error == null) {
          save.complete();
        } else {
          save.completeError(error);
        }
      }

      Future<_PendingMediaSaver> startSaveAndClose(WidgetTester tester) async {
        final saver = _PendingMediaSaver();
        await tester.pumpWidget(
          Provider<MediaSaver>.value(
            value: saver,
            child: _harness(images: _twoImageGallery),
          ),
        );
        await tester.tap(find.text('Open image'));
        await tester.pumpAndSettle();

        await tester.tap(_saveButton());
        await tester.pump();
        expect(saver.savedUrls, ['https://cdn.test/fullsize-1.jpg']);

        await tester.tap(
          find.descendant(
            of: find.byKey(_viewerKey),
            matching: find.byTooltip('Close'),
          ),
        );
        return saver;
      }

      testWidgets(
        '$outcome that finishes during the close transition still reports '
        '"$message" on the underlying screen',
        (tester) async {
          final saver = await startSaveAndClose(tester);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            find.byKey(_viewerKey),
            findsOneWidget,
            reason: 'the save must finish while the viewer is still fading out',
          );

          finishSave(saver);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byKey(_viewerKey), findsNothing);
          expect(find.text('Open image'), findsOneWidget);
          expect(find.text(message), findsOneWidget);
        },
      );

      testWidgets(
        '$outcome that finishes after the viewer is gone still reports '
        '"$message" on the underlying screen',
        (tester) async {
          final saver = await startSaveAndClose(tester);
          await tester.pumpAndSettle();
          expect(
            find.byKey(_viewerKey),
            findsNothing,
            reason:
                'the viewer route must be fully removed before the save ends',
          );

          finishSave(saver);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Open image'), findsOneWidget);
          expect(find.text(message), findsOneWidget);
        },
      );
    }
  });

  group('B6 a GIF in the viewer', () {
    const gifThumb = 'https://cdn.test/cat-thumb.jpg';
    const gifFull = 'https://cdn.test/cat-full.gif';
    const gif = EmbedImage(thumb: gifThumb, fullsize: gifFull, isGif: true);
    late FakeGifFrames frames;

    setUpAll(() async {
      frames = await FakeGifFrames.create();
    });

    tearDownAll(() => frames.dispose());

    Finder playGif() => find.descendant(
      of: find.byKey(_viewerKey),
      matching: find.bySemanticsLabel('Play GIF'),
    );
    Finder viewerImage(String url) => find.descendant(
      of: find.byKey(_viewerKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
      ),
    );

    testWidgets('shows the still thumb with Play GIF and never requests '
        'fullsize', (tester) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [gif],
        gifLoader: loader,
      );

      expect(viewerImage(gifFull), findsNothing);
      expect(viewerImage(gifThumb), findsOneWidget);
      expect(playGif(), findsOneWidget);
      expect(loader.requests, isEmpty);
    });

    testWidgets('a tap on the image away from Play GIF toggles the controls '
        'and does not play', (tester) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [gif],
        gifLoader: loader,
      );
      expect(playGif(), findsOneWidget);

      // Left edge, mid height: clear of the centred play control and of
      // the top corner buttons.
      await _singleTapAt(
        tester,
        tester.getRect(_interactiveViewer()).centerLeft + const Offset(20, 0),
      );

      _expectControls(
        tester,
        [_closeButton(), _saveButton()],
        shown: false,
        reason: 'a tap on a GIF still toggles the controls',
      );
      expect(loader.requests, isEmpty);
      expect(find.byKey(gifFrameKey), findsNothing);
    });

    testWidgets('Play GIF plays the fullsize GIF in place', (tester) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [gif],
        gifLoader: loader,
      );
      expect(playGif(), findsOneWidget);

      await tester.tap(playGif());
      await tester.pump();
      await tester.pump();

      expect(loader.requests, [gifFull]);
      expect(
        find.descendant(
          of: find.byKey(_imageSlotKey),
          matching: find.byKey(gifFrameKey),
        ),
        findsOneWidget,
      );
      expect(shownGifFrameWidth(tester), 10);
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownGifFrameWidth(tester), 11);
    });

    testWidgets('paging away from a playing GIF and back shows Play GIF', (
      tester,
    ) async {
      final loader = FakeGifCodecLoader(codec: FakeGifCodec(frames));
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: [gif, _twoImageGallery.first],
        gifLoader: loader,
      );
      expect(playGif(), findsOneWidget);
      await tester.tap(playGif());
      await tester.pump();
      await tester.pump();
      expect(shownGifFrameWidth(tester), 10);

      final pages = find.descendant(
        of: find.byKey(_viewerKey),
        matching: find.byType(PageView),
      );
      await tester.fling(pages, const Offset(-500, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_pageDots(index: 1, count: 2), findsOneWidget);
      await tester.fling(pages, const Offset(500, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_pageDots(index: 0, count: 2), findsOneWidget);

      expect(playGif(), findsOneWidget);
      expect(find.byKey(gifFrameKey), findsNothing);
    });
  });

  group('B7 the ALT badge', () {
    const altBadgeKey = Key('image-viewer-alt-badge');
    const altTextKey = Key('image-viewer-alt-text');
    const catAlt = 'A tabby cat asleep on a sunny windowsill';
    const dogAlt = 'A golden retriever catching a frisbee';

    Finder altBadge() => find.byKey(altBadgeKey);
    Finder altText(String alt) => find.descendant(
      of: find.byKey(altTextKey),
      matching: find.text(alt),
      matchRoot: true,
    );

    Future<void> swipeToNextPage(WidgetTester tester) async {
      await tester.fling(
        find.descendant(
          of: find.byKey(_viewerKey),
          matching: find.byType(PageView),
        ),
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reads ALT, announces Show alt text, and follows the page: '
        'absent for null and empty alt', (tester) async {
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
            alt: catAlt,
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-2.jpg',
            fullsize: 'https://cdn.test/fullsize-2.jpg',
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-3.jpg',
            fullsize: 'https://cdn.test/fullsize-3.jpg',
            alt: '',
          ),
        ],
      );

      expect(altBadge(), findsOneWidget);
      expect(
        find.descendant(of: altBadge(), matching: find.text('ALT')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Show alt text'), findsOneWidget);

      await swipeToNextPage(tester);
      expect(_pageDots(index: 1, count: 3), findsOneWidget);
      expect(altBadge(), findsNothing, reason: 'null alt has no badge');

      await swipeToNextPage(tester);
      expect(_pageDots(index: 2, count: 3), findsOneWidget);
      expect(altBadge(), findsNothing, reason: 'empty alt has no badge');
    });

    testWidgets('tapping the badge shows the full alt text', (tester) async {
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb.jpg',
            fullsize: 'https://cdn.test/fullsize.jpg',
            alt: catAlt,
          ),
        ],
      );
      expect(altBadge(), findsOneWidget);
      expect(find.byKey(altTextKey), findsNothing);

      await tester.tap(altBadge());
      await tester.pumpAndSettle();

      expect(altText(catAlt), findsOneWidget);
    });

    testWidgets('a 3000-character alt scrolls to its end inside the panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final longAlt = '${'word ' * 599}FINAL';
      expect(longAlt.length, 3000);
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: [
          EmbedImage(
            thumb: 'https://cdn.test/thumb.jpg',
            fullsize: 'https://cdn.test/fullsize.jpg',
            alt: longAlt,
          ),
        ],
      );
      expect(altBadge(), findsOneWidget);
      await tester.tap(altBadge());
      await tester.pumpAndSettle();

      final text = altText(longAlt);
      expect(text, findsOneWidget);
      // Just above the bottom edge of the text: its last line.
      const lastLine = Alignment(0, 0.99);
      expect(
        text.hitTestable(at: lastLine),
        findsNothing,
        reason: 'the panel is shorter than the text',
      );

      final panel = find
          .ancestor(of: text, matching: find.byType(Scrollable))
          .first;
      await tester.drag(panel, const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(text.hitTestable(at: lastLine), findsOneWidget);
    });

    testWidgets('hidden controls take the badge with them', (tester) async {
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb.jpg',
            fullsize: 'https://cdn.test/fullsize.jpg',
            alt: catAlt,
          ),
        ],
      );
      expect(altBadge().hitTestable(), findsOneWidget);

      await _singleTapAt(tester, tester.getCenter(_interactiveViewer()));

      _expectControls(
        tester,
        [_closeButton()],
        shown: false,
        reason: 'a single tap hides the controls',
      );
      expect(altBadge().hitTestable(), findsNothing);
    });

    testWidgets('changing page closes the panel and shows no stale alt', (
      tester,
    ) async {
      await _pumpViewerWithSaver(
        tester,
        saver: _RecordingMediaSaver(),
        images: const [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
            alt: catAlt,
          ),
          EmbedImage(
            thumb: 'https://cdn.test/thumb-2.jpg',
            fullsize: 'https://cdn.test/fullsize-2.jpg',
            alt: dogAlt,
          ),
        ],
      );
      expect(altBadge(), findsOneWidget);
      await tester.tap(altBadge());
      await tester.pumpAndSettle();
      expect(altText(catAlt), findsOneWidget);

      await swipeToNextPage(tester);

      expect(_pageDots(index: 1, count: 2), findsOneWidget);
      expect(find.text(catAlt), findsNothing);
      expect(find.byKey(altTextKey), findsNothing);
      expect(altBadge(), findsOneWidget);
    });
  });

  group(
    'a gallery swipe pages when mostly sideways and dismisses otherwise',
    () {
      const gallery = [
        EmbedImage(
          thumb: 'https://cdn.test/t1.jpg',
          fullsize: 'https://cdn.test/f1.jpg',
        ),
        EmbedImage(
          thumb: 'https://cdn.test/t2.jpg',
          fullsize: 'https://cdn.test/f2.jpg',
        ),
        EmbedImage(
          thumb: 'https://cdn.test/t3.jpg',
          fullsize: 'https://cdn.test/f3.jpg',
        ),
      ];

      Future<void> openGallery(WidgetTester tester) =>
          _openViewer(tester, images: gallery);

      for (final (description, throwOffset) in [
        ('up and to the right', const Offset(250, -320)),
        ('up and to the left', const Offset(-250, -320)),
        ('down and to the right', const Offset(250, 320)),
      ]) {
        testWidgets('a diagonal throw $description closes the viewer', (
          tester,
        ) async {
          await openGallery(tester);

          await tester.fling(_interactiveViewer().first, throwOffset, 1200);
          await tester.pumpAndSettle();

          expect(find.byKey(_viewerKey), findsNothing);
        });
      }

      testWidgets(
        'a slightly slanted sideways swipe pages and keeps the viewer',
        (tester) async {
          await openGallery(tester);

          await tester.fling(
            _interactiveViewer().first,
            const Offset(-400, 110),
            1200,
          );
          await tester.pumpAndSettle();

          expect(find.byKey(_viewerKey), findsOneWidget);
          expect(_pageDots(index: 1, count: 3), findsOneWidget);
        },
      );

      testWidgets(
        'with a screen reader on the gallery keeps its scroll actions',
        (tester) async {
          final semantics = tester.ensureSemantics();
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(accessibleNavigation: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await openGallery(tester);

          expect(
            find.semantics.byAction(SemanticsAction.scrollLeft),
            findsOne,
            reason: 'TalkBack and VoiceOver page the gallery with it',
          );
          semantics.dispose();
        },
      );

      testWidgets('a page swipe that bends downward still pages, and the next '
          'sideways swipe pages too', (tester) async {
        await openGallery(tester);
        final start = tester.getCenter(_interactiveViewer().first);

        final gesture = await tester.startGesture(start);
        // Small first steps, as a finger moves: paging claims the swipe
        // before the dismiss drag's larger slop.
        await gesture.moveBy(const Offset(-10, 0));
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(-70, 0));
          await tester.pump();
        }
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(0, 60));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byKey(_viewerKey), findsOneWidget);
        expect(_pageDots(index: 1, count: 3), findsOneWidget);

        await tester.fling(
          _interactiveViewer().first,
          const Offset(-400, 0),
          1200,
        );
        await tester.pumpAndSettle();
        expect(_pageDots(index: 2, count: 3), findsOneWidget);
      });

      testWidgets('with a phone\'s touch slop a slow sideways swipe pages', (
        tester,
      ) async {
        // Real phones report a touch slop; the dismiss drag's slop is twice
        // it, so paging must use the same device slop to claim first.
        tester.view.gestureSettings = const ui.GestureSettings(
          physicalTouchSlop: 8, // 2.67px at the test's 3x density
        );
        addTearDown(tester.view.resetGestureSettings);
        await openGallery(tester);

        final gesture = await tester.startGesture(
          tester.getCenter(_interactiveViewer().first),
        );
        for (var i = 0; i < 220; i++) {
          await gesture.moveBy(const Offset(-2, 0));
          await tester.pump(const Duration(milliseconds: 8));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byKey(_viewerKey), findsOneWidget);
        expect(_pageDots(index: 1, count: 3), findsOneWidget);
      });

      testWidgets('paging takes its fling tracking and devices from the scroll '
          'behaviour, like a PageView', (tester) async {
        await openGallery(tester);

        final detector = tester.widget<RawGestureDetector>(
          find
              .ancestor(
                of: find.byType(PageView),
                matching: find.byType(RawGestureDetector),
              )
              .first,
        );
        final factory = detector.gestures.values.single;
        final recognizer = factory.constructor() as DragGestureRecognizer;
        addTearDown(recognizer.dispose);
        factory.initializer(recognizer);

        final tracker = recognizer.velocityTrackerBuilder(
          const PointerDownEvent(),
        );
        expect(tracker, isA<IOSScrollViewFlingVelocityTracker>());
        expect(
          recognizer.multitouchDragStrategy,
          MultitouchDragStrategy.averageBoundaryPointers,
        );
        expect(
          recognizer.supportedDevices,
          isNot(contains(PointerDeviceKind.mouse)),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

      testWidgets('a short diagonal drag follows the finger and snaps back', (
        tester,
      ) async {
        await openGallery(tester);
        final slot = find.byKey(const Key('image-viewer-image-slot')).first;
        final start = tester.getCenter(slot);

        final gesture = await tester.startGesture(start);
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(10, -12));
          await tester.pump();
        }
        final moved = tester.getCenter(slot);
        expect(
          moved.dx,
          greaterThan(start.dx + 20),
          reason: 'follows sideways',
        );
        expect(moved.dy, lessThan(start.dy - 20), reason: 'follows upward');

        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byKey(_viewerKey), findsOneWidget);
        expect(_pageDots(index: 0, count: 3), findsOneWidget);
        expect(tester.getCenter(slot), start);
      });
    },
  );
}
