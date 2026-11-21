import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/separated_selection_area.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> _pumpApp(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  // The host test binding starts with no lifecycle state; a running app is
  // resumed, which is when SelectableRegion clears a selection on focus loss.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: body),
    ),
  );
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame so the region has its selectables
  // before the first gesture, as it would after any real app frame.
  await tester.pump();
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );

/// Global rect covering [word] inside the `Text` whose data is [text].
Rect _wordRect(WidgetTester tester, String text, String word) {
  final paragraph = _paragraph(tester, text);
  final start = text.indexOf(word);
  expect(start, isNonNegative, reason: '"$word" not in "$text"');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + word.length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

Future<void> _longPressWord(
  WidgetTester tester,
  String text,
  String word,
) async {
  await tester.longPressAt(_wordRect(tester, text, word).center);
  await tester.pumpAndSettle();
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

Future<void> _selectAllAndCopy(
  WidgetTester tester,
  String text,
  String word,
) async {
  await _longPressWord(tester, text, word);
  await _tapToolbar(tester, 'Select all');
  await _tapToolbar(tester, 'Copy');
}

/// Global rects of the Material selection handles currently drawn in the
/// overlay with a non-zero opacity.
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

Future<List<Rect>> _pumpUntilHandlesVisible(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (_visibleHandleRects(tester).length == 2) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  final rects = _visibleHandleRects(tester);
  expect(rects, hasLength(2), reason: 'visible selection handles');
  return rects;
}

void _expectNoSelectionUi(WidgetTester tester) {
  expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
  expect(find.text('Copy'), findsNothing);
  expect(find.text('Select all'), findsNothing);
}

SeparatedSelectionContainerDelegate _regionDelegate(WidgetTester tester) {
  final delegates = tester
      .widgetList<SelectionContainer>(
        find.descendant(
          of: find.byType(SeparatedSelectionArea),
          matching: find.byType(SelectionContainer),
        ),
      )
      .map((container) => container.delegate)
      .whereType<SeparatedSelectionContainerDelegate>()
      .toList();
  expect(
    delegates,
    hasLength(1),
    reason: 'SelectionContainer with a SeparatedSelectionContainerDelegate',
  );
  return delegates.single;
}

Widget _threeLineRegion() => const SeparatedSelectionArea(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text('alpha one'), Text('bravo two'), Text('charlie three')],
  ),
);

const _firstRegionKey = Key('first-region');
const _secondRegionKey = Key('second-region');
const _spacerKey = Key('inert-spacer');

Widget _twoRegions() => const Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SeparatedSelectionArea(
      key: _firstRegionKey,
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('first region text'),
      ),
    ),
    SizedBox(key: _spacerKey, width: 400, height: 200),
    SeparatedSelectionArea(
      key: _secondRegionKey,
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('second region text'),
      ),
    ),
  ],
);

