import 'dart:async';

import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const myDid = 'did:plc:me';
  const didA = 'did:plc:a';
  const didB = 'did:plc:b';

  late FakeAuthProvider authProvider;
  late MockCovesApiService mockApiService;
  late ProfileCache profileCache;
  late UserProfileProvider provider;
  late bool providerDisposed;

  /// One pending getProfile response per actor, completed by each test.
  late Map<String, Completer<UserProfile>> pendingProfiles;

  final profileA = UserProfile(did: didA, displayName: 'Profile A');
  final profileB = UserProfile(did: didB, displayName: 'Profile B');

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    mockApiService = MockCovesApiService();
    profileCache = ProfileCache(authProvider);
    pendingProfiles = {
      didA: Completer<UserProfile>(),
      didB: Completer<UserProfile>(),
    };

    when(mockApiService.getProfile(actor: anyNamed('actor')))
        .thenAnswer((invocation) {
          final actor = invocation.namedArguments[#actor] as String;
          return pendingProfiles[actor]!.future;
        });

    provider = UserProfileProvider(
      authProvider,
      apiService: mockApiService,
      commentService: MockCommentService(),
      profileCache: profileCache,
    );
    providerDisposed = false;
  });

  tearDown(() {
    if (!providerDisposed) {
      provider.dispose();
    }
    profileCache.dispose();
  });

  group('UserProfileProvider request invalidation', () {
    test('a superseded load that succeeds after the newer load does not '
        'replace the newer profile', () async {
      final loadA = provider.loadProfile(didA);
      provider.clearProfile();
      final loadB = provider.loadProfile(didB);
      pendingProfiles[didB]!.complete(profileB);
      await loadB;

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expect(provider.currentProfileDid, didB);
      expect(provider.profile, same(profileB));
      expect(provider.profileError, isNull);
      expect(provider.isLoadingProfile, isFalse);
    });

    test('a superseded load that fails after the newer load does not set an '
        'error on the newer profile', () async {
      final loadA = provider.loadProfile(didA);
      provider.clearProfile();
      final loadB = provider.loadProfile(didB);
      pendingProfiles[didB]!.complete(profileB);
      await loadB;

      pendingProfiles[didA]!.completeError(NetworkException('offline'));
      await loadA;

      expect(provider.profileError, isNull);
      expect(provider.profile, same(profileB));
      expect(provider.currentProfileDid, didB);
      expect(provider.isLoadingProfile, isFalse);
    });

    test('a superseded load that succeeds while the newer load is pending is '
        'not shown, and the newer load still lands', () async {
      final loadA = provider.loadProfile(didA);
      provider.clearProfile();
      final loadB = provider.loadProfile(didB);

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expect(provider.profile, isNull, reason: 'A was superseded by B');
      expect(provider.currentProfileDid, didB);
      expect(
        provider.isLoadingProfile,
        isTrue,
        reason: "B's load is still in flight",
      );

      pendingProfiles[didB]!.complete(profileB);
      await loadB;

      expect(provider.profile, same(profileB));
      expect(provider.currentProfileDid, didB);
      expect(provider.isLoadingProfile, isFalse);
    });

    test('a load that completes after sign-out is not applied to the '
        'provider view state', () async {
      final loadA = provider.loadProfile(didA);
      authProvider.setSignedInDid(null);

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expect(provider.profile, isNull);
      expect(provider.currentProfileDid, isNull);
    });
  });

  group('UserProfileProvider when the signed-in account ends or changes', () {
    const sessionChangedMessage =
        'Your session changed. Retry to reload this profile.';
    const otherAccountDid = 'did:plc:someone-else';

    void expectResetWithSessionChangedError() {
      expect(provider.profile, isNull);
      expect(provider.currentProfileDid, isNull);
      expect(provider.isLoadingProfile, isFalse);
      expect(provider.profileError, sessionChangedMessage);
    }

    test('signing out during a load drops the load and shows the '
        'session-changed error, even after the load succeeds', () async {
      final loadA = provider.loadProfile(didA);

      authProvider.setSignedInDid(null);

      expectResetWithSessionChangedError();

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expectResetWithSessionChangedError();
    });

    test('signing out during a load drops the load and shows the '
        'session-changed error, even after the load fails', () async {
      final loadA = provider.loadProfile(didA);

      authProvider.setSignedInDid(null);

      expectResetWithSessionChangedError();

      pendingProfiles[didA]!.completeError(NetworkException('offline'));
      await loadA;

      expectResetWithSessionChangedError();
    });

    test('switching accounts during a load drops the load and shows the '
        'session-changed error, even after the load succeeds', () async {
      final loadA = provider.loadProfile(didA);

      authProvider.setSignedInDid(otherAccountDid);

      expectResetWithSessionChangedError();

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expectResetWithSessionChangedError();
    });

    test('switching accounts during a load drops the load and shows the '
        'session-changed error, even after the load fails', () async {
      final loadA = provider.loadProfile(didA);

      authProvider.setSignedInDid(otherAccountDid);

      expectResetWithSessionChangedError();

      pendingProfiles[didA]!.completeError(NetworkException('offline'));
      await loadA;

      expectResetWithSessionChangedError();
    });

    test('signing out while showing a profile clears it and shows the '
        'session-changed error', () async {
      final loadA = provider.loadProfile(didA);
      pendingProfiles[didA]!.complete(profileA);
      await loadA;
      expect(provider.profile, same(profileA), reason: 'precondition');

      authProvider.setSignedInDid(null);

      expectResetWithSessionChangedError();
    });

    test('switching accounts while showing a profile clears it and shows the '
        'session-changed error', () async {
      final loadA = provider.loadProfile(didA);
      pendingProfiles[didA]!.complete(profileA);
      await loadA;
      expect(provider.profile, same(profileA), reason: 'precondition');

      authProvider.setSignedInDid(otherAccountDid);

      expectResetWithSessionChangedError();
    });

    test('signing out before anything was loaded leaves profileError '
        'null', () {
      authProvider.setSignedInDid(null);

      expect(provider.profile, isNull);
      expect(provider.currentProfileDid, isNull);
      expect(provider.isLoadingProfile, isFalse);
      expect(provider.profileError, isNull);
    });

    test('switching accounts before anything was loaded leaves profileError '
        'null', () {
      authProvider.setSignedInDid(otherAccountDid);

      expect(provider.profile, isNull);
      expect(provider.currentProfileDid, isNull);
      expect(provider.isLoadingProfile, isFalse);
      expect(provider.profileError, isNull);
    });
  });

  group('UserProfileProvider when an auth notification keeps the same '
      'account', () {
    /// A provider whose viewer is signed out from the start, with its own
    /// auth provider and cache.
    ({FakeAuthProvider auth, UserProfileProvider provider})
    newSignedOutProvider() {
      final signedOutAuth = FakeAuthProvider();
      final signedOutCache = ProfileCache(signedOutAuth);
      final signedOutProvider = UserProfileProvider(
        signedOutAuth,
        apiService: mockApiService,
        commentService: MockCommentService(),
        profileCache: signedOutCache,
      );
      addTearDown(() {
        signedOutProvider.dispose();
        signedOutCache.dispose();
      });
      return (auth: signedOutAuth, provider: signedOutProvider);
    }

    test('signed out from the start: a notification keeps the in-flight '
        'load, which then lands', () async {
      final (auth: signedOutAuth, provider: signedOutProvider) =
          newSignedOutProvider();
      final loadA = signedOutProvider.loadProfile(didA);

      signedOutAuth.setSignedInDid(null);

      expect(signedOutProvider.isLoadingProfile, isTrue);
      expect(signedOutProvider.currentProfileDid, didA);

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expect(signedOutProvider.profile, same(profileA));
      expect(signedOutProvider.currentProfileDid, didA);
      expect(signedOutProvider.isLoadingProfile, isFalse);
      expect(signedOutProvider.profileError, isNull);
    });

    test('signed out from the start: a notification keeps the shown '
        'profile', () async {
      final (auth: signedOutAuth, provider: signedOutProvider) =
          newSignedOutProvider();
      final loadA = signedOutProvider.loadProfile(didA);
      pendingProfiles[didA]!.complete(profileA);
      await loadA;
      expect(signedOutProvider.profile, same(profileA), reason: 'precondition');

      signedOutAuth.setSignedInDid(null);

      expect(signedOutProvider.profile, same(profileA));
      expect(signedOutProvider.currentProfileDid, didA);
      expect(signedOutProvider.profileError, isNull);
    });

    test('signed in with an unchanged DID: a notification keeps the '
        'in-flight load, which then lands', () async {
      final loadA = provider.loadProfile(didA);

      authProvider.setSignedInDid(myDid);

      expect(provider.isLoadingProfile, isTrue);
      expect(provider.currentProfileDid, didA);

      pendingProfiles[didA]!.complete(profileA);
      await loadA;

      expect(provider.profile, same(profileA));
      expect(provider.currentProfileDid, didA);
      expect(provider.isLoadingProfile, isFalse);
      expect(provider.profileError, isNull);
    });

    test('signed in with an unchanged DID: a notification keeps the shown '
        'profile', () async {
      final loadA = provider.loadProfile(didA);
      pendingProfiles[didA]!.complete(profileA);
      await loadA;
      expect(provider.profile, same(profileA), reason: 'precondition');

      authProvider.setSignedInDid(myDid);

      expect(provider.profile, same(profileA));
      expect(provider.currentProfileDid, didA);
      expect(provider.profileError, isNull);
    });
  });

  group('UserProfileProvider disposal', () {
    test('a pending load that succeeds after dispose throws nothing', () async {
      final loadA = provider.loadProfile(didA);
      provider.dispose();
      providerDisposed = true;

      pendingProfiles[didA]!.complete(profileA);

      await expectLater(loadA, completes);
    });

    test('a pending load that fails after dispose throws nothing', () async {
      final loadA = provider.loadProfile(didA);
      provider.dispose();
      providerDisposed = true;

      pendingProfiles[didA]!.completeError(NetworkException('offline'));

      await expectLater(loadA, completes);
    });

    test('a disposed provider is not notified of a sibling put for its '
        'DID', () async {
      final loadA = provider.loadProfile(didA);
      pendingProfiles[didA]!.complete(profileA);
      await loadA;
      expect(provider.profile, same(profileA), reason: 'precondition');
      var disposedProviderNotifications = 0;
      provider
        ..addListener(() => disposedProviderNotifications++)
        ..dispose();
      providerDisposed = true;

      final sibling = UserProfileProvider(
        authProvider,
        apiService: mockApiService,
        commentService: MockCommentService(),
        profileCache: profileCache,
      );
      addTearDown(sibling.dispose);
      final refreshedProfileA = UserProfile(
        did: didA,
        displayName: 'Refreshed A',
      );
      pendingProfiles[didA] = Completer<UserProfile>()
        ..complete(refreshedProfileA);

      await expectLater(
        sibling.loadProfile(didA, forceRefresh: true),
        completes,
      );

      expect(sibling.profile, same(refreshedProfileA), reason: 'precondition');
      expect(profileCache.get(didA), same(refreshedProfileA));
      expect(disposedProviderNotifications, 0);
    });
  });

  group('UserProfileProvider after a sign-out drops a load', () {
    test('is not loading, and a later load lands', () async {
      unawaited(provider.loadProfile(didA));
      expect(provider.isLoadingProfile, isTrue, reason: 'precondition');

      authProvider.setSignedInDid(null);

      expect(provider.isLoadingProfile, isFalse);

      final loadB = provider.loadProfile(didB);
      expect(provider.isLoadingProfile, isTrue);
      pendingProfiles[didB]!.complete(profileB);
      await loadB;

      expect(provider.profile, same(profileB));
      expect(provider.currentProfileDid, didB);
      expect(provider.isLoadingProfile, isFalse);
      expect(provider.profileError, isNull);
    });
  });
}
