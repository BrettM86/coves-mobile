import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../config/environment_config.dart';
import '../constants/default_avatars.dart';

/// Default avatar assignment for a user DID (PRD_DEFAULT_AVATARS §4.2).
///
/// `digest = SHA-256(UTF-8 DID)`, with the DID exactly as the API returned
/// it (no normalisation). The picture index is the big-endian uint32 of
/// digest bytes 0..4 mod the pool size; the tint index is the big-endian
/// uint32 of bytes 4..8 mod the palette size.
class DefaultAvatar {
  const DefaultAvatar._({required this.pictureIndex, required this.tintIndex});

  factory DefaultAvatar.forDid(String did) {
    final digest = digestOf(did);
    return DefaultAvatar._(
      pictureIndex: _uint32BigEndian(digest, 0) % defaultAvatarSlugs.length,
      tintIndex: _uint32BigEndian(digest, 4) % defaultAvatarTints.length,
    );
  }

  /// Index into [defaultAvatarSlugs].
  final int pictureIndex;

  /// Index into [defaultAvatarTints].
  final int tintIndex;

  String get slug => defaultAvatarSlugs[pictureIndex];

  Color get tint => defaultAvatarTints[tintIndex];

  /// The picture's URL on the AppView (§4.4).
  String get url =>
      '${EnvironmentConfig.current.apiUrl}/img/default-avatars/v1/$slug.webp';

  /// The full SHA-256 digest of the UTF-8 bytes of [did].
  @visibleForTesting
  static List<int> digestOf(String did) =>
      sha256.convert(utf8.encode(did)).bytes;

  static int _uint32BigEndian(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
