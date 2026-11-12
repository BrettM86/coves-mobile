import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/bluesky_profile_import_dialog.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/bluesky_import_test_helpers.dart';
import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String markupLookingName = '**bold** <b>x</b>';
const String blueskyBio = 'Bio from Bluesky';
const String avatarUrl =
    'https://cdn.bsky.app/img/avatar/plain/did:plc:me/bafkreiavatar@jpeg';
const String bannerUrl =
    'https://cdn.bsky.app/img/banner/plain/did:plc:me/bafkreibanner@jpeg';

/// All four fields; display name and avatar start checked.
const List<BlueskyImportChoice> fourChoices = [
  BlueskyImportChoice(
    view: BlueskyProfileImportFieldView(
      field: BlueskyProfileField.displayName,
      bluesky: markupLookingName,
      covesIsEmpty: true,
    ),
    initiallyChecked: true,
  ),
  BlueskyImportChoice(
    view: BlueskyProfileImportFieldView(
      field: BlueskyProfileField.description,
      bluesky: blueskyBio,
      covesIsEmpty: false,
    ),
    initiallyChecked: false,
  ),
  BlueskyImportChoice(
    view: BlueskyProfileImportFieldView(
      field: BlueskyProfileField.avatar,
      blueskyImageUrl: avatarUrl,
      covesIsEmpty: true,
    ),
    initiallyChecked: true,
  ),
  BlueskyImportChoice(
    view: BlueskyProfileImportFieldView(
      field: BlueskyProfileField.banner,
      blueskyImageUrl: bannerUrl,
      covesIsEmpty: false,
    ),
    initiallyChecked: false,
  ),
];

bool _moveEnabled(WidgetTester tester) {
  expect(moveToCovesButton, findsOneWidget);
  return tester.widget<ButtonStyleButton>(moveToCovesButton).enabled;
}

bool _noThanksEnabled(WidgetTester tester) {
  expect(noThanksButton, findsOneWidget);
  return tester.widget<ButtonStyleButton>(noThanksButton).enabled;
}

/// Pumps [milliseconds] of frames, 20ms apart.
Future<void> _pumpFor(WidgetTester tester, int milliseconds) async {
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 20) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The Bluesky card's own focus node.
FocusNode _cardFocusNode(WidgetTester tester) =>
    Focus.of(tester.element(blueskyImportCard));

/// The focus node of [field]'s toggle.
FocusNode _fieldFocusNode(WidgetTester tester, BlueskyProfileField field) {
  final focus = find
      .descendant(of: blueskyImportField(field), matching: find.byType(Focus))
      .first;
  return Focus.of(
    tester.element(
      find
          .descendant(of: focus, matching: find.byWidgetPredicate((_) => true))
          .last,
    ),
  );
}

