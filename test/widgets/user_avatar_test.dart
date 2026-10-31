import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// UserAvatar contract (PRD_DEFAULT_AVATARS §4.5, D12, D13).
///
/// A Coves user avatar takes the user's DID. With no usable real avatar it
/// draws the DID's default: a circle in the DID's tint with the default
/// picture on top, and the tinted circle alone while that picture is loading
/// or after it fails. An empty DID draws a plain Mist circle. Setting
/// `fallbackColor` (the Bluesky cards, D12) keeps the initial-on-colour
/// fallback and never asks for the default picture.

/// §4.2 vector: picture 15 `ocean-wave`, tint 5 Seafoam.
const _vectorDid = 'did:plc:ewvi7nxzyoun6zhxrhs64oiz';
const _seafoam = 0xFFD5E6E3;

/// Host tests run under EnvironmentConfig.test (apiUrl http://127.0.0.1:1).
const _defaultUrl = 'http://127.0.0.1:1/img/default-avatars/v1/ocean-wave.webp';

/// D13: the plain circle drawn for an empty DID.
const _mist = 0xFFDCE0EA;

/// BlueskyColors.avatarFallback.
const _blueskyFallback = 0xFF2E3D4F;

const _realUrl = 'https://cdn.example.test/avatars/ada.png';

/// A valid 1x1 PNG.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

enum _Outcome { serve, pend, fail }

/// Test-local image source for UserAvatar's `cacheManager` seam.
///
/// Per URL it serves real PNG bytes, stays pending forever, or fails. A URL
/// with no configured outcome fails. Every requested URL is recorded so a
/// test can assert that a URL was never asked for.
class _ControlledCacheManager extends Fake implements BaseCacheManager {
  _ControlledCacheManager(this.outcomes);

