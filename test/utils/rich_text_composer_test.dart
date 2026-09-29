import 'dart:convert';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/utils/rich_text_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each facet as its UTF-8 byte range and every feature it carries, so a
/// wrong range, wrong uri, extra feature or extra facet all show up
List<String>? describeFacets(List<RichTextFacet>? facets) {
  if (facets == null) {
    return null;
  }
  String describeFeature(FacetFeature feature) =>
      feature is LinkFacetFeature ? 'link ${feature.uri}' : feature.type;
  String describeFacet(RichTextFacet facet) {
    final range = '[${facet.index.byteStart},${facet.index.byteEnd})';
    return '$range ${facet.features.map(describeFeature).toList()}';
  }

  return facets.map(describeFacet).toList();
}

/// The expected description of a link facet over the first occurrence of
/// [linkText] in [content], with the range measured in UTF-8 bytes; [uri]
/// defaults to [linkText] when the emitted uri is the text as typed
String linkOver(String content, String linkText, {String? uri}) {
  final charStart = content.indexOf(linkText);
  final byteStart = utf8.encode(content.substring(0, charStart)).length;
  final byteEnd = byteStart + utf8.encode(linkText).length;
  return '[$byteStart,$byteEnd) [link ${uri ?? linkText}]';
}

/// Every input mapped to its described facets, so one failing expectation
/// shows the outcome of every case at once
Map<String, List<String>?> describeEach(List<String> inputs) => {
  for (final input in inputs)
    input: describeFacets(composeRichText(input).facets),
};

