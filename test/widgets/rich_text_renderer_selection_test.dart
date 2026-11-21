import 'dart:async';
import 'dart:convert';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/image_layout.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/media_surface.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:file/memory.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/mock_url_launcher_platform.dart';

int _byteLen(String s) => utf8.encode(s).length;

RichTextFacet _facetOver({
  required String fullText,
  required String span,
  required List<FacetFeature> features,
}) {
  final charStart = fullText.indexOf(span);
  if (charStart == -1) {
    throw ArgumentError('"$span" not found in "$fullText"');
  }
  final byteStart = _byteLen(fullText.substring(0, charStart));
  final byteEnd = byteStart + _byteLen(span);
  return RichTextFacet(
    index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
    features: features,
  );
}

/// Captures every `Clipboard.setData` text written during the test.
List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final args = methodCall.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// Mounts [body] under a plain Flutter SelectionArea on a 400x900 phone.
Future<void> _pumpInSelectionArea(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SelectionArea(child: SingleChildScrollView(child: body)),
      ),
    ),
  );
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
}

/// The rendered paragraph whose plain text starts with [prefix].
RenderParagraph _paragraph(WidgetTester tester, String prefix) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText &&
        widget.text
            .toPlainText(includeSemanticsLabels: false)
            .startsWith(prefix),
  );
  expect(finder, findsOneWidget, reason: 'paragraph starting "$prefix"');
  return tester.renderObject<RenderParagraph>(finder);
}

/// Global rect covering [word] inside the paragraph starting with [prefix].
Rect _wordRect(WidgetTester tester, String prefix, String word) {
  final paragraph = _paragraph(tester, prefix);
  final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final start = plain.indexOf(word);
  expect(start, isNonNegative, reason: '"$word" not in "$plain"');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + word.length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

Future<void> _longPressWord(
  WidgetTester tester,
  String prefix,
  String word,
) async {
  await tester.longPressAt(_wordRect(tester, prefix, word).center);
  await tester.pumpAndSettle();
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

Future<void> _selectAllAndCopy(
  WidgetTester tester,
  String prefix,
  String word,
) async {
  await _longPressWord(tester, prefix, word);
  await _tapToolbar(tester, 'Select all');
  await _tapToolbar(tester, 'Copy');
}

/// Global rects of the Material selection handles currently drawn with a
/// non-zero opacity.
List<Rect> _visibleHandleRects(WidgetTester tester) {
  final handles = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_TextSelectionHandlePainter',
  );
  final rects = <Rect>[];
  for (final element in handles.evaluate()) {
    var visible = true;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition && widget.opacity.value == 0) {
        visible = false;
        return false;
      }
      return true;
    });
    if (!visible) {
      continue;
    }
    final box = element.renderObject! as RenderBox;
    rects.add(
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
    );
  }
  return rects;
}

Future<List<Rect>> _pumpUntilHandlesVisible(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (_visibleHandleRects(tester).length == 2) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  final rects = _visibleHandleRects(tester);
  expect(rects, hasLength(2), reason: 'visible selection handles');
  return rects;
}

void _expectNoSelectionUi(WidgetTester tester) {
  expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
  expect(find.text('Copy'), findsNothing);
  expect(find.text('Select all'), findsNothing);
}

/// The GoRouter harness from test/widgets/rich_text_renderer_test.dart
/// (`_wrapInRouterApp`), with the home route's body under a SelectionArea.
GoRouter _routerWithSelectionArea(Widget child) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(body: SelectionArea(child: child)),
    ),
    GoRoute(
      path: '/profile/:actor',
      builder: (context, state) =>
          Scaffold(body: Text('profile:${state.pathParameters['actor']}')),
    ),
    GoRoute(
      path: '/community/:identifier',
      builder: (context, state) => Scaffold(
        body: Text('community:${state.pathParameters['identifier']}'),
      ),
    ),
  ],
);

const _structuredText =
    'Section heading\nFirst paragraph line.\n\nStill the first paragraph.\n'
    'Quoted words\nlet x = 1;\nClosing paragraph.';

final _structuredFacets = [
  _facetOver(
    fullText: _structuredText,
    span: 'Section heading',
    features: const [HeadingFacetFeature(level: 2)],
  ),
  _facetOver(
    fullText: _structuredText,
    span: 'Quoted words',
    features: const [BlockquoteFacetFeature()],
  ),
  _facetOver(
    fullText: _structuredText,
    span: 'let x = 1;',
    features: const [CodeBlockFacetFeature()],
  ),
];

