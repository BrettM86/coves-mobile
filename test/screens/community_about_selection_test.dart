import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/community_header.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/community_feed_harness.dart';
import '../test_helpers/test_mocks.dart';

const _description =
    'Rock pools and the creatures in them.\nNew members welcome.';

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

/// The description `Text` inside the community header.
Finder _headerDescription() => find.descendant(
  of: find.byType(CommunityHeader),
  matching: find.text(_description),
);

/// The description `Text` on the About tab: the same text outside the header.
Finder _aboutDescription() => find.byElementPredicate(
  (element) =>
      element.widget is Text &&
      (element.widget as Text).data == _description &&
      element.findAncestorWidgetOfExactType<CommunityHeader>() == null,
);

/// Global center of [word] inside the paragraph that [text] renders.
Offset _wordCenter(WidgetTester tester, Finder text, String word) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final start = _description.indexOf(word);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + word.length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return paragraph.localToGlobal(local.center);
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

/// Number of Material selection handles drawn with a non-zero opacity.
int _visibleHandleCount(WidgetTester tester) {
  final handles = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_TextSelectionHandlePainter',
  );
  return handles.evaluate().where((element) {
    var visible = true;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition && widget.opacity.value == 0) {
        visible = false;
        return false;
      }
      return true;
    });
    return visible;
  }).length;
}

/// Pumps the community screen for `tidepools` on its Feed tab.
Future<void> _pumpCommunity(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A running app is resumed, which is when SelectableRegion clears a
  // selection on focus loss.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  final api = MockCovesApiService();
  when(api.getCommunity(community: anyNamed('community'))).thenAnswer(
    (_) async => CommunityView(
      did: communityFeedTestDid,
      name: 'tidepools',
      displayName: 'Tidepools',
      description: _description,
      subscriberCount: 1234,
    ),
  );
  when(
    api.getCommunityFeed(
      community: anyNamed('community'),
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
    ),
  ).thenAnswer((_) async => TimelineResponse(feed: []));

  await pumpCommunityFeedScreen(tester, api);
  await tester.pumpAndSettle();
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
}

Future<void> _openAboutTab(WidgetTester tester) async {
  await tester.tap(find.text('About'));
  await tester.pumpAndSettle();
  await tester.pump();
}

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets(
    'Select all then Copy on the About-tab description copies only the '
    'description',
    (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpCommunity(tester);
      await _openAboutTab(tester);

      await tester.longPressAt(
        _wordCenter(tester, _aboutDescription(), 'creatures'),
      );
      await tester.pumpAndSettle();
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [
        'Rock pools and the creatures in them.\nNew members welcome.',
      ]);
    },
    variant: android,
  );

  testWidgets('long-pressing the header description on the Feed tab shows no '
      'selection', (tester) async {
    await _pumpCommunity(tester);

    await tester.longPressAt(
      _wordCenter(tester, _headerDescription(), 'creatures'),
    );
    await tester.pumpAndSettle();

    expect(_visibleHandleCount(tester), 0, reason: 'selection handles');
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
  }, variant: android);

  testWidgets(
    'the About-tab description is exposed to semantics as its full text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCommunity(tester);
      await _openAboutTab(tester);

      expect(_aboutDescription(), findsOneWidget);
      expect(
        tester.getSemantics(
          find.descendant(
            of: _aboutDescription(),
            matching: find.byType(RichText),
          ),
        ),
        isSemantics(
          label: 'Rock pools and the creatures in them.\nNew members welcome.',
        ),
      );
      semantics.dispose();
    },
    variant: android,
  );
}
