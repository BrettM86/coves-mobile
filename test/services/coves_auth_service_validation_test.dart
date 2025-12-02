import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'coves_auth_service_test.mocks.dart';

@GenerateMocks([Dio, FlutterSecureStorage])
void main() {
  late MockDio mockDio;
  late MockFlutterSecureStorage mockStorage;
  late CovesAuthService authService;

  setUp(() {
    CovesAuthService.resetInstance();
    mockDio = MockDio();
    mockStorage = MockFlutterSecureStorage();
    authService = CovesAuthService.createTestInstance(
      dio: mockDio,
      storage: mockStorage,
    );
  });

  tearDown(() {
    CovesAuthService.resetInstance();
  });

  group('Handle Validation', () {
    group('Valid inputs', () {
      test('should accept standard handle format', () {
        final result =
            authService.validateAndNormalizeHandle('alice.bsky.social');
        expect(result, 'alice.bsky.social');
      });

      test('should accept handle with @ prefix and strip it', () {
        final result =
            authService.validateAndNormalizeHandle('@alice.bsky.social');
        expect(result, 'alice.bsky.social');
      });

      test('should accept handle with leading/trailing whitespace and trim', () {
        final result =
            authService.validateAndNormalizeHandle('  alice.bsky.social  ');
        expect(result, 'alice.bsky.social');
      });

      test('should accept handle with hyphen in segment', () {
        final result =
            authService.validateAndNormalizeHandle('alice-bob.bsky.social');
        expect(result, 'alice-bob.bsky.social');
      });

      test('should accept handle with multiple hyphens', () {
        final result = authService
            .validateAndNormalizeHandle('alice-bob-charlie.bsky-app.social');
        expect(result, 'alice-bob-charlie.bsky-app.social');
      });

      test('should accept handle with multiple subdomains', () {
        final result = authService
            .validateAndNormalizeHandle('alice.subdomain.example.com');
        expect(result, 'alice.subdomain.example.com');
      });

      test('should accept handle with numbers', () {
        final result =
            authService.validateAndNormalizeHandle('user123.bsky.social');
        expect(result, 'user123.bsky.social');
      });

      test('should convert handle to lowercase', () {
        final result =
            authService.validateAndNormalizeHandle('Alice.Bsky.Social');
        expect(result, 'alice.bsky.social');
      });

      test('should extract and validate handle from Bluesky profile URL (HTTP)', () {
        final result = authService.validateAndNormalizeHandle(
            'http://bsky.app/profile/alice.bsky.social');
        expect(result, 'alice.bsky.social');
      });

      test('should extract and validate handle from Bluesky profile URL (HTTPS)', () {
        final result = authService.validateAndNormalizeHandle(
            'https://bsky.app/profile/alice.bsky.social');
        expect(result, 'alice.bsky.social');
      });

      test('should extract and validate handle from Bluesky profile URL with www', () {
        final result = authService.validateAndNormalizeHandle(
            'https://www.bsky.app/profile/alice.bsky.social');
        expect(result, 'alice.bsky.social');
      });

      test('should accept DID with plc method', () {
        final result =
            authService.validateAndNormalizeHandle('did:plc:abc123def456');
        expect(result, 'did:plc:abc123def456');
      });

      test('should accept DID with web method', () {
        final result =
            authService.validateAndNormalizeHandle('did:web:example.com');
        expect(result, 'did:web:example.com');
      });

      test('should accept DID with complex identifier', () {
        final result = authService
            .validateAndNormalizeHandle('did:plc:z72i7hdynmk6r22z27h6tvur');
        expect(result, 'did:plc:z72i7hdynmk6r22z27h6tvur');
      });

      test('should accept DID with periods and colons in identifier', () {
        final result = authService
            .validateAndNormalizeHandle('did:web:example.com:user:alice');
        expect(result, 'did:web:example.com:user:alice');
      });

      test('should accept short handle', () {
        final result = authService.validateAndNormalizeHandle('a.b');
        expect(result, 'a.b');
      });

      test('should normalize handle with @ prefix and whitespace', () {
        final result =
            authService.validateAndNormalizeHandle('  @Alice.Bsky.Social  ');
        expect(result, 'alice.bsky.social');
      });

      test('should accept handle with numeric first segment', () {
        final result =
            authService.validateAndNormalizeHandle('123.bsky.social');
        expect(result, '123.bsky.social');
      });

      test('should accept handle with numeric middle segment', () {
        final result =
            authService.validateAndNormalizeHandle('alice.456.social');
        expect(result, 'alice.456.social');
      });

      test('should accept handle with multiple numeric segments', () {
        final result =
            authService.validateAndNormalizeHandle('42.example.com');
        expect(result, '42.example.com');
      });

      test('should accept handle similar to 4chan.org', () {
        final result = authService.validateAndNormalizeHandle('4chan.org');
        expect(result, '4chan.org');
      });

      test('should accept handle with numeric and alpha mixed', () {
        final result =
            authService.validateAndNormalizeHandle('8.cn');
        expect(result, '8.cn');
      });

      test('should accept handle like IP but with valid TLD', () {
        final result =
            authService.validateAndNormalizeHandle('120.0.0.1.com');
        expect(result, '120.0.0.1.com');
      });
    });

    group('Invalid inputs', () {
      test('should throw ArgumentError when handle is empty', () {
        expect(
          () => authService.validateAndNormalizeHandle(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw ArgumentError when handle is whitespace-only', () {
        expect(
          () => authService.validateAndNormalizeHandle('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw ArgumentError for handle without period', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('domain format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle starting with hyphen', () {
        expect(
          () => authService.validateAndNormalizeHandle('-alice.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle ending with hyphen', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice-.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for segment with hyphen at end', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice.bsky-.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle starting with period', () {
        expect(
          () => authService.validateAndNormalizeHandle('.alice.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle ending with period', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice.bsky.social.'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with consecutive periods', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice..bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  (e.message.toString().contains('empty segments') ||
                      e.message.toString().contains('Invalid handle format')),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with spaces', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with @ in middle', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice@bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with underscore', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice_bob.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with exclamation mark', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice!.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle with slash', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice/bob.bsky.social'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid handle format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for handle exceeding 253 characters', () {
        // Create a handle that's 254 characters long
        final longHandle = '${'a' * 240}.bsky.social';
        expect(
          () => authService.validateAndNormalizeHandle(longHandle),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('too long'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for segment exceeding 63 characters', () {
        // DNS label limit is 63 characters per segment
        final longSegment = '${'a' * 64}.bsky.social';
        expect(
          () => authService.validateAndNormalizeHandle(longSegment),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('too long'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for TLD starting with digit', () {
        expect(
          () => authService.validateAndNormalizeHandle('alice.bsky.123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('TLD') &&
                  e.message.toString().contains('cannot start with a digit'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for all-numeric TLD', () {
        expect(
          () => authService.validateAndNormalizeHandle('123.456.789'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('TLD') &&
                  e.message.toString().contains('cannot start with a digit'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for IPv4 address (TLD starts with digit)', () {
        expect(
          () => authService.validateAndNormalizeHandle('127.0.0.1'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('TLD') &&
                  e.message.toString().contains('cannot start with a digit'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for IPv4 address variant', () {
        expect(
          () => authService.validateAndNormalizeHandle('192.168.0.142'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('TLD') &&
                  e.message.toString().contains('cannot start with a digit'),
            ),
          ),
        );
      });
    });

    group('DID Validation', () {
      test('should accept valid plc DID', () {
        final result =
            authService.validateAndNormalizeHandle('did:plc:abc123');
        expect(result, 'did:plc:abc123');
      });

      test('should accept valid web DID', () {
        final result =
            authService.validateAndNormalizeHandle('did:web:example.com');
        expect(result, 'did:web:example.com');
      });

      test('should accept DID with underscores in identifier', () {
        // Underscores are allowed in the DID pattern (part of [a-zA-Z0-9._:%-]+)
        final result =
            authService.validateAndNormalizeHandle('did:plc:abc_123');
        expect(result, 'did:plc:abc_123');
      });

      test('should throw ArgumentError for invalid DID with @ special chars', () {
        expect(
          () => authService.validateAndNormalizeHandle('did:plc:abc@123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for DID with uppercase method', () {
        expect(
          () => authService.validateAndNormalizeHandle('did:PLC:abc123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for DID with spaces', () {
        expect(
          () => authService.validateAndNormalizeHandle('did:plc:abc 123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for malformed DID (missing identifier)', () {
        expect(
          () => authService.validateAndNormalizeHandle('did:plc'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for malformed DID (missing method)', () {
        expect(
          () => authService.validateAndNormalizeHandle('did::abc123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for DID without prefix', () {
        expect(
          () => authService.validateAndNormalizeHandle('plc:abc123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('domain format'),
            ),
          ),
        );
      });

      test('should throw ArgumentError for DID with invalid method chars', () {
        expect(
          () => authService.validateAndNormalizeHandle('did:pl-c:abc123'),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.message.toString().contains('Invalid DID format'),
            ),
          ),
        );
      });
    });
  });
}
