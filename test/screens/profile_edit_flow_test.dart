// Editing the own profile refreshes every screen showing it.
//
// Each ProfileScreen owns its own profile state. Saving from
// EditProfileScreen must refresh the screen that opened it, and - when the
// edit was made from a pushed `/profile/<my-did>` page - also the own
// Profile tab underneath, with no extra user action.
//
// The tree provides only app-level dependencies (the same set main.dart
// registers); no UserProfileProvider is provided here.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/screens/home/edit_profile_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/widgets/icons/back_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/bluesky_import_test_helpers.dart';
import '../test_helpers/error_copy_rows.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';
const String oldDisplayName = 'Old name';
const String oldBio = 'Old bio';
const String newDisplayName = 'New name';
const String newBio = 'New bio';

/// The own Profile tab's screen.
Finder get _ownScreen => find.byWidgetPredicate(
  (widget) => widget is ProfileScreen && widget.actor == null,
  skipOffstage: false,
);

/// My profile opened by DID on top of the own tab.
Finder get _pushedScreen => find.byWidgetPredicate(
  (widget) => widget is ProfileScreen && widget.actor == myDid,
);

Finder _within(Finder scope, Finder matching) =>
    find.descendant(of: scope, matching: matching);

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;

  /// What the server returns for my profile; updateProfile replaces it.
  late UserProfile myServerProfile;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    // The screen's ViewerAuthorityProvider asks once per signed-in session.
    when(apiService.getViewerAuthority()).thenAnswer((_) async => false);
    myServerProfile = UserProfile(
      did: myDid,
      handle: myHandle,
      displayName: oldDisplayName,
      bio: oldBio,
    );

    when(apiService.getProfile(actor: myDid))
        .thenAnswer((_) async => myServerProfile);
    when(
      apiService.getAuthorPosts(
        actor: myDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: []));
    when(
      apiService.updateProfile(
        displayName: anyNamed('displayName'),
        bio: anyNamed('bio'),
        avatarBytes: anyNamed('avatarBytes'),
        avatarMimeType: anyNamed('avatarMimeType'),
        bannerBytes: anyNamed('bannerBytes'),
        bannerMimeType: anyNamed('bannerMimeType'),
      ),
    ).thenAnswer((invocation) async {
      myServerProfile = UserProfile(
        did: myDid,
        handle: myHandle,
        displayName: invocation.namedArguments[#displayName] as String?,
        bio: invocation.namedArguments[#bio] as String?,
      );
      return const UpdateProfileResponse(
        uri: 'at://did:plc:me/social.coves.actor.profile/self',
        cid: 'cid-updated',
      );
    });
  });

  tearDown(() {
    authProvider.dispose();
  });

  /// Pumps the app with the own profile at `/feed` (standing in for the
  /// Profile tab) and the real `/profile/:actor` route.
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    // Phone layout
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/feed',
      routes: [
        GoRoute(
          path: '/feed',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/:actor',
          builder: (context, state) =>
              ProfileScreen(actor: state.pathParameters['actor']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);
    return router;
  }

  /// Opens EditProfileScreen from [screen], replaces the display name and
  /// bio, and saves.
  Future<void> editAndSave(WidgetTester tester, Finder screen) async {
    await tester.tap(_within(screen, find.byTooltip('Edit Profile')));
    await pumpFrames(tester);
    expect(find.byType(EditProfileScreen), findsOneWidget);

    final fields = _within(
      find.byType(EditProfileScreen),
      find.byType(TextField),
    );
    await tester.enterText(fields.at(0), newDisplayName);
    await tester.enterText(fields.at(1), newBio);
    await tester.pump();

    await tester.tap(
      _within(find.byType(EditProfileScreen), find.text('Save')),
    );
    await pumpFrames(tester);
  }

  void verifyUpdateSentOnce() {
    verify(
      apiService.updateProfile(
        displayName: newDisplayName,
        bio: newBio,
        avatarBytes: anyNamed('avatarBytes'),
        avatarMimeType: anyNamed('avatarMimeType'),
        bannerBytes: anyNamed('bannerBytes'),
        bannerMimeType: anyNamed('bannerMimeType'),
      ),
    ).called(1);
  }

  testWidgets('saving an edit from the own profile refreshes that screen', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(_within(_ownScreen, find.text(oldBio)), findsOneWidget);

    await editAndSave(tester, _ownScreen);

    verifyUpdateSentOnce();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(_within(_ownScreen, find.text(newBio)), findsOneWidget);
    expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an edit from my profile opened by DID also refreshes '
      'the own Profile tab underneath after popping', (tester) async {
    final router = await pumpApp(tester);
    expect(_within(_ownScreen, find.text(oldBio)), findsOneWidget);

    unawaited(router.push('/profile/$myDid'));
    await pumpFrames(tester);
    expect(_within(_pushedScreen, find.text(oldBio)), findsOneWidget);

    await editAndSave(tester, _pushedScreen);

    verifyUpdateSentOnce();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(_within(_pushedScreen, find.text(newBio)), findsOneWidget);

    await tester.tap(_within(_pushedScreen, find.byType(BackIcon)));
    await pumpFrames(tester);
    expect(_pushedScreen, findsNothing);

    expect(_within(_ownScreen, find.text(newBio)), findsOneWidget);
    expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save that completes after the editor and my pushed profile '
      'were popped still refreshes the own Profile tab', (tester) async {
    // The save stays pending until the test completes it.
    final pendingUpdate = Completer<UpdateProfileResponse>();
    when(
      apiService.updateProfile(
        displayName: anyNamed('displayName'),
        bio: anyNamed('bio'),
        avatarBytes: anyNamed('avatarBytes'),
        avatarMimeType: anyNamed('avatarMimeType'),
        bannerBytes: anyNamed('bannerBytes'),
        bannerMimeType: anyNamed('bannerMimeType'),
      ),
    ).thenAnswer((_) => pendingUpdate.future);

    final router = await pumpApp(tester);
    expect(_within(_ownScreen, find.text(oldBio)), findsOneWidget);

    unawaited(router.push('/profile/$myDid'));
    await pumpFrames(tester);
    expect(_within(_pushedScreen, find.text(oldBio)), findsOneWidget);

    await editAndSave(tester, _pushedScreen);
    verifyUpdateSentOnce();
    expect(
      find.byType(EditProfileScreen),
      findsOneWidget,
      reason: 'the save is still pending',
    );

    // Leave the editor with its close button while the save is in flight.
    await tester.tap(
      _within(find.byType(EditProfileScreen), find.byIcon(Icons.close)),
    );
    await pumpFrames(tester);
    expect(find.byType(EditProfileScreen), findsNothing);

    // Leave my pushed profile, disposing the provider that is saving.
    await tester.tap(_within(_pushedScreen, find.byType(BackIcon)));
    await pumpFrames(tester);
    expect(_pushedScreen, findsNothing);

    // The server accepts the edit; the follow-up getProfile returns it.
    myServerProfile = UserProfile(
      did: myDid,
      handle: myHandle,
      displayName: newDisplayName,
      bio: newBio,
    );
    pendingUpdate.complete(
      const UpdateProfileResponse(
        uri: 'at://did:plc:me/social.coves.actor.profile/self',
        cid: 'cid-updated',
      ),
    );
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(_within(_ownScreen, find.text(newBio)), findsOneWidget);
    expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
  });

  testWidgets('a save whose follow-up profile fetch completes after the '
      'editor and my pushed profile were popped still refreshes the own '
      'Profile tab', (tester) async {
    final router = await pumpApp(tester);
    expect(_within(_ownScreen, find.text(oldBio)), findsOneWidget);

    unawaited(router.push('/profile/$myDid'));
    await pumpFrames(tester);
    expect(_within(_pushedScreen, find.text(oldBio)), findsOneWidget);

    // From here on, count only the save's requests. The save's follow-up
    // getProfile stays pending until the test completes it.
    clearInteractions(apiService);
    final pendingRefresh = Completer<UserProfile>();
    when(apiService.getProfile(actor: myDid))
        .thenAnswer((_) => pendingRefresh.future);

    await editAndSave(tester, _pushedScreen);
    verifyUpdateSentOnce();
    verify(apiService.getProfile(actor: myDid)).called(1);
    expect(
      find.byType(EditProfileScreen),
      findsOneWidget,
      reason: 'the follow-up fetch is still pending',
    );

    // Leave the editor with its close button while the fetch is in flight.
    await tester.tap(
      _within(find.byType(EditProfileScreen), find.byIcon(Icons.close)),
    );
    await pumpFrames(tester);
    expect(find.byType(EditProfileScreen), findsNothing);

    // Leave my pushed profile, disposing the provider whose fetch is
    // pending.
    await tester.tap(_within(_pushedScreen, find.byType(BackIcon)));
    await pumpFrames(tester);
    expect(_pushedScreen, findsNothing);

    // The follow-up fetch returns the edited profile.
    final updatedProfile = UserProfile(
      did: myDid,
      handle: myHandle,
      displayName: newDisplayName,
      bio: newBio,
    );
    pendingRefresh.complete(updatedProfile);
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(_within(_ownScreen, find.text(newBio)), findsOneWidget);
    expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
    final profileCache = Provider.of<ProfileCache>(
      tester.element(_ownScreen),
      listen: false,
    );
    expect(profileCache.get(myDid), same(updatedProfile));
    // The own tab adopted the result without a refresh of its own.
    verifyNever(apiService.getProfile(actor: anyNamed('actor')));
  });

  group('save failure copy', () {
    for (final row in errorCopyRows(
      'Could not update profile. Please try again.',
    )) {
      testWidgets('a ${row.name} save failure shows "${row.expected}"', (
        tester,
      ) async {
        when(
          apiService.updateProfile(
            displayName: anyNamed('displayName'),
            bio: anyNamed('bio'),
            avatarBytes: anyNamed('avatarBytes'),
            avatarMimeType: anyNamed('avatarMimeType'),
            bannerBytes: anyNamed('bannerBytes'),
            bannerMimeType: anyNamed('bannerMimeType'),
          ),
        ).thenThrow(row.error);
        await pumpApp(tester);

        await editAndSave(tester, _ownScreen);

        expect(
          _within(find.byType(SnackBar), find.text(row.expected)),
          findsOneWidget,
        );
        expect(find.textContaining('Failed to update profile'), findsNothing);
        if (row.rawText case final rawText?) {
          expect(find.textContaining(rawText), findsNothing);
        }
      });
    }

    testWidgets('a rejected image save shows the image copy, not the raw '
        'server text', (tester) async {
      when(
        apiService.updateProfile(
          displayName: anyNamed('displayName'),
          bio: anyNamed('bio'),
          avatarBytes: anyNamed('avatarBytes'),
          avatarMimeType: anyNamed('avatarMimeType'),
          bannerBytes: anyNamed('bannerBytes'),
          bannerMimeType: anyNamed('bannerMimeType'),
        ),
      ).thenThrow(
        ApiException(
          'Image dimensions too large',
          statusCode: 400,
          errorCode: 'ImageDimensionsTooLarge',
        ),
      );
      await pumpApp(tester);

      await editAndSave(tester, _ownScreen);

      verifyUpdateSentOnce();
      expect(
        _within(
          find.byType(SnackBar),
          find.text('This image is too large. Choose a smaller image.'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Image dimensions too large'), findsNothing);
    });
  });

  group('W5 import from Bluesky', () {
    const blueskyName = 'Name from Bluesky';
    const blueskyBio = 'Bio from Bluesky';

    /// Display name and banner are set on Coves; bio and avatar are empty.
    BlueskyProfileImport mixedImport(BlueskyProfileImportStatus status) =>
        BlueskyProfileImport(
          status: status,
          fields: const [
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
              blueskyImageUrl: 'https://cdn.bsky.app/img/avatar/plain/did:plc:me/bafkreiavatar@jpeg',
              covesIsEmpty: true,
            ),
            BlueskyProfileImportFieldView(
              field: BlueskyProfileField.banner,
              blueskyImageUrl: 'https://cdn.bsky.app/img/banner/plain/did:plc:me/bafkreibanner@jpeg',
              covesIsEmpty: false,
            ),
          ],
        );

    final card = blueskyImportCard;

    final importButton = _within(
      find.byType(EditProfileScreen),
      find.ancestor(
        of: find.text('Import from Bluesky'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    final saveButton = _within(
      find.byType(EditProfileScreen),
      find.ancestor(of: find.text('Save'), matching: find.byType(TextButton)),
    );
    bool isEnabled(WidgetTester tester, Finder button) =>
        tester.widget<ButtonStyleButton>(button).enabled;

    /// Opens Edit Profile from the own profile.
    Future<void> openEditor(WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(_within(_ownScreen, find.byTooltip('Edit Profile')));
      await pumpFrames(tester);
      expect(importButton, findsOneWidget);
    }

    Future<void> tapImportButton(WidgetTester tester) async {
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await pumpFrames(tester);
    }

    /// Opens Edit Profile from the own profile and taps the import button.
    Future<void> openImport(WidgetTester tester) async {
      await openEditor(tester);
      await tapImportButton(tester);
    }

    Future<void> tapDialogImport(WidgetTester tester) async {
      await tapMoveToCoves(tester);
      await pumpThroughImportSuccess(tester);
      await pumpFrames(tester);
    }

    setUp(() {
      when(apiService.dismissBlueskyProfileImport()).thenAnswer((_) async {});
    });

    testWidgets('a dismissed offer still lists every field, checked when '
        'empty on Coves, and No thanks does not dismiss again', (tester) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => mixedImport(BlueskyProfileImportStatus.dismissed),
      );
      await openImport(tester);

      expect(card, findsOneWidget);
      expect(
        [
          for (final field in BlueskyProfileField.values)
            (
              blueskyImportField(field).evaluate().length,
              blueskyImportFieldOffBadge(field).evaluate().length,
            ),
        ],
        // (on the card, Off badges): every field, Off when set on Coves.
        [(1, 1), (1, 0), (1, 0), (1, 1)],
      );
      expect(find.text(blueskyName), findsOneWidget);
      expect(find.text(blueskyBio), findsOneWidget);

      await tester.tap(find.text('No thanks'));
      await pumpFrames(tester);

      expect(card, findsNothing);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      verifyNever(apiService.dismissBlueskyProfileImport());
    });

    testWidgets('no Bluesky profile shows a message and no dialog', (
      tester,
    ) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => const BlueskyProfileImport(
          status: BlueskyProfileImportStatus.noBlueskyProfile,
          fields: [],
        ),
      );
      await openImport(tester);

      expect(
        _within(find.byType(SnackBar), find.text('No Bluesky profile found')),
        findsOneWidget,
      );
      expect(card, findsNothing);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('an import closes Edit Profile, refreshes the profile and '
        'confirms on the profile screen beneath', (tester) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => mixedImport(BlueskyProfileImportStatus.dismissed),
      );
      when(apiService.importBlueskyProfile(any)).thenAnswer((call) async {
        myServerProfile = UserProfile(
          did: myDid,
          handle: myHandle,
          displayName: oldDisplayName,
          bio: blueskyBio,
        );
        return call.positionalArguments.first as List<BlueskyProfileField>;
      });
      await openImport(tester);

      await tapDialogImport(tester);

      verify(
        apiService.importBlueskyProfile([
          BlueskyProfileField.description,
          BlueskyProfileField.avatar,
        ]),
      ).called(1);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(
        _within(
          find.byType(SnackBar),
          find.text('Imported your Bluesky profile.'),
        ),
        findsOneWidget,
      );
      expect(_within(_ownScreen, find.text(blueskyBio)), findsOneWidget);
      expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
    });

    testWidgets(
      'a NothingToImport error closes Edit Profile and says Nothing to import',
      (tester) async {
        when(apiService.getBlueskyProfileImport()).thenAnswer(
          (_) async => mixedImport(BlueskyProfileImportStatus.dismissed),
        );
        when(apiService.importBlueskyProfile(any)).thenThrow(
          ApiException(
            'Nothing to import',
            statusCode: 400,
            errorCode: 'NothingToImport',
          ),
        );
        await openImport(tester);

        await tapDialogImport(tester);

        expect(find.byType(EditProfileScreen), findsNothing);
        expect(
          _within(find.byType(SnackBar), find.text('Nothing to import')),
          findsOneWidget,
        );
      },
    );

    testWidgets('Import from Bluesky is disabled while a save is in flight', (
      tester,
    ) async {
      final pendingUpdate = Completer<UpdateProfileResponse>();
      when(
        apiService.updateProfile(
          displayName: anyNamed('displayName'),
          bio: anyNamed('bio'),
          avatarBytes: anyNamed('avatarBytes'),
          avatarMimeType: anyNamed('avatarMimeType'),
          bannerBytes: anyNamed('bannerBytes'),
          bannerMimeType: anyNamed('bannerMimeType'),
        ),
      ).thenAnswer((_) => pendingUpdate.future);
      await openEditor(tester);
      expect(isEnabled(tester, importButton), isTrue);

      final fields = _within(
        find.byType(EditProfileScreen),
        find.byType(TextField),
      );
      await tester.enterText(fields.at(1), newBio);
      await tester.pump();
      await tester.tap(saveButton);
      await tester.pump();

      expect(
        isEnabled(tester, importButton),
        isFalse,
        reason: 'the save is still pending',
      );

      pendingUpdate.complete(
        const UpdateProfileResponse(
          uri: 'at://did:plc:me/social.coves.actor.profile/self',
          cid: 'cid-updated',
        ),
      );
      await pumpFrames(tester);
    });

    testWidgets('Save is disabled while the import check and its dialog are '
        'in progress', (tester) async {
      final pendingCheck = Completer<BlueskyProfileImport>();
      when(apiService.getBlueskyProfileImport())
          .thenAnswer((_) => pendingCheck.future);
      await openEditor(tester);

      final fields = _within(
        find.byType(EditProfileScreen),
        find.byType(TextField),
      );
      await tester.enterText(fields.at(1), newBio);
      await tester.pump();
      expect(isEnabled(tester, saveButton), isTrue);

      await tapImportButton(tester);
      expect(
        isEnabled(tester, saveButton),
        isFalse,
        reason: 'the import check is pending',
      );

      pendingCheck.complete(mixedImport(BlueskyProfileImportStatus.dismissed));
      await pumpFrames(tester);
      expect(card, findsOneWidget);
      expect(
        isEnabled(tester, saveButton),
        isFalse,
        reason: 'the import dialog is open',
      );

      await tester.tap(find.text('No thanks'));
      await pumpFrames(tester);
    });

    testWidgets('nothing to import shows a message and no dialog', (
      tester,
    ) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => mixedImport(BlueskyProfileImportStatus.nothingToImport),
      );
      await openImport(tester);

      expect(
        _within(find.byType(SnackBar), find.text('Nothing to import')),
        findsOneWidget,
      );
      expect(card, findsNothing);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('a status other than nothingToImport with no fields shows '
        'Nothing to import and no dialog', (tester) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => const BlueskyProfileImport(
          status: BlueskyProfileImportStatus.dismissed,
          fields: [],
        ),
      );
      await openImport(tester);

      expect(
        _within(find.byType(SnackBar), find.text('Nothing to import')),
        findsOneWidget,
      );
      expect(card, findsNothing);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('an import refreshes the own profile even while an older '
        'profile load is in flight', (tester) async {
      when(apiService.getBlueskyProfileImport()).thenAnswer(
        (_) async => mixedImport(BlueskyProfileImportStatus.dismissed),
      );
      when(apiService.importBlueskyProfile(any)).thenAnswer((call) async {
        myServerProfile = UserProfile(
          did: myDid,
          handle: myHandle,
          displayName: oldDisplayName,
          bio: blueskyBio,
        );
        return call.positionalArguments.first as List<BlueskyProfileField>;
      });
      await openEditor(tester);

      // An older own-profile load is still pending when the import lands;
      // later fetches return the server's current profile.
      final staleLoad = Completer<UserProfile>();
      var profileFetches = 0;
      when(apiService.getProfile(actor: myDid)).thenAnswer((_) {
        profileFetches++;
        return profileFetches == 1
            ? staleLoad.future
            : Future.value(myServerProfile);
      });
      final profileProvider = Provider.of<UserProfileProvider>(
        tester.element(find.byType(EditProfileScreen)),
        listen: false,
      );
      unawaited(profileProvider.loadProfile(myDid, forceRefresh: true));
      await tester.pump();

      await tapImportButton(tester);
      await tapDialogImport(tester);
      expect(find.byType(EditProfileScreen), findsNothing);

      // The older load finishes last with the pre-import profile.
      staleLoad.complete(
        UserProfile(
          did: myDid,
          handle: myHandle,
          displayName: oldDisplayName,
          bio: oldBio,
        ),
      );
      await pumpFrames(tester);

      expect(_within(_ownScreen, find.text(blueskyBio)), findsOneWidget);
      expect(_within(_ownScreen, find.text(oldBio)), findsNothing);
    });

    testWidgets('closing Edit Profile while the import check is pending '
        'opens no dialog', (tester) async {
      final pendingCheck = Completer<BlueskyProfileImport>();
      when(apiService.getBlueskyProfileImport())
          .thenAnswer((_) => pendingCheck.future);
      await openImport(tester);

      await tester.tap(
        _within(find.byType(EditProfileScreen), find.byIcon(Icons.close)),
      );
      // The closing animation is running; the editor is still mounted.
      await tester.pump();
      expect(find.byType(EditProfileScreen), findsOneWidget);

      pendingCheck.complete(mixedImport(BlueskyProfileImportStatus.dismissed));
      await pumpFrames(tester);

      expect(card, findsNothing);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(_within(_ownScreen, find.text(oldBio)), findsOneWidget);
    });

    testWidgets('an account switch while the import check is pending opens '
        'no dialog', (tester) async {
      const otherDid = 'did:plc:other';
      when(apiService.getProfile(actor: otherDid)).thenAnswer(
        (_) async => UserProfile(did: otherDid, handle: 'other.coves.test'),
      );
      when(
        apiService.getAuthorPosts(
          actor: otherDid,
          filter: anyNamed('filter'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async => TimelineResponse(feed: []));
      final pendingCheck = Completer<BlueskyProfileImport>();
      when(apiService.getBlueskyProfileImport())
          .thenAnswer((_) => pendingCheck.future);
      await openImport(tester);

      authProvider.setSignedInDid(otherDid);
      await pumpFrames(tester);
      pendingCheck.complete(mixedImport(BlueskyProfileImportStatus.dismissed));
      await pumpFrames(tester);

      expect(card, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
