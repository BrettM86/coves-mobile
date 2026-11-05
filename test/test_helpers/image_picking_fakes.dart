// Image-picking fakes shared by the composer widget tests: a fake picker
// platform, a scripted uploadImage, and a pump loop for real file IO.

import 'dart:async';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/upload_image_response.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mockito/mockito.dart';

import 'pump_helpers.dart';
import 'test_mocks.dart';

/// Image picker platform that hands back the files a test queued and records
/// the options of every pick.
class FakePostImagePicker extends ImagePickerPlatform {
  List<XFile> nextMulti = const [];
  XFile? nextSingle;

  /// When set, the next multi-image pick waits for this and returns its
  /// files instead of [nextMulti].
  Completer<List<XFile>>? multiGate;
  final List<MultiImagePickerOptions> multiPicks = [];
  final List<({ImageSource source, ImagePickerOptions options})> singlePicks =
      [];

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiPicks.add(options);
    final gate = multiGate;
    if (gate != null) {
      multiGate = null;
      return gate.future;
    }
    return nextMulti;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    singlePicks.add((source: source, options: options));
    return nextSingle;
  }
}

/// The stubbed uploadImage: images are told apart by their bytes and named
/// by tag; each upload succeeds with `{'ref': {'$link': 'bafkrei-<tag>'}}`
/// unless the test fails it once or holds it behind a gate.
class UploadScript {
  UploadScript(MockCovesApiService api, this.imagesByTag) {
    when(
      api.uploadImage(
        any,
        any,
        cancelToken: anyNamed('cancelToken'),
        onSendProgress: anyNamed('onSendProgress'),
      ),
    ).thenAnswer(
      (invocation) => _answer(invocation.positionalArguments[0] as Uint8List),
    );
  }

  final Map<String, Uint8List> imagesByTag;

  /// Tags of the uploads made, in call order.
  final List<String> calls = [];

  /// Tags whose next upload fails.
  final Set<String> failOnce = {};

  /// Tags whose next upload throws the given exception.
  final Map<String, Exception> failOnceWith = {};

  /// Tags whose uploads wait for the gate to complete.
  final Map<String, Completer<void>> gates = {};

  Future<UploadImageResponse> _answer(Uint8List bytes) async {
    final tag = imagesByTag.entries
        .firstWhere((entry) => listEquals(entry.value, bytes))
        .key;
    calls.add(tag);
    final failure = failOnceWith.remove(tag);
    if (failure != null) {
      throw failure;
    }
    if (failOnce.remove(tag)) {
      throw ApiException(
        'Upload rate limited',
        statusCode: 429,
        errorCode: 'UploadRateLimited',
      );
    }
    await gates[tag]?.future;
    return UploadImageResponse(
      blob: {
        'ref': {r'$link': 'bafkrei-$tag'},
      },
      mimeType: 'image/png',
      size: bytes.length,
      aspectRatio: EmbedAspectRatio(width: 4, height: 3),
    );
  }
}

/// Lets real file IO started inside the fake-async test zone finish, then
/// runs the frames that follow.
///
/// Each open, write, read or close completes in the real event loop and
/// resumes the test zone only on a pump, so this alternates short real-time
/// windows with pumps. With [until] it repeats them until [until] holds and
/// fails after 50; without, it runs a fixed 20, for checks that something
/// did not happen.
Future<void> settleRealIo(WidgetTester tester, {bool Function()? until}) async {
  Future<void> window() async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  if (until == null) {
    for (var i = 0; i < 20; i++) {
      await window();
    }
  } else {
    var settled = until();
    for (var i = 0; !settled && i < 50; i++) {
      await window();
      settled = until();
    }
    if (!settled) {
      fail('real file IO did not reach the awaited state in 50 windows');
    }
  }
  await pumpFrames(tester);
}
