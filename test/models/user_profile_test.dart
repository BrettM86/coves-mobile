import 'package:coves_flutter/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses bio from "description" key (backend wire format)', () {
      // social.coves.actor.getProfile serializes the bio as "description"
      // (atProto profile convention) — regression test for the profile
      // header never showing a saved bio.
      final profile = UserProfile.fromJson(const {
        'did': 'did:plc:abc123',
        'handle': 'mari.local.coves.dev',
        'displayName': 'Mari',
        'description': 'Bio from the wire',
      });

      expect(profile.bio, 'Bio from the wire');
    });

    test('parses bio from "bio" key (lexicon field name)', () {
      final profile = UserProfile.fromJson(const {
        'did': 'did:plc:abc123',
        'bio': 'Lexicon-style bio',
      });

      expect(profile.bio, 'Lexicon-style bio');
    });

    test('prefers "bio" over "description" when both present', () {
      final profile = UserProfile.fromJson(const {
        'did': 'did:plc:abc123',
        'bio': 'bio wins',
        'description': 'description loses',
      });

      expect(profile.bio, 'bio wins');
    });

    test('bio is null when neither key present', () {
      final profile = UserProfile.fromJson(const {
        'did': 'did:plc:abc123',
      });

      expect(profile.bio, isNull);
    });

    test('throws FormatException on missing DID', () {
      expect(
        () => UserProfile.fromJson(const {'handle': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
