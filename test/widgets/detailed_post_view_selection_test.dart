import 'dart:convert';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/media/native_image_embed.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_image_cache_manager.dart';

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
  await _settle(tester);
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await _settle(tester);
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

/// Bounded stand-in for pumpAndSettle: media in these fixtures may stay
/// loading forever, so a settle is never awaited unbounded.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

// 2025-01-01T00:00Z; the month and day are the defaults.
final _createdAt = DateTime.utc(2025);
final _currentTime = DateTime.utc(2025, 1, 1, 3);

const _handle = 'field.author.test';

FeedViewPost _post({
  required String title,
  required String text,
  List<RichTextFacet>? facets,
  PostEmbed? embed,
  bool sensitive = false,
  String uri = 'at://did:plc:author/social.coves.community.post/sel',
}) => FeedViewPost(
  post: PostView(
    uri: uri,
    cid: 'cid-sel',
    rkey: uri.split('/').last,
    author: AuthorView(did: 'did:plc:author', handle: _handle),
    community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
    createdAt: _createdAt,
    indexedAt: _createdAt,
    record: PostRecord(
      title: title,
      content: text,
      facets: facets,
      labels: sensitive ? const ['nsfw'] : const [],
    ),
    stats: PostStats(upvotes: 7, downvotes: 0, score: 7, commentCount: 0),
    embed: embed,
  ),
);

/// Mounts [post] in a DetailedPostView on a 400x900 phone, with no
/// SelectionArea of the test's own: the view must supply the region.
Future<void> _pumpDetail(
  WidgetTester tester,
  FeedViewPost post, {
  FakeImageCacheManager? cacheManager,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    Provider<StreamableService>.value(
      value: StreamableService(),
      child: ImageCacheScope(
        cacheManager: cacheManager ?? FakeImageCacheManager(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailedPostView(post: post, currentTime: _currentTime),
            ),
          ),
        ),
      ),
    ),
  );
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
}

// Rich fixture R.
const _richTitle = 'Tide pool field notes';
const _richText =
    'Low tide survey\nWe counted anemones today.\n\nMost were near the rocks.\n'
    'Bring boots next time.\nsurvey --count 42\n\n[image]\n\n'
    'Thanks for reading.';
const _removedUrl = 'https://cdn.test/removed.jpg';

final _richFacets = [
  _facetOver(
    fullText: _richText,
    span: 'Low tide survey',
    features: const [HeadingFacetFeature(level: 2)],
  ),
  _facetOver(
    fullText: _richText,
    span: 'Bring boots next time.',
    features: const [BlockquoteFacetFeature()],
  ),
  _facetOver(
    fullText: _richText,
    span: 'survey --count 42',
    features: const [CodeBlockFacetFeature(language: 'shell')],
  ),
  _facetOver(
    fullText: _richText,
    span: '[image]',
    features: const [ImageFacetFeature(index: 0)],
  ),
];

FeedViewPost _richPost() => _post(
  title: _richTitle,
  text: _richText,
  facets: _richFacets,
  embed: ImagesPostEmbed(
    type: 'social.coves.embed.images#view',
    images: const [EmbedImage(thumb: _removedUrl, fullsize: _removedUrl)],
    data: const {},
  ),
);

