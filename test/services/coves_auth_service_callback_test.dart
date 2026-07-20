import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CovesAuthService.parseCallbackUrl()', () {
    test('parses a success callback into a session', () {
      final session = CovesAuthService.parseCallbackUrl(
        'social.coves:/callback?token=abc123&did=did:plc:test123'
        '&session_id=sess456&handle=test.user',
      );

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, 'test.user');
    });

    test(
      'throws SignInCancelledException on access_denied (user cancel/deny)',
      () {
        // Exact shape the backend redirects with when the user cancels on
        // the PDS sign-in page or denies the consent screen (cc98f26).
        expect(
          () => CovesAuthService.parseCallbackUrl(
            'social.coves:/callback?error=access_denied'
            '&error_description=The+user+rejected+the+request',
          ),
          throwsA(isA<SignInCancelledException>()),
        );
      },
    );

    test('throws a descriptive Exception on other server errors', () {
      expect(
        () => CovesAuthService.parseCallbackUrl(
          'social.coves:/callback?error=server_error',
        ),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e is! SignInCancelledException &&
                e.toString().contains('server_error'),
          ),
        ),
      );
    });

    test('still rejects a callback with no token and no error param', () {
      expect(
        () => CovesAuthService.parseCallbackUrl('social.coves:/callback'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
