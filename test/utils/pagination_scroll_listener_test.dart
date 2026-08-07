// RED-phase spec for the shared "near the bottom" pagination trigger.
//
// Compile-red until lib/utils/pagination_scroll_listener.dart exists. Kept
// self-contained so the rest of the suite still compiles.
//
// Mirrors feed_screen.dart:152-170 (the only current implementation that
// throttles) and replaces:
//   - community_feed_screen.dart:96-101 (-200px, no throttle)
//   - communities_see_all_screen.dart:90-97 (percentage trigger)
//   - profile_screen.dart:509/590 (build-phase triggers from itemBuilder)
//
// The listener attaches to an externally-owned ScrollController and must
// never dispose it.

import 'package:coves_flutter/utils/pagination_scroll_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-driven clock so throttle windows are deterministic — the widget
/// tester's fake async does not move DateTime.now().
class _FakeClock {
  DateTime value = DateTime.utc(2026);

  DateTime now() => value;

  void advance(Duration by) => value = value.add(by);
}

void main() {
  late ScrollController controller;
  late _FakeClock clock;
  late int calls;

  setUp(() {
    controller = ScrollController();
    clock = _FakeClock();
    calls = 0;
  });

  PaginationScrollListener buildListener({
    double threshold = 200,
    Duration throttle = const Duration(milliseconds: 100),
  }) {
    return PaginationScrollListener(
      controller: controller,
      onLoadMore: () => calls++,
      threshold: threshold,
      throttle: throttle,
      clock: clock.now,
    );
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemBuilder: (context, index) => SizedBox(
              height: 100,
              child: Text('item $index'),
            ),
          ),
        ),
      ),
    );
  }

  double bottomMinus(double offset) {
    return controller.position.maxScrollExtent - offset;
  }

  testWidgets('does not fire before attach', (tester) async {
    await pumpList(tester);
    buildListener();

    controller.jumpTo(bottomMinus(10));
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('fires when scrolled within 200px of the bottom', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(150));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('does not fire further than 200px from the bottom', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(201));
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('fires exactly at the threshold boundary', (tester) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(200));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('honours a custom threshold', (tester) async {
    await pumpList(tester);
    final listener = buildListener(threshold: 600)..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(500));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('throttles repeat triggers inside the 100ms window', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(150));
    await tester.pump();
    clock.advance(const Duration(milliseconds: 40));
    controller.jumpTo(bottomMinus(120));
    await tester.pump();
    clock.advance(const Duration(milliseconds: 40));
    controller.jumpTo(bottomMinus(90));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('fires again once the throttle window has passed', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(150));
    await tester.pump();
    clock.advance(const Duration(milliseconds: 150));
    controller.jumpTo(bottomMinus(120));
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets('stops firing after detach', (tester) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(150));
    await tester.pump();
    expect(calls, 1);

    listener.detach();
    clock.advance(const Duration(milliseconds: 500));
    controller.jumpTo(bottomMinus(50));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('re-attaching resumes firing', (tester) async {
    await pumpList(tester);
    final listener = buildListener()..attach();
    addTearDown(listener.dispose);

    listener
      ..detach()
      ..attach();
    controller.jumpTo(bottomMinus(150));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('attach is idempotent (no double fire)', (tester) async {
    await pumpList(tester);
    final listener = buildListener()
      ..attach()
      ..attach();
    addTearDown(listener.dispose);

    controller.jumpTo(bottomMinus(150));
    await tester.pump();

    expect(calls, 1);
  });

  group('checkNow', () {
    // Regression: the profile screen used to trigger pagination from its
    // item builder, which auto-loaded when a short first page did not fill
    // the viewport. A scroll listener alone never fires in that case, so
    // adopting screens ask explicitly once a page has landed.
    Future<void> pumpShortList(WidgetTester tester, {int items = 3}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: controller,
              itemCount: items,
              itemBuilder: (context, index) => SizedBox(
                height: 100,
                child: Text('item $index'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('fires when the content does not fill the viewport', (
      tester,
    ) async {
      await pumpShortList(tester);
      final listener = buildListener()..attach();
      addTearDown(listener.dispose);

      expect(controller.position.maxScrollExtent, 0);

      listener.checkNow();

      expect(calls, 1);
    });

    testWidgets('does not fire when the content is far from the bottom', (
      tester,
    ) async {
      await pumpList(tester);
      final listener = buildListener()..attach();
      addTearDown(listener.dispose);

      listener.checkNow();

      expect(calls, 0);
    });

    testWidgets('shares the throttle window with scroll triggers', (
      tester,
    ) async {
      await pumpShortList(tester);
      final listener = buildListener()..attach();
      addTearDown(listener.dispose);

      listener
        ..checkNow()
        ..checkNow();

      expect(calls, 1);

      clock.advance(const Duration(milliseconds: 150));
      listener.checkNow();

      expect(calls, 2);
    });

    testWidgets('does nothing before attach or after detach', (tester) async {
      await pumpShortList(tester);
      final listener = buildListener();
      addTearDown(listener.dispose);

      listener.checkNow();
      expect(calls, 0);

      listener
        ..attach()
        ..detach()
        ..checkNow();

      expect(calls, 0);
    });

    testWidgets('does nothing without a scroll client', (tester) async {
      final listener = buildListener()..attach();
      addTearDown(listener.dispose);

      expect(controller.hasClients, isFalse);
      expect(listener.checkNow, returnsNormally);
      expect(calls, 0);
    });
  });

  testWidgets('dispose does not dispose the borrowed controller', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();

    listener.dispose();

    // Still usable by its owner.
    controller.jumpTo(bottomMinus(150));
    await tester.pump();
    expect(calls, 0);
    expect(controller.hasClients, isTrue);
  });

  testWidgets('dispose is safe after the controller was disposed', (
    tester,
  ) async {
    await pumpList(tester);
    final listener = buildListener()..attach();

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();

    expect(listener.dispose, returnsNormally);
    expect(listener.dispose, returnsNormally);
  });
}
