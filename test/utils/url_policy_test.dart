// Spec for the single canonical http/https allowlist.
//
// RED: this file does not compile until lib/utils/url_policy.dart exists.
// The predicate is deliberately the STRICTEST of the five copies it replaces:
// scheme allowlist AND non-empty host.
import 'package:coves_flutter/utils/url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAllowedWebSchemes', () {
    test('is exactly http and https', () {
      expect(kAllowedWebSchemes, {'http', 'https'});
    });
  });

  group('isAllowedWebUrl accepts', () {
    test('https url with host', () {
      expect(isAllowedWebUrl('https://example.com'), isTrue);
    });

    test('http url with host', () {
      expect(isAllowedWebUrl('http://example.com'), isTrue);
    });

    test('uppercase scheme (case-insensitive)', () {
      expect(isAllowedWebUrl('HTTPS://example.com'), isTrue);
      expect(isAllowedWebUrl('HtTp://example.com'), isTrue);
    });

    test('url with port, path, query and fragment', () {
      expect(
        isAllowedWebUrl('https://example.com:8443/a/b?q=1&r=2#frag'),
        isTrue,
      );
    });

    test('url with userinfo and subdomain', () {
      expect(isAllowedWebUrl('https://user@cdn.example.co.uk/x.jpg'), isTrue);
    });

    test('bare host with trailing slash', () {
      expect(isAllowedWebUrl('http://example.com/'), isTrue);
    });

    test('ip literal host', () {
      expect(isAllowedWebUrl('http://127.0.0.1:8080/health'), isTrue);
    });
  });

  group('isAllowedWebUrl rejects non-http(s) schemes', () {
    test('javascript:', () {
      expect(isAllowedWebUrl('javascript:alert("xss")'), isFalse);
    });

    test('data:', () {
      expect(isAllowedWebUrl('data:text/html,<h1>XSS</h1>'), isFalse);
    });

    test('file:', () {
      expect(isAllowedWebUrl('file:///etc/passwd'), isFalse);
    });

    test('ftp:', () {
      expect(isAllowedWebUrl('ftp://example.com/pub'), isFalse);
    });

    test('content:', () {
      expect(isAllowedWebUrl('content://media/external/images/1'), isFalse);
    });

    test('scheme that merely starts with http', () {
      expect(isAllowedWebUrl('httpx://evil.com'), isFalse);
      expect(isAllowedWebUrl('httpsevil://evil.com'), isFalse);
      expect(isAllowedWebUrl('HTTPX://evil.com'), isFalse);
    });
  });

  group('isAllowedWebUrl rejects allowed schemes with no host', () {
    test('http:foo (opaque path, no authority)', () {
      expect(isAllowedWebUrl('http:foo'), isFalse);
    });

    test('https:///path (empty authority)', () {
      expect(isAllowedWebUrl('https:///path'), isFalse);
    });

    test('http:// (nothing at all)', () {
      expect(isAllowedWebUrl('http://'), isFalse);
    });

    test('https://:8080/x (port but no host)', () {
      expect(isAllowedWebUrl('https://:8080/x'), isFalse);
    });
  });

  group('isAllowedWebUrl rejects degenerate input', () {
    test('null', () {
      expect(isAllowedWebUrl(null), isFalse);
    });

    test('empty string', () {
      expect(isAllowedWebUrl(''), isFalse);
    });

    test('whitespace only', () {
      expect(isAllowedWebUrl('   '), isFalse);
    });

    test('no scheme at all', () {
      expect(isAllowedWebUrl('example.com'), isFalse);
      expect(isAllowedWebUrl('//example.com/path'), isFalse);
      expect(isAllowedWebUrl('/just/a/path'), isFalse);
    });

    test('unparseable garbage', () {
      expect(isAllowedWebUrl('not a url'), isFalse);
      expect(isAllowedWebUrl('ht tp://bad url'), isFalse);
    });

    test('never throws for hostile input', () {
      const hostile = [
        'http:foo',
        'https:///path',
        '::::',
        '%%%',
        'https://[not-an-ip]/x',
      ];
      for (final url in hostile) {
        expect(() => isAllowedWebUrl(url), returnsNormally, reason: url);
      }
    });
  });
}
