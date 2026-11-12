import 'dart:async';

import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/bluesky_profile_import_offer_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _aliceDid = 'did:plc:alice';
const _bobDid = 'did:plc:bob';

const _offer = BlueskyProfileImport(
  status: BlueskyProfileImportStatus.offer,
  fields: [
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.displayName,
      bluesky: 'Alice',
      covesIsEmpty: true,
    ),
    BlueskyProfileImportFieldView(
      field: BlueskyProfileField.description,
      bluesky: 'Bio text',
      covesIsEmpty: false,
    ),
  ],
);

const _nothingToImport = BlueskyProfileImport(
  status: BlueskyProfileImportStatus.nothingToImport,
  fields: [],
);

List<(BlueskyProfileField, bool)>? _pendingValues(
  BlueskyProfileImportOfferProvider provider,
) => provider.pendingChoices
    ?.map((choice) => (choice.view.field, choice.initiallyChecked))
    .toList();

void main() {
  late FakeAuthProvider auth;
  late ProfileCache cache;
  late MockCovesApiService apiService;
  late Object? sessionKey;
  BlueskyProfileImportOfferProvider? provider;

  setUp(() {
    auth = FakeAuthProvider(signedInDid: _aliceDid);
    cache = ProfileCache(auth);
    apiService = MockCovesApiService();
    sessionKey = 'alice-session-1';
    provider = null;
    when(apiService.dismissBlueskyProfileImport()).thenAnswer((_) async {});
  });

  tearDown(() {
    provider?.dispose();
    cache.dispose();
    auth.dispose();
  });

  BlueskyProfileImportOfferProvider createProvider() =>
      provider = BlueskyProfileImportOfferProvider(
        apiService: apiService,
        authProvider: auth,
        sessionKeyOf: () => sessionKey,
        profileCache: cache,
      );

  test('a signed-in offer exposes pending choices for the empty '
      'fields', () async {
    when(apiService.getBlueskyProfileImport()).thenAnswer((_) async => _offer);

    final offers = createProvider();
    await pumpEventQueue();

    expect(_pendingValues(offers), [(BlueskyProfileField.displayName, true)]);
  });

  test('auth notifications within the same session key never '
      'refetch', () async {
    when(apiService.getBlueskyProfileImport()).thenAnswer((_) async => _offer);

    final offers = createProvider();
    await pumpEventQueue();
    offers.markShown();
    auth.notifyWithoutChange();
    await pumpEventQueue();

    expect(offers.pendingChoices, isNull);
    verify(apiService.getBlueskyProfileImport()).called(1);
  });

  test('sign-out then the same account signing in again under a new '
      'session key refetches', () async {
    when(apiService.getBlueskyProfileImport()).thenAnswer((_) async => _offer);

    final offers = createProvider();
    await pumpEventQueue();
    offers.markShown();

    sessionKey = null;
    auth.setSignedInDid(null);
    await pumpEventQueue();
    sessionKey = 'alice-session-2';
    auth.setSignedInDid(_aliceDid);
    await pumpEventQueue();

    expect(_pendingValues(offers), [(BlueskyProfileField.displayName, true)]);
    verify(apiService.getBlueskyProfileImport()).called(2);
  });

  test('a fetch that completes after an account switch is discarded', () async {
    final aliceFetch = Completer<BlueskyProfileImport>();
    final bobFetch = Completer<BlueskyProfileImport>();
    final answers = [aliceFetch.future, bobFetch.future];
    when(apiService.getBlueskyProfileImport())
        .thenAnswer((_) => answers.removeAt(0));

    final offers = createProvider();
    await pumpEventQueue();
    sessionKey = 'bob-session-1';
    auth.setSignedInDid(_bobDid);
    await pumpEventQueue();
    aliceFetch.complete(_offer);
    await pumpEventQueue();

    expect(offers.pendingChoices, isNull);

    bobFetch.complete(_nothingToImport);
    await pumpEventQueue();
    expect(offers.pendingChoices, isNull);
  });

  test('a fetch error leaves no pending choices', () async {
    when(apiService.getBlueskyProfileImport())
        .thenAnswer((_) async => throw ApiException('fetch failed'));

    final offers = createProvider();
    await pumpEventQueue();

    expect(offers.pendingChoices, isNull);
  });

  test('decline calls dismiss and clears pending choices', () async {
    when(apiService.getBlueskyProfileImport()).thenAnswer((_) async => _offer);

    final offers = createProvider();
    await pumpEventQueue();
    await offers.decline();

    expect(offers.pendingChoices, isNull);
    verify(apiService.dismissBlueskyProfileImport()).called(1);
  });

  test('markShown clears pending choices without calling dismiss', () async {
    when(apiService.getBlueskyProfileImport()).thenAnswer((_) async => _offer);

    final offers = createProvider();
    await pumpEventQueue();
    offers.markShown();
    await pumpEventQueue();

    expect(offers.pendingChoices, isNull);
    verifyNever(apiService.dismissBlueskyProfileImport());
  });

  test('importFields returns the imported fields and clears pending choices, '
      'refreshing the own profile when it can', () async {
    final rows =
        <
          ({
            String label,
            Future<UserProfile> Function() refresh,
            String? cachedDisplayName,
          })
        >[
          (
            label: 'refresh succeeds',
            refresh: () async =>
                UserProfile(did: _aliceDid, displayName: 'Alice Imported'),
            cachedDisplayName: 'Alice Imported',
          ),
          (
            label: 'refresh fails',
            refresh: () async => throw ApiException('refresh failed'),
            cachedDisplayName: null,
          ),
        ];

    for (final row in rows) {
      final rowAuth = FakeAuthProvider(signedInDid: _aliceDid);
      final rowCache = ProfileCache(rowAuth);
      final rowApi = MockCovesApiService();
      when(rowApi.getBlueskyProfileImport()).thenAnswer((_) async => _offer);
      when(rowApi.importBlueskyProfile([BlueskyProfileField.displayName]))
          .thenAnswer((_) async => [BlueskyProfileField.displayName]);
      when(rowApi.getProfile(actor: _aliceDid))
          .thenAnswer((_) => row.refresh());
      final offers = BlueskyProfileImportOfferProvider(
        apiService: rowApi,
        authProvider: rowAuth,
        sessionKeyOf: () => 'alice-session-1',
        profileCache: rowCache,
      );
      addTearDown(() {
        offers.dispose();
        rowCache.dispose();
        rowAuth.dispose();
      });
      await pumpEventQueue();

      final imported = await offers.importFields([
        BlueskyProfileField.displayName,
      ]);

      expect(imported, [BlueskyProfileField.displayName], reason: row.label);
      expect(offers.pendingChoices, isNull, reason: row.label);
      expect(
        rowCache.get(_aliceDid)?.displayName,
        row.cachedDisplayName,
        reason: row.label,
      );
    }
  });
}
