// ImagePreparer's decision table and FlutterImageCompressEncoder's argument
// translation, with a recording fake encoder and an injected temp directory.

import 'dart:io';

import 'package:coves_flutter/models/picked_image.dart';
import 'package:coves_flutter/utils/image_format.dart';
import 'package:coves_flutter/utils/image_picker_utils.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test_helpers/fake_image_encoder.dart';
import '../test_helpers/image_fixtures.dart';

/// 12,000,000 bytes: over the 10,000,000-byte limit.
const _overBytes = 12000000;

/// One byte over the 10,000,000-byte limit.
const _justOverBytes = 10000001;

/// A second readable JPEG, distinct from [tinyJpeg4x3].
final Uint8List _otherJpeg = headerBytes(jpeg(2, 2));

final Uint8List _heic = headerBytes(ftyp('heic'), padTo: 64);

/// An expected encode request; a null `quality` is not checked.
typedef _Expected = ({
  EncodedImageFormat format,
  int? quality,
  ImageSize? targetSize,
});

const _jpeg90Uncapped = (
  format: EncodedImageFormat.jpeg,
  quality: 90,
  targetSize: null,
);

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'image_preparation',
    );
  });

  tearDown(() => temporaryDirectory.deleteSync(recursive: true));

  ImagePreparer preparerWith(RecordingImageEncoder encoder) => ImagePreparer(
    encoder: encoder,
    temporaryDirectory: () async => temporaryDirectory,
  );

  /// A picked image whose file lives outside the temp directory.
  PickedImage picked(Uint8List bytes, String mimeType, {String name = 'p'}) =>
      PickedImage(
        file: File('/picked/$name'),
        bytes: bytes,
        mimeType: mimeType,
      );

  /// Prepares [image] so a stub's synchronous throw lands in the future.
  Future<PickedImage> prepare(ImagePreparer preparer, PickedImage image) =>
      Future(() => preparer.prepare(image));

  void expectRequests(RecordingImageEncoder encoder, List<_Expected> expected) {
    expect(encoder.requests, hasLength(expected.length));
    for (var index = 0; index < expected.length; index++) {
      final actual = encoder.requests[index];
      final want = expected[index];
      expect(actual.format, want.format, reason: 'request $index format');
      expect(
        actual.targetSize,
        want.targetSize,
        reason: 'request $index targetSize',
      );
      if (want.quality case final quality?) {
        expect(actual.quality, quality, reason: 'request $index quality');
      }
    }
  }

  /// [result] is an owned file inside the temp directory holding [bytes].
  void expectOwnedOutput(PickedImage result, Uint8List bytes, String mime) {
    expect(result.mimeType, mime);
    expect(result.ownsFile, isTrue);
    expect(
      result.file.path.startsWith(
        '${temporaryDirectory.path}${Platform.pathSeparator}',
      ),
      isTrue,
      reason: '${result.file.path} inside ${temporaryDirectory.path}',
    );
    expect(listEquals(result.bytes, bytes), isTrue, reason: 'result bytes');
    expect(
      listEquals(result.file.readAsBytesSync(), bytes),
      isTrue,
      reason: 'file bytes',
    );
  }

  group('U1 within limits passes through unchanged', () {
    final rows = <({String name, Uint8List bytes, String mime})>[
      (name: 'JPEG', bytes: tinyJpeg4x3, mime: 'image/jpeg'),
      (name: 'PNG', bytes: tinyPng4x3, mime: 'image/png'),
      (name: 'WebP', bytes: headerBytes(webpVp8(4, 3)), mime: 'image/webp'),
      (name: 'GIF', bytes: animatedGif3x2, mime: 'image/gif'),
    ];
    for (final row in rows) {
      test('${row.name}: same file and bytes, not owned, no encode, nothing '
          'written', () async {
        final encoder = RecordingImageEncoder();
        final input = picked(row.bytes, row.mime);

        final result = await prepare(preparerWith(encoder), input);

        expect(result.file.path, '/picked/p');
        expect(result.bytes, same(row.bytes));
        expect(result.mimeType, row.mime);
        expect(result.ownsFile, isFalse);
        expect(encoder.requests, isEmpty);
        expect(temporaryDirectory.listSync(), isEmpty);
      });
    }
  });

  group('U2 HEIC, HEIF and AVIF convert to JPEG', () {
    final rows = <({String name, Uint8List bytes, String mime})>[
      (name: 'HEIC', bytes: _heic, mime: 'image/heic'),
      (
        name: 'HEIF',
        bytes: headerBytes(ftyp('heif'), padTo: 64),
        mime: 'image/heif',
      ),
      (
        name: 'AVIF',
        bytes: headerBytes(ftyp('avif'), padTo: 64),
        mime: 'image/avif',
      ),
    ];
    for (final row in rows) {
      test('${row.name}: one uncapped jpeg q90 encode, owned image/jpeg file '
          'in the temp directory', () async {
        final encoder = RecordingImageEncoder([tinyJpeg4x3]);

        final result = await prepare(
          preparerWith(encoder),
          picked(row.bytes, row.mime),
        );

        expectRequests(encoder, [_jpeg90Uncapped]);
        expectOwnedOutput(result, tinyJpeg4x3, 'image/jpeg');
      });
    }

    final overRows = <({String name, Uint8List converted, ImageSize target})>[
      (
        name: 'over the pixel limit (8192x6144)',
        converted: headerBytes(jpeg(8192, 6144)),
        target: (width: 4096, height: 3072),
      ),
      (
        name: 'over the byte limit (10,000,001 bytes, 8192x4096)',
        converted: headerBytes(jpeg(8192, 4096), padTo: _justOverBytes),
        target: (width: 4096, height: 2048),
      ),
    ];
    for (final row in overRows) {
      test('converted output ${row.name} is encoded again capped at '
          '${row.target.width}x${row.target.height}', () async {
        final encoder = RecordingImageEncoder([row.converted, tinyJpeg4x3]);

        final result = await prepare(
          preparerWith(encoder),
          picked(_heic, 'image/heic'),
        );

        expectRequests(encoder, [
          _jpeg90Uncapped,
          (
            format: EncodedImageFormat.jpeg,
            quality: 90,
            targetSize: row.target,
          ),
        ]);
        expect(
          listEquals(encoder.inputs[1], row.converted),
          isTrue,
          reason: 'the second encode takes the converted bytes',
        );
        expectOwnedOutput(result, tinyJpeg4x3, 'image/jpeg');
      });
    }

    test('two conversions into the same directory get distinct paths, each '
        'holding its own output', () async {
      final encoder = RecordingImageEncoder([tinyJpeg4x3, _otherJpeg]);
      final preparer = preparerWith(encoder);

      final first = await prepare(
        preparer,
        picked(_heic, 'image/heic', name: 'a'),
      );
      final second = await prepare(
        preparer,
        picked(_heic, 'image/heic', name: 'b'),
      );

      expect(first.file.path, isNot(second.file.path));
      expectOwnedOutput(first, tinyJpeg4x3, 'image/jpeg');
      expectOwnedOutput(second, _otherJpeg, 'image/jpeg');
    });
  });

  group('U3 over a limit re-encodes capped at 4096 on the long edge', () {
    const jpeg90 = EncodedImageFormat.jpeg;
    const pngFormat = EncodedImageFormat.png;
    const target4096x3072 = (width: 4096, height: 3072);
    final idat = pngChunk('IDAT', const []);
    final trns = pngChunk('tRNS', const [0, 0]);

    final rows =
        <
          ({
            String name,
            Uint8List bytes,
            String mime,
            _Expected request,
            String resultMime,
          })
        >[
          (
            name: 'JPEG of 12,000,000 bytes, 8192x4096',
            bytes: headerBytes(jpeg(8192, 4096), padTo: _overBytes),
            mime: 'image/jpeg',
            request: (
              format: jpeg90,
              quality: 90,
              targetSize: (width: 4096, height: 2048),
            ),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'JPEG 10000x6000 (60,000,000 pixels)',
            bytes: headerBytes(jpeg(10000, 6000)),
            mime: 'image/jpeg',
            request: (
              format: jpeg90,
              quality: 90,
              targetSize: (width: 4096, height: 2458),
            ),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'JPEG of 12,000,000 bytes, 10000x1000',
            bytes: headerBytes(jpeg(10000, 1000), padTo: _overBytes),
            mime: 'image/jpeg',
            request: (
              format: jpeg90,
              quality: 90,
              targetSize: (width: 4096, height: 409),
            ),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'JPEG of 12,000,000 bytes, 4000x3000 (no upscaling)',
            bytes: headerBytes(jpeg(4000, 3000), padTo: _overBytes),
            mime: 'image/jpeg',
            request: (format: jpeg90, quality: 90, targetSize: null),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'PNG colour type 6 (RGBA)',
            bytes: headerBytes(png(8192, 6144, chunks: [idat])),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 4 (grey with alpha)',
            bytes: headerBytes(png(8192, 6144, colorType: 4, chunks: [idat])),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 2 (RGB) with tRNS',
            bytes: headerBytes(
              png(8192, 6144, colorType: 2, chunks: [trns, idat]),
            ),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 3 (indexed) with tRNS',
            bytes: headerBytes(
              png(
                8192,
                6144,
                colorType: 3,
                chunks: [
                  pngChunk('PLTE', const [0, 0, 0]),
                  trns,
                  idat,
                ],
              ),
            ),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 2 with tRNS after a gAMA chunk',
            bytes: headerBytes(
              png(
                8192,
                6144,
                colorType: 2,
                chunks: [pngChunk('gAMA', be32(45455)), trns, idat],
              ),
            ),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 0 (grey) with tRNS',
            bytes: headerBytes(
              png(8192, 6144, colorType: 0, chunks: [trns, idat]),
            ),
            mime: 'image/png',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'PNG colour type 2 without tRNS',
            bytes: headerBytes(png(8192, 6144, colorType: 2, chunks: [idat])),
            mime: 'image/png',
            request: (format: jpeg90, quality: 90, targetSize: target4096x3072),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'WebP VP8X with the alpha flag',
            bytes: headerBytes(webpVp8x(8192, 6144, alpha: true)),
            mime: 'image/webp',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'WebP VP8L with the alpha bit set',
            bytes: headerBytes(webpVp8l(8192, 6144, alpha: true)),
            mime: 'image/webp',
            request: (
              format: pngFormat,
              quality: null,
              targetSize: target4096x3072,
            ),
            resultMime: 'image/png',
          ),
          (
            name: 'WebP VP8L with the alpha bit clear',
            bytes: headerBytes(webpVp8l(8192, 6144)),
            mime: 'image/webp',
            request: (format: jpeg90, quality: 90, targetSize: target4096x3072),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'WebP VP8X without the alpha flag',
            bytes: headerBytes(webpVp8x(8192, 6144)),
            mime: 'image/webp',
            request: (format: jpeg90, quality: 90, targetSize: target4096x3072),
            resultMime: 'image/jpeg',
          ),
          (
            name: 'WebP VP8 (lossy)',
            bytes: headerBytes(webpVp8(8192, 6144)),
            mime: 'image/webp',
            request: (format: jpeg90, quality: 90, targetSize: target4096x3072),
            resultMime: 'image/jpeg',
          ),
        ];

    for (final row in rows) {
      test('${row.name} → ${row.request.format.name} '
          '${switch (row.request.targetSize) {
            (:final width, :final height) => '${width}x$height',
            null => 'uncapped',
          }}, owned ${row.resultMime}', () async {
        final output = row.resultMime == 'image/png' ? tinyPng4x3 : tinyJpeg4x3;
        final encoder = RecordingImageEncoder([output]);

        final result = await prepare(
          preparerWith(encoder),
          picked(row.bytes, row.mime),
        );

        expectRequests(encoder, [row.request]);
        expect(
          listEquals(encoder.inputs.single, row.bytes),
          isTrue,
          reason: 'the encode takes the picked bytes',
        );
        expectOwnedOutput(result, output, row.resultMime);
      });
    }
  });

  group('U4 refusals leave the temp directory empty', () {
    final rows =
        <
          ({
            String name,
            Uint8List bytes,
            String mime,
            List<Object> outputs,
            bool encodes,
            String message,
          })
        >[
          (
            name: 're-encode output still over the byte limit',
            bytes: headerBytes(jpeg(8192, 4096), padTo: _overBytes),
            mime: 'image/jpeg',
            outputs: [headerBytes(jpeg(4096, 2048), padTo: _justOverBytes)],
            encodes: true,
            message: postImageTooLargeMessage,
          ),
          (
            name: 're-encode output still over the pixel limit',
            bytes: headerBytes(jpeg(10000, 6000)),
            mime: 'image/jpeg',
            outputs: [headerBytes(jpeg(8192, 6144))],
            encodes: true,
            message: postImageTooManyPixelsMessage,
          ),
          (
            name: 'GIF over the byte limit',
            bytes: headerBytes(gif('GIF89a', 100, 100), padTo: _overBytes),
            mime: 'image/gif',
            outputs: const [],
            encodes: false,
            message: postImageTooLargeMessage,
          ),
          (
            name: 'GIF over the pixel limit',
            bytes: headerBytes(gif('GIF89a', 8192, 6144)),
            mime: 'image/gif',
            outputs: const [],
            encodes: false,
            message: postImageTooManyPixelsMessage,
          ),
          (
            name: 'unknown bytes',
            bytes: Uint8List.fromList(List.filled(64, 7)),
            mime: 'application/octet-stream',
            outputs: const [],
            encodes: false,
            message: unsupportedPostImageFormatMessage,
          ),
          (
            name: 'encoder throws',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [Exception('decode failed')],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
          (
            name: 'encoder throws the plugin CompressError',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [CompressError('decode failed', code: 'decode_failed')],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
          (
            name: 'encoder throws UnsupportedError (unsupported platform)',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [UnsupportedError('not supported on this platform')],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
          (
            name: 'encoder returns empty bytes',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [Uint8List(0)],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
          (
            name: 'encoder returns bytes with no recognisable header',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [Uint8List.fromList(List.filled(64, 7))],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
          (
            name: 'encoder returns a JPEG signature with no frame header',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [
              Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
            ],
            encodes: true,
            message: unreadablePostImageMessage,
          ),
        ];

    for (final row in rows) {
      test('${row.name} → "${row.message}"', () async {
        final encoder = RecordingImageEncoder(row.outputs);

        await expectLater(
          prepare(preparerWith(encoder), picked(row.bytes, row.mime)),
          throwsA(
            isA<ImageValidationException>().having(
              (error) => error.message,
              'message',
              row.message,
            ),
          ),
        );

        if (!row.encodes) {
          expect(encoder.requests, isEmpty);
        }
        expect(temporaryDirectory.listSync(), isEmpty);
      });
    }
  });

  group('U7 storage failures are refused, leaving nothing behind', () {
    test(
      'the temp directory lookup failing → "$postImageNotSavedMessage"',
      () async {
        final encoder = RecordingImageEncoder([tinyJpeg4x3]);
        final preparer = ImagePreparer(
          encoder: encoder,
          temporaryDirectory: () async =>
              throw MissingPlatformDirectoryException('no temp directory'),
        );

        await expectLater(
          prepare(preparer, picked(_heic, 'image/heic')),
          throwsA(
            isA<ImageValidationException>().having(
              (error) => error.message,
              'message',
              postImageNotSavedMessage,
            ),
          ),
        );
      },
    );

    test(
      'the write failing (directory gone) → "$postImageNotSavedMessage"',
      () async {
        final encoder = RecordingImageEncoder([tinyJpeg4x3]);
        final missing = Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}missing',
        );
        final preparer = ImagePreparer(
          encoder: encoder,
          temporaryDirectory: () async => missing,
        );

        await expectLater(
          prepare(preparer, picked(_heic, 'image/heic')),
          throwsA(
            isA<ImageValidationException>().having(
              (error) => error.message,
              'message',
              postImageNotSavedMessage,
            ),
          ),
        );
        expect(missing.existsSync(), isFalse);
        expect(temporaryDirectory.listSync(), isEmpty);
      },
    );
  });

  group('U8 the decode is subsampled and absurd dimensions are refused', () {
    final sampleRows =
        <
          ({
            String name,
            Uint8List bytes,
            String mime,
            List<Uint8List> outputs,
            List<int> inSampleSizes,
          })
        >[
          (
            name: 'JPEG 16320x12240 (a 200 MP photo) decodes at 1/2',
            bytes: headerBytes(jpeg(16320, 12240)),
            mime: 'image/jpeg',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [2],
          ),
          (
            name: 'JPEG 8192x4096 decodes at 1/2 (long edge stays 4096)',
            bytes: headerBytes(jpeg(8192, 4096), padTo: _overBytes),
            mime: 'image/jpeg',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [2],
          ),
          (
            name: 'JPEG 8191x6200 decodes at full size',
            bytes: headerBytes(jpeg(8191, 6200)),
            mime: 'image/jpeg',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [1],
          ),
          (
            name: 'PNG 4000x20000 decodes at 1/4',
            bytes: headerBytes(png(4000, 20000)),
            mime: 'image/png',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [4],
          ),
          (
            name: 'JPEG of 12,000,000 bytes, 4000x3000 decodes at full size',
            bytes: headerBytes(jpeg(4000, 3000), padTo: _overBytes),
            mime: 'image/jpeg',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [1],
          ),
          (
            name: 'HEIC whose ispe is 16320x12240 converts at 1/2',
            bytes: headerBytes(
              heifWithExtents('heic', [
                (width: 320, height: 240),
                (width: 16320, height: 12240),
              ]),
            ),
            mime: 'image/heic',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [2],
          ),
          (
            name: 'HEIC without an ispe converts at full size',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [tinyJpeg4x3],
            inSampleSizes: [1],
          ),
          (
            name: 'converted output 8192x6144 re-encodes at 1/2',
            bytes: _heic,
            mime: 'image/heic',
            outputs: [headerBytes(jpeg(8192, 6144)), tinyJpeg4x3],
            inSampleSizes: [1, 2],
          ),
        ];

    for (final row in sampleRows) {
      test('${row.name}: inSampleSize ${row.inSampleSizes}', () async {
        final encoder = RecordingImageEncoder(row.outputs);

        await prepare(preparerWith(encoder), picked(row.bytes, row.mime));

        expect(
          encoder.requests.map((request) => request.inSampleSize).toList(),
          row.inSampleSizes,
        );
      });
    }

    final ceilingRows = <({String name, Uint8List bytes, String mime})>[
      (
        name: 'JPEG header claiming 65535x65535',
        bytes: headerBytes(jpeg(65535, 65535)),
        mime: 'image/jpeg',
      ),
      (
        name: 'PNG 20000x20001 (just over 400 MP)',
        bytes: headerBytes(png(20000, 20001)),
        mime: 'image/png',
      ),
      (
        name: 'WebP 30000x20000',
        bytes: headerBytes(webpVp8x(30000, 20000)),
        mime: 'image/webp',
      ),
      (
        name: 'AVIF whose ispe is 30000x30000',
        bytes: headerBytes(
          heifWithExtents('avif', [(width: 30000, height: 30000)]),
        ),
        mime: 'image/avif',
      ),
    ];

    for (final row in ceilingRows) {
      test('${row.name} is refused before any encode', () async {
        final encoder = RecordingImageEncoder([tinyJpeg4x3]);

        await expectLater(
          prepare(preparerWith(encoder), picked(row.bytes, row.mime)),
          throwsA(
            isA<ImageValidationException>().having(
              (error) => error.message,
              'message',
              'This image is too large. Choose a smaller image.',
            ),
          ),
        );
        expect(encoder.requests, isEmpty);
        expect(temporaryDirectory.listSync(), isEmpty);
      });
    }

    test('PNG 20000x20000 (exactly 400 MP) is encoded', () async {
      final encoder = RecordingImageEncoder([tinyJpeg4x3]);

      await prepare(
        preparerWith(encoder),
        picked(headerBytes(png(20000, 20000)), 'image/png'),
      );

      expect(encoder.requests.single.inSampleSize, 4);
    });
  });

  group('U8b without decode-time sampling the decode ceiling is 64 MP', () {
    final refusedRows = <({String name, Uint8List bytes, String mime})>[
      (
        name: 'JPEG 16320x12240 (a 200 MP photo)',
        bytes: headerBytes(jpeg(16320, 12240)),
        mime: 'image/jpeg',
      ),
      (
        name: 'PNG 8000x8001 (just over 64 MP)',
        bytes: headerBytes(png(8000, 8001)),
        mime: 'image/png',
      ),
      (
        name: 'HEIC whose ispe is 9000x8000',
        bytes: headerBytes(
          heifWithExtents('heic', [(width: 9000, height: 8000)]),
        ),
        mime: 'image/heic',
      ),
    ];

    for (final row in refusedRows) {
      test('${row.name} is refused before any encode', () async {
        final encoder = RecordingImageEncoder.withoutDecodeSampling([
          tinyJpeg4x3,
        ]);

        await expectLater(
          prepare(preparerWith(encoder), picked(row.bytes, row.mime)),
          throwsA(
            isA<ImageValidationException>().having(
              (error) => error.message,
              'message',
              'This image is too large. Choose a smaller image.',
            ),
          ),
        );
        expect(encoder.requests, isEmpty);
        expect(temporaryDirectory.listSync(), isEmpty);
      });
    }

    test('PNG 8000x8000 (exactly 64 MP) is encoded at full size', () async {
      final encoder = RecordingImageEncoder.withoutDecodeSampling([
        tinyJpeg4x3,
      ]);

      await prepare(
        preparerWith(encoder),
        picked(headerBytes(png(8000, 8000)), 'image/png'),
      );

      expect(encoder.requests.single.inSampleSize, 1);
    });

    test(
      'with decode-time sampling the same 200 MP JPEG decodes at 1/2',
      () async {
        final encoder = RecordingImageEncoder([tinyJpeg4x3]);

        await prepare(
          preparerWith(encoder),
          picked(headerBytes(jpeg(16320, 12240)), 'image/jpeg'),
        );

        expect(encoder.requests.single.inSampleSize, 2);
      },
    );
  });

  group('U6 FlutterImageCompressEncoder translates the request', () {
    final rows =
        <
          ({
            String name,
            EncodedImageFormat format,
            int quality,
            ImageSize? targetSize,
            int inSampleSize,
            int minEdge,
            CompressFormat compressFormat,
          })
        >[
          (
            name: 'jpeg q90 capped 4096x3072',
            format: EncodedImageFormat.jpeg,
            quality: 90,
            targetSize: (width: 4096, height: 3072),
            inSampleSize: 2,
            minEdge: 3072,
            compressFormat: CompressFormat.jpeg,
          ),
          (
            name: 'png q100 capped 2048x4096',
            format: EncodedImageFormat.png,
            quality: 100,
            targetSize: (width: 2048, height: 4096),
            inSampleSize: 4,
            minEdge: 2048,
            compressFormat: CompressFormat.png,
          ),
          (
            name: 'jpeg q75 uncapped',
            format: EncodedImageFormat.jpeg,
            quality: 75,
            targetSize: null,
            inSampleSize: 1,
            minEdge: 1073741824,
            compressFormat: CompressFormat.jpeg,
          ),
        ];

    for (final row in rows) {
      test('${row.name} → minWidth = minHeight = ${row.minEdge}, '
          '${row.compressFormat.name}, quality ${row.quality}, orientation '
          'applied, EXIF dropped, inSampleSize ${row.inSampleSize}, returning '
          'the plugin bytes', () async {
        final input = Uint8List.fromList(const [1, 2, 3]);
        final output = Uint8List.fromList(const [4, 5, 6]);
        final calls =
            <
              ({
                Uint8List image,
                int minWidth,
                int minHeight,
                int quality,
                bool autoCorrectionAngle,
                CompressFormat format,
                bool keepExif,
                int inSampleSize,
              })
            >[];
        Future<Uint8List> compress(
          Uint8List image, {
          required int minWidth,
          required int minHeight,
          required int quality,
          required bool autoCorrectionAngle,
          required CompressFormat format,
          required bool keepExif,
          required int inSampleSize,
        }) async {
          calls.add((
            image: image,
            minWidth: minWidth,
            minHeight: minHeight,
            quality: quality,
            autoCorrectionAngle: autoCorrectionAngle,
            format: format,
            keepExif: keepExif,
            inSampleSize: inSampleSize,
          ));
          return output;
        }

        final encoder = FlutterImageCompressEncoder(
          supportsDecodeSampling: true,
          compress: compress,
        );

        final result = await Future(
          () => encoder.encode(
            input,
            format: row.format,
            quality: row.quality,
            targetSize: row.targetSize,
            inSampleSize: row.inSampleSize,
          ),
        );

        expect(result, same(output));
        expect(calls, hasLength(1));
        final call = calls.single;
        expect(call.image, same(input));
        expect(call.minWidth, row.minEdge);
        expect(call.minHeight, row.minEdge);
        expect(call.quality, row.quality);
        expect(call.autoCorrectionAngle, isTrue);
        expect(call.format, row.compressFormat);
        expect(call.keepExif, isFalse);
        expect(call.inSampleSize, row.inSampleSize);
      });
    }
  });

  group('U9 the encoder arguments land the long edge on exactly 4096 under '
      "the plugin's float32 scaling", () {
    // flutter_image_compress_common 1.1.1, given minWidth = minHeight = m.
    // Android (BitmapCompressExt / CommonHandler): decode at 1/inSampleSize,
    // scale = max(1, min(w / m, h / m)), output (w / scale).toInt().
    // iOS (UIImage+scale.m): scale = min(1, m / shortEdge), output
    // floor(scale * edge).
    double f32(double value) => (Float32List(1)..[0] = value)[0];

    ImageSize android(ImageSize source, int sample, int m) {
      final w = f32(((source.width + sample - 1) ~/ sample).toDouble());
      final h = f32(((source.height + sample - 1) ~/ sample).toDouble());
      final minimum = f32(m.toDouble());
      final scaleW = f32(w / minimum);
      final scaleH = f32(h / minimum);
      final smaller = scaleW < scaleH ? scaleW : scaleH;
      final scale = smaller > 1 ? smaller : 1.0;
      return (width: f32(w / scale).toInt(), height: f32(h / scale).toInt());
    }

    ImageSize ios(ImageSize source, int m) {
      final w = f32(source.width.toDouble());
      final h = f32(source.height.toDouble());
      var scale = f32(m / (w < h ? w : h));
      if (scale > 1) {
        scale = 1;
      }
      return (width: f32(scale * w).floor(), height: f32(scale * h).floor());
    }

    final sizes = <ImageSize>[
      (width: 9000, height: 6000),
      (width: 6000, height: 9000),
      (width: 10000, height: 6000),
      (width: 8192, height: 4096),
      (width: 8192, height: 6144),
      (width: 7200, height: 7200),
      (width: 4500, height: 3000),
    ];

    for (final size in sizes) {
      test('${size.width}x${size.height}', () async {
        final source = headerBytes(
          jpeg(size.width, size.height),
          padTo: _overBytes,
        );
        final sampling = RecordingImageEncoder([tinyJpeg4x3]);
        await preparerWith(sampling).prepare(picked(source, 'image/jpeg'));
        final full = RecordingImageEncoder.withoutDecodeSampling([tinyJpeg4x3]);
        await preparerWith(full).prepare(picked(source, 'image/jpeg'));

        int minimumEdge(EncodeRequest request) {
          final target = request.targetSize!;
          return target.width < target.height ? target.width : target.height;
        }

        final onAndroid = android(
          size,
          sampling.requests.single.inSampleSize,
          minimumEdge(sampling.requests.single),
        );
        final onIos = ios(size, minimumEdge(full.requests.single));
        int long(ImageSize s) => s.width > s.height ? s.width : s.height;
        expect(long(onAndroid), 4096, reason: 'Android $onAndroid');
        expect(long(onIos), 4096, reason: 'iOS $onIos');
      });
    }
  });

  group('sweepStalePreparedImageFiles', () {
    final processStart = DateTime(2026, 1, 1, 12);
    final old = DateTime(2025, 12, 31, 8);

    File fileAt(String name, DateTime modified) =>
        File('${temporaryDirectory.path}/$name')
          ..writeAsBytesSync([1, 2, 3])
          ..setLastModifiedSync(modified);

    test('deletes only old files named like prepared images', () async {
      final oldJpeg = fileAt('post-image-1700000000000000-0.jpg', old);
      final oldPng = fileAt('post-image-1700000000000001-1.png', old);
      final kept = [
        fileAt('post-image-1800000000000000-2.jpg', DateTime(2026, 1, 1, 13)),
        fileAt('post-image-1800000000000001-3.png', processStart),
        fileAt('post-image-1-2.jpg.bak', old),
        fileAt('post-image-invalid.png', old),
        fileAt('xpost-image-1-2.jpg', old),
        fileAt('notes.txt', old),
      ];

      await sweepStalePreparedImageFiles(
        directory: temporaryDirectory,
        processStart: processStart,
      );

      expect(oldJpeg.existsSync(), isFalse, reason: 'old jpg');
      expect(oldPng.existsSync(), isFalse, reason: 'old png');
      for (final file in kept) {
        expect(file.existsSync(), isTrue, reason: file.uri.pathSegments.last);
      }
    });

    test('a file that cannot be deleted does not stop the sweep', () async {
      final protected = fileAt('post-image-1700000000000000-0.jpg', old);
      final deletable = [
        fileAt('post-image-1700000000000001-1.jpg', old),
        fileAt('post-image-1700000000000002-2.png', old),
      ];
      // The listing order is fixed so the failing delete comes first and
      // the sweep has to carry on past it to reach the other files.
      final directory = _FixedListingDirectory([
        _UndeletableFile(protected),
        ...deletable,
      ]);

      await sweepStalePreparedImageFiles(
        directory: directory,
        processStart: processStart,
      );

      expect(protected.existsSync(), isTrue, reason: 'protected');
      for (final file in deletable) {
        expect(file.existsSync(), isFalse, reason: file.uri.pathSegments.last);
      }
    });
  });
}

/// A directory whose listing is the given entities, in the given order.
class _FixedListingDirectory implements Directory {
  _FixedListingDirectory(this._entities);

  final List<FileSystemEntity> _entities;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.fromIterable(_entities);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real file whose delete always fails.
class _UndeletableFile implements File {
  _UndeletableFile(this._file);

  final File _file;

  @override
  Uri get uri => _file.uri;

  @override
  String get path => _file.path;

  @override
  DateTime lastModifiedSync() => _file.lastModifiedSync();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async =>
      throw FileSystemException('Operation not permitted', _file.path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
