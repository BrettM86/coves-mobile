// A recording ImageEncoder for host tests: never touches a platform channel.

import 'dart:async';
import 'dart:typed_data';

import 'package:coves_flutter/utils/image_preparation.dart';

/// What an encode was asked for, without the input bytes.
typedef EncodeRequest = ({
  EncodedImageFormat format,
  int quality,
  ImageSize? targetSize,
  int inSampleSize,
});

/// Records every encode and answers with `outputs` in order: a [Uint8List]
/// is returned, an [Exception] or [Error] is thrown. Running out of outputs
/// throws a [StateError], so an unexpected encode fails the test.
class RecordingImageEncoder implements ImageEncoder {
  RecordingImageEncoder([List<Object> outputs = const []])
    : _outputs = List.of(outputs),
      supportsDecodeSampling = true;

  /// An encoder like the iOS one, which decodes at full size.
  RecordingImageEncoder.withoutDecodeSampling(List<Object> outputs)
    : _outputs = List.of(outputs),
      supportsDecodeSampling = false;

  final List<Object> _outputs;

  @override
  final bool supportsDecodeSampling;

  /// The requests made, in call order.
  final List<EncodeRequest> requests = [];

  /// The input bytes of each request, in call order.
  final List<Uint8List> inputs = [];

  /// When set, every encode is recorded at once but answers only after this
  /// completes.
  Completer<void>? gate;

  @override
  Future<Uint8List> encode(
    Uint8List bytes, {
    required EncodedImageFormat format,
    required int quality,
    ImageSize? targetSize,
    int inSampleSize = 1,
  }) async {
    requests.add((
      format: format,
      quality: quality,
      targetSize: targetSize,
      inSampleSize: inSampleSize,
    ));
    inputs.add(bytes);
    await gate?.future;
    if (_outputs.isEmpty) {
      throw StateError('unexpected encode request $format $targetSize');
    }
    final output = _outputs.removeAt(0);
    if (output is Uint8List) {
      return output;
    }
    if (output is Error) {
      throw output;
    }
    throw output as Exception;
  }
}