/// Pumps R with its placed image failing as removed, and waits until the
/// "Image removed" placeholder shows.
Future<void> _pumpRich(WidgetTester tester) async {
  await _pumpDetail(
    tester,
    _richPost(),
    cacheManager: FakeImageCacheManager(
      errors: {_removedUrl: const HttpExceptionWithStatus(404, 'not found')},
    ),
  );
  for (var i = 0; i < 20; i++) {
    if (find.text('Image removed').evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.text('Image removed'), findsOneWidget);
}

/// Fixture 5(a): a self-labelled sensitive post with an external embed
/// carrying a three-image carousel and one source.
FeedViewPost _sensitiveCarouselPost() => _post(
  title: 'Harbour cleanup photos',
  text: 'We filled six bags.',
  sensitive: true,
  embed: PostEmbed.fromJson({
    r'$type': 'social.coves.embed.external#view',
    'external': {
      'uri': 'https://example.org/cleanup',
      'thumb': 'https://cdn.test/c1.jpg',
      'images': const [
        {'thumb': 'https://cdn.test/c1.jpg'},
        {'thumb': 'https://cdn.test/c2.jpg'},
        {'thumb': 'https://cdn.test/c3.jpg'},
      ],
      'sources': const [
        {
          'uri': 'https://sources.example.net/alpha',
          'title': 'Source alpha',
          'domain': 'sources.example.net',
        },
      ],
    },
  }),
);

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('long-pressing the title word "field" and tapping Copy '
      'copies exactly "field"', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpRich(tester);

    await _longPressWord(tester, _richTitle, 'field');
    await _tapToolbar(tester, 'Copy');

    expect(copied, ['field']);
  }, variant: android);

  testWidgets('Select all + Copy copies the title and every body block, '
      'without the removed image or the code language', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpRich(tester);

    await _selectAllAndCopy(tester, 'We counted', 'anemones');

    const expected =
        'Tide pool field notes\nLow tide survey\nWe counted anemones today.\n\n'
        'Most were near the rocks.\nBring boots next time.\n'
        'survey --count 42\nThanks for reading.';
    expect(copied, [expected]);
    expect(copied.single, isNot(contains('Image removed')));
    expect(copied.single, isNot(contains('shell')));
  }, variant: android);

  testWidgets('dragging the end handle from "anemones" to the end of "Bring" '
      'copies across the paragraph and the quote', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpRich(tester);

    final bring = _wordRect(tester, 'Bring boots', 'Bring');
    await _longPressWord(tester, 'We counted', 'anemones');
    final handles = await _pumpUntilHandlesVisible(tester);
    // The end handle is the one further right; its anchor is its top-left
    // corner, on the current end selection point.
    final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);

    final target = Offset(bring.right, bring.bottom);
    await tester.dragFrom(endHandle.center, target - endHandle.topLeft);
    await _settle(tester);

    await _tapToolbar(tester, 'Copy');

    expect(copied, ['anemones today.\n\nMost were near the rocks.\nBring']);
  }, variant: android);

  testWidgets('Select all + Copy of a plain post copies the title, a newline '
      'and the body', (tester) async {
    final copied = _captureClipboard(tester);
    await _pumpDetail(
      tester,
      _post(title: 'Plain title here', text: 'Just a plain body.'),
    );

    await _selectAllAndCopy(tester, 'Just a plain body.', 'plain');

    expect(copied, ['Plain title here\nJust a plain body.']);
  }, variant: android);

  testWidgets('flinging the revealed carousel left moves the counter to 2/3 '
      'and starts no selection', (tester) async {
    await _pumpDetail(tester, _sensitiveCarouselPost());

    await tester.tap(find.byKey(const Key('sensitive-content-banner')));
    await _settle(tester);
    expect(find.text('Harbour cleanup photos'), findsOneWidget);
    expect(find.text('@$_handle'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await _settle(tester);

    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('1/3'), findsNothing);
    _expectNoSelectionUi(tester);
  }, variant: android);

  testWidgets('long-pressing the revealed carousel or the sensitive banner '
      'starts no selection', (tester) async {
    await _pumpDetail(tester, _sensitiveCarouselPost());
    await tester.tap(find.byKey(const Key('sensitive-content-banner')));
    await _settle(tester);
    expect(find.byType(PageView), findsOneWidget);

    await tester.longPressAt(tester.getCenter(find.byType(PageView)));
    await _settle(tester);
    _expectNoSelectionUi(tester);

    await tester.longPressAt(
      tester.getCenter(find.byKey(const Key('sensitive-content-banner'))),
    );
    await _settle(tester);
    _expectNoSelectionUi(tester);
    expect(find.text('We filled six bags.'), findsOneWidget);
  }, variant: android);

  testWidgets('long-pressing the revealed sensitive banner\'s side padding '
      'starts no selection', (tester) async {
    await _pumpDetail(tester, _sensitiveCarouselPost());
    final banner = find.byKey(const Key('sensitive-content-banner'));
    await tester.tap(banner);
    await _settle(tester);

    final bannerRect = tester.getRect(find.byType(SensitiveContentBanner));
    final paddedRect = tester.getRect(
      find
          .ancestor(
            of: find.byType(SensitiveContentBanner),
            matching: find.byType(Padding),
          )
          .first,
    );
    final point = Offset(bannerRect.left - 4, bannerRect.center.dy);
    expect(bannerRect.contains(point), isFalse);
    expect(paddedRect.contains(point), isTrue);

    await tester.longPressAt(point);
    await _settle(tester);
    _expectNoSelectionUi(tester);
  }, variant: android);

  testWidgets('long-pressing the media section padding beside a single '
      'image starts no selection', (tester) async {
    await _pumpDetail(
      tester,
      _post(
        title: 'Single image post',
        text: 'Single image body.',
        embed: PostEmbed.fromJson({
          r'$type': 'social.coves.embed.images#view',
          'images': [
            {
              'thumb': 'https://cdn.test/s1-thumb.jpg',
              'fullsize': 'https://cdn.test/s1.jpg',
            },
          ],
        }),
      ),
    );
    final image = find.byKey(const Key('detail-images-embed'));
    expect(image, findsOneWidget);
    final imageRect = tester.getRect(image);
    final sectionRect = tester.getRect(
      find
          .ancestor(
            of: find.byType(NativeImageThumb),
            matching: find.byType(Padding),
          )
          .first,
    );
    final point = Offset(imageRect.left - 4, imageRect.center.dy);
    expect(imageRect.contains(point), isFalse);
    expect(sectionRect.contains(point), isTrue);

    await tester.longPressAt(point);
    await _settle(tester);
    _expectNoSelectionUi(tester);
  }, variant: android);

  testWidgets('long-pressing an image placed in the body starts no '
      'selection', (tester) async {
    await _pumpRich(tester);

    await tester.longPressAt(
      tester.getCenter(find.byKey(const Key('rich-text-image-0'))),
    );
    await _settle(tester);
    _expectNoSelectionUi(tester);
  }, variant: android);

  testWidgets('tapping the second native gallery image opens one viewer at '
      'index 1', (tester) async {
    await _pumpDetail(
      tester,
      _post(
        title: 'Gallery post',
        text: 'Gallery body.',
        embed: PostEmbed.fromJson({
          r'$type': 'social.coves.embed.images#view',
          'images': [
            {
              'thumb': 'https://cdn.test/g1-thumb.jpg',
              'fullsize': 'https://cdn.test/g1.jpg',
            },
            {
              'thumb': 'https://cdn.test/g2-thumb.jpg',
              'fullsize': 'https://cdn.test/g2.jpg',
            },
          ],
        }),
      ),
    );
    final gallery = find.descendant(
      of: find.byKey(const Key('detail-images-embed')),
      matching: find.byType(PageView),
    );
    expect(gallery, findsOneWidget);

    await tester.drag(gallery, const Offset(-400, 0));
    await _settle(tester);
    await tester.tap(gallery);
    await _settle(tester);

    expect(find.byType(ImageViewer), findsOneWidget);
    expect(
      tester.widget<ImageViewer>(find.byType(ImageViewer)).initialIndex,
      1,
    );
  }, variant: android);

  testWidgets('the title keeps its own semantics node and the author handle '
      'keeps its tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpRich(tester);

    expect(find.bySemanticsLabel(_richTitle), findsOneWidget);

    final handleNode = tester.getSemantics(find.text('@$_handle'));
    expect(handleNode.label, contains('@$_handle'));
    expect(
      handleNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the author row still opens the profile',
    );

    semantics.dispose();
  }, variant: android);
}
