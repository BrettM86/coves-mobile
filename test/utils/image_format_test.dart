import 'dart:convert';

import 'package:coves_flutter/utils/image_format.dart';
import 'package:coves_flutter/utils/image_picker_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/image_fixtures.dart';

/// checkPostImage reads the format and dimensions from the bytes alone
/// (PRD_IMAGES_MOBILE §3.2): no file name or extension is involved.
void main() {
  const formatMessage = 'Use a JPEG, PNG, WebP or GIF image.';

  Matcher refusedWith(Object message) => throwsA(
    isA<ImageValidationException>().having(
      (error) => error.message,
      'message',
      message,
    ),
  );

  group('checkPostImage accepts a supported header', () {
    final rows = <({String name, List<int> header, PostImageCheck expected})>[
      (
        name: 'PNG IHDR',
        header: png(640, 480),
        expected: (mimeType: 'image/png', width: 640, height: 480),
      ),
      (
        name: 'GIF87a screen',
        header: gif('GIF87a', 320, 200),
        expected: (mimeType: 'image/gif', width: 320, height: 200),
      ),
      (
        name: 'GIF89a screen',
        header: gif('GIF89a', 500, 250),
        expected: (mimeType: 'image/gif', width: 500, height: 250),
      ),
      (
        name: 'WebP VP8X',
        header: webpVp8x(4000, 3000),
        expected: (mimeType: 'image/webp', width: 4000, height: 3000),
      ),
      (
        name: 'WebP VP8L',
        header: webpVp8l(1024, 768),
        expected: (mimeType: 'image/webp', width: 1024, height: 768),
      ),
      (
        name: 'WebP VP8',
        header: webpVp8(800, 600),
        expected: (mimeType: 'image/webp', width: 800, height: 600),
      ),
      (
        name: 'JPEG with APP0 before SOF0',
        header: jpeg(1920, 1080),
        expected: (mimeType: 'image/jpeg', width: 1920, height: 1080),
      ),
    ];

    for (final row in rows) {
      test(row.name, () {
        expect(checkPostImage(headerBytes(row.header)), row.expected);
      });
    }
  });

  group('checkPostImage refuses an unsupported format', () {
    final rows = <({String name, List<int> header})>[
      (name: 'HEIC', header: ftyp('heic')),
      (name: 'AVIF', header: ftyp('avif')),
      (
        name: 'text',
        header: utf8.encode('This is a plain text file, not an image.\n'),
      ),
    ];

    for (final row in rows) {
      test('${row.name} with "$formatMessage"', () {
        expect(
          () => checkPostImage(headerBytes(row.header)),
          refusedWith(formatMessage),
        );
      });
    }

    test('a truncated PNG header', () {
      expect(
        () => checkPostImage(headerBytes(png(640, 480).sublist(0, 20))),
        throwsA(isA<ImageValidationException>()),
      );
    });
  });

  group('checkPostImage byte and pixel limits', () {
    test('exactly 10,000,000 bytes is accepted', () {
      expect(checkPostImage(headerBytes(png(100, 100), padTo: 10000000)), (
        mimeType: 'image/png',
        width: 100,
        height: 100,
      ));
    });

    test('10,000,001 bytes is refused with a size message', () {
      expect(
        () => checkPostImage(headerBytes(png(100, 100), padTo: 10000001)),
        refusedWith('This image is larger than 10 MB. Choose a smaller image.'),
      );
    });

    test('exactly 50,000,000 pixels is accepted', () {
      expect(checkPostImage(headerBytes(png(10000, 5000))), (
        mimeType: 'image/png',
        width: 10000,
        height: 5000,
      ));
    });

    test('50,000,001 pixels is refused with a size message', () {
      expect(
        () => checkPostImage(headerBytes(png(50000001, 1))),
        refusedWith('This image is too large. Choose a smaller image.'),
      );
    });
  });
}
