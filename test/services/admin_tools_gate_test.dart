import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/admin_tools_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _remove = {ModerationCapability.remove};

typedef _Arranged = ({
  Set<ModerationCapability> capabilities,
  Object? stamp,
  ViewerAuthorityProvider authority,
});

typedef _Row = ({
  String name,
  Future<_Arranged> Function() arrange,
  bool allowed,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A provider for [did] whose authority answers [admin], settled.
  Future<(FakeAuthProvider, ViewerAuthorityProvider)> authorityFor(
    String? did, {
    bool admin = true,
  }) async {
    final auth = FakeAuthProvider(signedInDid: did);
    final api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => admin);
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(() {
      authority.dispose();
      auth.dispose();
    });
    await pumpEventQueue();
    return (auth, authority);
  }

  test('S2 admin tools need the remove token, a live status '
      'and a stamp from the current session', () async {
    final rows = <_Row>[
      (
        name: 'instance admin, stamp from the current session',
        arrange: () async {
          final (_, authority) = await authorityFor('did:plc:admin-a');
          expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
          return (
            capabilities: _remove,
            stamp: authority.sessionKey,
            authority: authority,
          );
        },
        allowed: true,
      ),
      (
        name: 'not an instance admin, server granted the remove token',
        arrange: () async {
          final (_, authority) = await authorityFor(
            'did:plc:community-mod',
            admin: false,
          );
          expect(authority.status, ViewerAuthorityStatus.notAdmin);
          return (
            capabilities: _remove,
            stamp: authority.sessionKey,
            authority: authority,
          );
        },
        allowed: true,
      ),
      (
        name: 'stamp from before an account switch',
        arrange: () async {
          final (auth, authority) = await authorityFor('did:plc:admin-a');
          final stamp = authority.sessionKey;
          auth.setSignedInDid('did:plc:admin-b');
          await pumpEventQueue();
          expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
          return (capabilities: _remove, stamp: stamp, authority: authority);
        },
        allowed: false,
      ),
      (
        name: 'instance admin, no stamp from the surface',
        arrange: () async {
          final (_, authority) = await authorityFor('did:plc:admin-a');
          expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
          expect(authority.sessionKey, isNotNull);
          return (capabilities: _remove, stamp: null, authority: authority);
        },
        allowed: false,
      ),
      (
        name: 'signed out',
        arrange: () async {
          final (_, authority) = await authorityFor(null);
          expect(authority.status, ViewerAuthorityStatus.signedOut);
          return (
            capabilities: _remove,
            stamp: authority.sessionKey,
            authority: authority,
          );
        },
        allowed: false,
      ),
      (
        name: 'authority revoked',
        arrange: () async {
          final (_, authority) = await authorityFor('did:plc:admin-a');
          authority.markRevoked();
          expect(authority.status, ViewerAuthorityStatus.revoked);
          return (
            capabilities: _remove,
            stamp: authority.sessionKey,
            authority: authority,
          );
        },
        allowed: false,
      ),
      (
        name: 'capabilities without remove',
        arrange: () async {
          final (_, authority) = await authorityFor('did:plc:admin-a');
          return (
            capabilities: {
              ModerationCapability.restore,
              ModerationCapability.label,
            },
            stamp: authority.sessionKey,
            authority: authority,
          );
        },
        allowed: false,
      ),
    ];

    for (final row in rows) {
      final arranged = await row.arrange();
      expect(
        adminToolAllowed(
          capability: ModerationCapability.remove,
          capabilities: arranged.capabilities,
          loadedUnderSessionKey: arranged.stamp,
          authority: arranged.authority,
        ),
        row.allowed,
        reason: row.name,
      );
    }
  });
}
