// Spec for the shared link-display helpers in lib/utils/url_display.dart.
//
// One home for link-display parsing: the link bars, the detail view's link
// rows and the favicon all derive a domain from a URL here. Three functions:
//
//   domainOf(url)      the lowercased host of [url], or null when it has none
//                      (unparseable, relative, or authority-less).
//   linkLabelOf(uri)   the text a link bar shows for [uri]: its host when a
//                      tap can open it (isAllowedWebUrl), otherwise the uri
//                      trimmed of surrounding whitespace, or "Invalid link"
//                      when the uri is blank.
//   hostAndPath(url)   [url] without scheme, port, query and fragment:
//                      `example.com` or `example.com/a/b` when a tap can
//                      open it; otherwise the same fallback as linkLabelOf.
//
// The label comes from the uri alone, never from the author-declared
// `domain` field, because a tap opens the uri and the declared domain is
// record text an author can point at any site. A uri a tap cannot open is
// labelled by its own text even when it has a host (see the last group).
// All three take untrusted record data, so none of them throws.

import 'package:coves_flutter/utils/url_display.dart';
import 'package:coves_flutter/utils/url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('domainOf', () {
    test('returns the host of an absolute url', () {
      expect(domainOf('https://example.com'), 'example.com');
      expect(domainOf('https://example.com/a/b?c=d#e'), 'example.com');
      expect(domainOf('http://news.example.co.uk/story'), 'news.example.co.uk');
    });

    test('lowercases the host', () {
      expect(domainOf('https://EXAMPLE.com/Path'), 'example.com');
    });

    test('drops the port and any credentials', () {
      expect(domainOf('https://example.com:8443/x'), 'example.com');
    });

    test('returns null when there is no host', () {
      expect(domainOf(''), isNull);
      expect(domainOf('just-text'), isNull);
      expect(domainOf('/relative/path'), isNull);
      expect(domainOf('https://'), isNull);
    });

    test('never throws on a malformed url', () {
      // Callers feed this untrusted record data, so it has to be total.
      for (final input in <String>[
        'http://[',
        '://nope',
        'https://exa mple.com',
        '%%%',
      ]) {
        expect(() => domainOf(input), returnsNormally, reason: input);
      }
    });
  });

  group('linkLabelOf', () {
    test('shows the host of the uri, the site a tap opens', () {
      expect(linkLabelOf('https://evil.example/login'), 'evil.example');
    });

    test('drops userinfo and port, and lowercases the host', () {
      expect(
        linkLabelOf('https://paypal.com@EVIL.Example:8443/login'),
        'evil.example',
      );
    });

    test('shows a hostless uri as written', () {
      expect(linkLabelOf('https:paypal.com'), 'https:paypal.com');
    });

    test('shows a malformed uri as written, without throwing', () {
      expect(linkLabelOf('http://['), 'http://[');
    });

    test('shows a uri with a host but a scheme a tap cannot open as written, '
        'not its host', () {
      expect(linkLabelOf('ftp://paypal.com/'), 'ftp://paypal.com/');
      expect(linkLabelOf('//paypal.com/login'), '//paypal.com/login');
    });

    test('trims surrounding whitespace from a hostless uri', () {
      expect(linkLabelOf('  just-text \t'), 'just-text');
    });

    test('shows an absolute uri with leading whitespace as the whole trimmed '
        'uri, not its host, because the untrimmed uri has no host', () {
      expect(
        linkLabelOf('  https://example.com/path'),
        'https://example.com/path',
      );
    });

    test('returns "Invalid link" for a blank uri', () {
      for (final uri in <String>['', '   ', '\t\n']) {
        expect(linkLabelOf(uri), 'Invalid link', reason: '"$uri"');
      }
    });
  });

  group('hostAndPath', () {
    test('returns the bare host when there is no path', () {
      expect(hostAndPath('https://example.com'), 'example.com');
      expect(hostAndPath('https://example.com/'), 'example.com');
    });

    test('keeps the path', () {
      expect(hostAndPath('https://example.com/a/b'), 'example.com/a/b');
      expect(
        hostAndPath('https://example.com/2026/08/a-story'),
        'example.com/2026/08/a-story',
      );
    });

    test('drops the scheme, query and fragment', () {
      expect(hostAndPath('https://example.com/a?utm=x'), 'example.com/a');
      expect(hostAndPath('https://example.com/a#top'), 'example.com/a');
      expect(hostAndPath('http://example.com/a'), 'example.com/a');
    });

    test('returns a uri a tap cannot open trimmed, or "Invalid link" when it '
        'is blank', () {
      expect(hostAndPath('just-text'), 'just-text');
      expect(hostAndPath('  just-text \t'), 'just-text');
      expect(hostAndPath('ftp://paypal.com/x'), 'ftp://paypal.com/x');
      expect(hostAndPath(''), 'Invalid link');
      expect(hostAndPath('   '), 'Invalid link');
    });

    test('never throws on a malformed url', () {
      for (final input in <String>[
        'http://[',
        '://nope',
        'https://exa mple.com',
        '%%%',
      ]) {
        expect(() => hostAndPath(input), returnsNormally, reason: input);
      }
    });
  });

  // The label, the favicon and the tap share one predicate, isAllowedWebUrl.
  // A uri a tap can open is labelled by the host it opens. A uri a tap
  // refuses is labelled by its own text, trimmed, or "Invalid link" when
  // blank, even when Uri finds a host in it: `ftp://paypal.com/` must not
  // read "paypal.com" on a bar that cannot open PayPal. The favicon half of
  // this rule is pinned in test/widgets/media/favicon_test.dart.
  group('a uri is labelled by its host exactly when a tap can open it', () {
    /// Uris a tap refuses although Uri gives each the host `paypal.com`.
    const hostedUnopenableUris = <String>[
      '//paypal.com/login',
      'ftp://paypal.com/',
      'httpx://paypal.com',
      'intent://paypal.com/#Intent;scheme=https;end',
      'javascript://paypal.com/%0Aalert(1)',
      'file://paypal.com/x',
    ];

    const uris = <String>[
      'https://paypal.com/login',
      'http://paypal.com',
      'https://paypal.com@evil.example:8443/login',
      'https://evil.example ',
      ...hostedUnopenableUris,
      ' https://evil.example',
      '\thttps://evil.example',
      '\nhttps://evil.example',
      '//evil.example',
      'https:paypal.com',
      'https:///path',
      'http:foo',
      'https://',
      'not a valid url',
      '',
      '   ',
      'javascript:alert(1)',
      'mailto:a@evil.example',
      'http://[',
      '%%%',
    ];

    test('every hosted unopenable uri does parse to the host paypal.com', () {
      for (final uri in hostedUnopenableUris) {
        expect(domainOf(uri), 'paypal.com', reason: '"$uri"');
        expect(isAllowedWebUrl(uri), isFalse, reason: '"$uri"');
      }
    });

    test('linkLabelOf is the host exactly when the uri is launchable, and '
        'the trimmed uri or "Invalid link" otherwise', () {
      for (final uri in uris) {
        expect(
          linkLabelOf(uri) == domainOf(uri),
          isAllowedWebUrl(uri),
          reason: '"$uri" gave "${linkLabelOf(uri)}"',
        );
        if (isAllowedWebUrl(uri)) {
          expect(domainOf(uri), isNotNull, reason: '"$uri"');
        } else {
          expect(linkLabelOf(uri), _unopenableLabel(uri), reason: '"$uri"');
        }
      }
    });

    test('hostAndPath starts with the host exactly when the uri is '
        'launchable, and is the trimmed uri or "Invalid link" otherwise', () {
      for (final uri in uris) {
        if (isAllowedWebUrl(uri)) {
          expect(hostAndPath(uri), startsWith(domainOf(uri)!), reason: uri);
        } else {
          expect(hostAndPath(uri), _unopenableLabel(uri), reason: '"$uri"');
        }
      }
    });
  });
}

/// What a link a tap cannot open is labelled with: its trimmed text, or
/// "Invalid link" when that is empty.
String _unopenableLabel(String uri) {
  final trimmed = uri.trim();
  return trimmed.isEmpty ? 'Invalid link' : trimmed;
}
