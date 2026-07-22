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

    test('error param wins over valid token params (error precedence)', () {
      // A hostile app firing the social.coves scheme could pack both valid
      // session params AND an error code into one callback. The error must
      // win — never silently mint a session from a callback carrying one.
      expect(
        () => CovesAuthService.parseCallbackUrl(
          'social.coves:/callback?token=abc123&did=did:plc:test123'
          '&session_id=sess456&handle=test.user&error=access_denied',
        ),
        throwsA(isA<SignInCancelledException>()),
      );
    });

    test(
      'malformed percent-encoding (token=%ZZ) throws FormatException, '
      'not ArgumentError',
      () {
        // Uri.decodeComponent('%ZZ') throws ArgumentError — an Error, not an
        // Exception — which would escape every catch chain and crash the app.
        // parseCallbackUrl must convert it to a catchable FormatException.
        expect(
          () => CovesAuthService.parseCallbackUrl(
            'social.coves:/callback?token=%ZZ&did=did:plc:test123'
            '&session_id=sess456',
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'truncated UTF-8 percent-encoding throws FormatException with a safe '
      'message that does not echo the raw URL',
      () {
        expect(
          () => CovesAuthService.parseCallbackUrl(
            'social.coves:/callback?token=%E0%A4%A&did=did:plc:test123'
            '&session_id=sess456',
          ),
          throwsA(
            predicate(
              (e) =>
                  e is FormatException && !e.toString().contains('did:plc'),
            ),
          ),
        );
      },
    );

    test('totally garbled URL throws FormatException, not an Error', () {
      expect(
        // Unterminated IPv6 host — Uri.parse itself rejects this.
        () => CovesAuthService.parseCallbackUrl('http://[::garbled'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'non-access_denied error mentioning "cancelled" surfaces as a real '
      'error with the formatted description, not a quiet cancel',
      () {
        // Reviewer scenario: server-controlled text containing "cancelled"
        // must never be reclassified as a user cancel.
        expect(
          () => CovesAuthService.parseCallbackUrl(
            'social.coves:/callback?error=temporarily_unavailable'
            '&error_description=request+was+cancelled+by+upstream',
          ),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e is! SignInCancelledException &&
                  e.toString().contains(
                    'Authorization server error: temporarily_unavailable '
                    '(request was cancelled by upstream)',
                  ),
            ),
          ),
        );
      },
    );

    test('sanitizes error_description: strips control chars, caps length', () {
      final longDescription = 'a' * 500;
      final url =
          'social.coves:/callback?error=server_error'
          '&error_description='
          '${Uri.encodeComponent('evil\n\r\x01payload $longDescription')}';

      expect(
        () => CovesAuthService.parseCallbackUrl(url),
        throwsA(
          predicate((e) {
            final message = e.toString();
            return e is Exception &&
                e is! SignInCancelledException &&
                // Control characters (incl. newlines) are stripped, so
                // hostile callbacks can't inject lines into Sentry/logs.
                !message.contains('\n') &&
                !message.contains('\r') &&
                !message.contains('\x01') &&
                message.contains('evilpayload') &&
                // Description capped at ~200 chars plus ellipsis.
                message.length < 300 &&
                message.contains('...');
          }),
        ),
      );
    });
  });
}
