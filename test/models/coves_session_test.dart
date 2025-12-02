import 'dart:convert';

import 'package:coves_flutter/models/coves_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CovesSession.fromCallbackUri()', () {
    test('should parse valid URI with all parameters', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=did:plc:test123&session_id=sess456&handle=test.user',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, 'test.user');
    });

    test('should parse valid URI without optional handle', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, null);
    });

    test('should throw FormatException when token is missing', () {
      final uri = Uri.parse(
        'social.coves:/callback?did=did:plc:test123&session_id=sess456',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: token',
          ),
        ),
      );
    });

    test('should throw FormatException when did is missing', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&session_id=sess456',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: did',
          ),
        ),
      );
    });

    test('should throw FormatException when session_id is missing', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=did:plc:test123',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: session_id',
          ),
        ),
      );
    });

    test('should throw FormatException when token is empty', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=&did=did:plc:test123&session_id=sess456',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: token',
          ),
        ),
      );
    });

    test('should throw FormatException when did is empty', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=&session_id=sess456',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: did',
          ),
        ),
      );
    });

    test('should throw FormatException when session_id is empty', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=did:plc:test123&session_id=',
      );

      expect(
        () => CovesSession.fromCallbackUri(uri),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required parameter: session_id',
          ),
        ),
      );
    });

    test('should decode URL-encoded token values', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc%2B123%2F456%3D&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, 'abc+123/456=');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
    });

    test('should handle URL-encoded spaces in token', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=token%20with%20spaces&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, 'token with spaces');
    });

    test('should ignore extra/unknown parameters', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=abc123&did=did:plc:test123&session_id=sess456&extra=ignored&unknown=also_ignored',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
    });

    test('should handle complex token values', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(
        session.token,
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U',
      );
    });
  });

  group('CovesSession.fromJson()', () {
    test('should parse valid JSON with all fields', () {
      final json = {
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
        'handle': 'test.user',
      };

      final session = CovesSession.fromJson(json);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, 'test.user');
    });

    test('should parse valid JSON without optional handle', () {
      final json = {
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
      };

      final session = CovesSession.fromJson(json);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, null);
    });

    test('should parse JSON with null handle', () {
      final json = {
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
        'handle': null,
      };

      final session = CovesSession.fromJson(json);

      expect(session.handle, null);
    });

    test('should throw when token has wrong type', () {
      final json = {
        'token': 123, // Should be String
        'did': 'did:plc:test123',
        'session_id': 'sess456',
      };

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should throw when did has wrong type', () {
      final json = {
        'token': 'abc123',
        'did': 123, // Should be String
        'session_id': 'sess456',
      };

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should throw when session_id has wrong type', () {
      final json = {
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 123, // Should be String
      };

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should throw when token field is missing', () {
      final json = {'did': 'did:plc:test123', 'session_id': 'sess456'};

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should throw when did field is missing', () {
      final json = {'token': 'abc123', 'session_id': 'sess456'};

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should throw when session_id field is missing', () {
      final json = {'token': 'abc123', 'did': 'did:plc:test123'};

      expect(() => CovesSession.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('should handle extra fields in JSON', () {
      final json = {
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
        'extra_field': 'ignored',
        'another_field': 123,
      };

      final session = CovesSession.fromJson(json);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
    });
  });

  group('CovesSession.fromJsonString()', () {
    test('should parse valid JSON string', () {
      final jsonString = jsonEncode({
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
        'handle': 'test.user',
      });

      final session = CovesSession.fromJsonString(jsonString);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, 'test.user');
    });

    test('should parse valid JSON string without handle', () {
      final jsonString = jsonEncode({
        'token': 'abc123',
        'did': 'did:plc:test123',
        'session_id': 'sess456',
      });

      final session = CovesSession.fromJsonString(jsonString);

      expect(session.token, 'abc123');
      expect(session.did, 'did:plc:test123');
      expect(session.sessionId, 'sess456');
      expect(session.handle, null);
    });

    test('should throw on invalid JSON string', () {
      const invalidJson = '{invalid json}';

      expect(
        () => CovesSession.fromJsonString(invalidJson),
        throwsA(isA<FormatException>()),
      );
    });

    test('should throw on empty string', () {
      const emptyString = '';

      expect(
        () => CovesSession.fromJsonString(emptyString),
        throwsA(isA<FormatException>()),
      );
    });

    test('should throw on non-JSON string', () {
      const notJson = 'not a json string';

      expect(
        () => CovesSession.fromJsonString(notJson),
        throwsA(isA<FormatException>()),
      );
    });

    test('should throw on JSON array instead of object', () {
      const jsonArray = '["token", "did", "session_id"]';

      expect(
        () => CovesSession.fromJsonString(jsonArray),
        throwsA(isA<TypeError>()),
      );
    });

    test('should throw on null JSON', () {
      const nullJson = 'null';

      expect(
        () => CovesSession.fromJsonString(nullJson),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('toJson() / toJsonString()', () {
    test('should serialize to JSON with all fields', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final json = session.toJson();

      expect(json['token'], 'abc123');
      expect(json['did'], 'did:plc:test123');
      expect(json['session_id'], 'sess456');
      expect(json['handle'], 'test.user');
    });

    test('should serialize to JSON without handle when null', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      final json = session.toJson();

      expect(json['token'], 'abc123');
      expect(json['did'], 'did:plc:test123');
      expect(json['session_id'], 'sess456');
      expect(json.containsKey('handle'), false);
    });

    test('should serialize to JSON string', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final jsonString = session.toJsonString();
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(decoded['token'], 'abc123');
      expect(decoded['did'], 'did:plc:test123');
      expect(decoded['session_id'], 'sess456');
      expect(decoded['handle'], 'test.user');
    });

    test('should round-trip: create, serialize, deserialize, compare', () {
      const original = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final json = original.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.token, original.token);
      expect(restored.did, original.did);
      expect(restored.sessionId, original.sessionId);
      expect(restored.handle, original.handle);
    });

    test('should round-trip with JSON string', () {
      const original = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final jsonString = original.toJsonString();
      final restored = CovesSession.fromJsonString(jsonString);

      expect(restored.token, original.token);
      expect(restored.did, original.did);
      expect(restored.sessionId, original.sessionId);
      expect(restored.handle, original.handle);
    });

    test('should round-trip without handle', () {
      const original = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      final json = original.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.token, original.token);
      expect(restored.did, original.did);
      expect(restored.sessionId, original.sessionId);
      expect(restored.handle, null);
    });

    test('should handle special characters in serialization', () {
      const session = CovesSession(
        token: 'token+with/special=chars',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'user.with.dots',
      );

      final jsonString = session.toJsonString();
      final restored = CovesSession.fromJsonString(jsonString);

      expect(restored.token, session.token);
      expect(restored.handle, session.handle);
    });
  });

  group('copyWithToken()', () {
    test('should create new session with updated token', () {
      const original = CovesSession(
        token: 'old_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final updated = original.copyWithToken('new_token');

      expect(updated.token, 'new_token');
      expect(updated.did, original.did);
      expect(updated.sessionId, original.sessionId);
      expect(updated.handle, original.handle);
    });

    test('should preserve null handle when copying with new token', () {
      const original = CovesSession(
        token: 'old_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      final updated = original.copyWithToken('new_token');

      expect(updated.token, 'new_token');
      expect(updated.did, original.did);
      expect(updated.sessionId, original.sessionId);
      expect(updated.handle, null);
    });

    test('should not modify original session', () {
      const original = CovesSession(
        token: 'old_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final updated = original.copyWithToken('new_token');

      expect(original.token, 'old_token');
      expect(updated.token, 'new_token');
    });

    test('should handle empty string token', () {
      const original = CovesSession(
        token: 'old_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      final updated = original.copyWithToken('');

      expect(updated.token, '');
      expect(updated.did, original.did);
    });

    test('should handle complex token values', () {
      const original = CovesSession(
        token: 'old_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      const newToken =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';
      final updated = original.copyWithToken(newToken);

      expect(updated.token, newToken);
    });
  });

  group('toString()', () {
    test('should not expose token in string representation', () {
      const session = CovesSession(
        token: 'secret_token_abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(stringRep, isNot(contains('secret_token_abc123')));
      expect(stringRep, isNot(contains('token')));
    });

    test('should include did in string representation', () {
      const session = CovesSession(
        token: 'secret_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(stringRep, contains('did:plc:test123'));
    });

    test('should include handle in string representation', () {
      const session = CovesSession(
        token: 'secret_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(stringRep, contains('test.user'));
    });

    test('should include sessionId in string representation', () {
      const session = CovesSession(
        token: 'secret_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(stringRep, contains('sess456'));
    });

    test('should handle null handle in string representation', () {
      const session = CovesSession(
        token: 'secret_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      final stringRep = session.toString();

      expect(stringRep, contains('did:plc:test123'));
      expect(stringRep, contains('sess456'));
      expect(stringRep, contains('null'));
    });

    test('should follow expected format', () {
      const session = CovesSession(
        token: 'secret_token',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(
        stringRep,
        'CovesSession(did: did:plc:test123, handle: test.user, sessionId: sess456)',
      );
    });
  });

  group('Edge cases', () {
    test('should handle very long token values', () {
      final longToken = 'a' * 10000;
      final session = CovesSession(
        token: longToken,
        did: 'did:plc:test123',
        sessionId: 'sess456',
      );

      expect(session.token.length, 10000);

      final json = session.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.token, longToken);
    });

    test('should handle unicode characters in handle', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.用户.bsky.social',
      );

      final json = session.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.handle, 'test.用户.bsky.social');
    });

    test('should handle DID with different methods', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:web:example.com',
        sessionId: 'sess456',
      );

      final json = session.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.did, 'did:web:example.com');
    });

    test('should handle session with colons in sessionId', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess:456:789',
      );

      final json = session.toJson();
      final restored = CovesSession.fromJson(json);

      expect(restored.sessionId, 'sess:456:789');
    });

    test('should handle empty handle string', () {
      const session = CovesSession(
        token: 'abc123',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: '',
      );

      final json = session.toJson();

      expect(json['handle'], '');
    });

    test('should handle whitespace in token from callback URI', () {
      final uri = Uri.parse(
        'social.coves:/callback?token=%20abc123%20&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      expect(session.token, ' abc123 ');
    });

    test('should handle multiple URL encoding passes', () {
      // Token that's been double-encoded
      final uri = Uri.parse(
        'social.coves:/callback?token=abc%252B123&did=did:plc:test123&session_id=sess456',
      );

      final session = CovesSession.fromCallbackUri(uri);

      // Uri.queryParameters decodes once, Uri.decodeComponent decodes again
      expect(session.token, 'abc+123');
    });
  });

  group('Security', () {
    test('toString should not leak sensitive token data', () {
      const session = CovesSession(
        token: 'super_secret_encrypted_token_12345',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      // Verify the entire token is not present
      expect(stringRep, isNot(contains('super_secret_encrypted_token_12345')));
      // Verify even partial token data is not present
      expect(stringRep, isNot(contains('secret')));
      expect(stringRep, isNot(contains('encrypted')));
      expect(stringRep, isNot(contains('12345')));
    });

    test('toString should be safe for logging', () {
      const session = CovesSession(
        token: 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9',
        did: 'did:plc:test123',
        sessionId: 'sess456',
        handle: 'test.user',
      );

      final stringRep = session.toString();

      expect(stringRep, isNot(contains('Bearer')));
      expect(
        stringRep,
        isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')),
      );
    });
  });
}
