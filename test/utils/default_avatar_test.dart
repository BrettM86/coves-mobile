import 'package:coves_flutter/constants/default_avatars.dart';
import 'package:coves_flutter/utils/default_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Default avatar assignment (PRD_DEFAULT_AVATARS §4.1, §4.2).
///
/// Every expected value here is a literal. All but one come from the PRD;
/// the upper-case vector (no normalisation) is not in the PRD. None of them
/// is computed with the production code, and none is compared against
/// another client's output.
void main() {
  String hexPrefix(List<int> bytes, int length) => bytes
      .take(length)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  test('§4.2 vectors map each DID to its literal picture and tint', () {
    // (did, first 8 digest bytes, picture index, slug, tint index, tint ARGB)
    const vectors = <(String, String, int, String, int, int)>[
      (
        'did:plc:ewvi7nxzyoun6zhxrhs64oiz',
        '099e4ea96cd62c05',
        15,
        'ocean-wave',
        5,
        0xFFD5E6E3,
      ),
      (
        'did:plc:z72i7hdynmk6r22z27h6tvur',
        'f5b57a549b7ad681',
        20,
        'pufferfish',
        1,
        0xFFD8E8D4,
      ),
      (
        'did:web:coves.social',
        'e5417994bd0f54cd',
        23,
        'sandcastle',
        5,
        0xFFD5E6E3,
      ),
      // The DID is hashed exactly as given, never lower-cased first.
      (
        'DID:PLC:EWVI7NXZYOUN6ZHXRHS64OIZ',
        '750f5b447f0f42ee',
        9,
        'kelp-frond',
        6,
        0xFFEED6DA,
      ),
    ];

    for (final (did, prefix, pictureIndex, slug, tintIndex, tint) in vectors) {
      final digest = DefaultAvatar.digestOf(did);
      expect(hexPrefix(digest, 8), prefix, reason: 'digest prefix of $did');
      expect(digest, hasLength(32), reason: 'full SHA-256 digest of $did');

      final avatar = DefaultAvatar.forDid(did);
      expect(avatar.pictureIndex, pictureIndex, reason: 'picture of $did');
      expect(avatar.slug, slug, reason: 'slug of $did');
      expect(avatar.tintIndex, tintIndex, reason: 'tint index of $did');
      expect(avatar.tint.toARGB32(), tint, reason: 'tint colour of $did');
    }
  });

  test('the v1 pool and tint palette are the §4.1 lists in order', () {
    expect(defaultAvatarSlugs, const [
      'anchor',
      'beach-bucket-and-spade',
      'branch-of-coral',
      'clownfish',
      'compass',
      'dolphin',
      'eel',
      'hermit-crab-in-a-shell',
      'jellyfish',
      'kelp-frond',
      'life-ring',
      'lighthouse',
      'message-in-a-bottle',
      'narwhal',
      'nudibranch-sea-slug',
      'ocean-wave',
      'octopus',
      'oyster-with-a-pearl',
      'pelican',
      'penguin',
      'pufferfish',
      'puffin',
      'sand-dollar',
      'sandcastle',
      'scallop-shell',
      'sea-anemone',
      'sea-otter',
      'sea-turtle',
      'sea-urchin',
      'seahorse',
      'seal',
      'ships-wheel',
      'snorkel-mask',
      'spiral-sea-snail-shell',
      'squid',
      'starfish',
      'swordfish',
      'treasure-chest',
      'whale',
    ]);

    expect(defaultAvatarTints.map((tint) => tint.toARGB32()).toList(), const [
      0xFFF3D9C7, // Peach
      0xFFD8E8D4, // Sage
      0xFFCFE3EC, // Sky
      0xFFE6DDF0, // Lavender
      0xFFF4E7C1, // Sand
      0xFFD5E6E3, // Seafoam
      0xFFEED6DA, // Rose
      0xFFDCE0EA, // Mist
    ]);
  });

  test('the default picture URL is built on the environment apiUrl', () {
    // Host `flutter test` runs under EnvironmentConfig.test, whose apiUrl is
    // http://127.0.0.1:1.
    expect(
      DefaultAvatar.forDid('did:plc:ewvi7nxzyoun6zhxrhs64oiz').url,
      'http://127.0.0.1:1/img/default-avatars/v1/ocean-wave.webp',
    );
  });
}
