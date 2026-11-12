// The automatic Bluesky profile import offer appears over the shell for a
// signed-in user, through the real offer provider.

import 'dart:async';

import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/bluesky_import_test_helpers.dart';
import '../test_helpers/notifications_shell_harness.dart';
import '../test_helpers/pump_helpers.dart';

const String blueskyName = 'Alice on Bluesky';
const String blueskyBio = 'Bio from Bluesky';

/// Display name and banner are already set on Coves; bio and avatar are
/// empty.
const BlueskyProfileImport mixedOffer = BlueskyProfileImport(
  status: BlueskyProfileImportStatus.offer,
  fields: [
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.displayName,
      bluesky: blueskyName,
      covesIsEmpty: false,
    ),
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.description,
      bluesky: blueskyBio,
      covesIsEmpty: true,
    ),
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.avatar,
      blueskyImageUrl: 'https://cdn.bsky.app/img/avatar/plain/did:plc:alice/bafkreiavatar@jpeg',
      covesIsEmpty: true,
    ),
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.banner,
      blueskyImageUrl: 'https://cdn.bsky.app/img/banner/plain/did:plc:alice/bafkreibanner@jpeg',
      covesIsEmpty: false,
    ),
  ],
);

void main() {
  late NotificationsShellHarness harness;

  setUp(() {
    harness = NotificationsShellHarness(count: 0);
    when(harness.api.getBlueskyProfileImport())
        .thenAnswer((_) async => mixedOffer);
    when(harness.api.importBlueskyProfile(any)).thenAnswer(
      (call) async =>
          call.positionalArguments.first as List<BlueskyProfileField>,
    );
    when(harness.api.dismissBlueskyProfileImport()).thenAnswer((_) async {});
  });

  Future<void> mountShell(WidgetTester tester) async {
    useShellViewport(tester, const Size(540, 960));
    await harness.mount(tester);
    await pumpFrames(tester);
  }

  testWidgets('the offer appears over the shell with only the fields empty '
      'on Coves, and Import profile imports them and confirms', (tester) async {
    try {
      await mountShell(tester);

      expect(blueskyImportCard, findsOneWidget);
      expect(
        blueskyImportField(BlueskyProfileField.description),
        findsOneWidget,
      );
      expect(blueskyImportField(BlueskyProfileField.avatar), findsOneWidget);
      expect(blueskyImportField(BlueskyProfileField.displayName), findsNothing);
      expect(blueskyImportField(BlueskyProfileField.banner), findsNothing);
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.description),
        findsNothing,
      );
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.avatar),
        findsNothing,
      );
      expect(find.text(blueskyBio), findsOneWidget);
      expect(find.text(blueskyName), findsNothing);

      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await pumpFrames(tester);

      verify(
        harness.api.importBlueskyProfile([
          BlueskyProfileField.description,
          BlueskyProfileField.avatar,
        ]),
      ).called(1);
      expect(blueskyImportCard, findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Imported your Bluesky profile.'),
        ),
        findsOneWidget,
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('No thanks closes the offer and dismisses it on the server', (
    tester,
  ) async {
    try {
      await mountShell(tester);
      expect(blueskyImportCard, findsOneWidget);

      await tester.tap(find.text('No thanks'));
      await pumpFrames(tester);

      expect(blueskyImportCard, findsNothing);
      verify(harness.api.dismissBlueskyProfileImport()).called(1);
      verifyNever(harness.api.importBlueskyProfile(any));
    } finally {
      await harness.dispose(tester);
    }
  });
  testWidgets('an offer arriving while a route covers the shell waits until '
      'the shell is current again', (tester) async {
    final pendingOffer = Completer<BlueskyProfileImport>();
    when(harness.api.getBlueskyProfileImport())
        .thenAnswer((_) => pendingOffer.future);
    try {
      await mountShell(tester);
      expect(blueskyImportCard, findsNothing);

      final navigator = Navigator.of(
        tester.element(find.byType(MainShellScreen)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covering page')),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(find.text('Covering page'), findsOneWidget);

      pendingOffer.complete(mixedOffer);
      await pumpFrames(tester);

      expect(
        blueskyImportCard,
        findsNothing,
        reason: 'the shell is covered by the pushed route',
      );

      navigator.pop();
      await pumpFrames(tester);

      expect(find.text('Covering page'), findsNothing);
      expect(blueskyImportCard, findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}
