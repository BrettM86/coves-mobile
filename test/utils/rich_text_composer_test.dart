import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/rich_text_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each facet as its UTF-8 byte range and every feature it carries, so a
/// wrong range, wrong uri, extra feature or extra facet all show up
List<String>? describeFacets(List<RichTextFacet>? facets) {
  if (facets == null) {
    return null;
  }
  String describeFeature(FacetFeature feature) => switch (feature) {
    LinkFacetFeature(:final uri) => 'link $uri',
    MentionFacetFeature(:final did) => 'mention $did',
    _ => feature.type,
  };
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

/// Each pending mention as its UTF-8 byte range, kind and identifier, e.g.
/// '[3,22) user alice.coves.social'
List<String> describeMentions(List<PendingMention> mentions) => [
  for (final PendingMention(:kind, :identifier, :index) in mentions)
    '[${index.byteStart},${index.byteEnd}) ${kind.name} $identifier',
];

/// Every input mapped to its described pending mentions
Map<String, List<String>> describeMentionsEach(List<String> inputs) => {
  for (final input in inputs)
    input: describeMentions(composeRichText(input).mentions),
};

/// A [MentionResolver] answering from fixed tables
///
/// Records each lookup as it starts (`user <handle>` or `community <name>`)
/// and as it completes. An identifier with a gate waits for that gate before
/// answering; one with an error throws it; one missing from its table is not
/// found (null).
class FakeMentionResolver implements MentionResolver {
  FakeMentionResolver({
    this.handles = const {},
    this.communities = const {},
    this.errors = const {},
    this.gates = const {},
  });

  /// DID returned for each handle
  final Map<String, String> handles;

  /// DID returned for each community name or name@origin
  final Map<String, String> communities;

  /// Exception thrown for each lookup key (`user <handle>` or
  /// `community <name>`)
  final Map<String, Exception> errors;

  /// Gate each lookup key waits on before answering
  final Map<String, Completer<void>> gates;

  final List<String> started = [];
  final List<String> completed = [];

  @override
  Future<String?> resolveHandle(String handle) =>
      _lookUp('user $handle', handles[handle]);

  @override
  Future<String?> resolveCommunity(String community) =>
      _lookUp('community $community', communities[community]);

  Future<String?> _lookUp(String key, String? did) async {
    started.add(key);
    final gate = gates[key];
    if (gate != null) {
      await gate.future;
    }
    completed.add(key);
    final error = errors[key];
    if (error != null) {
      throw error;
    }
    return did;
  }
}

/// [text] composed and its mentions resolved through [resolver]
Future<ComposedRichText> composeAndResolve(
  String text,
  MentionResolver resolver,
) => resolveMentions(composeRichText(text), resolver);

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
      expect(describeFacets(composed.facets), ['[0,14) [link https://a.com/]']);
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

    test('reads the host after the last @ and before the first /, ? or #', () {
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
    });

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

  group('composeRichText user mentions', () {
    test('detects @handle mentions with UTF-8 ranges over the sigil', () {
      expect(
        describeMentionsEach([
          '@alice.coves.social',
          'cc @alice.coves.social please',
          // 'wörld ' is 7 bytes and the wave emoji 4, so the sigil is at 12
          'wörld 🌊 @alice.coves.social',
          '(@alice.coves.social)',
          '@alice.coves.social and @alice.coves.social',
        ]),
        {
          '@alice.coves.social': ['[0,19) user alice.coves.social'],
          'cc @alice.coves.social please': ['[3,22) user alice.coves.social'],
          'wörld 🌊 @alice.coves.social': ['[12,31) user alice.coves.social'],
          '(@alice.coves.social)': ['[1,20) user alice.coves.social'],
          '@alice.coves.social and @alice.coves.social': [
            '[0,19) user alice.coves.social',
            '[24,43) user alice.coves.social',
          ],
        },
      );
    });

    test('excludes trailing punctuation from the mention', () {
      expect(
        describeMentionsEach([
          '@alice.coves.social.',
          '@alice.coves.social...',
          '@alice.coves.social,',
          '@alice.coves.social!',
          '@alice.coves.social?',
          '@alice.coves.social;',
          '@alice.coves.social:',
          '@alice.coves.social)',
        ]),
        {
          '@alice.coves.social.': ['[0,19) user alice.coves.social'],
          '@alice.coves.social...': ['[0,19) user alice.coves.social'],
          '@alice.coves.social,': ['[0,19) user alice.coves.social'],
          '@alice.coves.social!': ['[0,19) user alice.coves.social'],
          '@alice.coves.social?': ['[0,19) user alice.coves.social'],
          '@alice.coves.social;': ['[0,19) user alice.coves.social'],
          '@alice.coves.social:': ['[0,19) user alice.coves.social'],
          '@alice.coves.social)': ['[0,19) user alice.coves.social'],
        },
      );
    });

    test('measures mention ranges against the trimmed content', () {
      final composed = composeRichText(' \n\t cc @alice.coves.social  ');
      expect(composed.content, 'cc @alice.coves.social');
      expect(describeMentions(composed.mentions), [
        '[3,22) user alice.coves.social',
      ]);
    });
  });

  group('composeRichText community mentions', () {
    test('detects !name and !name@origin mentions', () {
      final longestName = 'a' * 63;
      expect(
        describeMentionsEach([
          'see !gaming@coves.social today',
          'see !gaming today',
          'see !gaming, ok',
          'see !gaming.',
          '!$longestName',
          'hi @alice.coves.social in !gaming',
        ]),
        {
          'see !gaming@coves.social today': [
            '[4,24) community gaming@coves.social',
          ],
          'see !gaming today': ['[4,11) community gaming'],
          'see !gaming, ok': ['[4,11) community gaming'],
          'see !gaming.': ['[4,11) community gaming'],
          '!$longestName': ['[0,64) community $longestName'],
          'hi @alice.coves.social in !gaming': [
            '[3,22) user alice.coves.social',
            '[26,33) community gaming',
          ],
        },
      );
    });
  });

  group('composeRichText non-mentions', () {
    test('skips text that is not a valid mention', () {
      // Each case follows a real mention, so only the non-mention is skipped
      const real = '@bob.coves.social';
      final nonMentions = [
        '@not a handle',
        '@alice',
        '@',
        '!',
        'mail a@b.com',
        'x@alice.coves.social',
        'é@alice.coves.social',
        '5@alice.coves.social',
        '_@alice.coves.social',
        // U+1D400 MATHEMATICAL BOLD CAPITAL A is an astral \p{L}
        '𝐀@alice.coves.social',
        'costs 50@',
        'wow! amazing',
        '!-bad',
        '@alice..coves.social',
        '@alice-.coves.social',
        '!gaming@-bad.social',
        // 64 characters is one over the community name limit
        '!${'a' * 64}',
        // A word character right after the identifier rejects the mention
        '!community_name',
        '@alice.coves.social_x',
        // A combining mark right after the identifier is part of the word:
        // U+0301 after "cafe" and U+0300 after "socia"
        '!café',
        '@alice.coves.sociàl',
        // A handle's last label must start with a letter
        'meet @3.30pm',
        '@1.2',
        // A combining mark right before the sigil is part of the preceding
        // word: U+0301 after "cafe"
        'cafe\u0301@alice.coves.social',
        'cafe\u0301!gaming',
        // U+1D400 MATHEMATICAL BOLD CAPITAL A right after the identifier
        '@alice.coves.social\u{1D400}',
        // A handle is at most 253 characters; this one is 263
        '@${'a.' * 130}com',
        // A community address is at most 63 + 1 + 253 characters; this one is
        // 327, its origin alone 263
        '!${'a' * 63}@${'a.' * 130}com',
      ];
      expect(
        describeMentionsEach([for (final text in nonMentions) '$real $text']),
        {
          for (final text in nonMentions)
            '$real $text': ['[0,17) user bob.coves.social'],
        },
      );
    });

    test('finds no mention in a long run of sigils, in linear time', () async {
      // The reply field has no length limit and composing runs on the UI
      // thread, so scanning sigil-heavy text must stay linear. Composing runs
      // in another isolate so the test timeout can interrupt a slow scan,
      // which would otherwise block the timer until it finished.
      final outcomes = await Isolate.run(
        () => {
          "'@' x5000 then '.' x5000": describeMentions(
            composeRichText('${'@' * 5000}${'.' * 5000}').mentions,
          ),
          "'!' x10000": describeMentions(composeRichText('!' * 10000).mentions),
        },
      );
      expect(outcomes, {
        "'@' x5000 then '.' x5000": <String>[],
        "'!' x10000": <String>[],
      });
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('never detects a sigil inside a URL as a mention', () {
      const real = '@bob.coves.social';
      expect(
        {
          for (final url in [
            'https://bsky.app/profile/@alice.coves.social',
            'https://example.com/!gaming',
          ])
            url: {
              'mentions': describeMentions(
                composeRichText('$real $url').mentions,
              ),
              'facets': describeFacets(composeRichText('$real $url').facets),
            },
        },
        {
          'https://bsky.app/profile/@alice.coves.social': {
            'mentions': ['[0,17) user bob.coves.social'],
            'facets': [
              '[18,62) [link https://bsky.app/profile/@alice.coves.social]',
            ],
          },
          'https://example.com/!gaming': {
            'mentions': ['[0,17) user bob.coves.social'],
            'facets': ['[18,45) [link https://example.com/!gaming]'],
          },
        },
      );
    });

    test('never detects a sigil inside a URL candidate that is not linked', () {
      // The word character before the scheme rejects the link, not the URL
      const content = '@bob.coves.social xhttps://a.com/@alice.coves.social';
      final composed = composeRichText(content);
      expect(composed.facets, isNull);
      expect(describeMentions(composed.mentions), [
        '[0,17) user bob.coves.social',
      ]);
    });

    test('never detects a sigil inside a URL past the 200-link cap', () {
      final links = [for (var i = 0; i < 200; i++) 'https://a.com/$i'];
      final content =
          '@bob.coves.social ${links.join(' ')} '
          'https://example.com/@alice.coves.social';
      final composed = composeRichText(content);
      expect(composed.facets, hasLength(200));
      expect(describeMentions(composed.mentions), [
        '[0,17) user bob.coves.social',
      ]);
    });
  });

  group('resolveMentions', () {
    test('resolves a user mention through resolveHandle', () async {
      final resolver = FakeMentionResolver(
        handles: {'alice.coves.social': 'did:plc:alice'},
      );
      final resolved = await composeAndResolve(
        'hi @alice.coves.social',
        resolver,
      );
      expect(resolver.started, ['user alice.coves.social']);
      expect(resolved.content, 'hi @alice.coves.social');
      expect(describeFacets(resolved.facets), [
        '[3,22) [mention did:plc:alice]',
      ]);
    });

    test('resolves community mentions through resolveCommunity', () async {
      final resolver = FakeMentionResolver(
        communities: {
          'gaming': 'did:plc:gaming',
          'gaming@coves.social': 'did:plc:remotegaming',
        },
      );
      final resolved = await composeAndResolve(
        'see !gaming and !gaming@coves.social',
        resolver,
      );
      expect(
        resolver.started,
        unorderedEquals(['community gaming', 'community gaming@coves.social']),
      );
      expect(describeFacets(resolved.facets), [
        '[4,11) [mention did:plc:gaming]',
        '[16,36) [mention did:plc:remotegaming]',
      ]);
    });

    test(
      'looks up a repeated identifier once and facets each occurrence',
      () async {
        final resolver = FakeMentionResolver(
          handles: {'alice.coves.social': 'did:plc:alice'},
        );
        final resolved = await composeAndResolve(
          'hi @alice.coves.social and @alice.coves.social',
          resolver,
        );
        expect(resolver.started, ['user alice.coves.social']);
        expect(describeFacets(resolved.facets), [
          '[3,22) [mention did:plc:alice]',
          '[27,46) [mention did:plc:alice]',
        ]);
      },
    );

    test('looks up a handle once whatever its letter case and facets each '
        'occurrence', () async {
      // Either spelling resolves, so only the single lookup is pinned
      final resolver = FakeMentionResolver(
        handles: {
          'Alice.coves.social': 'did:plc:alice',
          'alice.coves.social': 'did:plc:alice',
        },
      );
      final resolved = await composeAndResolve(
        '@Alice.coves.social and @alice.coves.social',
        resolver,
      );
      expect(
        resolver.started,
        anyOf(
          equals(['user alice.coves.social']),
          equals(['user Alice.coves.social']),
        ),
      );
      expect(describeFacets(resolved.facets), [
        '[0,19) [mention did:plc:alice]',
        '[24,43) [mention did:plc:alice]',
      ]);
    });

    test(
      'merges mention facets with link facets sorted by byteStart',
      () async {
        final resolver = FakeMentionResolver(
          handles: {'alice.coves.social': 'did:plc:alice'},
          communities: {'gaming': 'did:plc:gaming'},
        );
        final resolved = await composeAndResolve(
          'https://a.com @alice.coves.social https://b.com !gaming',
          resolver,
        );
        expect(describeFacets(resolved.facets), [
          '[0,13) [link https://a.com]',
          '[14,33) [mention did:plc:alice]',
          '[34,47) [link https://b.com]',
          '[48,55) [mention did:plc:gaming]',
        ]);
      },
    );

    test('leaves mention-free text unchanged and looks nothing up', () async {
      // The last case has a mention, so this is not satisfied by doing nothing
      final inputs = [
        'plain words',
        'see https://a.com',
        'hi @alice.coves.social',
      ];
      final outcomes = <String, Object?>{};
      for (final input in inputs) {
        final resolver = FakeMentionResolver(
          handles: {'alice.coves.social': 'did:plc:alice'},
        );
        final resolved = await composeAndResolve(input, resolver);
        outcomes[input] = {
          'content': resolved.content,
          'lookups': resolver.started,
          'facets': describeFacets(resolved.facets),
        };
      }
      expect(outcomes, {
        'plain words': {
          'content': 'plain words',
          'lookups': <String>[],
          'facets': null,
        },
        'see https://a.com': {
          'content': 'see https://a.com',
          'lookups': <String>[],
          'facets': ['[4,17) [link https://a.com]'],
        },
        'hi @alice.coves.social': {
          'content': 'hi @alice.coves.social',
          'lookups': ['user alice.coves.social'],
          'facets': ['[3,22) [mention did:plc:alice]'],
        },
      });
    });

    test('drops a mention that is not found and keeps the rest', () async {
      // ghost.coves.social and !nowhere are missing from the tables (null)
      final resolver = FakeMentionResolver(
        handles: {'alice.coves.social': 'did:plc:alice'},
      );
      final inputs = [
        'hi @alice.coves.social and @ghost.coves.social',
        'https://a.com @ghost.coves.social',
        'only @ghost.coves.social !nowhere',
      ];
      final outcomes = <String, List<String>?>{};
      for (final input in inputs) {
        final resolved = await composeAndResolve(input, resolver);
        outcomes[input] = describeFacets(resolved.facets);
      }
      expect(outcomes, {
        'hi @alice.coves.social and @ghost.coves.social': [
          '[3,22) [mention did:plc:alice]',
        ],
        'https://a.com @ghost.coves.social': ['[0,13) [link https://a.com]'],
        'only @ghost.coves.social !nowhere': null,
      });
    });

    test('emits a mention facet only for a structurally valid DID', () async {
      const dids = [
        'did:plc:abc123',
        'did:web:example.com',
        'did:web:localhost%3A8080',
        'not-a-did',
        'did::abc',
        'did:plc:',
        'did:PLC:abc',
        'did:plc:a b',
        'did:plc:abc:',
      ];
      final outcomes = <String, List<String>?>{};
      for (final did in dids) {
        final resolver = FakeMentionResolver(
          handles: {'alice.coves.social': did},
        );
        final resolved = await composeAndResolve(
          'hi @alice.coves.social',
          resolver,
        );
        outcomes[did] = describeFacets(resolved.facets);
      }
      expect(outcomes, {
        'did:plc:abc123': ['[3,22) [mention did:plc:abc123]'],
        'did:web:example.com': ['[3,22) [mention did:web:example.com]'],
        'did:web:localhost%3A8080': [
          '[3,22) [mention did:web:localhost%3A8080]',
        ],
        'not-a-did': null,
        'did::abc': null,
        'did:plc:': null,
        'did:PLC:abc': null,
        'did:plc:a b': null,
        'did:plc:abc:': null,
      });
    });

    test('a resolved result has no pending mentions, so resolving it again '
        'looks nothing up and keeps its facets', () async {
      final resolved = await composeAndResolve(
        'hi @alice.coves.social see https://a.com',
        FakeMentionResolver(handles: {'alice.coves.social': 'did:plc:alice'}),
      );
      final secondResolver = FakeMentionResolver(
        handles: {'alice.coves.social': 'did:plc:alice'},
      );
      final again = await resolveMentions(resolved, secondResolver);
      expect(resolved.mentions, isEmpty);
      expect(secondResolver.started, isEmpty);
      expect(describeFacets(again.facets), [
        '[3,22) [mention did:plc:alice]',
        '[27,40) [link https://a.com]',
      ]);
    });
  });

  group('resolveMentions failures', () {
    test('throws the error of a lookup that fails', () async {
      final cases = <String, Exception>{
        'user alice.coves.social': ServerException(
          'Internal error',
          statusCode: 500,
        ),
        'community gaming': NetworkException('Connection refused'),
      };
      for (final MapEntry(key: failingKey, value: error) in cases.entries) {
        // The other mention resolves, so a partial result is not acceptable
        final resolver = FakeMentionResolver(
          handles: {'alice.coves.social': 'did:plc:alice'},
          communities: {'gaming': 'did:plc:gaming'},
          errors: {failingKey: error},
        );
        await expectLater(
          composeAndResolve('hi @alice.coves.social in !gaming', resolver),
          throwsA(same(error)),
          reason: 'when $failingKey fails',
        );
      }
    });

    test('throws as soon as one lookup fails, without waiting for a lookup '
        'still pending', () async {
      final error = ServerException('Internal error', statusCode: 500);
      final gate = Completer<void>();
      addTearDown(gate.complete);
      final resolver = FakeMentionResolver(
        communities: {'gaming': 'did:plc:gaming'},
        errors: {'user alice.coves.social': error},
        gates: {'community gaming': gate},
      );
      Object? thrown;
      var completedWithValue = false;
      unawaited(
        composeAndResolve(
          'hi @alice.coves.social in !gaming',
          resolver,
        ).then<void>(
          (_) {
            completedWithValue = true;
          },
          onError: (Object caught) {
            thrown = caught;
          },
        ),
      );
      await pumpEventQueue();
      expect(resolver.completed, ['user alice.coves.social']);
      expect(completedWithValue, isFalse);
      expect(thrown, same(error));
    });
  });

  group('resolveMentions caps', () {
    test('looks up at most the first 20 distinct identifiers and leaves '
        'the rest plain text', () async {
      final resolver = FakeMentionResolver(
        handles: {
          for (var i = 0; i < 21; i++) 'u$i.coves.social': 'did:plc:u$i',
        },
      );
      final resolved = await composeAndResolve(
        [for (var i = 0; i < 21; i++) '@u$i.coves.social'].join(' '),
        resolver,
      );
      expect(resolver.started, hasLength(20));
      expect(resolver.started.toSet(), {
        for (var i = 0; i < 20; i++) 'user u$i.coves.social',
      });
      final facets = describeFacets(resolved.facets)!;
      expect(facets, hasLength(20));
      expect(facets.last, '[332,349) [mention did:plc:u19]');
    });

    test('repeated occurrences do not consume the lookup cap and still get '
        'facets past it', () async {
      final repeats = List.filled(3, '@dup.coves.social');
      final distinct = [for (var i = 0; i < 25; i++) '@u$i.coves.social'];
      final resolver = FakeMentionResolver(
        handles: {
          'dup.coves.social': 'did:plc:dup',
          for (var i = 0; i < 25; i++) 'u$i.coves.social': 'did:plc:u$i',
        },
      );
      final resolved = await composeAndResolve(
        [...repeats, ...distinct, '@dup.coves.social'].join(' '),
        resolver,
      );
      expect(resolver.started, hasLength(20));
      expect(resolver.started.toSet(), {
        'user dup.coves.social',
        for (var i = 0; i < 19; i++) 'user u$i.coves.social',
      });
      // Three leading repeats, u0 to u18, then the trailing repeat
      final facets = describeFacets(resolved.facets)!;
      expect(facets, hasLength(23));
      expect(facets.sublist(21), [
        '[368,385) [mention did:plc:u18]',
        '[494,511) [mention did:plc:dup]',
      ]);
    });

    test('keeps 200 facets when mentions follow 199 links', () async {
      final links = [for (var i = 0; i < 199; i++) 'https://a.com/$i'];
      final resolver = FakeMentionResolver(
        handles: {
          'alice.coves.social': 'did:plc:alice',
          'bob.coves.social': 'did:plc:bob',
        },
      );
      final resolved = await composeAndResolve(
        '${links.join(' ')} @alice.coves.social @bob.coves.social',
        resolver,
      );
      final facets = describeFacets(resolved.facets)!;
      expect(facets, hasLength(200));
      expect(facets.sublist(198), [
        '[3454,3471) [link https://a.com/198]',
        '[3472,3491) [mention did:plc:alice]',
      ]);
    });

    test('truncates to 200 facets after sorting', () async {
      // The mention sorts first, so the last of the 200 links is dropped
      final links = [for (var i = 0; i < 200; i++) 'https://a.com/$i'];
      final resolver = FakeMentionResolver(
        handles: {'alice.coves.social': 'did:plc:alice'},
      );
      final resolved = await composeAndResolve(
        '@alice.coves.social ${links.join(' ')}',
        resolver,
      );
      final facets = describeFacets(resolved.facets)!;
      expect(facets, hasLength(200));
      expect(
        [facets.first, facets.last],
        [
          '[0,19) [mention did:plc:alice]',
          '[3474,3491) [link https://a.com/198]',
        ],
      );
    });
  });

  group('resolveMentions concurrency', () {
    test('starts every lookup before any completes', () async {
      final gates = {
        'user alice.coves.social': Completer<void>(),
        'community gaming': Completer<void>(),
      };
      final resolver = FakeMentionResolver(
        handles: {'alice.coves.social': 'did:plc:alice'},
        communities: {'gaming': 'did:plc:gaming'},
        gates: gates,
      );
      final pending = composeAndResolve(
        '@alice.coves.social !gaming',
        resolver,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        resolver.started,
        unorderedEquals(['user alice.coves.social', 'community gaming']),
      );
      expect(resolver.completed, isEmpty);

      for (final gate in gates.values) {
        gate.complete();
      }
      final resolved = await pending;
      expect(describeFacets(resolved.facets), [
        '[0,19) [mention did:plc:alice]',
        '[20,27) [mention did:plc:gaming]',
      ]);
    });
  });
}
