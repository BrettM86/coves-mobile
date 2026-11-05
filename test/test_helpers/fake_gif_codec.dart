import 'dart:async';
import 'dart:ui' as ui;

import 'package:coves_flutter/widgets/media/gif_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The key of the in-place animated GIF frame.
const gifFrameKey = kGifFrameKey;

/// Three distinguishable frames with literal, unequal durations.
///
/// Frame i is `10 + i` pixels wide, so a test reads which frame is on
/// screen from the shown image's width. Build once with [create] in
/// setUpAll (it needs real async) and [dispose] in tearDownAll.
class FakeGifFrames {
  FakeGifFrames._(this.images);

  static const durations = [
    Duration(milliseconds: 100),
    Duration(milliseconds: 300),
    Duration(milliseconds: 200),
  ];

  /// The width of frame i.
  static int widthOf(int frame) => 10 + frame;

  final List<ui.Image> images;

  static Future<FakeGifFrames> create() async => FakeGifFrames._([
    for (var i = 0; i < durations.length; i++)
      await createTestImage(width: widthOf(i), height: 6, cache: false),
  ]);

  void dispose() {
    for (final image in images) {
      image.dispose();
    }
  }
}

/// A frame whose image is its own handle (a clone), so the recipient may
/// dispose it.
class FakeFrameInfo implements ui.FrameInfo {
  FakeFrameInfo(this.duration, this.image);

  @override
  final Duration duration;

  @override
  final ui.Image image;
}

/// A codec over the first [frameCount] of [FakeGifFrames] (all three by
/// default) that reports [repetitionCount] (-1 loops forever, 0 plays once)
/// and keeps yielding frames in order, wrapping, for as long as it is asked.
///
/// When [controlled], every getNextFrame call stays pending until the test
/// completes its entry in [pendingFrames]. The request numbered
/// [failOnRequest] (0-based) fails instead.
class FakeGifCodec implements ui.Codec {
  FakeGifCodec(
    this.frames, {
    this.controlled = false,
    this.failOnRequest,
    this.repetitionCount = -1,
    int? frameCount,
  }) : frameCount = frameCount ?? FakeGifFrames.durations.length;

  final FakeGifFrames frames;
  final bool controlled;
  final int? failOnRequest;

  @override
  final int repetitionCount;

  int requestCount = 0;
  bool disposed = false;
  final List<Completer<ui.FrameInfo>> pendingFrames = [];

  @override
  final int frameCount;

  /// The frame request [n] (0-based) yields.
  ui.FrameInfo frameFor(int n) {
    final index = n % frameCount;
    return FakeFrameInfo(
      FakeGifFrames.durations[index],
      frames.images[index].clone(),
    );
  }

  @override
  Future<ui.FrameInfo> getNextFrame() {
    final n = requestCount++;
    if (n == failOnRequest) {
      return Future<ui.FrameInfo>.error(Exception('GIF frame decode failed'));
    }
    if (!controlled) {
      return Future<ui.FrameInfo>.value(frameFor(n));
    }
    final completer = Completer<ui.FrameInfo>();
    pendingFrames.add(completer);
    return completer.future;
  }

  /// Completes every pending request with its frame.
  void completePending() {
    final pending = List.of(pendingFrames);
    pendingFrames.clear();
    final first = requestCount - pending.length;
    for (var i = 0; i < pending.length; i++) {
      pending[i].complete(frameFor(first + i));
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// A GifCodecLoader that records every requested url.
///
/// Resolves immediately with [codec], fails with [error], or, when
/// [controlled], stays pending until the test completes [pending].
class FakeGifCodecLoader {
  FakeGifCodecLoader({this.codec, this.error, this.controlled = false});

  final ui.Codec? codec;
  final Object? error;
  final bool controlled;

  final List<String> requests = [];
  Completer<ui.Codec>? pending;

  Future<ui.Codec> load(String url) {
    requests.add(url);
    if (controlled) {
      return (pending = Completer<ui.Codec>()).future;
    }
    final error = this.error;
    if (error != null) {
      return Future<ui.Codec>.error(error);
    }
    return Future<ui.Codec>.value(codec);
  }
}

/// The width of the shown GIF frame, or null when no frame is shown.
int? shownGifFrameWidth(WidgetTester tester) {
  final finder = find.byKey(gifFrameKey);
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<RawImage>(finder).image?.width;
}