/// Presses Tab until [node] has keyboard focus.
Future<void> _tabTo(WidgetTester tester, FocusNode node) async {
  for (var step = 0; step < 30 && !node.hasPrimaryFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(node.hasPrimaryFocus, isTrue, reason: 'reachable with Tab');
}

/// How many copies of [text] show outside the resting Bluesky slot and the
/// Coves card: on the floating copy of the card.
int _floatingCopies(String text) =>
    find.text(text).evaluate().length -
    find
        .descendant(of: blueskyImportCard, matching: find.text(text))
        .evaluate()
        .length -
    find
        .descendant(of: covesImportTarget, matching: find.text(text))
        .evaluate()
        .length;

/// Which of the four fields show the "Off" badge, in display order.
List<bool> _offStates() => [
  for (final field in BlueskyProfileField.values)
    blueskyImportFieldOffBadge(field).evaluate().isNotEmpty,
];

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService apiService;
  late ViewerAuthorityProvider viewerAuthority;

  /// Every field list onImport was called with.
  late List<List<BlueskyProfileField>> importRequests;

  /// Each onImport call takes the next answer; an empty queue echoes the
  /// requested fields.
  late List<Future<List<BlueskyProfileField>> Function()> importAnswers;
  late int declineCount;

  /// Completes with the dialog's result once it closes.
  late Completer<List<BlueskyProfileField>?> dialogResult;

  setUp(() {
    auth = FakeAuthProvider(signedInDid: 'did:plc:me');
    apiService = MockCovesApiService();
    when(apiService.getViewerAuthority()).thenAnswer((_) async => false);
    viewerAuthority = ViewerAuthorityProvider(
      apiService: apiService,
      authProvider: auth,
    );
    importRequests = [];
    importAnswers = [];
    declineCount = 0;
  });

  tearDown(() {
    viewerAuthority.dispose();
    auth.dispose();
  });

  Future<List<BlueskyProfileField>> fakeImport(
    List<BlueskyProfileField> fields,
  ) {
    importRequests.add(List.of(fields));
    if (importAnswers.isEmpty) {
      return Future.value(fields);
    }
    return importAnswers.removeAt(0)();
  }

  Future<void> fakeDecline() async {
    declineCount++;
  }

  /// Pumps an app with an "Open" button and opens the dialog from it. The
  /// view is tall enough for the Bluesky card and the Coves target to both be
  /// on screen.
  Future<void> openDialog(
    WidgetTester tester, {
    List<BlueskyImportChoice> choices = fourChoices,
    bool withDecline = true,
    bool disableAnimations = false,
    Size viewSize = const Size(540, 1800),
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    dialogResult = Completer<List<BlueskyProfileField>?>();
    await tester.pumpWidget(
      ChangeNotifierProvider<ViewerAuthorityProvider>.value(
        value: viewerAuthority,
        child: ImageCacheScope(
          cacheManager: FakeImageCacheManager(),
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showBlueskyProfileImportDialog(
                        context,
                        choices: choices,
                        onImport: fakeImport,
                        onDecline: withDecline ? fakeDecline : null,
                      ).then(dialogResult.complete);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('W1 rendering and selection', () {
    testWidgets('the Bluesky card shows each choice, text verbatim and images '
        'with their literal URLs, above the hollow Coves target', (
      tester,
    ) async {
      await openDialog(tester);

      expect(blueskyImportCard, findsOneWidget);
      expect(
        find.descendant(of: blueskyImportCard, matching: find.text('Bluesky')),
        findsOneWidget,
      );

      // Markup-looking text is shown as plain text, not rendered.
      expect(
        find.descendant(
          of: blueskyImportField(BlueskyProfileField.displayName),
          matching: find.text(markupLookingName),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text(markupLookingName)).data,
        markupLookingName,
      );
      expect(
        find.descendant(
          of: blueskyImportField(BlueskyProfileField.description),
          matching: find.text(blueskyBio),
        ),
        findsOneWidget,
      );

      String previewUrl(BlueskyProfileField field) => tester
          .widget<CachedNetworkImage>(
            find.descendant(
              of: blueskyImportField(field),
              matching: find.byType(CachedNetworkImage),
            ),
          )
          .imageUrl;
      expect(previewUrl(BlueskyProfileField.avatar), avatarUrl);
      expect(previewUrl(BlueskyProfileField.banner), bannerUrl);

      expect(covesImportTarget, findsOneWidget);
    });

    testWidgets('shows the approved copy, and names the Coves card "Your '
        'Coves profile" for assistive tech only', (tester) async {
      final semantics = tester.ensureSemantics();
      await openDialog(tester);

      expect(find.text('Import your Bluesky profile'), findsOneWidget);
      expect(
        find.text(
          'Drag your Bluesky card onto your Coves profile to copy it over. '
          'Tap a field to leave it out.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Drag onto your Coves profile, or tap Import profile'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: covesImportTarget, matching: find.text('Coves')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: covesImportTarget,
          matching: find.text('Drop here'),
        ),
        findsOneWidget,
      );
      expect(find.text('No thanks'), findsOneWidget);
      expect(find.text('Import profile'), findsOneWidget);

      expect(find.text('Your Coves profile'), findsNothing);
      expect(find.bySemanticsLabel('Your Coves profile'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('each field toggle is named by its label alone', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openDialog(tester);

      expect(
        [
          for (final field in BlueskyProfileField.values)
            tester.getSemantics(blueskyImportField(field)).label,
        ],
        ['Display name', 'Bio', 'Avatar', 'Banner'],
      );
      semantics.dispose();
    });

    testWidgets('tapping a field toggles its Off badge, and Import profile '
        'sends exactly the included fields in display order and closes with '
        'the imported list', (tester) async {
      await openDialog(tester);

      // Off = !initiallyChecked.
      expect(_offStates(), [false, true, false, true]);

      // Tap order differs from display order.
      await tester.tap(blueskyImportField(BlueskyProfileField.banner));
      await tester.pump();
      await tester.tap(blueskyImportField(BlueskyProfileField.description));
      await tester.pump();
      await tester.tap(blueskyImportField(BlueskyProfileField.displayName));
      await tester.pump();

      expect(_offStates(), [true, false, false, false]);

      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(importRequests, [
        [
          BlueskyProfileField.description,
          BlueskyProfileField.avatar,
          BlueskyProfileField.banner,
        ],
      ]);
      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [
        BlueskyProfileField.description,
        BlueskyProfileField.avatar,
        BlueskyProfileField.banner,
      ]);
      expect(blueskyImportCard, findsNothing);
    });

    testWidgets('Import profile is disabled when every field is off', (
      tester,
    ) async {
      await openDialog(tester);
      expect(_moveEnabled(tester), isTrue);

      await tester.tap(blueskyImportField(BlueskyProfileField.displayName));
      await tester.pump();
      await tester.tap(blueskyImportField(BlueskyProfileField.avatar));
      await tester.pump();

      expect(_offStates(), [true, true, true, true]);
      expect(_moveEnabled(tester), isFalse);
    });
  });

  group('W1b dragging the card', () {
    testWidgets('dropping the card on the Coves target imports the included '
        'fields and closes with the imported list', (tester) async {
      await openDialog(tester);

      final distance =
          tester.getCenter(covesImportTarget).dy -
          tester.getCenter(blueskyImportCard).dy;
      await tester.drag(blueskyImportCard, Offset(0, distance));
      await _pumpFor(tester, 600);

      expect(importRequests, hasLength(1), reason: 'the card has landed');
      expect(dialogResult.isCompleted, isFalse, reason: 'seat pause');

      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(importRequests, [
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
      ]);
      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);
      expect(blueskyImportCard, findsNothing);
    });

    testWidgets('a short drag springs the card back without importing', (
      tester,
    ) async {
      await openDialog(tester);
      final restingTopLeft = tester.getTopLeft(blueskyImportCard);

      await tester.drag(blueskyImportCard, const Offset(0, 20));
      await tester.pumpAndSettle();

      expect(importRequests, isEmpty);
      expect(dialogResult.isCompleted, isFalse);
      expect(tester.getTopLeft(blueskyImportCard), restingTopLeft);
      expect(_moveEnabled(tester), isTrue);
    });

    testWidgets('a short fast fling released well before halfway springs the '
        'card back without importing', (tester) async {
      await openDialog(tester);
      final restingTopLeft = tester.getTopLeft(blueskyImportCard);
      final distance =
          tester.getCenter(covesImportTarget).dy -
          tester.getCenter(blueskyImportCard).dy;
      expect(distance, greaterThan(200), reason: '50px is well short of half');

      // A quick flick: a 50px throw at 3000 px/s, released far short of the
      // target.
      await tester.fling(blueskyImportCard, const Offset(0, 50), 3000);
      await tester.pumpAndSettle();

      expect(importRequests, isEmpty);
      expect(dialogResult.isCompleted, isFalse);
      expect(tester.getTopLeft(blueskyImportCard), restingTopLeft);
      expect(_moveEnabled(tester), isTrue);
    });

    testWidgets('on a 390x700 phone with a long bio the Coves card and both '
        'buttons are on screen without scrolling', (tester) async {
      final longBio = List.filled(
        40,
        'A long Bluesky bio line that wraps.',
      ).join(' ');
      await openDialog(
        tester,
        viewSize: const Size(390, 700),
        choices: [
          fourChoices[0],
          BlueskyImportChoice(
            view: BlueskyProfileImportFieldView(
              field: BlueskyProfileField.description,
              bluesky: longBio,
              covesIsEmpty: true,
            ),
            initiallyChecked: true,
          ),
          fourChoices[2],
          fourChoices[3],
        ],
      );

      for (final (name, finder) in [
        ('Coves card', covesImportTarget),
        ('No thanks', noThanksButton),
        ('Import profile', moveToCovesButton),
      ]) {
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(0), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(700), reason: name);
      }
    });

    testWidgets('a press that moves under 6px toggles the field under it; one '
        'that moves 6px or more drags and does not toggle', (tester) async {
      await openDialog(tester);
      final bio = blueskyImportField(BlueskyProfileField.description);
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.description),
        findsOneWidget,
      );

      var gesture = await tester.startGesture(tester.getCenter(bio));
      await gesture.moveBy(const Offset(3, 4));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.description),
        findsNothing,
        reason: 'a 5px press is a tap',
      );

      gesture = await tester.startGesture(tester.getCenter(bio));
      await gesture.moveBy(const Offset(0, 6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.description),
        findsNothing,
        reason: 'a 6px press is a drag, not a tap',
      );
      expect(importRequests, isEmpty);
      expect(dialogResult.isCompleted, isFalse);
    });

    testWidgets('dropping the card with no fields selected springs it back '
        'without importing', (tester) async {
      await openDialog(tester);
      await tester.tap(blueskyImportField(BlueskyProfileField.displayName));
      await tester.pump();
      await tester.tap(blueskyImportField(BlueskyProfileField.avatar));
      await tester.pump();
      expect(_offStates(), [true, true, true, true]);
      final restingTopLeft = tester.getTopLeft(blueskyImportCard);

      final distance =
          tester.getCenter(covesImportTarget).dy -
          tester.getCenter(blueskyImportCard).dy;
      await tester.drag(blueskyImportCard, Offset(0, distance));
      await tester.pumpAndSettle();

      expect(importRequests, isEmpty);
      expect(dialogResult.isCompleted, isFalse);
      expect(tester.getTopLeft(blueskyImportCard), restingTopLeft);
    });

    testWidgets('at 768px wide or more the cards sit side by side; on a phone '
        'they stack; both cards always match in size', (tester) async {
      await openDialog(tester, viewSize: const Size(1280, 900));
      var bluesky = tester.getRect(blueskyImportCard);
      var coves = tester.getRect(covesImportTarget);
      expect(coves.left, greaterThan(bluesky.right), reason: 'wide');
      expect(coves.top, lessThan(bluesky.bottom), reason: 'wide: one row');
      expect(coves.size, bluesky.size, reason: 'wide');
      expect(bluesky.height, 328, reason: 'wide card height');

      await openDialog(tester, viewSize: const Size(390, 844));
      bluesky = tester.getRect(blueskyImportCard);
      coves = tester.getRect(covesImportTarget);
      expect(coves.top, greaterThanOrEqualTo(bluesky.bottom), reason: 'phone');
      expect(coves.size, bluesky.size, reason: 'phone');
      expect(bluesky.height, 220, reason: 'phone card height');
    });

    testWidgets('with animations disabled Import profile still closes with the '
        'imported list', (tester) async {
      await openDialog(tester, disableAnimations: true);

      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(importRequests, [
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
      ]);
      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);
      expect(blueskyImportCard, findsNothing);
    });

    testWidgets('with a second finger down, a tap with the first toggles only '
        'the field the first finger pressed', (tester) async {
      await openDialog(tester);
      expect(_offStates(), [false, true, false, true]);

      final first = await tester.startGesture(
        tester.getCenter(blueskyImportField(BlueskyProfileField.displayName)),
        pointer: 1,
      );
      final second = await tester.startGesture(
        tester.getCenter(blueskyImportField(BlueskyProfileField.banner)),
        pointer: 2,
      );
      await first.up();
      await tester.pump();
      await second.up();
      await tester.pumpAndSettle();

      expect(_offStates(), [true, true, false, true]);
      expect(importRequests, isEmpty);
    });

    testWidgets('a field toggled off does not travel on the floating card, '
        'and the Coves header never shows it', (tester) async {
      await openDialog(tester);
      expect(
        blueskyImportFieldOffBadge(BlueskyProfileField.description),
        findsOneWidget,
      );

      final start = tester.getCenter(blueskyImportCard);
      final distance = tester.getCenter(covesImportTarget).dy - start.dy;
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(_floatingCopies(blueskyBio), 0, reason: 'dragging');

      await gesture.moveBy(Offset(0, distance - 40));
      await tester.pump();
      expect(_floatingCopies(blueskyBio), 0, reason: 'over the target');

      await gesture.up();
      for (var elapsed = 0; elapsed < 600; elapsed += 20) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(_floatingCopies(blueskyBio), 0, reason: 'moving at $elapsed');
        expect(
          find.descendant(
            of: covesImportTarget,
            matching: find.text(blueskyBio),
          ),
          findsNothing,
          reason: 'Coves header at $elapsed',
        );
      }
      expect(importRequests, [
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
      ]);
      expect(
        find.descendant(of: covesImportTarget, matching: find.text(blueskyBio)),
        findsNothing,
        reason: 'seated',
      );

      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('a field toggle that had keyboard focus has it again, or the '
        'card does, after a drag from it springs back', (tester) async {
      await openDialog(tester);
      final bio = blueskyImportField(BlueskyProfileField.description);
      await _tabTo(
        tester,
        _fieldFocusNode(tester, BlueskyProfileField.description),
      );

      final gesture = await tester.startGesture(tester.getCenter(bio));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(importRequests, isEmpty);
      final fieldFocused = _fieldFocusNode(
        tester,
        BlueskyProfileField.description,
      ).hasPrimaryFocus;
      final cardFocused = _cardFocusNode(tester).hasPrimaryFocus;
      expect(
        fieldFocused || cardFocused,
        isTrue,
        reason: 'focus is on ${FocusManager.instance.primaryFocus}',
      );
    });
  });

  group('W2 declining', () {
    final declineActions = <(String, Future<void> Function(WidgetTester))>[
      ('No thanks', (tester) => tester.tap(find.text('No thanks'))),
      ('close X', (tester) => tester.tap(find.byTooltip('Close'))),
      ('barrier tap', (tester) => tester.tapAt(const Offset(8, 8))),
      ('system back', (tester) => tester.binding.handlePopRoute()),
    ];

    testWidgets('No thanks, the close X, a barrier tap and system back each '
        'close with null and call onDecline once', (tester) async {
      for (final (name, decline) in declineActions) {
        declineCount = 0;
        await openDialog(tester);

        await decline(tester);
        await tester.pumpAndSettle();

        expect(dialogResult.isCompleted, isTrue, reason: name);
        expect(await dialogResult.future, isNull, reason: name);
        expect(declineCount, 1, reason: name);
        expect(blueskyImportCard, findsNothing, reason: name);
      }
      expect(importRequests, isEmpty);
    });

    testWidgets('with no onDecline each of them just closes with null', (
      tester,
    ) async {
      for (final (name, decline) in declineActions) {
        await openDialog(tester, withDecline: false);

        await decline(tester);
        await tester.pumpAndSettle();

        expect(dialogResult.isCompleted, isTrue, reason: name);
        expect(await dialogResult.future, isNull, reason: name);
        expect(blueskyImportCard, findsNothing, reason: name);
        expect(tester.takeException(), isNull, reason: name);
      }
    });
  });

  group('W3 import outcomes', () {
    testWidgets('a generic failure returns the card, keeps the dialog open '
        'with the error and Import profile enabled again', (tester) async {
      final pending = Completer<List<BlueskyProfileField>>();
      importAnswers.add(() => pending.future);
      await openDialog(tester);
      final restingTopLeft = tester.getTopLeft(blueskyImportCard);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 700);
      expect(importRequests, hasLength(1));
      expect(_moveEnabled(tester), isFalse, reason: 'import in flight');

      pending.completeError(
        ApiException('Bluesky is unavailable right now', statusCode: 400),
      );
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isFalse);
      expect(blueskyImportCard, findsOneWidget);
      expect(find.text('Bluesky is unavailable right now'), findsOneWidget);
      expect(tester.getTopLeft(blueskyImportCard), restingTopLeft);
      expect(_moveEnabled(tester), isTrue);
    });

    testWidgets('a Conflict asks to try again, and a retry that succeeds '
        'closes with the imported list', (tester) async {
      importAnswers
        ..add(
          () => Future.error(
            ApiException(
              'Profile changed',
              statusCode: 409,
              errorCode: 'Conflict',
            ),
          ),
        )
        ..add(() async => [BlueskyProfileField.displayName]);
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isFalse);
      expect(find.textContaining('Try again'), findsOneWidget);
      expect(_moveEnabled(tester), isTrue);

      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [BlueskyProfileField.displayName]);
      expect(importRequests, [
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
      ]);
    });

    testWidgets('an unexpected non-API failure returns the card, keeps the '
        'dialog open with an error and Import profile enabled again', (
      tester,
    ) async {
      importAnswers.add(() => Future.error(StateError('unexpected')));
      await openDialog(tester);
      final restingTopLeft = tester.getTopLeft(blueskyImportCard);

      await tapMoveToCoves(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(dialogResult.isCompleted, isFalse);
      expect(blueskyImportCard, findsOneWidget);
      expect(
        find.text('Could not import from Bluesky. Please try again.'),
        findsOneWidget,
      );
      expect(_moveEnabled(tester), isTrue);
      expect(tester.getTopLeft(blueskyImportCard), restingTopLeft);
    });

    testWidgets('a card moved with Enter while focused has keyboard focus '
        'again once a failed import returns it', (tester) async {
      importAnswers.add(
        () => Future.error(
          ApiException('Bluesky is unavailable right now', statusCode: 400),
        ),
      );
      await openDialog(tester);
      await _tabTo(tester, _cardFocusNode(tester));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(importRequests, hasLength(1));
      expect(find.text('Bluesky is unavailable right now'), findsOneWidget);
      expect(
        _cardFocusNode(tester).hasPrimaryFocus,
        isTrue,
        reason: 'focus is on ${FocusManager.instance.primaryFocus}',
      );
    });

    testWidgets('NothingToImport closes with an empty list', (tester) async {
      importAnswers.add(
        () => Future.error(
          ApiException(
            'Nothing to import',
            statusCode: 400,
            errorCode: 'NothingToImport',
          ),
        ),
      );
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, <BlueskyProfileField>[]);
      expect(blueskyImportCard, findsNothing);
    });

    testWidgets('an account change while open closes it without declining; '
        'a token refresh does not', (tester) async {
      await openDialog(tester);

      auth.notifyWithoutChange();
      await tester.pumpAndSettle();
      expect(blueskyImportCard, findsOneWidget, reason: 'same session');

      auth.setSignedInDid('did:plc:someone-else');
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, isNull);
      expect(blueskyImportCard, findsNothing);
      expect(declineCount, 0);
      expect(importRequests, isEmpty);
    });

    testWidgets('an account change during the seat pause closes with '
        'null without declining', (tester) async {
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 1000);
      expect(importRequests, hasLength(1));
      expect(dialogResult.isCompleted, isFalse, reason: 'seat pause');

      auth.setSignedInDid('did:plc:someone-else');
      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();

      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, isNull);
      expect(declineCount, 0);
      expect(blueskyImportCard, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an account change while a declined dialog is closing does '
        'not pop the route beneath', (tester) async {
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider<ViewerAuthorityProvider>.value(
          value: viewerAuthority,
          child: ImageCacheScope(
            cacheManager: FakeImageCacheManager(),
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            body: Center(
                              child: ElevatedButton(
                                onPressed: () => showBlueskyProfileImportDialog(
                                  context,
                                  choices: fourChoices,
                                  onImport: fakeImport,
                                  onDecline: fakeDecline,
                                ),
                                child: const Text('Open'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Push'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(blueskyImportCard, findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      auth.setSignedInDid('did:plc:someone-else');
      await tester.pumpAndSettle();

      expect(blueskyImportCard, findsNothing);
      expect(find.text('Open'), findsOneWidget, reason: 'pushed route stays');
      expect(declineCount, 1);
    });
  });

  group('W4 move and seat', () {
    testWidgets('Import profile calls onImport when the card lands after the '
        '560ms move, not when tapped', (tester) async {
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 500);
      expect(importRequests, isEmpty, reason: 'the card is still moving');

      await _pumpFor(tester, 100);
      expect(importRequests, [
        [BlueskyProfileField.displayName, BlueskyProfileField.avatar],
      ]);
    });

    testWidgets('a fast import waits for the 2700ms seat pause before '
        'closing with the imported list', (tester) async {
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 600);
      expect(importRequests, hasLength(1));

      // 3100ms in: the card landed at 560ms, so the pause has 160ms left.
      await _pumpFor(tester, 2500);
      expect(dialogResult.isCompleted, isFalse, reason: 'seat pause');
      expect(covesImportTarget, findsOneWidget);

      await _pumpFor(tester, 300);
      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);
    });

    testWidgets('an import still pending after the seat pause keeps the '
        'dialog open, and it closes with the imported list once it '
        'completes', (tester) async {
      final pending = Completer<List<BlueskyProfileField>>();
      importAnswers.add(() => pending.future);
      await openDialog(tester);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 4000);
      expect(importRequests, hasLength(1));
      expect(dialogResult.isCompleted, isFalse, reason: 'import pending');
      expect(covesImportTarget, findsOneWidget);

      pending.complete([BlueskyProfileField.displayName]);
      await _pumpFor(tester, 100);

      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [BlueskyProfileField.displayName]);
    });

    testWidgets('with animations disabled the card lands after a 150ms '
        'crossfade and the seat pause is 600ms', (tester) async {
      await openDialog(tester, disableAnimations: true);

      await tapMoveToCoves(tester);
      await _pumpFor(tester, 100);
      expect(importRequests, isEmpty, reason: 'still crossfading');

      await _pumpFor(tester, 100);
      expect(importRequests, hasLength(1));

      // 660ms in: the card landed at 150ms, so the pause has 90ms left.
      await _pumpFor(tester, 460);
      expect(dialogResult.isCompleted, isFalse, reason: 'seat pause');

      await _pumpFor(tester, 240);
      expect(dialogResult.isCompleted, isTrue);
      expect(await dialogResult.future, [
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);
    });

    testWidgets('with animations disabled the Coves card contents only fade '
        'in, never scale, during the 150ms crossfade', (tester) async {
      await openDialog(tester, disableAnimations: true);

      await tapMoveToCoves(tester);
      for (var elapsed = 0; elapsed <= 160; elapsed += 20) {
        final scales = [
          for (final transform in tester.widgetList<Transform>(
            find.descendant(
              of: covesImportTarget,
              matching: find.byType(Transform),
            ),
          ))
            transform.transform.getMaxScaleOnAxis(),
        ];
        expect(
          scales.every((scale) => scale == 1.0),
          isTrue,
          reason: 'scales $scales at ${elapsed}ms',
        );
        await tester.pump(const Duration(milliseconds: 20));
      }

      await pumpThroughImportSuccess(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('a barrier tap or system back during the seat pause closes '
        'at once with the imported list and does not decline', (tester) async {
      final endActions = <(String, Future<void> Function(WidgetTester))>[
        ('barrier tap', (tester) => tester.tapAt(const Offset(8, 8))),
        ('system back', (tester) => tester.binding.handlePopRoute()),
      ];
      for (final (name, end) in endActions) {
        importRequests.clear();
        declineCount = 0;
        await openDialog(tester);

        await tapMoveToCoves(tester);
        await _pumpFor(tester, 1000);
        expect(importRequests, hasLength(1), reason: name);
        expect(dialogResult.isCompleted, isFalse, reason: name);

        await end(tester);
        await _pumpFor(tester, 100);

        expect(dialogResult.isCompleted, isTrue, reason: name);
        expect(await dialogResult.future, [
          BlueskyProfileField.displayName,
          BlueskyProfileField.avatar,
        ], reason: name);
        expect(declineCount, 0, reason: name);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('No thanks is disabled from the start of the move through '
        'the whole seat pause', (tester) async {
      await openDialog(tester);
      expect(_noThanksEnabled(tester), isTrue);

      await tapMoveToCoves(tester);
      expect(_noThanksEnabled(tester), isFalse, reason: 'move started');

      await _pumpFor(tester, 300);
      expect(_noThanksEnabled(tester), isFalse, reason: 'moving');

      await _pumpFor(tester, 700);
      expect(_noThanksEnabled(tester), isFalse, reason: 'seated');

      await _pumpFor(tester, 2000);
      expect(_noThanksEnabled(tester), isFalse, reason: 'late in the pause');
      expect(declineCount, 0);
    });
  });
}
