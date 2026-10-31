import 'package:flutter/painting.dart';

/// v1 default-avatar picture pool, in assignment order.
///
/// Source of truth: PRD_DEFAULT_AVATARS §4.1 and the AppView's embedded
/// `/img/default-avatars/v1/` files in the coves backend. Frozen (D5):
/// changing or reordering it moves most users to a different picture.
const List<String> defaultAvatarSlugs = <String>[
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
];

/// v1 default-avatar tint palette, in assignment order (PRD_DEFAULT_AVATARS
/// §4.1, approved in D10). Used in both light and dark themes.
const List<Color> defaultAvatarTints = <Color>[
  Color(0xFFF3D9C7), // Peach
  Color(0xFFD8E8D4), // Sage
  Color(0xFFCFE3EC), // Sky
  Color(0xFFE6DDF0), // Lavender
  Color(0xFFF4E7C1), // Sand
  Color(0xFFD5E6E3), // Seafoam
  Color(0xFFEED6DA), // Rose
  Color(0xFFDCE0EA), // Mist
];

/// Plain circle colour for an empty DID (PRD_DEFAULT_AVATARS D13, Mist).
const Color defaultAvatarEmptyDidColor = Color(0xFFDCE0EA);
