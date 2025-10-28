/// Unit tests for the identity resolution layer.
///
/// Note: These are basic validation tests. Real integration tests would
/// require network calls to live services.

import 'package:flutter_test/flutter_test.dart';
import 'package:atproto_oauth_flutter/src/identity/identity.dart';

void main() {
  group('DID Validation', () {
    test('isDidPlc validates did:plc correctly', () {
      // did:plc must be exactly 32 chars total (8 prefix + 24 base32 [a-z2-7])
      expect(isDidPlc('did:plc:z72i7hdynmk6r22z27h6abc2'), isTrue);
      expect(isDidPlc('did:plc:2222222222222222222222ab'), isTrue);
      expect(isDidPlc('did:plc:abcdefgabcdefgabcdefgabc'), isTrue);

      // Wrong length
      expect(isDidPlc('did:plc:short'), isFalse);
      expect(isDidPlc('did:plc:toolonggggggggggggggggggggg'), isFalse);

      // Wrong prefix
      expect(isDidPlc('did:web:example.com'), isFalse);

      // Invalid characters (not base32)
      expect(isDidPlc('did:plc:0000000000000000000000'), isFalse); // has 0
      expect(isDidPlc('did:plc:1111111111111111111111'), isFalse); // has 1
    });

    test('isDidWeb validates did:web correctly', () {
      expect(isDidWeb('did:web:example.com'), isTrue);
      expect(isDidWeb('did:web:example.com:user:alice'), isTrue);
      expect(isDidWeb('did:web:localhost%3A3000'), isTrue);

      // Wrong prefix
      expect(isDidWeb('did:plc:abc123xyz789abc123xyz789'), isFalse);

      // Can't start with colon after prefix
      expect(isDidWeb('did:web::example.com'), isFalse);
    });

    test('isDid validates general DIDs', () {
      expect(isDid('did:plc:abc123xyz789abc123xyz789'), isTrue);
      expect(isDid('did:web:example.com'), isTrue);
      expect(isDid('did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK'), isTrue);

      // Invalid
      expect(isDid('not-a-did'), isFalse);
      expect(isDid('did:'), isFalse);
      expect(isDid('did:method'), isFalse);
      expect(isDid(''), isFalse);
    });

    test('extractDidMethod extracts method name', () {
      expect(extractDidMethod('did:plc:abc123'), equals('plc'));
      expect(extractDidMethod('did:web:example.com'), equals('web'));
      expect(extractDidMethod('did:key:z6Mk...'), equals('key'));
    });

    test('didWebToUrl converts did:web to URL', () {
      final url1 = didWebToUrl('did:web:example.com');
      expect(url1.toString(), equals('https://example.com'));

      final url2 = didWebToUrl('did:web:example.com:user:alice');
      expect(url2.toString(), equals('https://example.com/user/alice'));

      final url3 = didWebToUrl('did:web:localhost%3A3000');
      expect(url3.toString(), equals('http://localhost:3000'));
    });

    test('urlToDidWeb converts URL to did:web', () {
      final did1 = urlToDidWeb(Uri.parse('https://example.com'));
      expect(did1, equals('did:web:example.com'));

      final did2 = urlToDidWeb(Uri.parse('https://example.com/user/alice'));
      expect(did2, equals('did:web:example.com:user:alice'));
    });
  });

  group('Handle Validation', () {
    test('isValidHandle validates handles', () {
      expect(isValidHandle('alice.example.com'), isTrue);
      expect(isValidHandle('user.bsky.social'), isTrue);
      expect(isValidHandle('sub.domain.example.com'), isTrue);
      expect(isValidHandle('a.b'), isTrue);

      // Invalid
      expect(isValidHandle(''), isFalse);
      expect(isValidHandle('no-tld'), isFalse);
      expect(isValidHandle('.starts-with-dot.com'), isFalse);
      expect(isValidHandle('ends-with-dot.com.'), isFalse);
      expect(isValidHandle('has..double-dot.com'), isFalse);
      expect(isValidHandle('has spaces.com'), isFalse);

      // Too long (254+ chars)
      final longHandle = '${'a' * 250}.com';
      expect(isValidHandle(longHandle), isFalse);
    });

    test('normalizeHandle converts to lowercase', () {
      expect(normalizeHandle('Alice.Example.Com'), equals('alice.example.com'));
      expect(normalizeHandle('USER.BSKY.SOCIAL'), equals('user.bsky.social'));
    });

    test('asNormalizedHandle validates and normalizes', () {
      expect(asNormalizedHandle('Alice.Example.Com'), equals('alice.example.com'));
      expect(asNormalizedHandle('invalid'), isNull);
      expect(asNormalizedHandle(''), isNull);
    });
  });

  group('DID Document', () {
    test('DidDocument parses from JSON', () {
      final json = {
        'id': 'did:plc:abc123xyz789abc123xyz789',
        'alsoKnownAs': ['at://alice.bsky.social'],
        'service': [
          {
            'id': '#atproto_pds',
            'type': 'AtprotoPersonalDataServer',
            'serviceEndpoint': 'https://pds.example.com',
          }
        ],
      };

      final doc = DidDocument.fromJson(json);

      expect(doc.id, equals('did:plc:abc123xyz789abc123xyz789'));
      expect(doc.alsoKnownAs, contains('at://alice.bsky.social'));
      expect(doc.service?.length, equals(1));
      expect(doc.service?[0].type, equals('AtprotoPersonalDataServer'));
    });

    test('DidDocument extracts PDS URL', () {
      final doc = DidDocument(
        id: 'did:plc:test',
        service: [
          DidService(
            id: '#atproto_pds',
            type: 'AtprotoPersonalDataServer',
            serviceEndpoint: 'https://pds.example.com',
          ),
        ],
      );

      expect(doc.extractPdsUrl(), equals('https://pds.example.com'));
    });

    test('DidDocument extracts handle', () {
      final doc = DidDocument(
        id: 'did:plc:test',
        alsoKnownAs: ['at://alice.bsky.social', 'https://example.com'],
      );

      expect(doc.extractAtprotoHandle(), equals('alice.bsky.social'));
      expect(doc.extractNormalizedHandle(), equals('alice.bsky.social'));
    });

    test('DidDocument returns null for missing PDS', () {
      final doc = DidDocument(id: 'did:plc:test');
      expect(doc.extractPdsUrl(), isNull);
    });

    test('DidDocument returns null for missing handle', () {
      final doc = DidDocument(id: 'did:plc:test');
      expect(doc.extractAtprotoHandle(), isNull);
      expect(doc.extractNormalizedHandle(), isNull);
    });
  });

  group('Cache', () {
    test('InMemoryDidCache stores and retrieves', () async {
      final cache = InMemoryDidCache(ttl: Duration(seconds: 1));
      final doc = DidDocument(id: 'did:plc:test');

      await cache.set('did:plc:test', doc);
      final retrieved = await cache.get('did:plc:test');

      expect(retrieved?.id, equals('did:plc:test'));
    });

    test('InMemoryDidCache expires entries', () async {
      final cache = InMemoryDidCache(ttl: Duration(milliseconds: 100));
      final doc = DidDocument(id: 'did:plc:test');

      await cache.set('did:plc:test', doc);

      // Should exist immediately
      expect(await cache.get('did:plc:test'), isNotNull);

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 150));

      // Should be expired
      expect(await cache.get('did:plc:test'), isNull);
    });

    test('InMemoryHandleCache stores and retrieves', () async {
      final cache = InMemoryHandleCache(ttl: Duration(seconds: 1));

      await cache.set('alice.bsky.social', 'did:plc:test');
      final retrieved = await cache.get('alice.bsky.social');

      expect(retrieved, equals('did:plc:test'));
    });

    test('Cache clears all entries', () async {
      final cache = InMemoryDidCache();
      final doc = DidDocument(id: 'did:plc:test');

      await cache.set('did:plc:test', doc);
      expect(await cache.get('did:plc:test'), isNotNull);

      await cache.clear();
      expect(await cache.get('did:plc:test'), isNull);
    });
  });

  group('Error Types', () {
    test('IdentityResolverError has message', () {
      final error = IdentityResolverError('Test error');
      expect(error.message, equals('Test error'));
      expect(error.toString(), contains('Test error'));
    });

    test('InvalidDidError includes DID', () {
      final error = InvalidDidError('not:valid', 'Invalid format');
      expect(error.did, equals('not:valid'));
      expect(error.toString(), contains('not:valid'));
      expect(error.toString(), contains('Invalid format'));
    });

    test('InvalidHandleError includes handle', () {
      final error = InvalidHandleError('invalid', 'Invalid format');
      expect(error.handle, equals('invalid'));
      expect(error.toString(), contains('invalid'));
      expect(error.toString(), contains('Invalid format'));
    });
  });
}
