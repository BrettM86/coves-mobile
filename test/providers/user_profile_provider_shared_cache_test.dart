import 'dart:async';

import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const myDid = 'did:plc:me';
  const profileDid = 'did:plc:x';

  late FakeAuthProvider authProvider;
  late MockCovesApiService mockApiService;
  late ProfileCache profileCache;

  /// Responses handed out by getProfile, in call order.
  late List<Future<UserProfile>> profileResponses;

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    mockApiService = MockCovesApiService();
    profileCache = ProfileCache(authProvider);
    profileResponses = [];

    when(mockApiService.getProfile(actor: anyNamed('actor'))).thenAnswer((
      invocation,
    ) {
      if (profileResponses.isEmpty) {
        final actor = invocation.namedArguments[#actor] as String;
        return Future.value(
          UserProfile(did: actor, displayName: 'Unexpected extra fetch'),
        );
      }
      return profileResponses.removeAt(0);
    });
  });

  tearDown(() {
    profileCache.dispose();
  });

  /// A provider wired to the shared cache and API mock, disposed after the
  /// test.
  UserProfileProvider newProvider() {
    final provider = UserProfileProvider(
      authProvider,
      apiService: mockApiService,
      commentService: MockCommentService(),
      profileCache: profileCache,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  group('UserProfileProvider with a shared ProfileCache', () {
    test('a loaded profile is written into the shared cache', () async {
      final loaded = UserProfile(did: profileDid, displayName: 'Loaded');
      profileResponses.add(Future.value(loaded));

      await newProvider().loadProfile(profileDid);

      expect(profileCache.get(profileDid), same(loaded));
    });

    test('a second provider sharing the cache gets the profile immediately '
        'without another API call', () async {
      final loaded = UserProfile(did: profileDid, displayName: 'Loaded');
      profileResponses.add(Future.value(loaded));
      final providerA = newProvider();
      final providerB = newProvider();

      await providerA.loadProfile(profileDid);

      final loadB = providerB.loadProfile(profileDid);

      // Checked before awaiting: a cache hit must be synchronous.
      expect(providerB.profile, same(loaded));
      expect(providerB.isLoadingProfile, isFalse);

      await loadB;

      verify(mockApiService.getProfile(actor: profileDid)).called(1);
    });

    test('forceRefresh fetches again and a later provider sees the refreshed '
        'profile without another API call', () async {
      final original = UserProfile(did: profileDid, displayName: 'Original');
      final refreshed = UserProfile(did: profileDid, displayName: 'Refreshed');
      profileResponses
        ..add(Future.value(original))
        ..add(Future.value(refreshed));
      final providerA = newProvider();
      final providerB = newProvider();
      final providerC = newProvider();

      await providerA.loadProfile(profileDid);
      await providerB.loadProfile(profileDid, forceRefresh: true);
      await providerC.loadProfile(profileDid);

      expect(providerB.profile, same(refreshed));
      expect(providerC.profile?.displayName, 'Refreshed');
      expect(providerC.profile, same(refreshed));
      verify(mockApiService.getProfile(actor: profileDid)).called(2);
    });
  });

  group('UserProfileProvider stale responses', () {
    test('a response for a request started before sign-out is not written '
        'into the shared cache', () async {
      final staleResponse = Completer<UserProfile>();
      final fresh = UserProfile(did: profileDid, displayName: 'Fresh');
      profileResponses
        ..add(staleResponse.future)
        ..add(Future.value(fresh));
      final providerA = newProvider();

      final staleLoad = providerA.loadProfile(profileDid);
      authProvider.setSignedInDid(null);
      staleResponse.complete(
        UserProfile(did: profileDid, displayName: 'Stale'),
      );
      await staleLoad;

      expect(
        profileCache.get(profileDid),
        isNull,
        reason: 'the old session response must not be cached',
      );

      // A request in the new session is still cached.
      authProvider.setSignedInDid(myDid);
      await newProvider().loadProfile(profileDid);

      expect(profileCache.get(profileDid), same(fresh));
    });

    test('a response for a request started before the signed-in DID changed '
        'is not written into the shared cache', () async {
      final staleResponse = Completer<UserProfile>();
      final fresh = UserProfile(did: profileDid, displayName: 'Fresh');
      profileResponses
        ..add(staleResponse.future)
        ..add(Future.value(fresh));
      final providerA = newProvider();

      final staleLoad = providerA.loadProfile(profileDid);
      authProvider.setSignedInDid('did:plc:another-account');
      staleResponse.complete(
        UserProfile(did: profileDid, displayName: 'Stale'),
      );
      await staleLoad;

      expect(
        profileCache.get(profileDid),
        isNull,
        reason: 'the previous account response must not be cached',
      );

      // A request in the new account's session is still cached.
      await newProvider().loadProfile(profileDid);

      expect(profileCache.get(profileDid), same(fresh));
    });
  });
}
