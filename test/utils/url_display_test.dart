// Spec for the shared link-display helpers.
//
// Three surfaces derive a display domain and a favicon domain from a URL
// today — external_link_bar.dart, source_link_bar.dart and
// detailed_post_view.dart (`_formatUrlForDisplay`) — each with its own copy
// of the parse-and-fall-back dance. One home, two functions.
//
// Target API — lib/utils/url_display.dart:
//
//   /// The host of [url], or null when it has none (unparseable, relative,
//   /// or authority-less). Never throws.
//   String? domainOf(String url);
//
//   /// [url] with the scheme, port, query and fragment stripped:
//   /// `example.com` or `example.com/a/b`. Returns [url] unchanged when it
//   /// has no host. Never throws.
//   String hostAndPath(String url);
//
// Callers keep their own precedence rules (the link bars prefer the embed's
// declared `domain` field and fall back to `domainOf(uri) ?? uri`); these
// helpers only do the parsing.
//
// COMPILE-RED until lib/utils/url_display.dart exists.

import 'package:coves_flutter/utils/url_display.dart';
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

    test('returns the input unchanged when there is no host', () {
      expect(hostAndPath('just-text'), 'just-text');
      expect(hostAndPath(''), '');
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
}