bool _containsRect(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

void main() {
  // Pins Android and resets debugDefaultTargetPlatformOverride after each
  // test (a plain tearDown runs after the binding's debug-variable check).
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('Select all + Copy joins the region\'s Texts with newlines', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    await _pumpApp(tester, _threeLineRegion());

    await _selectAllAndCopy(tester, 'alpha one', 'alpha');

    expect(copied, ['alpha one\nbravo two\ncharlie three']);
  }, variant: android);

  testWidgets('dragging the end handle from "two" to the end of "charlie" '
      r'copies exactly "two\ncharlie"', (tester) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    await _pumpApp(tester, _threeLineRegion());

    await _longPressWord(tester, 'bravo two', 'two');
    final handles = await _pumpUntilHandlesVisible(tester);
    // The end (right) handle is the one further right; its anchor is its
    // top-left corner, which sits on the current end selection point.
    final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);

    final charlie = _wordRect(tester, 'charlie three', 'charlie');
    final target = Offset(charlie.right, charlie.bottom);
    // tester.drag delivers the full offset (touch slop included), so the
    // handle anchor moves by exactly target - anchor.
    await tester.dragFrom(endHandle.center, target - endHandle.topLeft);
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget, reason: 'toolbar after drag');
    await _tapToolbar(tester, 'Copy');

    expect(copied, ['two\ncharlie']);
  }, variant: android);

  testWidgets('a SelectionContainer.disabled child is left out and an '
      'in-Text blank line is kept', (tester) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    await _pumpApp(
      tester,
      const SeparatedSelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('alpha one'),
            SelectionContainer.disabled(child: Text('hidden label')),
            Text('bravo\n\ntwo'),
          ],
        ),
      ),
    );

    await _selectAllAndCopy(tester, 'alpha one', 'alpha');

    expect(copied, ['alpha one\nbravo\n\ntwo']);
  }, variant: android);

  testWidgets('two stacked regions select and copy independently', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    await _pumpApp(tester, _twoRegions());

    await _selectAllAndCopy(tester, 'first region text', 'first');
    expect(copied, ['first region text']);

    // Android Copy clears the selection, so select in the first region again.
    await _longPressWord(tester, 'first region text', 'first');
    await _pumpUntilHandlesVisible(tester);

    await _longPressWord(tester, 'second region text', 'second');
    final handles = await _pumpUntilHandlesVisible(tester);
    final secondBounds = tester.getRect(find.byKey(_secondRegionKey));
    for (final handle in handles) {
      expect(
        _containsRect(secondBounds, handle),
        isTrue,
        reason: 'handle $handle within second region $secondBounds',
      );
    }

    await _tapToolbar(tester, 'Copy');
    expect(copied, ['first region text', 'second']);
  }, variant: android);

  testWidgets('tapping an inert spot outside every region clears the '
      'selection', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpApp(tester, _twoRegions());

    await _longPressWord(tester, 'first region text', 'first');
    await _pumpUntilHandlesVisible(tester);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byKey(_spacerKey)));
    await tester.pumpAndSettle();

    _expectNoSelectionUi(tester);
    expect(_paragraph(tester, 'first region text').selections, isEmpty);
  }, variant: android);

  testWidgets('a quick tap on a gesture child inside another region clears '
      'the selection and fires the child', (tester) async {
    addTearDown(tester.view.reset);
    var linkTaps = 0;
    await _pumpApp(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeparatedSelectionArea(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('first region text'),
            ),
          ),
          const SizedBox(width: 400, height: 200),
          SeparatedSelectionArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: GestureDetector(
                onTap: () => linkTaps++,
                child: const Text('second region link'),
              ),
            ),
          ),
        ],
      ),
    );

    await _longPressWord(tester, 'first region text', 'first');
    await _pumpUntilHandlesVisible(tester);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('second region link'));
    await tester.pumpAndSettle();

    expect(linkTaps, 1);
    _expectNoSelectionUi(tester);
    expect(_paragraph(tester, 'first region text').selections, isEmpty);
  }, variant: android);

  testWidgets('dragging the end handle from the edge of its touch target '
      'over another region extends the selection', (tester) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    // No padding between the regions, so the first region's end handle
    // hangs below its text line over the second region. The spacer leaves
    // room for the toolbar above the selection, clear of the handle.
    await _pumpApp(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 200),
          SeparatedSelectionArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: Text('first region text'),
            ),
          ),
          SeparatedSelectionArea(
            key: _secondRegionKey,
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Text('second region text second region text'),
            ),
          ),
        ],
      ),
    );

    await _longPressWord(tester, 'first region text', 'first');
    final handles = await _pumpUntilHandlesVisible(tester);
    final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);
    // Inside the handle's 48 px touch target but below the painted handle.
    final start = endHandle.bottomCenter + const Offset(0, 6);
    expect(
      (start - endHandle.center).distance,
      lessThan(kMinInteractiveDimension / 2),
      reason: 'start point inside the handle touch target',
    );
    expect(
      tester.getRect(find.byKey(_secondRegionKey)).contains(start),
      isTrue,
      reason: 'start point over the second region',
    );

    final region = _wordRect(tester, 'first region text', 'region');
    final target = Offset(region.right, region.bottom);
    await tester.dragFrom(start, target - endHandle.topLeft);
    await tester.pumpAndSettle();

    expect(_paragraph(tester, 'first region text').selections, isNotEmpty);
    await _tapToolbar(tester, 'Copy');
    expect(copied, ['first region']);
  }, variant: android);

  testWidgets('a parent rebuild keeps the delegate and the selection; '
      'unmounting disposes the delegate', (tester) async {
    addTearDown(tester.view.reset);
    final copied = _captureClipboard(tester);
    var color = Colors.black;
    late StateSetter setParentState;
    await _pumpApp(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setParentState = setState;
          return SeparatedSelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('alpha one', style: TextStyle(color: color)),
                Text('bravo two', style: TextStyle(color: color)),
              ],
            ),
          );
        },
      ),
    );

    await _longPressWord(tester, 'alpha one', 'alpha');
    await _tapToolbar(tester, 'Select all');
    final delegateBefore = _regionDelegate(tester);

    setParentState(() => color = Colors.red);
    await tester.pump();

    expect(identical(_regionDelegate(tester), delegateBefore), isTrue);
    await _tapToolbar(tester, 'Copy');
    expect(copied, ['alpha one\nbravo two']);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const Scaffold()),
    );
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(delegateBefore),
      throwsFlutterError,
    );
  }, variant: android);

  testWidgets('a vertical drag on region text scrolls the list without '
      'selecting', (tester) async {
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpApp(
      tester,
      ListView.builder(
        controller: controller,
        itemCount: 40,
        itemBuilder: (context, index) => SizedBox(
          height: 60,
          child: index == 2
              ? const SeparatedSelectionArea(child: Text('scroll me'))
              : Text('item $index'),
        ),
      ),
    );

    await tester.drag(find.text('scroll me'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    _expectNoSelectionUi(tester);
  }, variant: android);
}
