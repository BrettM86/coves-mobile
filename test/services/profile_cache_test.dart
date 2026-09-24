import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_providers.dart';

UserProfile _profile(String did, {String? displayName}) =>
    UserProfile(did: did, displayName: displayName ?? 'Name of $did');

String _didFor(int index) => 'did:plc:user$index';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const myDid = 'did:plc:me';

  late FakeAuthProvider authProvider;
  late ProfileCache cache;

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    cache = ProfileCache(authProvider);
  });

  tearDown(() {
    cache.dispose();
  });

  /// Fills the cache to capacity with user0 (oldest) .. user49 (newest).
  List<UserProfile> fillToCapacity() {
    return [
      for (var index = 0; index < ProfileCache.maxEntries; index++)
        _profile(_didFor(index)),
    ]..forEach(cache.put);
  }

  group('ProfileCache LRU', () {
    test('get of a DID that was never put returns null', () {
      expect(cache.get('did:plc:missing'), isNull);
    });

    test('put then get by DID returns the profile', () {
      final profile = _profile('did:plc:alice');

      cache.put(profile);

      expect(cache.get('did:plc:alice'), same(profile));
    });

    test('putting a newer profile for the same DID replaces it', () {
      final older = _profile('did:plc:alice', displayName: 'Old name');
      final newer = _profile('did:plc:alice', displayName: 'New name');

      cache
        ..put(older)
        ..put(newer);

      expect(cache.get('did:plc:alice'), same(newer));
    });

    test('putting one more distinct DID at capacity evicts the least '
        'recently used entry', () {
      final profiles = fillToCapacity();
      final extra = _profile(_didFor(ProfileCache.maxEntries));

      cache.put(extra);

      expect(cache.get(_didFor(0)), isNull, reason: 'oldest entry evicted');
      for (var index = 1; index < ProfileCache.maxEntries; index++) {
        expect(
          cache.get(_didFor(index)),
          same(profiles[index]),
          reason: '${_didFor(index)} should remain cached',
        );
      }
      expect(cache.get(extra.did), same(extra));
    });

    test('get refreshes recency, so the next-oldest entry is evicted', () {
      final profiles = fillToCapacity();

      // Touch the oldest entry so it becomes most recently used.
      expect(cache.get(_didFor(0)), same(profiles[0]));

      final extra = _profile(_didFor(ProfileCache.maxEntries));
      cache.put(extra);

      expect(cache.get(_didFor(0)), same(profiles[0]));
      expect(
        cache.get(_didFor(1)),
        isNull,
        reason: 'user1 was the least recently used after user0 was read',
      );
      for (var index = 2; index < ProfileCache.maxEntries; index++) {
        expect(cache.get(_didFor(index)), same(profiles[index]));
      }
      expect(cache.get(extra.did), same(extra));
    });

    test('re-putting an existing DID at capacity evicts nothing', () {
      final profiles = fillToCapacity();
      final refreshedOldest = _profile(_didFor(0), displayName: 'Refreshed');

      cache.put(refreshedOldest);

      expect(cache.get(_didFor(0)), same(refreshedOldest));
      for (var index = 1; index < ProfileCache.maxEntries; index++) {
        expect(
          cache.get(_didFor(index)),
          same(profiles[index]),
          reason: '${_didFor(index)} should not have been evicted',
        );
      }
    });
  });

  group('ProfileCache put listeners', () {
    test('a throwing listener does not stop later listeners, put does not '
        'throw, the profile is stored, and the error is reported', () {
      final reportedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      addTearDown(() => FlutterError.onError = originalOnError);

      final listenerError = StateError('listener failed');
      cache.addPutListener((_) => throw listenerError);
      final laterListenerProfiles = <UserProfile>[];
      cache.addPutListener(laterListenerProfiles.add);
      final alice = _profile('did:plc:alice');

      expect(() => cache.put(alice), returnsNormally);

      expect(laterListenerProfiles, [same(alice)]);
      expect(cache.get(alice.did), same(alice));
      expect(reportedErrors, hasLength(1));
      expect(reportedErrors.single.exception, same(listenerError));
    });
  });

  group('ProfileCache auth', () {
    test('clears when the auth provider notifies it is signed out', () {
      final alice = _profile('did:plc:alice');
      final bob = _profile('did:plc:bob');
      cache
        ..put(alice)
        ..put(bob);
      expect(cache.get(alice.did), same(alice), reason: 'precondition');
      expect(cache.get(bob.did), same(bob), reason: 'precondition');

      authProvider.setSignedInDid(null);

      expect(cache.get(alice.did), isNull);
      expect(cache.get(bob.did), isNull);
    });

    test('clears when the auth provider notifies a different signed-in '
        'DID', () {
      final alice = _profile('did:plc:alice');
      final bob = _profile('did:plc:bob');
      cache
        ..put(alice)
        ..put(bob);
      expect(cache.get(alice.did), same(alice), reason: 'precondition');
      expect(cache.get(bob.did), same(bob), reason: 'precondition');

      authProvider.setSignedInDid('did:plc:someone-else');

      expect(cache.get(alice.did), isNull);
      expect(cache.get(bob.did), isNull);
    });

    test('keeps entries when the auth provider notifies with the same '
        'signed-in DID', () {
      final alice = _profile('did:plc:alice');
      cache.put(alice);

      authProvider.notifyWithoutChange();

      expect(cache.get(alice.did), same(alice));
    });

    test('keeps entries and generation when the auth provider notifies while '
        'still signed out', () {
      final signedOutAuthProvider = FakeAuthProvider();
      final signedOutCache = ProfileCache(signedOutAuthProvider);
      addTearDown(signedOutCache.dispose);
      final alice = _profile('did:plc:alice');
      signedOutCache.put(alice);
      final generationBefore = signedOutCache.generation;

      signedOutAuthProvider.notifyWithoutChange();

      expect(signedOutCache.get(alice.did), same(alice));
      expect(signedOutCache.generation, generationBefore);
    });

    test('generation increments on sign-out and on account change, and is '
        'unchanged after a same-DID notification', () {
      final initialGeneration = cache.generation;

      authProvider.notifyWithoutChange();
      expect(cache.generation, initialGeneration);

      authProvider.setSignedInDid(null);
      expect(cache.generation, initialGeneration + 1);

      authProvider.setSignedInDid(myDid);
      final signedInGeneration = cache.generation;

      authProvider.setSignedInDid('did:plc:someone-else');
      expect(cache.generation, signedInGeneration + 1);

      authProvider.notifyWithoutChange();
      expect(cache.generation, signedInGeneration + 1);
    });

    test('clears a profile cached while signed out when the viewer signs '
        'in', () {
      final signedOutAuthProvider = FakeAuthProvider();
      final signedOutCache = ProfileCache(signedOutAuthProvider);
      addTearDown(signedOutCache.dispose);
      final alice = _profile('did:plc:alice');
      signedOutCache.put(alice);
      expect(
        signedOutCache.get(alice.did),
        same(alice),
        reason: 'precondition',
      );

      signedOutAuthProvider.setSignedInDid(myDid);

      expect(signedOutCache.get(alice.did), isNull);
    });

    test('still stores profiles after being cleared by a sign-out', () {
      cache.put(_profile('did:plc:alice'));
      authProvider.setSignedInDid(null);
      final bob = _profile('did:plc:bob');

      cache.put(bob);

      expect(cache.get(bob.did), same(bob));
    });

    test('listens to the auth provider until disposed', () {
      final separateAuthProvider = FakeAuthProvider(signedInDid: myDid);
      final separateCache = ProfileCache(separateAuthProvider);

      expect(
        separateAuthProvider.isObserved,
        isTrue,
        reason: 'the cache must listen for sign-out and account changes',
      );

      separateCache.dispose();

      expect(
        separateAuthProvider.isObserved,
        isFalse,
        reason: 'dispose must remove the auth listener',
      );
    });
  });

  group('ProfileCache request ordering', () {
    const aliceDid = 'did:plc:alice';
    const bobDid = 'did:plc:bob';

    test('a put with an older request sequence than the cached entry is '
        'ignored and not announced', () {
      final olderSequence = cache.nextRequestSequence();
      final newerSequence = cache.nextRequestSequence();
      final newer = _profile(aliceDid, displayName: 'New name');
      final older = _profile(aliceDid, displayName: 'Old name');
      cache.put(newer, requestSequence: newerSequence);
      final announced = <UserProfile>[];
      cache.addPutListener(announced.add);
      expect(cache.get(aliceDid), same(newer), reason: 'precondition');

      cache.put(older, requestSequence: olderSequence);

      expect(cache.get(aliceDid), same(newer));
      expect(announced, isEmpty);
    });

    test('a put with a newer request sequence replaces the entry and is '
        'announced', () {
      final olderSequence = cache.nextRequestSequence();
      final newerSequence = cache.nextRequestSequence();
      final older = _profile(aliceDid, displayName: 'Old name');
      final newer = _profile(aliceDid, displayName: 'New name');
      cache.put(older, requestSequence: olderSequence);
      final announced = <UserProfile>[];
      cache.addPutListener(announced.add);
      expect(cache.get(aliceDid), same(older), reason: 'precondition');

      cache.put(newer, requestSequence: newerSequence);

      expect(cache.get(aliceDid), same(newer));
      expect(announced, [same(newer)]);
    });

    test('a put without a request sequence counts as newest and replaces an '
        'entry that has one', () {
      final sequenced = _profile(aliceDid, displayName: 'Sequenced');
      cache.put(sequenced, requestSequence: cache.nextRequestSequence());
      final unsequenced = _profile(aliceDid, displayName: 'Unsequenced');

      cache.put(unsequenced);

      expect(cache.get(aliceDid), same(unsequenced));
    });

    test('ordering is per DID: an older sequence for one DID is accepted '
        'when only another DID holds a newer one', () {
      final olderSequence = cache.nextRequestSequence();
      final newerSequence = cache.nextRequestSequence();
      cache.put(_profile(aliceDid), requestSequence: newerSequence);
      final bob = _profile(bobDid);

      cache.put(bob, requestSequence: olderSequence);

      expect(cache.get(bobDid), same(bob));
    });

    test('requestSequenceOf does not change the LRU order', () {
      fillToCapacity();
      final oldestDid = _didFor(0);

      expect(cache.requestSequenceOf(oldestDid), isNotNull);
      cache.put(_profile(_didFor(ProfileCache.maxEntries)));

      expect(cache.get(oldestDid), isNull, reason: 'oldest entry evicted');
      expect(cache.get(_didFor(1)), isNotNull);
    });

    test('after a session clear, a put with any request sequence is '
        'accepted', () {
      final olderSequence = cache.nextRequestSequence();
      final newerSequence = cache.nextRequestSequence();
      cache.put(_profile(aliceDid), requestSequence: newerSequence);
      authProvider.setSignedInDid(null);
      final afterClear = _profile(aliceDid, displayName: 'After clear');

      cache.put(afterClear, requestSequence: olderSequence);

      expect(cache.get(aliceDid), same(afterClear));
    });
  });
}
