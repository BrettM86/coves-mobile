import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/moderation/moderation_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/test_mocks.dart';

const _reasons = [
  ModerationReason.spam,
  ModerationReason.harassment,
  ModerationReason.doxing,
  ModerationReason.illegalContent,
  ModerationReason.ruleViolation,
  ModerationReason.moderatorDiscretion,
];

Finder get _removeButton => find.ancestor(
  of: find.text('Remove'),
  matching: find.bySubtype<ButtonStyleButton>(),
);

const _failureMessage = "Couldn't remove this post. Try again.";

Future<List<(ModerationReason, String?)>> _openSheet(
  WidgetTester tester, {
  Future<void> Function(ModerationReason reason, String? privateNote)? onSubmit,
}) async {
  final submissions = <(ModerationReason, String?)>[];
  // Signed out, so the session never changes under these tests.
  final apiService = tokenlessApiService();
  final auth = FakeAuthProvider();
  final authority = ViewerAuthorityProvider(
    apiService: apiService,
    authProvider: auth,
  );
  addTearDown(() {
    authority.dispose();
    auth.dispose();
    apiService.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ModerationActionSheet.show<void>(
              context,
              title: 'Remove post',
              confirmLabel: 'Remove',
              reasons: _reasons,
              failureMessage: _failureMessage,
              authority: authority,
              onSubmit: (reason, privateNote) async {
                submissions.add((reason, privateNote));
                await onSubmit?.call(reason, privateNote);
              },
            ),
            child: const Text('Open moderation'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open moderation'));
  await tester.pumpAndSettle();
  return submissions;
}

Future<List<(ModerationReason, String?)>> _openSheetWithSpamSelected(
  WidgetTester tester, {
  Future<void> Function(ModerationReason reason, String? privateNote)? onSubmit,
}) async {
  final submissions = await _openSheet(tester, onSubmit: onSubmit);
  expect(find.text('Spam'), findsOneWidget);
  await tester.tap(find.text('Spam'));
  await tester.pumpAndSettle();
  return submissions;
}

void main() {
  testWidgets('B3 1,000 ASCII characters enable Remove', (tester) async {
    final submissions = await _openSheetWithSpamSelected(tester);
    await tester.enterText(find.byType(TextField), 'a' * 1000);
    await tester.pump();
    expect(
      tester.widget<ButtonStyleButton>(_removeButton).onPressed,
      isNotNull,
    );
    expect(find.text('Note is too long'), findsNothing);
    await tester.tap(_removeButton);
    await tester.pumpAndSettle();
    expect(submissions, [(ModerationReason.spam, 'a' * 1000)]);
  });

  testWidgets('B3 1,001 ASCII characters disable Remove without truncation', (
    tester,
  ) async {
    await _openSheetWithSpamSelected(tester);
    await tester.enterText(find.byType(TextField), 'a' * 1001);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a' * 1001,
    );
    expect(tester.widget<ButtonStyleButton>(_removeButton).onPressed, isNull);
    expect(find.text('Note is too long'), findsOneWidget);
  });

  testWidgets('B3 1,000 👍🏽 graphemes (8,000 bytes) enable Remove', (
    tester,
  ) async {
    await _openSheetWithSpamSelected(tester);
    await tester.enterText(find.byType(TextField), '👍🏽' * 1000);
    await tester.pump();
    expect(
      tester.widget<ButtonStyleButton>(_removeButton).onPressed,
      isNotNull,
    );
    expect(find.text('Note is too long'), findsNothing);
  });

  testWidgets('B4 400 family emoji (10,000 bytes) enable Remove', (
    tester,
  ) async {
    final submissions = await _openSheetWithSpamSelected(tester);
    await tester.enterText(find.byType(TextField), '👨‍👩‍👧‍👦' * 400);
    await tester.pump();
    expect(
      tester.widget<ButtonStyleButton>(_removeButton).onPressed,
      isNotNull,
    );
    expect(find.text('Note is too long'), findsNothing);
    await tester.tap(_removeButton);
    await tester.pumpAndSettle();
    expect(submissions, [(ModerationReason.spam, '👨‍👩‍👧‍👦' * 400)]);
  });

  testWidgets('B4 401 family emoji exceed 10,000 bytes without truncation', (
    tester,
  ) async {
    await _openSheetWithSpamSelected(tester);
    await tester.enterText(find.byType(TextField), '👨‍👩‍👧‍👦' * 401);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '👨‍👩‍👧‍👦' * 401,
    );
    expect(tester.widget<ButtonStyleButton>(_removeButton).onPressed, isNull);
    expect(find.text('Note is too long'), findsOneWidget);
  });
  group('keyboard-constrained layout', () {
    void useLandscapePhoneWithKeyboard(WidgetTester tester, double inset) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
    }

    testWidgets('a short window with the keyboard up scrolls to Remove', (
      tester,
    ) async {
      useLandscapePhoneWithKeyboard(tester, 200);
      final submissions = await _openSheet(tester);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Spam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_removeButton);
      await tester.pumpAndSettle();
      await tester.tap(_removeButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(submissions, [(ModerationReason.spam, null)]);
    });

    testWidgets('a keyboard taller than 80% of the window does not throw', (
      tester,
    ) async {
      useLandscapePhoneWithKeyboard(tester, 350);
      await _openSheet(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'W7 enlarged failure footer scrolls above keyboard and retries',
      (tester) async {
        useLandscapePhoneWithKeyboard(tester, 0);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final submissions = await _openSheet(
          tester,
          onSubmit: (_, _) =>
              Future<void>.error(ApiException('Unavailable', statusCode: 503)),
        );
        await tester.ensureVisible(find.text('Spam'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Spam'));
        await tester.pumpAndSettle();
        await tester.tap(_removeButton);
        await tester.pumpAndSettle();
        expect(find.text(_failureMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_removeButton);
        await tester.pumpAndSettle();
        final rect = tester.getRect(_removeButton);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(140));
        await tester.tap(_removeButton);
        await tester.pumpAndSettle();
        expect(submissions, [
          (ModerationReason.spam, null),
          (ModerationReason.spam, null),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('submission errors', () {
    const privateNote = 'private moderator note 7f3a';

    Future<List<FlutterErrorDetails>> submitCapturingReports(
      WidgetTester tester,
      Object error,
    ) async {
      await _openSheetWithSpamSelected(
        tester,
        onSubmit: (_, _) => Future<void>.error(error),
      );
      await tester.enterText(find.byType(TextField), privateNote);
      await tester.pump();
      final reports = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        await tester.tap(_removeButton);
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = originalOnError;
      }
      return reports;
    }

    testWidgets('an unexpected error is reported without the note', (
      tester,
    ) async {
      final error = StateError('Unknown removal outcome');
      final reports = await submitCapturingReports(tester, error);

      expect(reports, hasLength(1));
      expect(reports.single.exception, same(error));
      expect(reports.single.toString(), isNot(contains(privateNote)));
      expect(find.text(_failureMessage), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(_removeButton).onPressed,
        isNotNull,
      );
    });

    testWidgets('an ApiException shows the failure without a report', (
      tester,
    ) async {
      final reports = await submitCapturingReports(
        tester,
        ApiException('Server unavailable', statusCode: 503),
      );

      expect(reports, isEmpty);
      expect(find.text(_failureMessage), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(_removeButton).onPressed,
        isNotNull,
      );
    });
  });

  group('a session change while the sheet is closing', () {
    final rows = [
      (
        name: 'B8 after Close',
        closeSheet: (WidgetTester tester) async {
          await tester.tap(find.byTooltip('Close'));
        },
      ),
      (
        name: 'B8 after a successful submit that closes',
        closeSheet: (WidgetTester tester) async {
          await tester.tap(find.text('Spam'));
          await tester.pumpAndSettle();
          await tester.tap(_removeButton);
        },
      ),
      (
        // System back closes the sheet through the route, not the sheet's
        // own close.
        name: 'B8 after system back',
        closeSheet: (WidgetTester tester) async {
          await tester.binding.handlePopRoute();
        },
      ),
    ];
    for (final row in rows) {
      testWidgets('${row.name}, the route the sheet was opened from stays', (
        tester,
      ) async {
        final apiService = MockCovesApiService();
        when(apiService.getViewerAuthority()).thenAnswer((_) async => true);
        final auth = FakeAuthProvider(
          signedInDid: 'did:plc:admin',
          signedInHandle: 'admin.coves.test',
        );
        final authority = ViewerAuthorityProvider(
          apiService: apiService,
          authProvider: auth,
        );
        addTearDown(() {
          authority.dispose();
          auth.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (baseContext) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(baseContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (pushedContext) => TextButton(
                            onPressed: () => ModerationActionSheet.show<void>(
                              pushedContext,
                              title: 'Remove post',
                              confirmLabel: 'Remove',
                              reasons: _reasons,
                              failureMessage: _failureMessage,
                              authority: authority,
                              onSubmit: (_, _) async {},
                              onResult: (_) async =>
                                  const ModerationSheetDecision(),
                            ),
                            child: const Text('Pushed route'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Base route'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Base route'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pushed route'));
        await tester.pumpAndSettle();

        await row.closeSheet(tester);
        // Let the sheet start closing without finishing its animation.
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 50));
        final sheet = find.bySubtype<ModerationActionSheet>();
        expect(sheet, findsOneWidget, reason: 'still animating closed');
        expect(
          ModalRoute.of(tester.element(sheet))!.isCurrent,
          isFalse,
          reason: 'the sheet route is already closing',
        );

        auth.setSignedInDid(null);
        await tester.pumpAndSettle();

        expect(find.bySubtype<ModerationActionSheet>(), findsNothing);
        expect(find.text('Pushed route'), findsOneWidget);
        expect(find.text('Base route'), findsNothing);
      });
    }
  });
}