  final Map<String, _Outcome> outcomes;
  final List<String> requestedUrls = [];
  final List<StreamController<FileResponse>> _pending = [];
  final _fileSystem = MemoryFileSystem();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requestedUrls.add(url);
    switch (outcomes[url] ?? _Outcome.fail) {
      case _Outcome.serve:
        final file = _fileSystem.file('/${requestedUrls.length}.png')
          ..writeAsBytesSync(_pngBytes);
        return Stream.value(
          FileInfo(file, FileSource.Online, DateTime(2100), url),
        );
      case _Outcome.pend:
        final controller = StreamController<FileResponse>();
        _pending.add(controller);
        return controller.stream;
      case _Outcome.fail:
        return Stream.error(HttpExceptionWithStatus(404, 'not found: $url'));
    }
  }

  Future<void> closePending() async {
    for (final controller in _pending) {
      await controller.close();
    }
    _pending.clear();
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  void clearImageCache() {
    // CachedNetworkImageProvider equality ignores the cache manager, so a
    // decoded default picture would otherwise leak between cases.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  setUp(clearImageCache);
  tearDown(clearImageCache);

  /// Lets the controlled streams deliver and real image decoding finish.
  /// Bounded: a pending stream never settles.
  Future<void> letImagesLoad(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// Unmounts the avatar and closes pending streams so nothing leaks.
  Future<void> finish(
    WidgetTester tester,
    _ControlledCacheManager cacheManager,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await cacheManager.closePending();
  }

  Finder inAvatar(Finder matching) =>
      find.descendant(of: find.byType(UserAvatar), matching: matching);

  /// Circular decorated boxes painted by the avatar.
  Finder circles() => inAvatar(
    find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          (decoration.shape == BoxShape.circle ||
              decoration.borderRadius != null);
    }),
  );

  /// The single circle filled with [argb].
  Finder circleOf(int argb) => inAvatar(
    find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color?.toARGB32() == argb &&
          (decoration.shape == BoxShape.circle ||
              decoration.borderRadius != null);
    }),
  );

  List<int?> circleColours(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(circles())
      .map((box) => (box.decoration as BoxDecoration).color?.toARGB32())
      .toList();

  /// RawImages inside the avatar that actually hold a decoded picture.
  Finder paintedImages() => inAvatar(
    find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    ),
  );

  /// The tinted circle of [size] is painted, alone: no initial, no spinner,
  /// no error widget, no picture.
  void expectCircleAlone(WidgetTester tester, int argb, double size) {
    expect(
      circleColours(tester),
      equals([argb]),
      reason: 'the avatar circle is filled with the expected colour',
    );
    expect(tester.getSize(circleOf(argb).first), Size(size, size));
    expect(inAvatar(find.byType(Text)), findsNothing, reason: 'no initial');
    expect(
      inAvatar(find.byType(CircularProgressIndicator)),
      findsNothing,
      reason: 'no spinner',
    );
    expect(inAvatar(find.byType(Icon)), findsNothing, reason: 'no error icon');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(paintedImages(), findsNothing, reason: 'no picture yet');
  }

  /// A decoded picture fills the avatar at [size], covering the circle of
  /// [argb] and painted after (on top of) it.
  void expectPictureOverCircle(WidgetTester tester, int argb, double size) {
    expect(
      paintedImages(),
      findsOneWidget,
      reason: 'a decoded picture is painted inside the avatar',
    );
    final image = tester.widget<RawImage>(paintedImages());
    expect(image.fit, BoxFit.cover);
    expect(tester.getSize(paintedImages()), Size(size, size));

    expect(
      circleColours(tester),
      equals([argb]),
      reason: 'the tinted circle sits under the picture',
    );
    final circle = circleOf(argb).first;
    expect(tester.getRect(paintedImages()), tester.getRect(circle));

    final renderObjects = tester.allRenderObjects.toList();
    final circleIndex = renderObjects.indexOf(tester.renderObject(circle));
    final imageIndex = renderObjects.indexOf(
      tester.renderObject<RenderImage>(paintedImages()),
    );
    expect(
      circleIndex,
      lessThan(imageIndex),
      reason: 'the picture is painted on top of the circle',
    );
    expect(inAvatar(find.byType(Text)), findsNothing, reason: 'no initial');
  }

  group('UserAvatar default avatar (no real avatar)', () {
    for (final avatarUrl in const <String?>[null, '']) {
      final label = avatarUrl == null ? 'null' : 'empty';

      testWidgets(
        'avatarUrl $label: tinted circle alone while the picture is pending',
        (tester) async {
          final cacheManager = _ControlledCacheManager({
            _defaultUrl: _Outcome.pend,
          });
          await tester.pumpWidget(
            wrap(
              UserAvatar(
                name: 'ada.test',
                did: _vectorDid,
                avatarUrl: avatarUrl,
                size: 40,
                cacheManager: cacheManager,
              ),
            ),
          );
          await letImagesLoad(tester);

          expectCircleAlone(tester, _seafoam, 40);
          expect(cacheManager.requestedUrls, [_defaultUrl]);

          await finish(tester, cacheManager);
        },
      );

      testWidgets(
        'avatarUrl $label: default picture painted over the tinted circle',
        (tester) async {
          final cacheManager = _ControlledCacheManager({
            _defaultUrl: _Outcome.serve,
          });
          await tester.pumpWidget(
            wrap(
              UserAvatar(
                name: 'ada.test',
                did: _vectorDid,
                avatarUrl: avatarUrl,
                size: 40,
                cacheManager: cacheManager,
              ),
            ),
          );
          await letImagesLoad(tester);

          expectPictureOverCircle(tester, _seafoam, 40);
          expect(cacheManager.requestedUrls, [_defaultUrl]);

          await finish(tester, cacheManager);
        },
      );

      testWidgets(
        'avatarUrl $label: tinted circle alone when the picture fails',
        (tester) async {
          final cacheManager = _ControlledCacheManager({
            _defaultUrl: _Outcome.fail,
          });
          await tester.pumpWidget(
            wrap(
              UserAvatar(
                name: 'ada.test',
                did: _vectorDid,
                avatarUrl: avatarUrl,
                size: 40,
                cacheManager: cacheManager,
              ),
            ),
          );
          await letImagesLoad(tester);

          expectCircleAlone(tester, _seafoam, 40);
          expect(cacheManager.requestedUrls, contains(_defaultUrl));
          expect(tester.takeException(), isNull);

          await finish(tester, cacheManager);
        },
      );
    }
  });

  group('UserAvatar real avatar', () {
    testWidgets('a served real avatar is painted; the default is never '
        'requested', (tester) async {
      final cacheManager = _ControlledCacheManager({
        _realUrl: _Outcome.serve,
        _defaultUrl: _Outcome.serve,
      });
      await tester.pumpWidget(
        wrap(
          UserAvatar(
            name: 'ada.test',
            did: _vectorDid,
            avatarUrl: _realUrl,
            size: 40,
            cacheManager: cacheManager,
          ),
        ),
      );
      await letImagesLoad(tester);

      expect(paintedImages(), findsOneWidget);
      expect(tester.getSize(paintedImages()), const Size(40, 40));
      expect(inAvatar(find.byType(Text)), findsNothing);
      expect(cacheManager.requestedUrls, [_realUrl]);

      await finish(tester, cacheManager);
    });

    testWidgets('a failing real avatar falls back to the default picture on '
        'its tint', (tester) async {
      final cacheManager = _ControlledCacheManager({
        _realUrl: _Outcome.fail,
        _defaultUrl: _Outcome.serve,
      });
      await tester.pumpWidget(
        wrap(
          UserAvatar(
            name: 'ada.test',
            did: _vectorDid,
            avatarUrl: _realUrl,
            size: 40,
            cacheManager: cacheManager,
          ),
        ),
      );
      await letImagesLoad(tester);

      expectPictureOverCircle(tester, _seafoam, 40);
      expect(
        cacheManager.requestedUrls,
        containsAllInOrder([_realUrl, _defaultUrl]),
      );
      expect(tester.takeException(), isNull);

      await finish(tester, cacheManager);
    });
  });

  group('UserAvatar empty DID (D13)', () {
    testWidgets('draws a plain Mist circle and requests no picture', (
      tester,
    ) async {
      // (avatarUrl, outcome of avatarUrl) — no real avatar, an empty one, and
      // a real one that fails. None may hash '' into a default picture.
      const cases = <(String?, _Outcome?)>[
        (null, null),
        ('', null),
        (_realUrl, _Outcome.fail),
      ];
      for (final (avatarUrl, outcome) in cases) {
        clearImageCache();
        final cacheManager = _ControlledCacheManager({
          _realUrl: ?outcome,
          _defaultUrl: _Outcome.serve,
        });
        await tester.pumpWidget(
          wrap(
            UserAvatar(
              name: 'ada.test',
              did: '',
              avatarUrl: avatarUrl,
              size: 40,
              cacheManager: cacheManager,
            ),
          ),
        );
        await letImagesLoad(tester);

        expectCircleAlone(tester, _mist, 40);
        expect(
          cacheManager.requestedUrls.where((url) => url != _realUrl),
          isEmpty,
          reason: 'avatarUrl $avatarUrl: no default picture is requested',
        );
        if (avatarUrl == null || avatarUrl.isEmpty) {
          expect(
            cacheManager.requestedUrls,
            isEmpty,
            reason: 'avatarUrl $avatarUrl: no image request at all',
          );
        }

        await finish(tester, cacheManager);
      }
    });
  });

  group('UserAvatar fallbackColor mode (Bluesky, D12)', () {
    UserAvatar bluesky({
      String name = 'ada.test',
      String? avatarUrl,
      Color? fallbackTextColor,
      BaseCacheManager? cacheManager,
    }) => UserAvatar(
      name: name,
      did: _vectorDid,
      avatarUrl: avatarUrl,
      size: 40,
      fallbackColor: const Color(_blueskyFallback),
      fallbackTextColor: fallbackTextColor,
      cacheManager: cacheManager,
    );

    testWidgets('draws the initial on fallbackColor and never requests the '
        'default picture', (tester) async {
      final cacheManager = _ControlledCacheManager({
        _defaultUrl: _Outcome.serve,
      });
      await tester.pumpWidget(wrap(bluesky(cacheManager: cacheManager)));
      await letImagesLoad(tester);

      expect(find.text('A'), findsOneWidget);
      expect(circleColours(tester), [_blueskyFallback]);
      expect(cacheManager.requestedUrls, isNot(contains(_defaultUrl)));

      await finish(tester, cacheManager);
    });

    testWidgets('a failed real avatar draws the initial and never requests '
        'the default picture', (tester) async {
      final cacheManager = _ControlledCacheManager({
        _realUrl: _Outcome.fail,
        _defaultUrl: _Outcome.serve,
      });
      await tester.pumpWidget(
        wrap(bluesky(avatarUrl: _realUrl, cacheManager: cacheManager)),
      );
      await letImagesLoad(tester);

      expect(cacheManager.requestedUrls, contains(_realUrl));
      expect(find.text('A'), findsOneWidget);
      expect(circleColours(tester), [_blueskyFallback]);
      expect(cacheManager.requestedUrls, isNot(contains(_defaultUrl)));

      await finish(tester, cacheManager);
    });

    testWidgets('renders "?" for an empty name instead of throwing', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(bluesky(name: '')));

      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
    });

    test('fallbackTextColor without fallbackColor is rejected', () {
      // Not const: a const call would trip the assert at compile time.
      final name = 'ada.test'.toString();
      expect(
        () => UserAvatar(
          name: name,
          did: _vectorDid,
          size: 40,
          fallbackTextColor: AppColors.coral,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('fallback text is white by default and overridable', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(bluesky()));
      expect(
        tester.widget<Text>(find.text('A')).style?.color?.toARGB32(),
        Colors.white.toARGB32(),
      );

      await tester.pumpWidget(
        wrap(bluesky(fallbackTextColor: AppColors.coral)),
      );
      expect(
        tester.widget<Text>(find.text('A')).style?.color?.toARGB32(),
        AppColors.coral.toARGB32(),
      );
    });

    testWidgets('an empty avatarUrl draws the initial instead of loading', (
      tester,
    ) async {
      final cacheManager = _ControlledCacheManager({
        _defaultUrl: _Outcome.serve,
      });
      await tester.pumpWidget(
        wrap(bluesky(avatarUrl: '', cacheManager: cacheManager)),
      );
      await letImagesLoad(tester);

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('A'), findsOneWidget);
      expect(cacheManager.requestedUrls, isEmpty);

      await finish(tester, cacheManager);
    });
  });

  group('UserAvatar geometry', () {
    testWidgets('the default circle fills exactly size x size', (tester) async {
      final cacheManager = _ControlledCacheManager({
        _defaultUrl: _Outcome.pend,
      });
      await tester.pumpWidget(
        wrap(
          UserAvatar(
            name: 'ada.test',
            did: _vectorDid,
            size: 24,
            cacheManager: cacheManager,
          ),
        ),
      );

      expect(circles(), findsWidgets);
      for (final element in circles().evaluate()) {
        expect(element.size, const Size(24, 24));
      }

      await finish(tester, cacheManager);
    });

    testWidgets('is circular', (tester) async {
      const size = 24.0;
      final cacheManager = _ControlledCacheManager({
        _defaultUrl: _Outcome.pend,
      });
      await tester.pumpWidget(
        wrap(
          UserAvatar(
            name: 'ada.test',
            did: _vectorDid,
            size: size,
            cacheManager: cacheManager,
          ),
        ),
      );

      final decoration =
          tester.widget<DecoratedBox>(circles().first).decoration
              as BoxDecoration;
      final isCircle =
          decoration.shape == BoxShape.circle ||
          decoration.borderRadius == BorderRadius.circular(size / 2);
      expect(isCircle, isTrue, reason: 'user avatars are always circular');

      await finish(tester, cacheManager);
    });

    testWidgets('loads a real avatar at exactly the avatar size', (
      tester,
    ) async {
      // The comment_card bug this widget replaced was an image smaller than
      // its own fallback, which reflowed the row when loading failed.
      final cacheManager = _ControlledCacheManager({_realUrl: _Outcome.pend});
      await tester.pumpWidget(
        wrap(
          UserAvatar(
            name: 'ada.test',
            did: _vectorDid,
            size: 24,
            avatarUrl: _realUrl,
            cacheManager: cacheManager,
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedNetworkImage && widget.imageUrl == _realUrl,
        ),
      );
      expect(image.width, 24);
      expect(image.height, 24);
      expectCircleAlone(tester, _seafoam, 24);

      await finish(tester, cacheManager);
    });

    testWidgets('clips with at most one ClipOval', (tester) async {
      // ProfileHeader's geometry tests locate the avatar via a single
      // ClipOval descendant (test/widgets/profile_header_test.dart) — nesting
      // another one inside UserAvatar would break them.
      for (final avatarUrl in const <String?>[_realUrl, null]) {
        final cacheManager = _ControlledCacheManager({
          _realUrl: _Outcome.pend,
          _defaultUrl: _Outcome.pend,
        });
        await tester.pumpWidget(
          wrap(
            UserAvatar(
              name: 'ada.test',
              did: _vectorDid,
              size: 74,
              avatarUrl: avatarUrl,
              cacheManager: cacheManager,
            ),
          ),
        );

        expect(
          tester.widgetList(find.byType(ClipOval)).length,
          lessThanOrEqualTo(1),
          reason: 'avatarUrl $avatarUrl',
        );

        await finish(tester, cacheManager);
      }
    });
  });
}