void main() {
  group('composeRichText content', () {
    test('strips leading and trailing spaces, tabs and newlines', () {
      final composed = composeRichText(' \t\n hello world \n\t ');
      expect(composed.content, 'hello world');
    });

    test('strips leading and trailing Unicode whitespace and U+FEFF', () {
      final composed = composeRichText(
        '\u00A0\u3000\u2028\uFEFFhello\uFEFF\u2028\u3000\u00A0',
      );
      expect(composed.content, 'hello');
    });

    test('keeps interior whitespace unchanged', () {
      final composed = composeRichText('  a \u00A0\n\tb  ');
      expect(composed.content, 'a \u00A0\n\tb');
    });
  });

  group('composeRichText without links', () {
    test('facets are null for text with no links', () {
      final composed = composeRichText('just some plain words');
      expect(composed.content, 'just some plain words');
      expect(composed.facets, isNull);
    });

    test('facets are null for empty input', () {
      final composed = composeRichText('');
      expect(composed.content, '');
      expect(composed.facets, isNull);
    });

    test('facets are null for whitespace-only input', () {
      final composed = composeRichText(' \n\t\u00A0\u3000\uFEFF ');
      expect(composed.content, '');
      expect(composed.facets, isNull);
    });
  });

  group('composeRichText link facets', () {
    test('measures a URL after a 4-byte emoji in UTF-8 bytes', () {
      const content = 'hi 👋 https://example.com/path';
      final composed = composeRichText(content);
      expect(composed.content, content);
      expect(describeFacets(composed.facets), [
        linkOver(content, 'https://example.com/path'),
      ]);
      // 'hi ' (3) + emoji (4) + space (1), not the UTF-16 index 6
      expect(composed.facets!.single.index.byteStart, 8);
    });

    test('returns one facet per URL in text order', () {
      const content = 'see https://a.com and http://b.org/x ok';
      final composed = composeRichText(content);
      expect(describeFacets(composed.facets), [
        linkOver(content, 'https://a.com'),
        linkOver(content, 'http://b.org/x'),
      ]);
    });

    test('links URLs at the very start and very end of the content', () {
      const content = 'https://start.com middle https://end.com';
      final composed = composeRichText(content);
      expect(describeFacets(composed.facets), [
        '[0,17) [link https://start.com]',
        linkOver(content, 'https://end.com'),
      ]);
      expect(composed.facets!.last.index.byteEnd, utf8.encode(content).length);
    });

    test('measures ranges against the trimmed content', () {
      final composed = composeRichText(' \n 👋 https://a.com/x  ');
      const content = '👋 https://a.com/x';
      expect(composed.content, content);
      expect(describeFacets(composed.facets), [
        linkOver(content, 'https://a.com/x'),
      ]);
      // Emoji (4) + space (1); the trimmed leading whitespace is not counted
      expect(composed.facets!.single.index.byteStart, 5);
    });
  });

  group('composeRichText URL boundaries', () {
    test('matches the scheme case-insensitively and lowercases it', () {
      const content = 'see Https://a.com/X and HTTP://Example.com/Path';
      final composed = composeRichText(content);
      expect(composed.content, content);
      expect(describeFacets(composed.facets), [
        linkOver(content, 'Https://a.com/X', uri: 'https://a.com/X'),
        linkOver(
          content,
          'HTTP://Example.com/Path',
          uri: 'http://Example.com/Path',
        ),
      ]);
    });

    test('starts a URL only at a word boundary', () {
      expect(
        describeEach([
          'xhttps://a.com',
          '\u00E9https://a.com',
          '_https://a.com',
          '9https://a.com',
          // U+216B ROMAN NUMERAL TWELVE is \p{N}
          '\u216Bhttps://a.com',
          // U+1D400 MATHEMATICAL BOLD CAPITAL A is an astral \p{L}
          '\uD835\uDC00https://a.com',
          '(https://a.com',
          '"https://a.com',
          'a https://a.com',
          '👋https://a.com',
          'https://a.com',
        ]),
        {
          'xhttps://a.com': null,
          '\u00E9https://a.com': null,
          '_https://a.com': null,
          '9https://a.com': null,
          '\u216Bhttps://a.com': null,
          '\uD835\uDC00https://a.com': null,
          '(https://a.com': ['[1,14) [link https://a.com]'],
          '"https://a.com': ['[1,14) [link https://a.com]'],
          'a https://a.com': ['[2,15) [link https://a.com]'],
          // The emoji is 4 UTF-8 bytes
          '👋https://a.com': ['[4,17) [link https://a.com]'],
          'https://a.com': ['[0,13) [link https://a.com]'],
        },
      );
    });

    test('ends a URL at whitespace, angle brackets or a backtick', () {
      expect(
        describeEach([
          'see https://a.com/x\nnext',
          '<https://a.com/x>',
          '`https://a.com/x`',
        ]),
        {
          'see https://a.com/x\nnext': ['[4,19) [link https://a.com/x]'],
          '<https://a.com/x>': ['[1,16) [link https://a.com/x]'],
          '`https://a.com/x`': ['[1,16) [link https://a.com/x]'],
        },
      );
    });

    test('trims trailing punctuation but keeps a balanced closing paren', () {
      expect(
        describeEach([
          'https://a.com/x.',
          'https://a.com/x?!',
          'Check https://a.com/x, then',
          '(see https://a.com/x)',
          'https://en.wikipedia.org/wiki/Foo_(bar)',
          'https://en.wikipedia.org/wiki/Foo_(bar)).',
          '"https://a.com/x".',
          "'https://a.com/x'",
          'https://a.com/x?q=1:',
          // Nothing but the scheme is left after trimming
          'https://.',
        ]),
        {
          'https://a.com/x.': ['[0,15) [link https://a.com/x]'],
          'https://a.com/x?!': ['[0,15) [link https://a.com/x]'],
          'Check https://a.com/x, then': ['[6,21) [link https://a.com/x]'],
          '(see https://a.com/x)': ['[5,20) [link https://a.com/x]'],
          'https://en.wikipedia.org/wiki/Foo_(bar)': [
            '[0,39) [link https://en.wikipedia.org/wiki/Foo_(bar)]',
          ],
          'https://en.wikipedia.org/wiki/Foo_(bar)).': [
            '[0,39) [link https://en.wikipedia.org/wiki/Foo_(bar)]',
          ],
          '"https://a.com/x".': ['[1,16) [link https://a.com/x]'],
          "'https://a.com/x'": ['[1,16) [link https://a.com/x]'],
          'https://a.com/x?q=1:': ['[0,19) [link https://a.com/x?q=1]'],
          'https://.': null,
        },
      );
    });

    test('trims a long run of unbalanced closing parens in linear time', () {
      // The reply field has no length limit and composing runs on the UI
      // thread, so the trailing-punctuation trim must stay linear
      final content = 'https://a.com/${')' * 60000}';
      final stopwatch = Stopwatch()..start();
      final composed = composeRichText(content);
      stopwatch.stop();
      expect(describeFacets(composed.facets), [
        '[0,14) [link https://a.com/]',
      ]);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('does not link scheme-less domains or non-http(s) schemes', () {
      final inputs = [
        'e.g',
        'node.js',
        'example.com',
        'www.example.com',
        'https://',
        'http:foo',
        'https:///path',
        'ftp://a.com',
        'mailto:a@b.com',
        'javascript:alert(1)',
      ];
      expect(describeEach(inputs), {for (final input in inputs) input: null});
    });
  });

  group('composeRichText backend link acceptance', () {
    test(
      'does not link a URL whose host has bytes outside printable ASCII',
      () {
        const mixed = 'https://ex\u00E4mple.com/x and https://b.com';
        expect(
          describeEach([
            'https://ex\u00E4mple.com/x',
            'https://\u00E4..com/x',
            'https://ex\u00E4mple.com:8080/x',
            // U+007F DELETE is ASCII but not printable
            'https://a\u007F.com/x',
            // Only the host counts: non-ASCII userinfo, path and query link
            'https://us\u00E9r@a.com/x',
            'https://a.com/caf\u00E9',
            'https://a.com/x?q=caf\u00E9',
            mixed,
          ]),
          {
            'https://ex\u00E4mple.com/x': null,
            'https://\u00E4..com/x': null,
            'https://ex\u00E4mple.com:8080/x': null,
            'https://a\u007F.com/x': null,
            'https://us\u00E9r@a.com/x': [
              '[0,21) [link https://us\u00E9r@a.com/x]',
            ],
            'https://a.com/caf\u00E9': [
              '[0,19) [link https://a.com/caf\u00E9]',
            ],
            'https://a.com/x?q=caf\u00E9': [
              '[0,23) [link https://a.com/x?q=caf\u00E9]',
            ],
            mixed: [linkOver(mixed, 'https://b.com')],
          },
        );
        expect(composeRichText(mixed).content, mixed);
      },
    );

    test(
      'reads the host after the last @ and before the first /, ? or #',
      () {
        final unlinked = [
          // An @ after the authority is not userinfo, so the host is 'ä..com'
          'https://ä..com/@b',
          'https://ä..com?@b',
          'https://ä..com#@b',
          'https://user:pw@/path',
          'https://exämple.com:8443/path',
        ];
        const linked = [
          'https://[2001:db8::1]:8443/x',
          'https://üser@[2001:db8::1]:8080/p',
          'https://example.com:8443/pokémon',
        ];
        expect(describeEach([...unlinked, ...linked]), {
          for (final input in unlinked) input: null,
          for (final input in linked) input: [linkOver(input, input)],
        });
        expect(
          {for (final input in unlinked) input: composeRichText(input).content},
          {for (final input in unlinked) input: input},
        );
      },
    );

    test('links a URL only up to 8192 bytes after backend encoding', () {
      // The backend percent-encodes every byte outside 0x21..0x7E into three
      int normalizedLength(String uri) => utf8
          .encode(uri)
          .fold(0, (sum, byte) => sum + (byte >= 0x21 && byte <= 0x7E ? 1 : 3));
      const prefix = 'https://a.com/';
      String asciiUrl(int length) => prefix + 'a' * (length - prefix.length);
      // 'e' with acute is 2 UTF-8 bytes that each encode to 3
      String accentedUrl(int normalized) =>
          '$prefix${'a' * (normalized - prefix.length - 6)}\u00E9';

      final cases = {
        'ascii 8192': asciiUrl(8192),
        'ascii 8193': asciiUrl(8193),
        'accented 8192': accentedUrl(8192),
        'accented 8193': accentedUrl(8193),
      };
      expect(
        cases.map((label, url) => MapEntry(label, normalizedLength(url))),
        {
          'ascii 8192': 8192,
          'ascii 8193': 8193,
          'accented 8192': 8192,
          'accented 8193': 8193,
        },
      );
      // The accented URL over the cap is still under it in raw bytes
      expect(utf8.encode(cases['accented 8193']!).length, 8189);

      // The URL itself is replaced by <url> to keep failure output readable
      expect(
        cases.map(
          (label, url) => MapEntry(
            label,
            describeFacets(composeRichText(url).facets)
                ?.map((facet) => facet.replaceAll(url, '<url>'))
                .toList(),
          ),
        ),
        {
          'ascii 8192': ['[0,8192) [link <url>]'],
          'ascii 8193': null,
          'accented 8192': ['[0,8188) [link <url>]'],
          'accented 8193': null,
        },
      );
    });

    test('keeps only the first 200 of 201 links', () {
      final urls = [for (var i = 0; i <= 200; i++) 'https://a.com/$i'];
      final content = urls.join(' ');
      final composed = composeRichText(content);
      expect(composed.facets, hasLength(200));
      expect(describeFacets(composed.facets), [
        for (final url in urls.take(200)) linkOver(content, url),
      ]);
    });

    test('counts only accepted links toward the 200-link cap', () {
      // The word boundary rejects each of these candidates
      final rejected = [for (var i = 0; i < 5; i++) 'xhttps://a.com/$i'];
      final urls = [for (var i = 0; i <= 200; i++) 'https://b.com/$i'];
      final content = [...rejected, ...urls].join(' ');
      final composed = composeRichText(content);
      expect(composed.facets, hasLength(200));
      expect(describeFacets([composed.facets!.first, composed.facets!.last]), [
        linkOver(content, urls.first),
        linkOver(content, urls[199]),
      ]);
    });
  });
}
