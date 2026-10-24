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

    test('prefers "description" over "bio" when both present', () {
      final profile = UserProfile.fromJson(const {
        'did': 'did:plc:abc123',
        'bio': 'bio loses',
        'description': 'description wins',
      });

      expect(profile.bio, 'description wins');
    });

    test('bio is null when neither key present', () {
      final profile = UserProfile.fromJson(const {'did': 'did:plc:abc123'});

      expect(profile.bio, isNull);
    });

    test('throws FormatException on missing DID', () {
      expect(
        () => UserProfile.fromJson(const {'handle': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('UserProfile.toJson', () {
    test('writes the bio as "description", not "bio"', () {
      final json = UserProfile(
        did: 'did:plc:abc123',
        bio: 'Bio on the wire',
      ).toJson();

      expect(json['description'], 'Bio on the wire');
      expect(json.containsKey('bio'), isFalse);
    });
  });

  group('ProfileViewerState.fromJson', () {
    const uri = 'at://did:plc:viewer/social.coves.actor.block/3abc';

    test('parses backend "blocking" record-URI shape as blocked', () {
      final viewer = ProfileViewerState.fromJson(const {'blocking': uri});

      expect(viewer.blocked, isTrue);
      expect(viewer.blockUri, uri);
    });

    test('parses legacy blocked/blockUri shape', () {
      final viewer = ProfileViewerState.fromJson(const {
        'blocked': true,
        'blockUri': uri,
      });

      expect(viewer.blocked, isTrue);
      expect(viewer.blockUri, uri);
    });

    test('not blocked when no block keys present', () {
      final viewer = ProfileViewerState.fromJson(const {'blockedBy': false});

      expect(viewer.blocked, isFalse);
      expect(viewer.blockUri, isNull);
    });

    test('blocked without any URI is treated as not blocked (defensive)', () {
      final viewer = ProfileViewerState.fromJson(const {'blocked': true});

      expect(viewer.blocked, isFalse);
    });

    test('non-string blocking value parses as not blocked (no TypeError)', () {
      final viewer = ProfileViewerState.fromJson(const {'blocking': 123});

      expect(viewer.blocked, isFalse);
      expect(viewer.blockUri, isNull);
    });

    test('non-string blockUri and non-bool blocked parse defensively', () {
      final viewer = ProfileViewerState.fromJson(const {
        'blockUri': 42,
        'blocked': 'yes',
        'blockedBy': 'nope',
      });

      expect(viewer.blocked, isFalse);
      expect(viewer.blockUri, isNull);
      expect(viewer.blockedBy, isFalse);
    });

    test('explicit blocked=false wins over a present blocking URI', () {
      // Pins current behavior for the contradictory shape: an explicit
      // bool from the server is trusted over URI presence.
      final viewer = ProfileViewerState.fromJson(const {
        'blocked': false,
        'blocking': uri,
      });

      expect(viewer.blocked, isFalse);
    });
  });
}
