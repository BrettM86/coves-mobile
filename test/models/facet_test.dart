import 'package:coves_flutter/models/facet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteSlice', () {
    test('valid construction with positive values', () {
      const slice = ByteSlice(byteStart: 0, byteEnd: 10);

      expect(slice.byteStart, 0);
      expect(slice.byteEnd, 10);
    });

    test('valid construction with same start and end', () {
      const slice = ByteSlice(byteStart: 5, byteEnd: 5);

      expect(slice.byteStart, 5);
      expect(slice.byteEnd, 5);
    });

    test('equality and hashCode', () {
      const slice1 = ByteSlice(byteStart: 0, byteEnd: 10);
      const slice2 = ByteSlice(byteStart: 0, byteEnd: 10);
      const slice3 = ByteSlice(byteStart: 0, byteEnd: 20);

      expect(slice1, equals(slice2));
      expect(slice1.hashCode, slice2.hashCode);
      expect(slice1, isNot(equals(slice3)));
    });

    test('toJson/fromJson round-trip', () {
      const original = ByteSlice(byteStart: 5, byteEnd: 15);
      final json = original.toJson();
      final restored = ByteSlice.fromJson(json);

      expect(restored, equals(original));
      expect(json['byteStart'], 5);
      expect(json['byteEnd'], 15);
    });

    test('fromJson throws FormatException on missing byteStart', () {
      expect(
        () => ByteSlice.fromJson({'byteEnd': 10}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('byteStart'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on missing byteEnd', () {
      expect(
        () => ByteSlice.fromJson({'byteStart': 0}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('byteEnd'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on invalid byte range (end < start)',
        () {
      expect(
        () => ByteSlice.fromJson({'byteStart': 10, 'byteEnd': 5}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid byte range'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on negative byteStart', () {
      expect(
        () => ByteSlice.fromJson({'byteStart': -1, 'byteEnd': 10}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid byte range'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on negative byteEnd', () {
      expect(
        () => ByteSlice.fromJson({'byteStart': 0, 'byteEnd': -5}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid byte range'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on non-int byteStart', () {
      expect(
        () => ByteSlice.fromJson({'byteStart': 'invalid', 'byteEnd': 10}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('byteStart'),
          ),
        ),
      );
    });

    test('fromJson throws FormatException on non-int byteEnd', () {
      expect(
        () => ByteSlice.fromJson({'byteStart': 0, 'byteEnd': 'invalid'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('byteEnd'),
          ),
        ),
      );
    });

    test('toString format', () {
      const slice = ByteSlice(byteStart: 5, byteEnd: 15);

      expect(slice.toString(), 'ByteSlice(5, 15)');
    });
  });

  group('FacetFeature.fromJson', () {
    test('parses LinkFacetFeature correctly', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#link',
        'uri': 'https://example.com',
      };

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<LinkFacetFeature>());
      expect((feature as LinkFacetFeature).uri, 'https://example.com');
    });

    test('returns UnknownFacetFeature for unknown types', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#futureFeature',
        'attr': 'value',
      };

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'social.coves.richtext.facet#futureFeature');
    });

    test(r'returns UnknownFacetFeature when $type is missing', () {
      final json = {'uri': 'https://example.com'};

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'unknown');
    });

    test(r'returns UnknownFacetFeature when $type is empty', () {
      final json = {r'$type': '', 'uri': 'https://example.com'};

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
    });

    test(r'returns UnknownFacetFeature when $type is a non-string int', () {
      final json = {r'$type': 42, 'uri': 'https://example.com'};

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'unknown');
    });

    test(r'returns UnknownFacetFeature when $type is a list', () {
      final json = {
        r'$type': ['x'],
      };

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'unknown');
    });

    test('degrades link with missing uri to UnknownFacetFeature', () {
      final json = {r'$type': 'social.coves.richtext.facet#link'};

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('degrades link with empty uri to UnknownFacetFeature', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#link',
        'uri': '',
      };

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('degrades link with non-string uri to UnknownFacetFeature', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#link',
        'uri': 123,
      };

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('parses MentionFacetFeature correctly', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#mention',
        'did': 'did:plc:abc123',
      };

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<MentionFacetFeature>());
      expect((feature as MentionFacetFeature).did, 'did:plc:abc123');
    });

    test('degrades mention with missing did to UnknownFacetFeature', () {
      final json = {r'$type': 'social.coves.richtext.facet#mention'};

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('parses simple formatting features', () {
      expect(
        FacetFeature.fromJson({
          r'$type': 'social.coves.richtext.facet#bold',
        }),
        isA<BoldFacetFeature>(),
      );
      expect(
        FacetFeature.fromJson({
          r'$type': 'social.coves.richtext.facet#italic',
        }),
        isA<ItalicFacetFeature>(),
      );
      expect(
        FacetFeature.fromJson({
          r'$type': 'social.coves.richtext.facet#strikethrough',
        }),
        isA<StrikethroughFacetFeature>(),
      );
      expect(
        FacetFeature.fromJson({
          r'$type': 'social.coves.richtext.facet#code',
        }),
        isA<CodeFacetFeature>(),
      );
    });

    test('parses spoiler with and without reason', () {
      final withReason = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#spoiler',
        'reason': 'ending',
      });
      expect(withReason, isA<SpoilerFacetFeature>());
      expect((withReason as SpoilerFacetFeature).reason, 'ending');

      final withoutReason = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#spoiler',
      });
      expect(withoutReason, isA<SpoilerFacetFeature>());
      expect((withoutReason as SpoilerFacetFeature).reason, isNull);
    });

    test('parses blockquote with absent level as level 1', () {
      final feature = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#blockquote',
      });

      expect(feature, isA<BlockquoteFacetFeature>());
      expect((feature as BlockquoteFacetFeature).level, 1);
    });

    test('parses blockquote level and clamps out-of-range values', () {
      final level3 = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#blockquote',
        'level': 3,
      });
      expect((level3 as BlockquoteFacetFeature).level, 3);

      final level9 = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#blockquote',
        'level': 9,
      });
      expect((level9 as BlockquoteFacetFeature).level, 6);
    });

    test('degrades blockquote with non-int level to UnknownFacetFeature', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#blockquote',
        'level': 'two',
      };

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('parses heading level and clamps out-of-range values', () {
      final feature = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#heading',
        'level': 2,
      });

      expect(feature, isA<HeadingFacetFeature>());
      expect((feature as HeadingFacetFeature).level, 2);

      final level9 = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#heading',
        'level': 9,
      });
      expect((level9 as HeadingFacetFeature).level, 6);
    });

    test('degrades heading with missing level to UnknownFacetFeature', () {
      final json = {r'$type': 'social.coves.richtext.facet#heading'};

      expect(FacetFeature.fromJson(json), isA<UnknownFacetFeature>());
    });

    test('parses codeBlock with and without language', () {
      final withLang = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#codeBlock',
        'language': 'go',
      });
      expect(withLang, isA<CodeBlockFacetFeature>());
      expect((withLang as CodeBlockFacetFeature).language, 'go');

      final withoutLang = FacetFeature.fromJson({
        r'$type': 'social.coves.richtext.facet#codeBlock',
      });
      expect(withoutLang, isA<CodeBlockFacetFeature>());
      expect((withoutLang as CodeBlockFacetFeature).language, isNull);
    });

    test('new features round-trip through JSON', () {
      final features = <FacetFeature>[
        const MentionFacetFeature(did: 'did:plc:xyz'),
        const BoldFacetFeature(),
        const ItalicFacetFeature(),
        const StrikethroughFacetFeature(),
        const SpoilerFacetFeature(reason: 'plot'),
        const BlockquoteFacetFeature(level: 2),
        const HeadingFacetFeature(level: 1),
        const CodeFacetFeature(),
        const CodeBlockFacetFeature(language: 'python'),
      ];

      for (final original in features) {
        final restored = FacetFeature.fromJson(original.toJson());
        expect(restored, original, reason: 'round-trip of ${original.type}');
      }
    });
  });

  group('RichTextFacet.blockFeature', () {
    test('returns the first block-level feature', () {
      const facet = RichTextFacet(
        index: ByteSlice(byteStart: 0, byteEnd: 5),
        features: [
          BoldFacetFeature(),
          HeadingFacetFeature(level: 2),
        ],
      );

      expect(facet.blockFeature, const HeadingFacetFeature(level: 2));
    });

    test('returns null when only inline features present', () {
      const facet = RichTextFacet(
        index: ByteSlice(byteStart: 0, byteEnd: 5),
        features: [
          BoldFacetFeature(),
          LinkFacetFeature(uri: 'https://example.com'),
        ],
      );

      expect(facet.blockFeature, isNull);
    });
  });

  group('parseFacetsFromRecord', () {
    test('drops malformed facets but keeps valid ones', () {
      final record = {
        'facets': [
          {
            // Malformed: missing byteStart
            'index': {'byteEnd': 5},
            'features': [
              {r'$type': 'social.coves.richtext.facet#bold'},
            ],
          },
          {
            'index': {'byteStart': 0, 'byteEnd': 5},
            'features': [
              {r'$type': 'social.coves.richtext.facet#bold'},
            ],
          },
        ],
      };

      final facets = parseFacetsFromRecord(record);

      expect(facets, isNotNull);
      expect(facets!.length, 1);
      expect(facets.first.features.first, const BoldFacetFeature());
    });

    test('returns null when every facet is malformed', () {
      final record = {
        'facets': [
          {
            'index': {'byteEnd': 5},
            'features': <Map<String, dynamic>>[],
          },
        ],
      };

      expect(parseFacetsFromRecord(record), isNull);
    });

    test('truncates to the first 200 facets (backend MaxFacets cap)', () {
      final record = {
        'facets': List.generate(
          201,
          (i) => {
            'index': {'byteStart': i, 'byteEnd': i + 1},
            'features': [
              {r'$type': 'social.coves.richtext.facet#bold'},
            ],
          },
        ),
      };

      final facets = parseFacetsFromRecord(record);

      expect(facets, isNotNull);
      expect(facets!.length, 200);
      // First 200 survive: last kept facet is index 199
      expect(facets.last.index, const ByteSlice(byteStart: 199, byteEnd: 200));
    });

    test('drops a facet with more than 20 features but keeps siblings', () {
      final record = {
        'facets': [
          {
            'index': {'byteStart': 0, 'byteEnd': 5},
            'features': List.generate(
              21,
              (_) => {r'$type': 'social.coves.richtext.facet#bold'},
            ),
          },
          {
            'index': {'byteStart': 10, 'byteEnd': 15},
            'features': [
              {r'$type': 'social.coves.richtext.facet#italic'},
            ],
          },
        ],
      };

      final facets = parseFacetsFromRecord(record);

      expect(facets, isNotNull);
      expect(facets!.length, 1);
      expect(facets.first.index, const ByteSlice(byteStart: 10, byteEnd: 15));
      expect(facets.first.features.first, const ItalicFacetFeature());
    });

    test('drops a facet whose features is a non-list without nuking siblings',
        () {
      final record = {
        'facets': [
          {
            'index': {'byteStart': 0, 'byteEnd': 5},
            'features': 'not-a-list',
          },
          {
            'index': {'byteStart': 10, 'byteEnd': 15},
            'features': [
              {r'$type': 'social.coves.richtext.facet#bold'},
            ],
          },
        ],
      };

      final facets = parseFacetsFromRecord(record);

      expect(facets, isNotNull);
      expect(facets!.length, 1);
      expect(facets.first.index, const ByteSlice(byteStart: 10, byteEnd: 15));
    });
  });

  group('LinkFacetFeature', () {
    test('construction and properties', () {
      const feature = LinkFacetFeature(uri: 'https://example.com');

      expect(feature.uri, 'https://example.com');
      expect(feature.type, 'social.coves.richtext.facet#link');
    });

    test(r'toJson produces correct format with $type field', () {
      const feature = LinkFacetFeature(uri: 'https://example.com/path?q=1');
      final json = feature.toJson();

      expect(json[r'$type'], 'social.coves.richtext.facet#link');
      expect(json['uri'], 'https://example.com/path?q=1');
      expect(json.length, 2);
    });

    test('equality and hashCode', () {
      const feature1 = LinkFacetFeature(uri: 'https://example.com');
      const feature2 = LinkFacetFeature(uri: 'https://example.com');
      const feature3 = LinkFacetFeature(uri: 'https://other.com');

      expect(feature1, equals(feature2));
      expect(feature1.hashCode, feature2.hashCode);
      expect(feature1, isNot(equals(feature3)));
    });

    test('toString format', () {
      const feature = LinkFacetFeature(uri: 'https://example.com');

      expect(feature.toString(), 'LinkFacetFeature(https://example.com)');
    });

    test('toJson/fromJson round-trip', () {
      const original = LinkFacetFeature(uri: 'https://example.com/test');
      final json = original.toJson();
      final restored = FacetFeature.fromJson(json);

      expect(restored, isA<LinkFacetFeature>());
      expect((restored as LinkFacetFeature).uri, original.uri);
    });
  });

  group('UnknownFacetFeature', () {
    test('preserves original JSON data', () {
      final data = {
        r'$type': 'social.coves.richtext.facet#hashtag',
        'tag': 'flutter',
        'extra': 'preserved',
      };
      final feature = UnknownFacetFeature(data: data);

      expect(feature.data, data);
      expect(feature.type, 'social.coves.richtext.facet#hashtag');
    });

    test('round-trips through toJson', () {
      final data = {
        r'$type': 'social.coves.richtext.facet#mention',
        'did': 'did:plc:abc123',
        'handle': 'user.bsky.social',
      };
      final feature = UnknownFacetFeature(data: data);
      final json = feature.toJson();

      expect(json, data);
    });

    test(r'type property returns $type from data', () {
      const feature = UnknownFacetFeature(data: {
        r'$type': 'custom.feature#type',
      });

      expect(feature.type, 'custom.feature#type');
    });

    test(r'type property returns "unknown" when $type is missing', () {
      const feature = UnknownFacetFeature(data: {'foo': 'bar'});

      expect(feature.type, 'unknown');
    });

    test(r'type property returns "unknown" when $type is not a string', () {
      const feature = UnknownFacetFeature(data: {r'$type': 42});

      expect(feature.type, 'unknown');
    });

    test('equality works with same data', () {
      const feature1 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });
      const feature2 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });
      const feature3 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 456,
      });

      expect(feature1, equals(feature2));
      expect(feature1, isNot(equals(feature3)));
    });

    test('hashCode is stable and equal instances hash equally', () {
      const feature = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });

      // Stable across calls (the old entries-based hash returned a
      // different value per invocation)
      expect(feature.hashCode, feature.hashCode);

      // ==/hashCode contract: equal content hashes equally, even when the
      // maps were built in a different key order
      const a = UnknownFacetFeature(data: {r'$type': 'test', 'value': 123});
      const b = UnknownFacetFeature(data: {'value': 123, r'$type': 'test'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      // Usable as a set member
      expect({a}.contains(b), isTrue);
    });

    test('toString format', () {
      const feature = UnknownFacetFeature(data: {
        r'$type': 'social.coves.richtext.facet#future',
      });

      expect(
        feature.toString(),
        'UnknownFacetFeature(social.coves.richtext.facet#future)',
      );
    });
  });

  group('RichTextFacet', () {
    test('valid construction and properties', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.index, index);
      expect(facet.features.length, 1);
      expect(facet.features[0], isA<LinkFacetFeature>());
    });

    test('fromJson parses correctly', () {
      final json = {
        'index': {'byteStart': 5, 'byteEnd': 25},
        'features': [
          {
            r'$type': 'social.coves.richtext.facet#link',
            'uri': 'https://example.com',
          },
        ],
      };

      final facet = RichTextFacet.fromJson(json);

      expect(facet.index.byteStart, 5);
      expect(facet.index.byteEnd, 25);
      expect(facet.features.length, 1);
      expect(facet.features[0], isA<LinkFacetFeature>());
      expect((facet.features[0] as LinkFacetFeature).uri, 'https://example.com');
    });

    test('fromJson parses multiple features', () {
      final json = {
        'index': {'byteStart': 0, 'byteEnd': 10},
        'features': [
          {
            r'$type': 'social.coves.richtext.facet#link',
            'uri': 'https://example.com',
          },
          {
            r'$type': 'social.coves.richtext.facet#mention',
            'did': 'did:plc:abc',
          },
        ],
      };

      final facet = RichTextFacet.fromJson(json);

      expect(facet.features.length, 2);
      expect(facet.features[0], isA<LinkFacetFeature>());
      expect(facet.features[1], isA<MentionFacetFeature>());
      expect((facet.features[1] as MentionFacetFeature).did, 'did:plc:abc');
    });

    test('fromJson throws on missing index', () {
      final json = {
        'features': [
          {
            r'$type': 'social.coves.richtext.facet#link',
            'uri': 'https://example.com',
          },
        ],
      };

      expect(
        () => RichTextFacet.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('index'),
          ),
        ),
      );
    });

    test('fromJson throws on invalid index type', () {
      final json = {
        'index': 'invalid',
        'features': [],
      };

      expect(
        () => RichTextFacet.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('index'),
          ),
        ),
      );
    });

    test('fromJson throws on missing features', () {
      final json = {
        'index': {'byteStart': 0, 'byteEnd': 10},
      };

      expect(
        () => RichTextFacet.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('features'),
          ),
        ),
      );
    });

    test('fromJson throws on invalid features type', () {
      final json = {
        'index': {'byteStart': 0, 'byteEnd': 10},
        'features': 'invalid',
      };

      expect(
        () => RichTextFacet.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('features'),
          ),
        ),
      );
    });

    test('toJson produces correct format', () {
      const index = ByteSlice(byteStart: 10, byteEnd: 30);
      const features = [LinkFacetFeature(uri: 'https://test.org')];
      const facet = RichTextFacet(index: index, features: features);

      final json = facet.toJson();

      expect(json['index'], {'byteStart': 10, 'byteEnd': 30});
      expect(json['features'], [
        {r'$type': 'social.coves.richtext.facet#link', 'uri': 'https://test.org'},
      ]);
    });

    test('toJson/fromJson round-trip', () {
      const index = ByteSlice(byteStart: 5, byteEnd: 25);
      const features = [LinkFacetFeature(uri: 'https://example.com/path')];
      const original = RichTextFacet(index: index, features: features);

      final json = original.toJson();
      final restored = RichTextFacet.fromJson(json);

      expect(restored.index, original.index);
      expect(restored.features.length, original.features.length);
      expect(restored.linkUri, original.linkUri);
    });

    test('hasLink returns true when contains LinkFacetFeature', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, true);
    });

    test('hasLink returns false when no LinkFacetFeature', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      final features = [
        const UnknownFacetFeature(data: {r'$type': 'mention'}),
      ];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, false);
    });

    test('hasLink returns false with empty features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = <FacetFeature>[];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, false);
    });

    test('linkUri returns URI when has link', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com/page')];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, 'https://example.com/page');
    });

    test('linkUri returns first link URI when multiple links', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [
        LinkFacetFeature(uri: 'https://first.com'),
        LinkFacetFeature(uri: 'https://second.com'),
      ];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, 'https://first.com');
    });

    test('linkUri returns null when no link', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      final features = [
        const UnknownFacetFeature(data: {r'$type': 'mention'}),
      ];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, null);
    });

    test('linkUri returns null with empty features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = <FacetFeature>[];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, null);
    });

    test('equality and hashCode', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      const facet1 = RichTextFacet(index: index, features: features);
      const facet2 = RichTextFacet(index: index, features: features);
      const facet3 = RichTextFacet(
        index: ByteSlice(byteStart: 0, byteEnd: 20),
        features: features,
      );

      expect(facet1, equals(facet2));
      expect(facet1.hashCode, facet2.hashCode);
      expect(facet1, isNot(equals(facet3)));
    });

    test('equality with different features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const facet1 = RichTextFacet(
        index: index,
        features: [LinkFacetFeature(uri: 'https://example.com')],
      );
      const facet2 = RichTextFacet(
        index: index,
        features: [LinkFacetFeature(uri: 'https://other.com')],
      );

      expect(facet1, isNot(equals(facet2)));
    });

    test('toString format', () {
      const index = ByteSlice(byteStart: 5, byteEnd: 15);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      const facet = RichTextFacet(index: index, features: features);

      expect(facet.toString(), 'RichTextFacet(ByteSlice(5, 15), 1 features)');
    });

    test('filters out non-map items in features array', () {
      final json = {
        'index': {'byteStart': 0, 'byteEnd': 10},
        'features': [
          {
            r'$type': 'social.coves.richtext.facet#link',
            'uri': 'https://example.com',
          },
          'invalid string',
          123,
          null,
        ],
      };

      final facet = RichTextFacet.fromJson(json);

      // Only the valid map should be parsed
      expect(facet.features.length, 1);
      expect(facet.features[0], isA<LinkFacetFeature>());
    });
  });
}