/// The clipboard after Select all + Copy of [_structuredText].
const _structuredCopied =
    'Section heading\nFirst paragraph line.\n\nStill the first paragraph.\n'
    'Quoted words\nlet x = 1;\nClosing paragraph.';

/// The clipboard after Select all + Copy of the nested-quotes fixture.
const _nestedQuotesCopied =
    'Opening paragraph.\nOuter quote line\nInner quote line\n'
    'Quoted heading\nQuoted body line\nClosing paragraph.';

/// A body that is entirely one quote holding a heading and a body line.
const _quoteOnlyText = 'Quoted heading\nQuoted body line';
final _quoteOnlyFacets = [
  _facetOver(
    fullText: _quoteOnlyText,
    span: _quoteOnlyText,
    features: const [BlockquoteFacetFeature()],
  ),
  _facetOver(
    fullText: _quoteOnlyText,
    span: 'Quoted heading',
    features: const [HeadingFacetFeature(level: 3)],
  ),
];

/// [_structuredText] as one quote over the whole body: a single root block.
final _structuredWholeQuoteFacets = [
  _facetOver(
    fullText: _structuredText,
    span: _structuredText,
    features: const [BlockquoteFacetFeature()],
  ),
];

/// Lays its child out twice on every layout: first at [narrowWidth], then
/// with the incoming constraints. A new [generation] forces a relayout.
class _LayOutTwice extends SingleChildRenderObjectWidget {
  const _LayOutTwice({required this.generation, super.child});

  static const double narrowWidth = 200;

  final int generation;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayOutTwice(generation);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLayOutTwice renderObject,
  ) {
    renderObject.generation = generation;
  }
}

class _RenderLayOutTwice extends RenderProxyBox {
  _RenderLayOutTwice(this._generation);

  int _generation;
  int get generation => _generation;
  set generation(int value) {
    if (value != _generation) {
      _generation = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    child!.layout(
      constraints.copyWith(minWidth: 0, maxWidth: _LayOutTwice.narrowWidth),
    );
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;
  }
}

const _imageText = 'Intro\n\n[image]\n\nOutro';
const _imageUrl = 'https://cdn.test/placed.jpg';
const _imageBlockKey = Key('rich-text-image-0');

final _imageFacets = [
  _facetOver(
    fullText: _imageText,
    span: '[image]',
    features: const [ImageFacetFeature(index: 0)],
  ),
];

PostEmbed _placedImageEmbed({String? alt}) => ImagesPostEmbed(
  type: 'social.coves.embed.images#view',
  images: [EmbedImage(thumb: _imageUrl, fullsize: _imageUrl, alt: alt)],
  data: const {},
);

/// A valid 1x1 PNG.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Serves a real PNG for every URL from an in-memory file system, following
/// `_ControlledCacheManager` in test/widgets/user_avatar_test.dart.
class _ServingCacheManager extends Fake implements BaseCacheManager {
  final _fileSystem = MemoryFileSystem();
  var _served = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    _served++;
    final file = _fileSystem.file('/$_served.png')..writeAsBytesSync(_pngBytes);
    return Stream.value(FileInfo(file, FileSource.Online, DateTime(2100), url));
  }

  @override
  Future<void> removeFile(String key) async {}
}

Finder _inImageBlock(Finder matching) =>
    find.descendant(of: find.byKey(_imageBlockKey), matching: matching);

Finder _decodedImage() => _inImageBlock(
  find.byWidgetPredicate(
    (widget) => widget is RawImage && widget.image != null,
  ),
);

