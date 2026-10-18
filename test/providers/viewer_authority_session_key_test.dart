import 'dart:async';

import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider auth;
  late MockCovesApiService api;

  setUp(() {
    auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
    api = MockCovesApiService();
    addTearDown(() => auth.dispose());
  });

  ViewerAuthorityProvider createProvider() {
    final provider = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  test('S1 the session key follows the signed-in session, '
      'not token refreshes or authority reloads', () async {
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    final provider = createProvider();
    await pumpEventQueue();
    expect(provider.status, ViewerAuthorityStatus.instanceAdmin);

    final k1 = provider.sessionKey;
    expect(k1, isNotNull);

    // A token refresh notifies with the same DID.
    auth.notifyWithoutChange();
    await pumpEventQueue();
    expect(provider.sessionKey, k1);

    // Reloading authority for the same session keeps the key.
    await provider.refresh();
    expect(provider.status, ViewerAuthorityStatus.instanceAdmin);
    expect(provider.sessionKey, k1);

    auth.setSignedInDid(null);
    expect(provider.sessionKey, isNull);

    // The same account signing in again is a new session.
    auth.setSignedInDid('did:plc:alice');
    await pumpEventQueue();
    final k2 = provider.sessionKey;
    expect(k2, isNotNull);
    expect(k2, isNot(k1));

    auth.setSignedInDid('did:plc:bob');
    await pumpEventQueue();
    final k3 = provider.sessionKey;
    expect(k3, isNotNull);
    expect(k3, isNot(k1));
    expect(k3, isNot(k2));
  });

  test('S1 an account switch while authority is loading notifies listeners '
      'with the new key before any authority answer lands', () async {
    final answers = [Completer<bool>(), Completer<bool>()];
    var call = 0;
    when(api.getViewerAuthority()).thenAnswer((_) => answers[call++].future);
    final provider = createProvider();
    expect(provider.status, ViewerAuthorityStatus.loading);
    final aliceKey = provider.sessionKey;

    final seenKeys = <Object?>[];
    provider.addListener(() => seenKeys.add(provider.sessionKey));

    auth.setSignedInDid('did:plc:bob');

    expect(seenKeys, isNotEmpty);
    expect(provider.status, ViewerAuthorityStatus.loading);
    final bobKey = provider.sessionKey;
    expect(bobKey, isNotNull);
    expect(bobKey, isNot(aliceKey));
    expect(seenKeys.last, bobKey);
    expect(answers.where((answer) => answer.isCompleted), isEmpty);

    answers[0].complete(true);
    answers[1].complete(false);
    await pumpEventQueue();
    expect(provider.status, ViewerAuthorityStatus.notAdmin);
    expect(provider.sessionKey, bobKey);
  });

  test('S1 sessionKey describes the current account even to an auth '
      "listener that runs before the provider's own", () async {
    when(api.getViewerAuthority()).thenAnswer((_) async => true);

    ViewerAuthorityProvider? authority;
    final earlyReadings = <Object?>[];
    void earlyListener() {
      final current = authority;
      if (current != null) {
        earlyReadings.add(current.sessionKey);
      }
    }

    auth.addListener(earlyListener);
    addTearDown(() => auth.removeListener(earlyListener));

    authority = createProvider();
    await pumpEventQueue();
    final k1 = authority.sessionKey;
    expect(k1, isNotNull);

    auth.setSignedInDid('did:plc:bob');
    expect(earlyReadings, hasLength(1));
    final seenDuringBobSwitch = earlyReadings.single;
    expect(seenDuringBobSwitch, isNotNull);
    expect(seenDuringBobSwitch, isNot(equals(k1)));
    await pumpEventQueue();
    final bobKey = authority.sessionKey;
    expect(bobKey, equals(seenDuringBobSwitch));

    // Bob's key was minted as an upcoming key; signing out and back in as
    // bob must still mint a new one.
    auth.setSignedInDid(null);
    await pumpEventQueue();
    expect(authority.sessionKey, isNull);
    earlyReadings.clear();
    auth.setSignedInDid('did:plc:bob');
    expect(earlyReadings, hasLength(1));
    await pumpEventQueue();
    final secondBobKey = authority.sessionKey;
    expect(secondBobKey, isNotNull);
    expect(secondBobKey, equals(earlyReadings.single));
    expect(secondBobKey, isNot(equals(k1)));
    expect(secondBobKey, isNot(equals(bobKey)));

    earlyReadings.clear();
    auth.setSignedInDid('did:plc:carol');
    expect(earlyReadings, hasLength(1));
    final seenDuringCarolSwitch = earlyReadings.single;
    expect(seenDuringCarolSwitch, isNotNull);
    expect(seenDuringCarolSwitch, isNot(equals(bobKey)));
    await pumpEventQueue();
    expect(authority.sessionKey, equals(seenDuringCarolSwitch));
  });
}
