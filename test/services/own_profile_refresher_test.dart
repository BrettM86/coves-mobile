import 'dart:async';

import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/services/own_profile_refresher.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _did = 'did:plc:alice';

void main() {
  late FakeAuthProvider auth;
  late ProfileCache cache;
  late MockCovesApiService apiService;

  setUp(() {
    auth = FakeAuthProvider(signedInDid: _did);
    cache = ProfileCache(auth);
    apiService = MockCovesApiService();
  });

  tearDown(() {
    cache.dispose();
    auth.dispose();
  });

  test('refreshOwnProfile puts the fetched profile in the cache', () async {
    when(apiService.getProfile(actor: _did)).thenAnswer(
      (_) async => UserProfile(did: _did, displayName: 'Alice Fetched'),
    );

    await refreshOwnProfile(apiService: apiService, cache: cache, did: _did);

    expect(cache.get(_did)?.displayName, 'Alice Fetched');
  });

  test('a newer put landing while the fetch is pending wins over the '
      'older fetch result', () async {
    final pendingProfile = Completer<UserProfile>();
    when(apiService.getProfile(actor: _did))
        .thenAnswer((_) => pendingProfile.future);

    final refresh = refreshOwnProfile(
      apiService: apiService,
      cache: cache,
      did: _did,
    );
    await pumpEventQueue();
    cache.put(UserProfile(did: _did, displayName: 'Alice Newer'));
    pendingProfile.complete(UserProfile(did: _did, displayName: 'Alice Older'));
    await refresh;

    expect(cache.get(_did)?.displayName, 'Alice Newer');
  });

  test('a sign-out during the fetch means its result is not cached', () async {
    final pendingProfile = Completer<UserProfile>();
    when(apiService.getProfile(actor: _did))
        .thenAnswer((_) => pendingProfile.future);

    final refresh = refreshOwnProfile(
      apiService: apiService,
      cache: cache,
      did: _did,
    );
    await pumpEventQueue();
    auth.setSignedInDid(null);
    pendingProfile.complete(UserProfile(did: _did, displayName: 'Alice Stale'));
    await refresh;

    expect(cache.get(_did), isNull);
  });
}
