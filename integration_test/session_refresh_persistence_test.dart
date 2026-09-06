// Requires the real local backend and an existing signed-in dev app session.
// On Android, configure adb reverse through `make mobile-setup` in coves.
// Build the ordinary app with the pubspec build number before signing in.
// Flutter may uninstall an older-version test build on a version downgrade,
// which clears Android storage and invalidates this test's precondition.
// Run with the same application flavor used for the manual sign-in:
// flutter test integration_test/session_refresh_persistence_test.dart \
//   -d <device-id> --flavor dev --dart-define=ENVIRONMENT=local --no-uninstall
//
// This explicitly requests a refresh and then reads native secure storage.
// It does not simulate token expiration or claim a full process restart.
import 'dart:async';

import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real local session refresh persists the renewed sealed token', (
    tester,
  ) async {
    expect(
      EnvironmentConfig.current.isLocal,
      isTrue,
      reason: 'Run with --flavor dev --dart-define=ENVIRONMENT=local.',
    );

    // Existing debug app diagnostics include identity values. Silence their
    // console output during this live check; assertions expose booleans only.
    await runZoned(
      () async {
        final authProvider = AuthProvider();
        try {
          await authProvider.initialize();
          expect(
            authProvider.isAuthenticated && authProvider.session != null,
            isTrue,
            reason:
                'Sign into the dev app on this device using a local account '
                'before running this test. Do not clear its app data.',
          );
          final originalSession = authProvider.session!;

          final refreshed = await authProvider.refreshToken().timeout(
            const Duration(seconds: 45),
          );
          expect(
            refreshed,
            isTrue,
            reason:
                'The real local backend must successfully refresh the session.',
          );
          expect(
            authProvider.isAuthenticated && authProvider.session != null,
            isTrue,
            reason: 'A successful refresh must keep the user signed in.',
          );
          final refreshedSession = authProvider.session!;
          expect(
            refreshedSession.did == originalSession.did &&
                refreshedSession.handle == originalSession.handle,
            isTrue,
            reason: 'Refreshing must preserve the signed-in identity.',
          );
          expect(
            refreshedSession.token.isNotEmpty &&
                refreshedSession.token != originalSession.token,
            isTrue,
            reason: 'Refreshing must return a new nonempty sealed token.',
          );

          // restoreSession always reads FlutterSecureStorage before updating
          // the service cache, so this checks the persisted native value.
          final restoredSession = await CovesAuthService().restoreSession();
          expect(
            restoredSession != null,
            isTrue,
            reason:
                'The refreshed session must be readable from secure storage.',
          );
          expect(
            restoredSession!.token == refreshedSession.token,
            isTrue,
            reason: 'Secure storage must contain the renewed sealed token.',
          );
          expect(
            restoredSession.did == refreshedSession.did &&
                restoredSession.handle == refreshedSession.handle,
            isTrue,
            reason:
                'The persisted session must preserve the signed-in identity.',
          );
        } finally {
          authProvider.dispose();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {},
      ),
    );
  });
}
