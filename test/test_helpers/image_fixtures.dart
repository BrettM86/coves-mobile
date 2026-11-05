// Image bytes for post-image tests: header builders that the format check
// reads (no pixel data), and tiny complete images that really decode.

import 'dart:convert';
import 'dart:typed_data';

List<int> be32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];
List<int> be16(int value) => [(value >> 8) & 0xff, value & 0xff];
List<int> le16(int value) => [value & 0xff, (value >> 8) & 0xff];
List<int> le24(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
];
List<int> le32(int value) => [...le24(value), (value >> 24) & 0xff];

/// PNG signature plus an IHDR chunk (CRC not checked by a header read),
/// with colour type [colorType] (6 is RGBA) and [chunks] after IHDR.
List<int> png(
  int width,
  int height, {
  int colorType = 6,
  List<List<int>> chunks = const [],
}) => [
  137, 80, 78, 71, 13, 10, 26, 10, //
  ...be32(13), ...ascii.encode('IHDR'),
  ...be32(width), ...be32(height),
  8, colorType, 0, 0, 0, // bit depth, colour type, compression, filter,
  // interlace
  0, 0, 0, 0, // CRC
  for (final chunk in chunks) ...chunk,
];

/// A PNG chunk of [type] holding [data], with a zero CRC.
List<int> pngChunk(String type, List<int> data) => [
  ...be32(data.length),
  ...ascii.encode(type),
  ...data,
  0, 0, 0, 0, // CRC
];

List<int> gif(String version, int width, int height) => [
  ...ascii.encode(version),
  ...le16(width),
  ...le16(height),
  0, 0, 0, // packed fields, background, aspect
];

List<int> riffWebp(String chunk, List<int> payload) => [
  ...ascii.encode('RIFF'),
  ...le32(4 + 8 + payload.length),
  ...ascii.encode('WEBP'),
  ...ascii.encode(chunk),
  ...le32(payload.length),
  ...payload,
];

/// Extended WebP: canvas width-1 and height-1 as 24-bit fields; [alpha]
/// sets the alpha flag.
List<int> webpVp8x(int width, int height, {bool alpha = false}) =>
    riffWebp('VP8X', [
      if (alpha) 0x10 else 0, 0, 0, 0, // flags, reserved
      ...le24(width - 1),
      ...le24(height - 1),
    ]);

/// Lossless WebP: signature 0x2f, then 14-bit width-1 and height-1 and the
/// alpha_is_used bit, set by [alpha].
List<int> webpVp8l(int width, int height, {bool alpha = false}) =>
    riffWebp('VP8L', [
      0x2f,
      ...le32(
        ((width - 1) & 0x3fff) |
            (((height - 1) & 0x3fff) << 14) |
            (alpha ? 1 << 28 : 0),
      ),
    ]);

/// Lossy WebP: key-frame tag, start code, 14-bit width and height.
List<int> webpVp8(int width, int height) => riffWebp('VP8 ', [
  0x10, 0x00, 0x00, // key frame, shown
  0x9d, 0x01, 0x2a, // start code
  ...le16(width),
  ...le16(height),
]);

/// JPEG with an APP0 (JFIF) segment before the SOF0 frame header.
List<int> jpeg(int width, int height) => [
  0xff, 0xd8, // SOI
  0xff, 0xe0, ...be16(16), ...ascii.encode('JFIF'), 0, 1, 1, 0, //
  ...be16(1), ...be16(1), 0, 0, // density, no thumbnail
  0xff, 0xc0, ...be16(17), 8, // SOF0, length, precision
  ...be16(height), ...be16(width),
  3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1, // three components
];

/// ISO-BMFF ftyp box with [brand] as the major brand.
List<int> ftyp(String brand) => [
  ...be32(24),
  ...ascii.encode('ftyp'),
  ...ascii.encode(brand),
  ...be32(0),
  ...ascii.encode('mif1'),
  ...ascii.encode(brand),
];

/// ISO-BMFF box of [type] holding [payload].
List<int> isoBox(String type, List<int> payload) => [
  ...be32(8 + payload.length),
  ...ascii.encode(type),
  ...payload,
];

/// An ftyp box with [brand], then a meta box whose item property container
/// holds one ispe (image spatial extents) property per entry of [extents].
List<int> heifWithExtents(
  String brand,
  List<({int width, int height})> extents,
) => [
  ...ftyp(brand),
  ...isoBox('meta', [
    ...be32(0),
    ...isoBox('hdlr', [...be32(0), ...be32(0), ...ascii.encode('pict')]),
    ...isoBox('iprp', [
      ...isoBox('ipco', [
        for (final extent in extents)
          ...isoBox('ispe', [
            ...be32(0),
            ...be32(extent.width),
            ...be32(extent.height),
          ]),
      ]),
    ]),
  ]),
];

/// [header] as bytes, zero-padded to [padTo].
Uint8List headerBytes(List<int> header, {int padTo = 0}) {
  return Uint8List(padTo > header.length ? padTo : header.length)
    ..setAll(0, header);
}

/// A complete 1x1 PNG.
final Uint8List tinyPng1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUiqkS56n6+AAAACklEQV'
  'QI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg==',
);

/// A complete 4x3 PNG.
final Uint8List tinyPng4x3 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAADAQMAAACOOjyFAAAAA1BMVEXMM2ZvdfOjAAAAC0lEQV'
  'QI12NgAAEAAAYAAWb0yWwAAAAASUVORK5CYII=',
);

/// A complete 4x3 baseline JPEG.
final Uint8List tinyJpeg4x3 = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGB'
  'cUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgo'
  'KCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAADAA'
  'QDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA'
  '/8QAFQEBAQAAAAAAAAAAAAAAAAAABgf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAx'
  'EAPwCXAUUYf//Z',
);

/// A complete two-frame, looping 3x2 GIF89a.
final Uint8List animatedGif3x2 = base64Decode(
  'R0lGODlhAwACAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAFAAAACwAAAAAAwACAA'
  'ACAoRfACH5BAAUAAAALAAAAAADAAIAgAAA/wAAAAIChF8AOw==',
);
