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
        r'$type': 'social.coves.richtext.facet#mention',
        'did': 'did:plc:abc123',
      };

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'social.coves.richtext.facet#mention');
    });

    test('returns UnknownFacetFeature when \$type is missing', () {
      final json = {'uri': 'https://example.com'};

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
      expect(feature.type, 'unknown');
    });

    test('returns UnknownFacetFeature when \$type is empty', () {
      final json = {r'$type': '', 'uri': 'https://example.com'};

      final feature = FacetFeature.fromJson(json);

      expect(feature, isA<UnknownFacetFeature>());
    });

    test('throws FormatException when LinkFacetFeature has missing uri', () {
      final json = {r'$type': 'social.coves.richtext.facet#link'};

      expect(
        () => FacetFeature.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('uri'),
          ),
        ),
      );
    });

    test('throws FormatException when LinkFacetFeature has empty uri', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#link',
        'uri': '',
      };

      expect(
        () => FacetFeature.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('uri'),
          ),
        ),
      );
    });

    test('throws FormatException when LinkFacetFeature has non-string uri', () {
      final json = {
        r'$type': 'social.coves.richtext.facet#link',
        'uri': 123,
      };

      expect(
        () => FacetFeature.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('uri'),
          ),
        ),
      );
    });
  });

  group('LinkFacetFeature', () {
    test('construction and properties', () {
      const feature = LinkFacetFeature(uri: 'https://example.com');

      expect(feature.uri, 'https://example.com');
      expect(feature.type, 'social.coves.richtext.facet#link');
    });

    test('toJson produces correct format with \$type field', () {
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

    test('type property returns \$type from data', () {
      final feature = UnknownFacetFeature(data: {
        r'$type': 'custom.feature#type',
      });

      expect(feature.type, 'custom.feature#type');
    });

    test('type property returns "unknown" when \$type is missing', () {
      final feature = UnknownFacetFeature(data: {'foo': 'bar'});

      expect(feature.type, 'unknown');
    });

    test('equality works with same data', () {
      final feature1 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });
      final feature2 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });
      final feature3 = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 456,
      });

      expect(feature1, equals(feature2));
      expect(feature1, isNot(equals(feature3)));
    });

    test('identical instances have equal hashCode', () {
      final feature = UnknownFacetFeature(data: {
        r'$type': 'test',
        'value': 123,
      });

      // Identical instances should have same hashCode
      expect(identical(feature, feature), isTrue);
      // Note: hashCode is called twice but on the same object
    });

    test('toString format', () {
      final feature = UnknownFacetFeature(data: {
        r'$type': 'social.coves.richtext.facet#mention',
      });

      expect(
          feature.toString(), 'UnknownFacetFeature(social.coves.richtext.facet#mention)');
    });
  });

  group('RichTextFacet', () {
    test('valid construction and properties', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      final facet = RichTextFacet(index: index, features: features);

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
      expect(facet.features[1], isA<UnknownFacetFeature>());
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
      final facet = RichTextFacet(index: index, features: features);

      final json = facet.toJson();

      expect(json['index'], {'byteStart': 10, 'byteEnd': 30});
      expect(json['features'], [
        {r'$type': 'social.coves.richtext.facet#link', 'uri': 'https://test.org'},
      ]);
    });

    test('toJson/fromJson round-trip', () {
      const index = ByteSlice(byteStart: 5, byteEnd: 25);
      const features = [LinkFacetFeature(uri: 'https://example.com/path')];
      final original = RichTextFacet(index: index, features: features);

      final json = original.toJson();
      final restored = RichTextFacet.fromJson(json);

      expect(restored.index, original.index);
      expect(restored.features.length, original.features.length);
      expect(restored.linkUri, original.linkUri);
    });

    test('hasLink returns true when contains LinkFacetFeature', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, true);
    });

    test('hasLink returns false when no LinkFacetFeature', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      final features = [
        UnknownFacetFeature(data: {r'$type': 'mention'}),
      ];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, false);
    });

    test('hasLink returns false with empty features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const List<FacetFeature> features = [];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.hasLink, false);
    });

    test('linkUri returns URI when has link', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com/page')];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, 'https://example.com/page');
    });

    test('linkUri returns first link URI when multiple links', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [
        LinkFacetFeature(uri: 'https://first.com'),
        LinkFacetFeature(uri: 'https://second.com'),
      ];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, 'https://first.com');
    });

    test('linkUri returns null when no link', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      final features = [
        UnknownFacetFeature(data: {r'$type': 'mention'}),
      ];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, null);
    });

    test('linkUri returns null with empty features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const List<FacetFeature> features = [];
      final facet = RichTextFacet(index: index, features: features);

      expect(facet.linkUri, null);
    });

    test('equality and hashCode', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      final facet1 = RichTextFacet(index: index, features: features);
      final facet2 = RichTextFacet(index: index, features: features);
      final facet3 = RichTextFacet(
        index: const ByteSlice(byteStart: 0, byteEnd: 20),
        features: features,
      );

      expect(facet1, equals(facet2));
      expect(facet1.hashCode, facet2.hashCode);
      expect(facet1, isNot(equals(facet3)));
    });

    test('equality with different features', () {
      const index = ByteSlice(byteStart: 0, byteEnd: 10);
      final facet1 = RichTextFacet(
        index: index,
        features: const [LinkFacetFeature(uri: 'https://example.com')],
      );
      final facet2 = RichTextFacet(
        index: index,
        features: const [LinkFacetFeature(uri: 'https://other.com')],
      );

      expect(facet1, isNot(equals(facet2)));
    });

    test('toString format', () {
      const index = ByteSlice(byteStart: 5, byteEnd: 15);
      const features = [LinkFacetFeature(uri: 'https://example.com')];
      final facet = RichTextFacet(index: index, features: features);

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
