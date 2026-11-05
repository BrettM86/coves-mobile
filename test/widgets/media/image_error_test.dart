import 'dart:async';
import 'dart:io';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/image_layout.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_aspect.dart';
import 'package:coves_flutter/widgets/media/media_surface.dart';
import 'package:coves_flutter/widgets/media/native_image_embed.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/fake_image_cache_manager.dart';
import '../../test_helpers/semantics_helpers.dart';

const _thumbUrl = 'https://cdn.test/removed-thumb.jpg';
const _fullsizeUrl = 'https://cdn.test/removed-fullsize.jpg';

/// 4:3 sits inside both the feed (3:4–16:9) and detail (1:3–3:1) bounds, so
/// every surface reserves exactly 4:3 of its width.
final _image = EmbedImage(
  thumb: _thumbUrl,
  fullsize: _fullsizeUrl,
  aspectRatio: EmbedAspectRatio(width: 4, height: 3),
);

/// The test surface: 400 x 800 logical pixels.
const _surfaceSize = Size(400, 800);

/// One image widget under test.
typedef _Surface = ({
  String name,

  /// The URL this surface fetches, and so must evict on a 404.
  String url,
  Widget Function(EmbedImage image) build,

  /// The size the "Image removed" placeholder must fill.
  Size reservedSize,
});

/// A placed image covering the whole body of a full-mode renderer.
Widget _richTextWithPlacedImage(EmbedImage image) {
  const text = '[image]';
  const facets = [
    RichTextFacet(
      index: ByteSlice(byteStart: 0, byteEnd: text.length),
      features: [ImageFacetFeature(index: 0)],
    ),
  ];
  return RichTextRenderer(
    text: text,
    facets: facets,
    images: imageLayout(
      ImagesPostEmbed(
        type: 'social.coves.embed.images#view',
        images: [image],
        data: const {},
      ),
      text,
      facets,
    ),
  );
}

final List<_Surface> _surfaces = [
  (
    name: 'S1 NativeImageThumb (feed, thumb)',
    url: _thumbUrl,
    build: (image) => NativeImageThumb(images: [image], keyPrefix: 'post'),
    reservedSize: const Size(400, 300),
  ),
  (
    name: 'S1b NativeImageThumb (detail, fullsize)',
    url: _fullsizeUrl,
    build: (image) => NativeImageThumb(
      images: [image],
      keyPrefix: 'detail',
      source: MediaImageSource.fullsize,
    ),
    reservedSize: const Size(400, 300),
  ),
  (
    name: 'S2 ImageViewer page (fullsize, thumb pending)',
    url: _fullsizeUrl,
    build: (image) => ImageViewer(images: [image]),
    reservedSize: _surfaceSize,
  ),
  (
    name: 'S3 RichTextRenderer placed image (fullsize)',
    url: _fullsizeUrl,
    build: _richTextWithPlacedImage,
    reservedSize: const Size(400, 300),
  ),
  (
    name: 'S4 comment NativeImageGallery page (thumb)',
    url: _thumbUrl,
    build: (image) => NativeImageGallery(
      images: [image],
      keyPrefix: 'comment',
      onOpen: (_) {},
      bounds: kFeedRatioBounds,
      fill: kFeedMediaFill,
      source: MediaImageSource.thumb,
    ),
    // 4:3 is inside the feed bounds, so the page is 400 wide by 400 * 3 / 4.
    reservedSize: const Size(400, 300),
  ),
  (
    name: 'S5 SensitiveImagePlaceholder (thumb)',
    url: _thumbUrl,
    build: (image) => SensitiveImagePlaceholder(
      image: image,
      bounds: kFeedRatioBounds,
      onReveal: () {},
    ),
    reservedSize: const Size(400, 300),
  ),
];

bool _isSensitive(_Surface surface) => surface.name.startsWith('S5');

/// One failure a load can end in.
typedef _ErrorKind = ({
  String name,
  Object Function(String url) error,
  bool removed,
});

final List<_ErrorKind> _errorKinds = [
  (
    name: 'HTTP 404',
    error: (url) => HttpExceptionWithStatus(
      404,
      'Invalid statusCode: 404',
      uri: Uri.parse(url),
    ),
    removed: true,
  ),
  (
    name: 'HTTP 403',
    error: (url) => HttpExceptionWithStatus(
      403,
      'Invalid statusCode: 403',
      uri: Uri.parse(url),
    ),
    removed: false,
  ),
  (
    name: 'HTTP 500',
    error: (url) => HttpExceptionWithStatus(
      500,
      'Invalid statusCode: 500',
      uri: Uri.parse(url),
    ),
    removed: false,
  ),
  (
    name: 'non-HTTP StateError',
    error: (_) => StateError('image decode failed'),
    removed: false,
  ),
];

/// A cache manager whose eviction fails with [error].
class _FailingEvictionCacheManager extends FakeImageCacheManager {
  _FailingEvictionCacheManager(this.error);

  final Object error;

  @override
  Future<void> removeFile(String key) => Future<void>.error(error);
}

