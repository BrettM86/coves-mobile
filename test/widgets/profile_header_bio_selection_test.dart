import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/widgets/profile_header.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selection on the profile bio: the bio in [ProfileDetails] is a selection
/// region of its own, while the DID row in [ProfileHeader] keeps tap-to-copy.

const _bio = 'Writes about tide pools.\n\nLives by the sea.';
const _did = 'did:plc:bioowner123';

UserProfile _profile() => UserProfile(
  did: _did,
  handle: 'bio.owner.test',
  displayName: 'Bio Owner',
  bio: _bio,
  createdAt: DateTime.utc(2024, 3, 15, 12),
  stats: const ProfileStats(
    postCount: 12,
    commentCount: 34,
    membershipCount: 5,
  ),
);

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

/// Pumps the profile screen skeleton (copied from `pumpAt` in
/// profile_header_test.dart) with the bio fixture.
Future<void> _pumpProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The host test binding starts with no lifecycle state; a running app is
  // resumed, which is when SelectableRegion clears a selection on focus loss.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  final profile = _profile();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ProfileHeader.expandedHeightFor(context),
                flexibleSpace: ProfileHeader(profile: profile),
              ),
              SliverToBoxAdapter(child: ProfileDetails(profile: profile)),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      ),
    ),
  );
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
}

RenderParagraph _bioParagraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(_bio), matching: find.byType(RichText)),
    );

/// Global rect covering [word] inside the bio.
Rect _bioWordRect(WidgetTester tester, String word) {
  final paragraph = _bioParagraph(tester);
  final start = _bio.indexOf(word);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + word.length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

/// The bio's selected ranges as `[start, end)` pairs, direction ignored.
List<(int, int)> _bioSelectedRanges(WidgetTester tester) =>
    _bioParagraph(tester).selections
        .map((selection) => (selection.start, selection.end))
        .toList();

Future<void> _longPressBioWord(WidgetTester tester, String word) async {
  await tester.longPressAt(_bioWordRect(tester, word).center);
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

Future<void> _pumpUntilHandlesVisible(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (_visibleHandleRects(tester).length == 2) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    _visibleHandleRects(tester),
    hasLength(2),
    reason: 'visible selection handles',
  );
}

/// Long-press `tide`, check the word selection and toolbar, then Select all
/// and Copy, and check the clipboard holds exactly the bio.
Future<void> _expectBioSelectAllCopy(
  WidgetTester tester,
  String selectAllLabel,
) async {
  final copied = _captureClipboard(tester);
  await _pumpProfile(tester);

  await _longPressBioWord(tester, 'tide');

  expect(_bioSelectedRanges(tester), [(13, 17)], reason: '"tide" selected');
  expect(find.text('Copy'), findsOneWidget);
  expect(find.text(selectAllLabel), findsOneWidget);

  await _tapToolbar(tester, selectAllLabel);
  await _tapToolbar(tester, 'Copy');

  expect(copied, ['Writes about tide pools.\n\nLives by the sea.']);
}

void main() {
  // TargetPlatformVariant pins the platform and resets
  // debugDefaultTargetPlatformOverride before the binding's debug-variable
  // check (a plain tearDown runs after it).
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'Android: long-press "tide" in the bio, Select all, Copy copies exactly '
    'the bio',
    (tester) => _expectBioSelectAllCopy(tester, 'Select all'),
    variant: android,
  );

  testWidgets(
    'iOS: long-press "tide" in the bio, Select All, Copy copies exactly '
    'the bio',
    (tester) => _expectBioSelectAllCopy(tester, 'Select All'),
    variant: iOS,
  );

  testWidgets('tapping the DID row with a bio selection clears the selection '
      'and copies the DID', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpProfile(tester);

    // `sea` is on the bio's last line, so the toolbar opens below the DID
    // row; a first-line word puts the toolbar over the DID row.
    await _longPressBioWord(tester, 'sea');
    await _pumpUntilHandlesVisible(tester);
    expect(find.text('Copy'), findsOneWidget);

    final didCenter = tester.getCenter(find.text(_did));
    final didParagraph = tester.renderObject(find.text(_did));
    expect(
      tester
          .hitTestOnBinding(didCenter)
          .path
          .any((entry) => entry.target == didParagraph),
      isTrue,
      reason: 'the tap reaches the DID text, not the toolbar',
    );
    await tester.tapAt(didCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
    expect(_bioSelectedRanges(tester), isEmpty);
    expect(copied.last, 'did:plc:bioowner123');
    expect(find.text('DID copied to clipboard'), findsOneWidget);
  }, variant: android);

  testWidgets('semantics: the bio is one node labelled exactly the bio, and '
      'the DID row keeps its tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpProfile(tester);

    expect(
      find.semantics.byPredicate(
        (node) => node.label == 'Writes about tide pools.\n\nLives by the sea.',
      ),
      findsOne,
    );
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label.contains('did:plc:bioowner123') &&
            node.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
      findsOne,
    );
    semantics.dispose();
  }, variant: android);
}
