import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_image_cache_manager.dart';

const _alt = 'A purple anemone on a grey rock';
const _viewerKey = Key('image-viewer');
const _altTextKey = Key('image-viewer-alt-text');
const _altBadgeKey = Key('image-viewer-alt-badge');

const _gallery = [
  EmbedImage(
    thumb: 'https://cdn.test/thumb-1.jpg',
    fullsize: 'https://cdn.test/fullsize-1.jpg',
    alt: _alt,
  ),
  EmbedImage(
    thumb: 'https://cdn.test/thumb-2.jpg',
    fullsize: 'https://cdn.test/fullsize-2.jpg',
  ),
];

/// Captures every `Clipboard.setData` text written during the test.
List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final args = methodCall.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
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
  return copied;
}

/// Bounded stand-in for pumpAndSettle: the images stay loading forever, so a
/// settle is never awaited unbounded.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Alt text far taller than the panel's cap of 40% of the screen height.
final _longAlt = [
  'Opening line of a long description.',
  for (var i = 1; i <= 60; i++) 'Sentence $i describes more of the scene.',
  'Closing line of the description.',
].join(' ');

/// Opens the lightbox on [gallery] at image 1 on a 400x900 phone, with no
/// image ever fetched, then opens the alt text panel.
Future<void> _openViewerWithAltPanel(
  WidgetTester tester, {
  List<EmbedImage> gallery = _gallery,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ImageCacheScope(
      cacheManager: FakeImageCacheManager(),
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => ImageViewer.open(context, gallery),
                child: const Text('Open image'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Open image'));
  await _settle(tester);
  await tester.tap(find.byKey(_altBadgeKey));
  await _settle(tester);
  expect(find.byKey(_altTextKey), findsOneWidget);
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
}

/// Global rect covering [word] in the alt text panel's paragraph.
Rect _altWordRect(WidgetTester tester, String word) {
  final finder = find.descendant(
    of: find.byKey(_altTextKey),
    matching: find.byType(RichText),
  );
  expect(finder, findsOneWidget, reason: 'alt text paragraph');
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final start = plain.indexOf(word);
  expect(start, isNonNegative, reason: '"$word" not in "$plain"');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + word.length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await _settle(tester);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

/// Global rects of the Material selection handles currently drawn: non-zero
/// opacity, and following a connected leader (a follower whose leader layer
/// is gone, as for a handle scrolled out of its viewport, paints nothing).
List<Rect> _visibleHandleRects(WidgetTester tester) {
  final handles = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_TextSelectionHandlePainter',
  );
  final rects = <Rect>[];
  for (final element in handles.evaluate()) {
    var visible = true;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition && widget.opacity.value == 0) {
        visible = false;
        return false;
      }
      if (widget is CompositedTransformFollower &&
          !widget.showWhenUnlinked &&
          widget.link.leader == null) {
        visible = false;
        return false;
      }
      return true;
    });
    if (!visible) {
      continue;
    }
    final box = element.renderObject! as RenderBox;
    rects.add(
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
    );
  }
  return rects;
}

/// The InteractiveViewer of the page on screen: the one under the screen's
/// centre, which is clear of the alt panel in the bottom-left corner.
Finder _visibleInteractiveViewer() => find
    .descendant(
      of: find.byKey(_viewerKey),
      matching: find.byType(InteractiveViewer),
    )
    .hitTestable();

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets(
    'B4 long-press, Select all, Copy in the alt panel copies the alt text',
    (tester) async {
      final copied = _captureClipboard(tester);
      await _openViewerWithAltPanel(tester);

      await tester.longPressAt(_altWordRect(tester, 'anemone').center);
      await _settle(tester);
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [_alt]);
    },
    variant: android,
  );

  testWidgets(
    'B1 a selection handle scrolled out of a long alt panel is not drawn',
    (tester) async {
      await _openViewerWithAltPanel(
        tester,
        gallery: [
          EmbedImage(
            thumb: 'https://cdn.test/thumb-1.jpg',
            fullsize: 'https://cdn.test/fullsize-1.jpg',
            alt: _longAlt,
          ),
        ],
      );
      final panel = find.byKey(_altTextKey);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: panel, matching: find.byType(Scrollable)),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the long alt overflows the panel',
      );

      // A drawn handle's top sits on its selection point's line, so it must
      // fall inside the panel; a handle off the panel is not drawn at all.
      void expectHandlesInsidePanel(String when) {
        final panelRect = tester.getRect(panel);
        final handles = _visibleHandleRects(tester);
        expect(handles, hasLength(1), reason: '$when: handles $handles');
        expect(
          handles.single.top,
          inInclusiveRange(panelRect.top, panelRect.bottom),
          reason: '$when: handle ${handles.single} vs panel $panelRect',
        );
      }

      await tester.longPressAt(_altWordRect(tester, 'Opening').center);
      await _settle(tester);
      await _tapToolbar(tester, 'Select all');
      // The end of the selection is far below the panel's bottom edge.
      expectHandlesInsidePanel('before scrolling');

      // The start of the selection scrolls far above the panel's top edge.
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await _settle(tester);
      expectHandlesInsidePanel('after scrolling to the end');
    },
    variant: android,
  );

  testWidgets(
    'B5 a horizontal fling with the alt panel open pages to image 2 and '
    'shows no selection UI',
    (tester) async {
      await _openViewerWithAltPanel(tester);
      final viewer = _visibleInteractiveViewer();
      expect(viewer, findsOneWidget);

      await tester.flingFrom(
        tester.getCenter(viewer),
        const Offset(-300, 0),
        1200,
      );
      await _settle(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('image-viewer-page-indicator')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MediaPageDots &&
                widget.index == 1 &&
                widget.count == 2,
          ),
        ),
        findsOneWidget,
      );
      expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Select all'), findsNothing);
    },
    variant: android,
  );

  testWidgets(
    'B7 the alt panel exposes the alt text and the badge keeps its label '
    'and tap action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _openViewerWithAltPanel(tester);

      expect(
        find.descendant(
          of: find.byKey(_altTextKey),
          matching: find.bySemanticsLabel(RegExp('^${RegExp.escape(_alt)}\$')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(_altBadgeKey)),
        isSemantics(label: 'Show alt text', hasTapAction: true),
      );
      semantics.dispose();
    },
    variant: android,
  );
}