void _useFixedSurface(WidgetTester tester) {
  tester.view.physicalSize = _surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [child] under the app theme, with [cacheManager] scoped above the
/// MaterialApp so pushed routes load through it too.
Future<void> _pumpScoped(
  WidgetTester tester,
  FakeImageCacheManager cacheManager,
  Widget child,
) {
  return tester.pumpWidget(
    ImageCacheScope(
      cacheManager: cacheManager,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
}

/// Lets a released failure reach the error widget and its eviction.
Future<void> _settleFailure(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

final Finder _removedText = find.text('Image removed');
final Finder _removedPlaceholder = find.byKey(kImageRemovedPlaceholderKey);

Finder _concealedBackdrop() => find.descendant(
  of: find.byType(SensitiveImagePlaceholder),
  matching: find.byType(ImageFiltered),
);

void main() {
  void clearImageCache() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  setUp(clearImageCache);
  tearDown(clearImageCache);

  group('image load failure', () {
    for (final surface in _surfaces) {
      for (final kind in _errorKinds) {
        testWidgets('${surface.name}: ${kind.name}', (tester) async {
          _useFixedSurface(tester);
          final gate = Completer<void>();
          final cacheManager = FakeImageCacheManager(
            errors: {surface.url: kind.error(surface.url)},
            gate: gate,
          );

          await _pumpScoped(tester, cacheManager, surface.build(_image));
          final sizeWhileLoading = _isSensitive(surface)
              ? tester.getSize(find.byType(SensitiveImagePlaceholder))
              : null;

          gate.complete();
          await _settleFailure(tester);

          if (kind.removed) {
            expect(_removedText, findsOneWidget);
            expect(tester.getSize(_removedPlaceholder), surface.reservedSize);
            if (sizeWhileLoading != null) {
              expect(tester.getSize(_removedPlaceholder), sizeWhileLoading);
            }
            expect(find.byIcon(Icons.broken_image), findsNothing);
            expect(cacheManager.removedKeys, equals({surface.url}));
          } else {
            expect(_removedText, findsNothing);
            if (_isSensitive(surface)) {
              expect(_concealedBackdrop(), findsOneWidget);
              expect(find.text('NSFW Content'), findsOneWidget);
            } else {
              expect(find.byIcon(Icons.broken_image), findsOneWidget);
            }
            expect(cacheManager.removedKeys, equals(<String>{}));
          }
        });
      }
    }
  });

  group('SensitiveImagePlaceholder', () {
    testWidgets('a removed image is shown unblurred, readable, and has '
        'nothing to reveal', (tester) async {
      _useFixedSurface(tester);
      final semantics = tester.ensureSemantics();
      var revealed = false;
      final cacheManager = FakeImageCacheManager(
        errors: {
          _thumbUrl: HttpExceptionWithStatus(
            404,
            'Invalid statusCode: 404',
            uri: Uri.parse(_thumbUrl),
          ),
        },
      );

      await _pumpScoped(
        tester,
        cacheManager,
        SensitiveImagePlaceholder(
          image: _image,
          bounds: kFeedRatioBounds,
          onReveal: () => revealed = true,
        ),
      );
      await _settleFailure(tester);

      expect(_removedText, findsOneWidget);
      for (final removed in [_removedText, _removedPlaceholder]) {
        expect(
          find.ancestor(of: removed, matching: find.byType(ImageFiltered)),
          findsNothing,
        );
        expect(
          find.ancestor(of: removed, matching: find.byType(ExcludeSemantics)),
          findsNothing,
        );
      }
      expect(find.text('NSFW Content'), findsNothing);

      final labels = [
        for (final node in allSemanticsNodes(tester, _removedText)) node.label,
      ];
      expect(labels, anyElement(contains('Image removed')));
      expect(labels, isNot(anyElement(contains('Show sensitive content'))));
      expect(
        activatableLabels(tester, _removedText),
        isNot(contains('Show sensitive content')),
      );

      await tester.tap(_removedPlaceholder);
      await tester.pump();
      expect(revealed, isFalse);

      semantics.dispose();
    });

    testWidgets('showing a different image after a removal conceals again', (
      tester,
    ) async {
      _useFixedSurface(tester);
      final cacheManager = FakeImageCacheManager(
        errors: {
          _thumbUrl: HttpExceptionWithStatus(
            404,
            'Invalid statusCode: 404',
            uri: Uri.parse(_thumbUrl),
          ),
        },
      );
      Widget placeholderFor(EmbedImage image) => SensitiveImagePlaceholder(
        image: image,
        bounds: kFeedRatioBounds,
        onReveal: () {},
      );

      await _pumpScoped(tester, cacheManager, placeholderFor(_image));
      await _settleFailure(tester);
      expect(_removedText, findsOneWidget);

      // Same element, new image whose load is still pending.
      await _pumpScoped(
        tester,
        cacheManager,
        placeholderFor(
          EmbedImage(
            thumb: 'https://cdn.test/other-thumb.jpg',
            fullsize: 'https://cdn.test/other-fullsize.jpg',
            aspectRatio: EmbedAspectRatio(width: 4, height: 3),
          ),
        ),
      );
      await tester.pump();

      expect(_removedText, findsNothing);
      expect(_concealedBackdrop(), findsOneWidget);
      expect(find.text('NSFW Content'), findsOneWidget);
    });
  });

  group('evictRemovedImage', () {
    late void Function(FlutterErrorDetails)? originalOnError;
    late List<FlutterErrorDetails> reported;

    setUp(() {
      originalOnError = FlutterError.onError;
      reported = [];
      FlutterError.onError = reported.add;
    });
    tearDown(() => FlutterError.onError = originalOnError);

    test('an I/O exception completes without reporting', () async {
      await evictRemovedImage(
        _FailingEvictionCacheManager(
          const FileSystemException('disk unavailable'),
        ),
        'https://cdn.example/a.jpg',
      );

      expect(reported, isEmpty);
    });

    test('a programming error is reported to the framework', () async {
      final error = StateError('cache manager bug');

      await evictRemovedImage(
        _FailingEvictionCacheManager(error),
        'https://cdn.example/a.jpg',
      );

      expect(reported, hasLength(1));
      expect(reported.single.exception, same(error));
      expect(reported.single.stack, isNotNull);
    });
  });
}
