// Every profile screen owns its own UserProfileProvider, but they share one
// ProfileCache. When one provider refreshes a profile (after updateProfile),
// a sibling provider already showing that DID adopts the refreshed profile
// and notifies, without being asked to reload. Siblings showing a different
// DID are left alone.

import 'dart:async';

import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String otherDid = 'did:plc:other';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late ProfileCache profileCache;

  /// What the server returns for my profile; updateProfile replaces it.
  late UserProfile myServerProfile;

  final otherProfile = UserProfile(
    did: otherDid,
    handle: 'other.coves.test',
    displayName: 'Other Person',
  );

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    apiService = MockCovesApiService();
    profileCache = ProfileCache(authProvider);
    myServerProfile = UserProfile(
      did: myDid,
      handle: 'me.coves.test',
      displayName: 'Old name',
    );

    when(apiService.getProfile(actor: anyNamed('actor')))
        .thenAnswer((invocation) async {
          final actor = invocation.namedArguments[#actor] as String;
          if (actor == myDid) {
            return myServerProfile;
          }
          if (actor == otherDid) {
            return otherProfile;
          }
          throw StateError('Unexpected getProfile actor: $actor');
        });

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
        handle: 'me.coves.test',
        displayName: invocation.namedArguments[#displayName] as String?,
      );
      return const UpdateProfileResponse(
        uri: 'at://did:plc:me/social.coves.actor.profile/self',
        cid: 'cid-updated',
      );
    });
  });

  tearDown(() {
    profileCache.dispose();
    authProvider.dispose();
  });

  /// A provider wired to the shared cache and API mock, disposed after the
  /// test.
  UserProfileProvider newProvider() {
    final provider = UserProfileProvider(
      authProvider,
      apiService: apiService,
      commentService: MockCommentService(),
      profileCache: profileCache,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  test(
    'a sibling showing the same DID adopts the refreshed profile after '
    'updateProfile, and a sibling showing another DID is untouched',
    () async {
      final providerA = newProvider();
      final providerB = newProvider();
      final providerOther = newProvider();

      await providerA.loadProfile(myDid);
      await providerB.loadProfile(myDid);
      await providerOther.loadProfile(otherDid);
      expect(providerA.profile?.displayName, 'Old name');
      expect(providerB.profile?.displayName, 'Old name');

      var providerANotifications = 0;
      providerA.addListener(() => providerANotifications++);
      var providerOtherNotifications = 0;
      providerOther.addListener(() => providerOtherNotifications++);

      await providerB.updateProfile(displayName: 'New name');
      // Allow an asynchronous hand-off between siblings to land.
      await Future<void>.delayed(Duration.zero);

      verify(
        apiService.updateProfile(
          displayName: 'New name',
          bio: anyNamed('bio'),
          avatarBytes: anyNamed('avatarBytes'),
          avatarMimeType: anyNamed('avatarMimeType'),
          bannerBytes: anyNamed('bannerBytes'),
          bannerMimeType: anyNamed('bannerMimeType'),
        ),
      ).called(1);
      expect(providerB.profile?.displayName, 'New name');

      // Provider A never called loadProfile again, yet shows the refresh.
      expect(providerA.profile?.displayName, 'New name');
      expect(providerA.currentProfileDid, myDid);
      expect(providerANotifications, greaterThanOrEqualTo(1));

      // The sibling on another DID neither changed nor rebuilt.
      expect(providerOther.profile, same(otherProfile));
      expect(providerOther.currentProfileDid, otherDid);
      expect(providerOtherNotifications, 0);

      // My profile was fetched only by A's first load and B's forced refresh:
      // B's first load hit the cache, and A adopting the refresh made no
      // request of its own.
      verify(apiService.getProfile(actor: myDid)).called(2);
      verify(apiService.getProfile(actor: otherDid)).called(1);
    },
  );

  group('adopting a sibling put of the same DID', () {
    /// Other's profile as a sibling fetched it most recently.
    final freshOtherProfile = UserProfile(
      did: otherDid,
      handle: 'other.coves.test',
      displayName: 'Fresh name',
    );

    /// Other's profile as an earlier request saw it.
    final olderOtherProfile = UserProfile(
      did: otherDid,
      handle: 'other.coves.test',
      displayName: 'Older name',
    );

    /// Answers successive getProfile(otherDid) calls with [responses], in
    /// order.
    void answerOtherProfileInOrder(
      List<Future<UserProfile> Function()> responses,
    ) {
      final remaining = List.of(responses);
      when(apiService.getProfile(actor: otherDid))
          .thenAnswer((_) => remaining.removeAt(0)());
    }

    test('a sibling put during a load wins over a late failure', () async {
      final pendingLoad = Completer<UserProfile>();
      answerOtherProfileInOrder([
        () => pendingLoad.future,
        () async => freshOtherProfile,
      ]);
      final providerA = newProvider();
      final providerB = newProvider();

      final loadB = providerB.loadProfile(otherDid);
      expect(providerB.isLoadingProfile, isTrue, reason: 'precondition');

      await providerA.loadProfile(otherDid);
      expect(
        providerA.profile,
        same(freshOtherProfile),
        reason: 'precondition',
      );

      pendingLoad.completeError(NotFoundException('Profile not found'));
      await loadB;

      expect(providerB.profile, same(freshOtherProfile));
      expect(providerB.isLoadingProfile, isFalse);
      expect(providerB.profileError, isNull);
    });

    test('a sibling put during a load wins over a late success with an older '
        'profile', () async {
      final pendingLoad = Completer<UserProfile>();
      answerOtherProfileInOrder([
        () => pendingLoad.future,
        () async => freshOtherProfile,
      ]);
      final providerA = newProvider();
      final providerB = newProvider();

      final loadB = providerB.loadProfile(otherDid);
      expect(providerB.isLoadingProfile, isTrue, reason: 'precondition');

      await providerA.loadProfile(otherDid);
      expect(
        providerA.profile,
        same(freshOtherProfile),
        reason: 'precondition',
      );

      pendingLoad.complete(olderOtherProfile);
      await loadB;

      expect(providerB.profile, same(freshOtherProfile));
      expect(providerB.isLoadingProfile, isFalse);
      expect(providerB.profileError, isNull);
      // The late result is ignored everywhere, not only by B.
      expect(profileCache.get(otherDid), same(freshOtherProfile));
      expect(providerA.profile, same(freshOtherProfile));
    });

    test('a sibling put clears the error of a failed refresh', () async {
      answerOtherProfileInOrder([
        () async => olderOtherProfile,
        () async => throw NetworkException('offline'),
        () async => freshOtherProfile,
      ]);
      final providerA = newProvider();
      final providerB = newProvider();

      await providerB.loadProfile(otherDid);
      await providerB.loadProfile(otherDid, forceRefresh: true);
      expect(
        providerB.profile,
        same(olderOtherProfile),
        reason: 'precondition',
      );
      expect(providerB.profileError, isNotNull, reason: 'precondition');

      await providerA.loadProfile(otherDid, forceRefresh: true);
      expect(
        providerA.profile,
        same(freshOtherProfile),
        reason: 'precondition',
      );

      expect(providerB.profile, same(freshOtherProfile));
      expect(providerB.profileError, isNull);
    });

    test('a sibling put does not replace the error of a failed first '
        'load', () async {
      answerOtherProfileInOrder([
        () async => throw NetworkException('offline'),
        () async => freshOtherProfile,
      ]);
      final providerA = newProvider();
      final providerB = newProvider();

      await providerB.loadProfile(otherDid);
      expect(providerB.profile, isNull, reason: 'precondition');
      final loadError = providerB.profileError;
      expect(loadError, isNotNull, reason: 'precondition');

      await providerA.loadProfile(otherDid);
      expect(
        providerA.profile,
        same(freshOtherProfile),
        reason: 'precondition',
      );

      expect(providerB.profile, isNull);
      expect(providerB.profileError, loadError);
    });
  });

  group('overlapping requests: the newer request wins, whichever response '
      'arrives first', () {
    /// Other's profile as the newer request sees it.
    final freshOtherProfile = UserProfile(
      did: otherDid,
      handle: 'other.coves.test',
      displayName: 'Fresh name',
    );

    /// Other's profile as the older request saw it.
    final olderOtherProfile = UserProfile(
      did: otherDid,
      handle: 'other.coves.test',
      displayName: 'Older name',
    );

    /// Answers successive getProfile([actor]) calls with the returned
    /// Completers, in order.
    List<Completer<UserProfile>> queuePendingProfiles(String actor, int count) {
      final pending = List.generate(count, (_) => Completer<UserProfile>());
      final remaining = List.of(pending);
      when(apiService.getProfile(actor: actor))
          .thenAnswer((_) => remaining.removeAt(0).future);
      return pending;
    }

    test('the newer request wins when the older one completes first', () async {
      final [olderRequest, newerRequest] = queuePendingProfiles(otherDid, 2);
      final providerA = newProvider();
      final providerB = newProvider();

      final loadA = providerA.loadProfile(otherDid);
      final loadB = providerB.loadProfile(otherDid);
      verify(apiService.getProfile(actor: otherDid)).called(2);

      olderRequest.complete(olderOtherProfile);
      await loadA;
      await Future<void>.delayed(Duration.zero);

      newerRequest.complete(freshOtherProfile);
      await loadB;
      await Future<void>.delayed(Duration.zero);

      expect(profileCache.get(otherDid)?.displayName, 'Fresh name');
      expect(profileCache.get(otherDid), same(freshOtherProfile));
      expect(providerA.profile?.displayName, 'Fresh name');
      expect(providerA.profile, same(freshOtherProfile));
      expect(providerB.profile?.displayName, 'Fresh name');
      expect(providerB.profile, same(freshOtherProfile));
      expect(providerA.isLoadingProfile, isFalse);
      expect(providerB.isLoadingProfile, isFalse);
      expect(providerA.profileError, isNull);
      expect(providerB.profileError, isNull);
    });

    test('the newer request reports its own failure when the older one '
        'succeeded first', () async {
      final [olderRequest, newerRequest] = queuePendingProfiles(otherDid, 2);
      final providerA = newProvider();
      final providerB = newProvider();

      final loadA = providerA.loadProfile(otherDid);
      final loadB = providerB.loadProfile(otherDid);
      verify(apiService.getProfile(actor: otherDid)).called(2);

      olderRequest.complete(olderOtherProfile);
      await loadA;
      await Future<void>.delayed(Duration.zero);

      newerRequest.completeError(NetworkException('offline'));
      await loadB;

      expect(providerB.profileError, isNotNull);
      expect(providerB.isLoadingProfile, isFalse);
    });

    for (final secondRequestCompletesFirst in [false, true]) {
      final order = secondRequestCompletesFirst
          ? 'second request completes first'
          : 'first request completes first';
      test('requests for different DIDs do not suppress each other '
          '($order)', () async {
        final [otherRequest] = queuePendingProfiles(otherDid, 1);
        final [myRequest] = queuePendingProfiles(myDid, 1);
        final providerA = newProvider();
        final providerB = newProvider();

        final loadA = providerA.loadProfile(otherDid);
        final loadB = providerB.loadProfile(myDid);

        if (secondRequestCompletesFirst) {
          myRequest.complete(myServerProfile);
          await loadB;
          otherRequest.complete(freshOtherProfile);
          await loadA;
        } else {
          otherRequest.complete(freshOtherProfile);
          await loadA;
          myRequest.complete(myServerProfile);
          await loadB;
        }

        expect(providerA.profile, same(freshOtherProfile));
        expect(providerB.profile, same(myServerProfile));
        expect(profileCache.get(otherDid), same(freshOtherProfile));
        expect(profileCache.get(myDid), same(myServerProfile));
        expect(providerA.profileError, isNull);
        expect(providerB.profileError, isNull);
      });
    }
  });

  group('a save whose provider is disposed during the follow-up fetch', () {
    /// My profile as the save's follow-up fetch returns it.
    final updatedProfile = UserProfile(
      did: myDid,
      handle: 'me.coves.test',
      displayName: 'Old name',
      bio: 'New bio',
    );

    /// Both providers show my profile; the next getProfile(myDid) stays
    /// pending on the returned Completer, and earlier requests are cleared
    /// from the mock's record. Each test disposes provider B itself.
    Future<
      ({
        UserProfileProvider providerA,
        UserProfileProvider providerB,
        Completer<UserProfile> pendingRefresh,
      })
    >
    showMyProfileInTwoProviders() async {
      final providerA = newProvider();
      final providerB = UserProfileProvider(
        authProvider,
        apiService: apiService,
        commentService: MockCommentService(),
        profileCache: profileCache,
      );
      await providerA.loadProfile(myDid);
      await providerB.loadProfile(myDid);
      expect(providerA.profile?.bio, isNull, reason: 'precondition');
      expect(providerB.isOwnProfile, isTrue, reason: 'precondition');

      clearInteractions(apiService);
      final pendingRefresh = Completer<UserProfile>();
      when(apiService.getProfile(actor: myDid))
          .thenAnswer((_) => pendingRefresh.future);
      return (
        providerA: providerA,
        providerB: providerB,
        pendingRefresh: pendingRefresh,
      );
    }

    test('still puts the refreshed profile in the cache, and a sibling '
        'showing my profile adopts it', () async {
      final (:providerA, :providerB, :pendingRefresh) =
          await showMyProfileInTwoProviders();

      final save = providerB.updateProfile(bio: 'New bio');
      // Let the API update complete and the follow-up fetch start.
      await Future<void>.delayed(Duration.zero);
      verify(apiService.getProfile(actor: myDid)).called(1);
      expect(providerB.isLoadingProfile, isTrue, reason: 'precondition');

      providerB.dispose();
      pendingRefresh.complete(updatedProfile);
      await expectLater(save, completes);

      expect(profileCache.get(myDid)?.bio, 'New bio');
      expect(profileCache.get(myDid), same(updatedProfile));
      expect(providerA.profile?.bio, 'New bio');
      expect(providerA.profile, same(updatedProfile));
      verifyNever(apiService.getProfile(actor: anyNamed('actor')));
    });

    test('does not cache the refreshed profile when the signed-in account '
        'changed while the fetch was pending', () async {
      final (:providerA, :providerB, :pendingRefresh) =
          await showMyProfileInTwoProviders();

      final save = providerB.updateProfile(bio: 'New bio');
      await Future<void>.delayed(Duration.zero);
      verify(apiService.getProfile(actor: myDid)).called(1);

      providerB.dispose();
      authProvider.setSignedInDid(otherDid);
      pendingRefresh.complete(updatedProfile);
      await save;

      expect(profileCache.get(myDid), isNull);
      expect(providerA.profile, isNull);
    });
  });
}
