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
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/edit_profile_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/widgets/icons/back_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

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
}
