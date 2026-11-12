import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/bluesky_profile_import_offer_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_mocks.dart';

/// The app-wide Bluesky profile import offer provider, as main.dart
/// registers it. Reads the [ViewerAuthorityProvider] and [ProfileCache]
/// registered above it.
///
/// Lazy: it is created, and checks for an offer, only once something reads
/// it (the shell does), so a harness that never mounts the shell makes no
/// `getBlueskyProfileImport` call.
SingleChildWidget blueskyImportOfferRegistration({
  required AuthProvider auth,
  required CovesApiService apiService,
}) => ChangeNotifierProvider<BlueskyProfileImportOfferProvider>(
  create: (context) {
    final authority = context.read<ViewerAuthorityProvider>();
    return BlueskyProfileImportOfferProvider(
      apiService: apiService,
      authProvider: auth,
      sessionKeyOf: () => authority.sessionKey,
      profileCache: context.read<ProfileCache>(),
    );
  },
);

/// Answers the automatic offer check with no Bluesky profile, so no offer
/// dialog appears over the shell.
void stubNoBlueskyProfileImport(MockCovesApiService api) {
  when(api.getBlueskyProfileImport()).thenAnswer(
    (_) async => const BlueskyProfileImport(
      status: BlueskyProfileImportStatus.noBlueskyProfile,
      fields: [],
    ),
  );
}

/// The draggable Bluesky card in the import dialog.
Finder get blueskyImportCard => find.byKey(const ValueKey('blueskyImportCard'));

/// The Coves card, the hollow drop target in the import dialog.
Finder get covesImportTarget => find.byKey(const ValueKey('covesImportTarget'));

/// The tappable [field] on the Bluesky card.
Finder blueskyImportField(BlueskyProfileField field) =>
    find.byKey(ValueKey('blueskyImportField-${field.name}'));

/// The "Off" badge of [field], present only while the field is left out.
Finder blueskyImportFieldOffBadge(BlueskyProfileField field) =>
    find.descendant(of: blueskyImportField(field), matching: find.text('Off'));

/// The dialog's primary "Import profile" button.
Finder get moveToCovesButton => find.ancestor(
  of: find.text('Import profile'),
  matching: find.bySubtype<ButtonStyleButton>(),
);

/// The dialog's secondary "No thanks" button.
Finder get noThanksButton => find.ancestor(
  of: find.text('No thanks'),
  matching: find.bySubtype<ButtonStyleButton>(),
);

/// Taps "Import profile" in the import dialog.
Future<void> tapMoveToCoves(WidgetTester tester) async {
  expect(moveToCovesButton, findsOneWidget);
  await tester.ensureVisible(moveToCovesButton);
  await tester.tap(moveToCovesButton);
  await tester.pump();
}

/// Bounded pumps through the 560ms move into the Coves slot, the 2700ms
/// seat pause and the dialog's closing transition (4.5s in all). Safe while
/// a spinner is up.
Future<void> pumpThroughImportSuccess(WidgetTester tester) async {
  for (var step = 0; step < 45; step++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