void _clearImageCache() {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  setUp(_clearImageCache);
  tearDown(_clearImageCache);

  testWidgets('Select all + Copy puts heading, paragraph, quote and code '
      'block on separate lines', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: _structuredText, facets: _structuredFacets),
    );

    await _selectAllAndCopy(tester, 'Section heading', 'heading');

    expect(copied, [_structuredCopied]);
  }, variant: android);

  testWidgets('Select all + Copy separates nested quotes and a heading '
      'inside a quote', (tester) async {
    const text =
        'Opening paragraph.\nOuter quote line\nInner quote line\n'
        'Quoted heading\nQuoted body line\nClosing paragraph.';
    final facets = [
      _facetOver(
        fullText: text,
        span: 'Outer quote line',
        features: const [BlockquoteFacetFeature()],
      ),
      _facetOver(
        fullText: text,
        span: 'Inner quote line',
        features: const [BlockquoteFacetFeature(level: 2)],
      ),
      _facetOver(
        fullText: text,
        span: 'Quoted heading\nQuoted body line',
        features: const [BlockquoteFacetFeature()],
      ),
      _facetOver(
        fullText: text,
        span: 'Quoted heading',
        features: const [HeadingFacetFeature(level: 3)],
      ),
    ];
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: text, facets: facets),
    );

    await _selectAllAndCopy(tester, 'Opening paragraph.', 'Opening');

    expect(copied, [_nestedQuotesCopied]);
  }, variant: android);

  testWidgets('Select all + Copy keeps the code block lines and leaves out '
      'its language label', (tester) async {
    const text = 'Before code.\nfirst code line\nsecond code line\nAfter code.';
    final facets = [
      _facetOver(
        fullText: text,
        span: 'first code line\nsecond code line',
        features: const [CodeBlockFacetFeature(language: 'shell')],
      ),
    ];
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: text, facets: facets),
    );

    await _selectAllAndCopy(tester, 'Before code.', 'Before');

    expect(copied, [
      'Before code.\nfirst code line\nsecond code line\nAfter code.',
    ]);
  }, variant: android);

  final imageStates =
      <
        ({
          String name,
          BaseCacheManager Function() cacheManager,
          void Function(WidgetTester tester) expectState,
        })
      >[
        (
          name: 'loading',
          cacheManager: FakeImageCacheManager.new,
          expectState: (tester) {
            expect(_inImageBlock(find.byType(MediaFill)), findsOneWidget);
            expect(_decodedImage(), findsNothing);
            expect(
              _inImageBlock(find.byIcon(Icons.broken_image)),
              findsNothing,
            );
            expect(find.text('Image removed'), findsNothing);
          },
        ),
        (
          name: 'loaded',
          cacheManager: _ServingCacheManager.new,
          expectState: (tester) {
            expect(_decodedImage(), findsOneWidget);
          },
        ),
        (
          name: '404',
          cacheManager: () => FakeImageCacheManager(
            errors: {
              _imageUrl: const HttpExceptionWithStatus(404, 'not found'),
            },
          ),
          expectState: (tester) {
            expect(_inImageBlock(find.text('Image removed')), findsOneWidget);
          },
        ),
        (
          name: 'other error',
          cacheManager: () => FakeImageCacheManager(
            errors: {_imageUrl: Exception('network down')},
          ),
          expectState: (tester) {
            expect(
              _inImageBlock(find.byIcon(Icons.broken_image)),
              findsOneWidget,
            );
          },
        ),
      ];

  for (final state in imageStates) {
    testWidgets('Select all + Copy leaves out a placed image '
        '(${state.name})', (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpInSelectionArea(
        tester,
        ImageCacheScope(
          cacheManager: state.cacheManager(),
          child: RichTextRenderer(
            text: _imageText,
            facets: _imageFacets,
            images: imageLayout(_placedImageEmbed(), _imageText, _imageFacets),
          ),
        ),
      );
      // Let the cache stream deliver and real decoding finish. Bounded: a
      // loading stream never settles.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      state.expectState(tester);

      await _selectAllAndCopy(tester, 'Intro', 'Intro');

      expect(copied, ['Intro\nOutro']);
    }, variant: android);
  }

  testWidgets('dragging the end handle from "heading" to the end of "First" '
      r'copies exactly "heading\nFirst"', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: _structuredText, facets: _structuredFacets),
    );

    await _longPressWord(tester, 'Section heading', 'heading');
    final handles = await _pumpUntilHandlesVisible(tester);
    // The end handle is the one further right; its anchor is its top-left
    // corner, on the current end selection point.
    final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);

    final first = _wordRect(tester, 'First paragraph line.', 'First');
    final target = Offset(first.right, first.bottom);
    await tester.dragFrom(endHandle.center, target - endHandle.topLeft);
    await tester.pumpAndSettle();

    await _tapToolbar(tester, 'Copy');

    expect(copied, ['heading\nFirst']);
  }, variant: android);

  testWidgets('a parent rebuild keeps Select all copying the separated '
      'text', (tester) async {
    final copied = _captureClipboard(tester);
    late StateSetter rebuildParent;
    var rebuilds = 0;
    await _pumpInSelectionArea(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuildParent = setState;
          rebuilds++;
          return RichTextRenderer(
            text: _structuredText,
            facets: _structuredFacets,
          );
        },
      ),
    );

    await _longPressWord(tester, 'Section heading', 'heading');
    await _tapToolbar(tester, 'Select all');

    final rebuildsBefore = rebuilds;
    rebuildParent(() {});
    await tester.pump();
    expect(rebuilds, rebuildsBefore + 1, reason: 'parent rebuilt');

    await _tapToolbar(tester, 'Copy');

    expect(copied, [_structuredCopied]);
  }, variant: android);

  testWidgets('Select all + Copy separates a heading and a line in a quote '
      'that is the whole body', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: _quoteOnlyText, facets: _quoteOnlyFacets),
    );

    await _selectAllAndCopy(tester, 'Quoted heading', 'heading');

    expect(copied, [_quoteOnlyText]);
  }, variant: android);

  testWidgets('a parent rebuild keeps Select all copying a whole-body quote '
      'separated', (tester) async {
    final copied = _captureClipboard(tester);
    late StateSetter rebuildParent;
    var rebuilds = 0;
    await _pumpInSelectionArea(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuildParent = setState;
          rebuilds++;
          return RichTextRenderer(
            text: _quoteOnlyText,
            facets: _quoteOnlyFacets,
          );
        },
      ),
    );

    await _longPressWord(tester, 'Quoted heading', 'heading');
    await _tapToolbar(tester, 'Select all');

    final rebuildsBefore = rebuilds;
    rebuildParent(() {});
    await tester.pump();
    expect(rebuilds, rebuildsBefore + 1, reason: 'parent rebuilt');

    await _tapToolbar(tester, 'Copy');

    expect(copied, [_quoteOnlyText]);
  }, variant: android);

  testWidgets('Select all + Copy still separates the quotes after the first '
      'of two multi-block quotes becomes single-block', (tester) async {
    const text =
        'Intro line.\nFirst heading\nFirst body\nMiddle line.\n'
        'Second heading\nSecond body\nOutro line.';
    final quoteFacets = [
      _facetOver(
        fullText: text,
        span: 'First heading\nFirst body',
        features: const [BlockquoteFacetFeature()],
      ),
      _facetOver(
        fullText: text,
        span: 'Second heading\nSecond body',
        features: const [BlockquoteFacetFeature()],
      ),
      _facetOver(
        fullText: text,
        span: 'Second heading',
        features: const [HeadingFacetFeature(level: 3)],
      ),
    ];
    final firstHeading = _facetOver(
      fullText: text,
      span: 'First heading',
      features: const [HeadingFacetFeature(level: 3)],
    );
    final copied = _captureClipboard(tester);
    late StateSetter rebuildParent;
    var facets = [...quoteFacets, firstHeading];
    await _pumpInSelectionArea(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuildParent = setState;
          return RichTextRenderer(text: text, facets: facets);
        },
      ),
    );

    rebuildParent(() => facets = quoteFacets);
    await tester.pump();
    await tester.pump();

    await _selectAllAndCopy(tester, 'Intro line.', 'Intro');

    expect(tester.takeException(), isNull);
    expect(copied, [text]);
  }, variant: android);

  testWidgets('Select all + Copy still separates the blocks after the body '
      'goes from many blocks to one and back across frames', (tester) async {
    final copied = _captureClipboard(tester);
    late StateSetter rebuildParent;
    var facets = _structuredFacets;
    await _pumpInSelectionArea(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuildParent = setState;
          return RichTextRenderer(text: _structuredText, facets: facets);
        },
      ),
    );

    rebuildParent(() => facets = _structuredWholeQuoteFacets);
    await tester.pump();
    rebuildParent(() => facets = _structuredFacets);
    await tester.pump();
    await tester.pump();

    await _selectAllAndCopy(tester, 'Section heading', 'heading');

    expect(tester.takeException(), isNull);
    expect(copied, [_structuredCopied]);
  }, variant: android);

  testWidgets('Select all + Copy still separates the blocks after the body '
      'goes from many blocks to one and back within one frame', (tester) async {
    // The renderer State is kept while a parent lays it out twice per frame:
    // first narrow (one block), then at full width (many blocks). So the
    // root container from the previous frame is deactivated and a new one
    // mounted before that frame's finalizeTree disposes the old one.
    final copied = _captureClipboard(tester);
    late StateSetter relayout;
    var generation = 0;
    await _pumpInSelectionArea(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          relayout = setState;
          return _LayOutTwice(
            generation: generation,
            child: LayoutBuilder(
              builder: (context, constraints) => RichTextRenderer(
                text: _structuredText,
                facets: constraints.maxWidth < _LayOutTwice.narrowWidth + 1
                    ? _structuredWholeQuoteFacets
                    : _structuredFacets,
              ),
            ),
          );
        },
      ),
    );

    relayout(() => generation++);
    await tester.pump();
    await tester.pump();

    await _selectAllAndCopy(tester, 'Section heading', 'heading');

    expect(tester.takeException(), isNull);
    expect(copied, [_structuredCopied]);
  }, variant: android);

  testWidgets('revealing a spoiler keeps the selection and the renderer '
      'still separates blocks after the reveal', (tester) async {
    const text = 'Section heading\nThe ending is Rosebud';
    final facets = [
      _facetOver(
        fullText: text,
        span: 'Section heading',
        features: const [HeadingFacetFeature(level: 2)],
      ),
      _facetOver(
        fullText: text,
        span: 'Rosebud',
        features: const [SpoilerFacetFeature()],
      ),
    ];
    final copied = _captureClipboard(tester);
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: text, facets: facets),
    );

    await _longPressWord(tester, 'Section heading', 'heading');

    final spoilerTaps = <TapGestureRecognizer>[];
    _paragraph(tester, 'The ending is').text.visitChildren((span) {
      if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
        spoilerTaps.add(span.recognizer! as TapGestureRecognizer);
      }
      return true;
    });
    expect(spoilerTaps, hasLength(1), reason: 'spoiler span recognizer');
    spoilerTaps.single.onTap!();
    await tester.pumpAndSettle();

    expect(
      _paragraph(
        tester,
        'The ending is',
      ).text.toPlainText(includeSemanticsLabels: false),
      'The ending is Rosebud',
      reason: 'spoiler revealed',
    );
    expect(find.text('Copy'), findsOneWidget, reason: 'toolbar after reveal');
    await _tapToolbar(tester, 'Copy');
    expect(copied, ['heading']);

    // Copy on Android clears the selection, so select again.
    await _selectAllAndCopy(tester, 'Section heading', 'heading');

    expect(copied, ['heading', 'Section heading\nThe ending is Rosebud']);
  }, variant: android);

  testWidgets('tapping a link under a SelectionArea launches it and shows '
      'no selection UI', (tester) async {
    final previousPlatform = UrlLauncherPlatform.instance;
    final launcher = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
    const text = 'Read https://example.com/guide now';
    final facets = [
      _facetOver(
        fullText: text,
        span: 'https://example.com/guide',
        features: const [LinkFacetFeature(uri: 'https://example.com/guide')],
      ),
    ];
    await _pumpInSelectionArea(
      tester,
      RichTextRenderer(text: text, facets: facets),
    );

    // Tap inside the URL's first line: at 400 wide the URL may wrap.
    await tester.tapAt(_wordRect(tester, 'Read', 'https').center);
    await tester.pumpAndSettle();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));

    expect(launcher.launchedUrls, ['https://example.com/guide']);
    _expectNoSelectionUi(tester);
  }, variant: android);

  testWidgets('tapping a mention under a SelectionArea opens the profile '
      'route', (tester) async {
    const text = 'hey @alice.test look';
    final router = _routerWithSelectionArea(
      RichTextRenderer(
        text: text,
        facets: [
          _facetOver(
            fullText: text,
            span: '@alice.test',
            features: const [MentionFacetFeature(did: 'did:plc:alice')],
          ),
        ],
      ),
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();

    await tester.tapAt(_wordRect(tester, 'hey', '@alice.test').center);
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/profile/did:plc:alice');
  }, variant: android);

  testWidgets('a placed image under a SelectionArea keeps its alt-text button '
      'semantics and opens the lightbox on tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpInSelectionArea(
      tester,
      ImageCacheScope(
        cacheManager: FakeImageCacheManager(),
        child: RichTextRenderer(
          text: _imageText,
          facets: _imageFacets,
          images: imageLayout(
            _placedImageEmbed(alt: 'A purple anemone'),
            _imageText,
            _imageFacets,
          ),
        ),
      ),
    );
    expect(_inImageBlock(find.byType(MediaFill)), findsOneWidget);
    expect(_decodedImage(), findsNothing);

    expect(
      tester.getSemantics(find.byKey(_imageBlockKey)),
      isSemantics(label: 'A purple anemone', isButton: true, isImage: true),
    );

    await tester.tap(find.byKey(_imageBlockKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ImageViewer), findsOneWidget);
    expect(
      tester.widget<ImageViewer>(find.byType(ImageViewer)).initialIndex,
      0,
    );
    semantics.dispose();
  }, variant: android);
}
