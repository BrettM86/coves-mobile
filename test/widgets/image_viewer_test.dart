import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/media_saver.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

/// Pumps the viewer directly as the app's home under a [MediaSaver].
Future<void> _pumpViewerWithSaver(
  WidgetTester tester, {
  required MediaSaver saver,
  required List<EmbedImage> images,
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(
    Provider<MediaSaver>.value(
      value: saver,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ImageViewer(images: images, initialIndex: initialIndex),
      ),
    ),
  );
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
}) {
  return MaterialApp(
    theme: AppTheme.dark,
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
}) async {
  await tester.pumpWidget(_harness(images: images));
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

void main() {
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
        find.descendant(of: viewerFinder, matching: find.text('1/2')),
        findsOneWidget,
        reason: 'the pinch must not page away from the first gallery image',
      );
    },
  );

  testWidgets(
    'unzoomed gallery diagonal drag dismisses without outer X translation',
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
        0.0,
        reason: 'gallery horizontal motion must remain reserved for paging',
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
        find.descendant(of: viewerFinder, matching: find.text('1/2')),
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
        find.descendant(of: viewerFinder, matching: find.text('2/2')),
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
          find.descendant(of: viewerFinder, matching: find.text('2/2')),
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
          find.descendant(of: viewerFinder, matching: find.text('2/3')),
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
}
