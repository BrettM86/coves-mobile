import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/widgets/share_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A `LinkSharer` that records dispatches instead of opening a native sheet.
class RecordingLinkSharer implements LinkSharer {
  final List<String> sharedUrls = [];
  final List<Rect> sharePositionOrigins = [];

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    sharedUrls.add(url);
    sharePositionOrigins.add(sharePositionOrigin);
  }
}

/// A `LinkSharer` that fails the way the platform channel can.
class FailingLinkSharer implements LinkSharer {
  FailingLinkSharer(this.error);

  final Exception error;
  int calls = 0;

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    calls++;
    throw error;
  }
}

/// A `LinkSharer` whose dispatch stays in flight until the test settles it.
class PendingLinkSharer implements LinkSharer {
  final Completer<void> completer = Completer<void>();
  int calls = 0;

  @override
  Future<void> shareLink(String url, {required Rect sharePositionOrigin}) {
    calls++;
    return completer.future;
  }
}

void main() {
  // Literal, never produced by the code under test.
  const shareUrl = 'https://coves.social/c/gaming';

  late RecordingLinkSharer linkSharer;

  setUp(() {
    linkSharer = RecordingLinkSharer();
  });

  /// The tap handler asks for haptics, which has no platform behind it here.
  void stubHaptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) => Future<Object?>.value(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> pumpShareButton(
    WidgetTester tester, {
    required bool useIconButton,
  }) {
    stubHaptics(tester);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Provider<LinkSharer>.value(
            value: linkSharer,
            child: Center(
              child: ShareButton(url: shareUrl, useIconButton: useIconButton),
            ),
          ),
        ),
      ),
    );
  }

  group('ShareButton dispatch', () {
    testWidgets('the card style shares its url once, anchored on itself', (
      tester,
    ) async {
      await pumpShareButton(tester, useIconButton: false);

      final buttonRect = tester.getRect(find.byType(ShareButton));
      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(linkSharer.sharedUrls, [shareUrl]);
      expect(linkSharer.sharePositionOrigins, hasLength(1));

      // The iPad share sheet needs a real anchor rectangle, not Rect.zero.
      final origin = linkSharer.sharePositionOrigins.single;
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
      expect(origin, buttonRect);

      expect(find.text('Share coming soon!'), findsNothing);
    });

    testWidgets('the app bar style shares its url once, anchored on itself', (
      tester,
    ) async {
      await pumpShareButton(tester, useIconButton: true);

      final buttonRect = tester.getRect(find.byType(ShareButton));
      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(linkSharer.sharedUrls, [shareUrl]);
      expect(linkSharer.sharePositionOrigins, hasLength(1));

      final origin = linkSharer.sharePositionOrigins.single;
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
      expect(origin, buttonRect);

      expect(find.text('Share coming soon!'), findsNothing);
    });

    testWidgets('the sharer is looked up on tap, not while building', (
      tester,
    ) async {
      // Call sites that never get tapped must not require the provider, so
      // building without one above the button is not an error.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: Center(child: ShareButton(url: shareUrl))),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ShareButton), findsOneWidget);
    });
  });

  group('ShareButton failure paths', () {
    Future<void> pumpShareButtonWith(
      WidgetTester tester, {
      required LinkSharer sharer,
      String? url,
    }) {
      stubHaptics(tester);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Provider<LinkSharer>.value(
              value: sharer,
              child: Center(child: ShareButton(url: url)),
            ),
          ),
        ),
      );
    }

    testWidgets('a button with no link shares nothing and says so', (
      tester,
    ) async {
      await pumpShareButtonWith(tester, sharer: linkSharer);

      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(linkSharer.sharedUrls, isEmpty);
      expect(find.text("Couldn't create link"), findsOneWidget);
    });

    testWidgets('a sharer that fails in some other way does not report', (
      tester,
    ) async {
      // Only the platform channel failing is an expected outcome of sharing.
      // Anything else is a bug in the sharer, and swallowing it behind
      // "Couldn't share link" would hide it from crash reporting.
      final sharer = FailingLinkSharer(Exception('boom'));
      await pumpShareButtonWith(tester, sharer: sharer, url: shareUrl);

      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(sharer.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNotNull);
    });

    testWidgets('no sharer above the button surfaces the wiring mistake', (
      tester,
    ) async {
      // A screen that forgot the provider is a wiring bug, not a share that
      // failed: reporting it as one would leave the button permanently dead
      // with nothing pointing at the cause.
      stubHaptics(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: Center(child: ShareButton(url: shareUrl))),
        ),
      );

      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<ProviderNotFoundException>());
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a platform exception from the share sheet is reported too', (
      tester,
    ) async {
      final sharer = FailingLinkSharer(
        PlatformException(code: 'share_failed'),
      );
      await pumpShareButtonWith(tester, sharer: sharer, url: shareUrl);

      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(sharer.calls, 1);
      expect(find.text("Couldn't share link"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share that completes normally says nothing', (tester) async {
      // Dismissing the native sheet is indistinguishable from sharing: the
      // platform call simply completes, and that is not a failure.
      await pumpShareButtonWith(tester, sharer: linkSharer, url: shareUrl);

      await tester.tap(find.byType(ShareButton));
      await tester.pumpAndSettle();

      expect(linkSharer.sharedUrls, [shareUrl]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failure after the button is gone touches no dead context', (
      tester,
    ) async {
      final sharer = PendingLinkSharer();
      await pumpShareButtonWith(tester, sharer: sharer, url: shareUrl);

      await tester.tap(find.byType(ShareButton));
      await tester.pump();
      expect(
        sharer.calls,
        1,
        reason: 'the share must be in flight before the button is disposed',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      sharer.completer.completeError(PlatformException(code: 'share_failed'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
