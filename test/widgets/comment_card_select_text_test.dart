// The comment "⋯" menu's `Select text` item and the bottom sheet it opens,
// which shows only the comment's body, selectable.
import 'dart:convert';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:coves_flutter/widgets/separated_selection_area.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _parentPostUri =
    'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
const _authorDid = 'did:plc:sheetauthor';
const _viewerDid = 'did:plc:viewer999';

const _shortBody =
    'Earlier point here\nI agree with this.\n\nThe ending is Rosebud';

const _longBody =
    'Line 1.\nLine 2.\nLine 3.\nLine 4.\nLine 5.\nLine 6.\nLine 7.\n'
    'Line 8.\nLine 9.\nLine 10.\nLine 11.\nLine 12.\nLine 13.\nLine 14.\n'
    'Line 15.\nLine 16.\nLine 17.\nLine 18.\nLine 19.\nLine 20.\nLine 21.\n'
    'Line 22.\nLine 23.\nLine 24.\nLine 25.\nLine 26.\nLine 27.\nLine 28.\n'
    'Line 29.\nLine 30.\nLine 31.\nLine 32.\nLine 33.\nLine 34.\nLine 35.\n'
    'Line 36.\nLine 37.\nLine 38.\nLine 39.\nLine 40.';

final _createdAt = DateTime.utc(2025);
final _currentTime = DateTime.utc(2025, 1, 1, 5);

int _byteLen(String s) => utf8.encode(s).length;

RichTextFacet _facetOver({
  required String fullText,
  required String span,
  required List<FacetFeature> features,
}) {
  final charStart = fullText.indexOf(span);
  final byteStart = _byteLen(fullText.substring(0, charStart));
  final byteEnd = byteStart + _byteLen(span);
  return RichTextFacet(
    index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
    features: features,
  );
}

CommentView _comment({
  required String content,
  List<RichTextFacet>? facets,
  Map<String, dynamic>? embed,
  PostEmbed? parsedEmbed,
}) {
  return CommentView(
    uri: 'at://$_authorDid/social.coves.community.comment/3ksheet01',
    cid: 'cid-sheet',
    record: CommentRecord(content: content, facets: facets),
    createdAt: _createdAt,
    indexedAt: _createdAt,
    author: AuthorView(did: _authorDid, handle: 'sheet.author.test'),
    post: CommentRef(uri: _parentPostUri, cid: 'cid123'),
    stats: const CommentStats(upvotes: 3, score: 3),
    embed: embed,
    parsedEmbed: parsedEmbed,
  );
}

/// Fixture S: a blockquote line, a plain paragraph and a spoiler.
CommentView _shortComment() => _comment(
  content: _shortBody,
  facets: [
    _facetOver(
      fullText: _shortBody,
      span: 'Earlier point here',
      features: const [BlockquoteFacetFeature()],
    ),
    _facetOver(
      fullText: _shortBody,
      span: 'Rosebud',
      features: const [SpoilerFacetFeature()],
    ),
  ],
);

/// Fixture L: forty lines, taller than the sheet's maximum height.
CommentView _longComment() => _comment(content: _longBody);

/// Fixture I: no text, one image.
CommentView _imageOnlyComment() {
  const image = EmbedImage(
    thumb: 'https://cdn.test/t1.jpg',
    fullsize: 'https://cdn.test/f1.jpg',
  );
  final raw = <String, dynamic>{
    r'$type': 'social.coves.embed.images#view',
    'images': [
      {'thumb': image.thumb, 'fullsize': image.fullsize},
    ],
  };
  return _comment(
    content: '',
    embed: raw,
    parsedEmbed: ImagesPostEmbed(
      type: 'social.coves.embed.images#view',
      images: const [image],
      data: raw,
    ),
  );
}

const _imagesBody = 'Look at this\n\n[image]\n\nNice';

/// Two images: the second placed in the body by an `#image` facet over
/// `[image]`, the first left for the gallery.
CommentView _placedImageComment() {
  const images = [
    EmbedImage(
      thumb: 'https://cdn.test/gallery-thumb.jpg',
      fullsize: 'https://cdn.test/gallery-full.jpg',
    ),
    EmbedImage(
      thumb: 'https://cdn.test/placed-thumb.jpg',
      fullsize: 'https://cdn.test/placed-full.jpg',
    ),
  ];
  final raw = <String, dynamic>{
    r'$type': 'social.coves.embed.images#view',
    'images': [
      for (final image in images)
        {'thumb': image.thumb, 'fullsize': image.fullsize},
    ],
  };
  return _comment(
    content: _imagesBody,
    facets: [
      _facetOver(
        fullText: _imagesBody,
        span: '[image]',
        features: const [ImageFacetFeature(index: 1)],
      ),
    ],
    embed: raw,
    parsedEmbed: ImagesPostEmbed(
      type: 'social.coves.embed.images#view',
      images: images,
      data: raw,
    ),
  );
}

/// A tombstone placeholder as the AppView serves it.
CommentView _placeholder({
  required String deletionReason,
  ModerationView? moderation,
}) {
  return CommentView(
    uri: 'at://did:plc:author/social.coves.community.comment/gone',
    cid: 'cid-gone',
    isDeleted: true,
    deletionReason: deletionReason,
    moderation: moderation,
    createdAt: _createdAt,
    indexedAt: _createdAt,
    author: AuthorView(did: 'did:plc:author', handle: 'handle.invalid'),
    post: CommentRef(uri: _parentPostUri, cid: 'cid123'),
    stats: const CommentStats(replyCount: 2),
  );
}

CommentView _deletedComment() => _placeholder(deletionReason: 'author');

CommentView _removedComment() => _placeholder(
  deletionReason: 'moderator',
  moderation: const ModerationView(
    state: ModerationState.removed,
    sources: [
      ModerationSource(
        authorityDid: 'did:web:coves.social',
        scope: ModerationScope(kind: ModerationScopeKind.instance),
      ),
    ],
  ),
);

PostView _parentPost() {
  return PostView(
    uri: _parentPostUri,
    cid: 'cid123',
    rkey: '3kabcxyz',
    author: AuthorView(did: 'did:plc:author123', handle: 'alice.coves.social'),
    community: CommunityRef(
      did: 'did:plc:community456',
      name: 'Gaming',
      origin: 'coves.social',
    ),
    createdAt: DateTime(2024),
    indexedAt: DateTime(2024),
    record: const PostRecord(content: 'Parent post', title: 'Parent Post'),
    stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 1),
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

late MockAuthProvider _auth;
late MockVoteProvider _votes;
late BlockProvider _blocks;

void _setUpProviders() {
  _auth = MockAuthProvider();
  _votes = MockVoteProvider();
  _blocks = BlockProvider(
    apiService: MockCovesApiService(),
    authProvider: _auth,
  );
  _signIn();
  when(_votes.isLiked(any)).thenReturn(false);
  when(_votes.getVoteState(any)).thenReturn(null);
  when(_votes.isPending(any)).thenReturn(false);
  when(_votes.getAdjustedScore(any, any))
      .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
}

/// Signed in as a viewer who is not the comment's author.
void _signIn() {
  when(_auth.isAuthenticated).thenReturn(true);
  when(_auth.did).thenReturn(_viewerDid);
}

void _signOut() {
  when(_auth.isAuthenticated).thenReturn(false);
  when(_auth.did).thenReturn(null);
}

/// Captures every `Clipboard.setData` text; also answers haptics.
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

/// Mounts a card for [comment], wrapped by [wrapCard] if given, on a
/// 400x900 view.
Future<void> _pumpCard(
  WidgetTester tester,
  CommentView comment, {
  PostView? parentPost,
  bool isCollapsed = false,
  Widget Function(Widget card)? wrapCard,
}) async {
  final Widget card = CommentCard(
    comment: comment,
    sessionStamp: null,
    parentPost: parentPost,
    currentTime: _currentTime,
    isCollapsed: isCollapsed,
  );
  await _pumpApp(tester, wrapCard == null ? card : wrapCard(card));
}

/// Mounts [child] in a scrolling scaffold with the card's providers, on a
/// 400x900 view.
Future<void> _pumpApp(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<VoteProvider>.value(value: _votes),
        ChangeNotifierProvider<BlockProvider>.value(value: _blocks),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final _menuTrigger = find.byTooltip('Comment options');

Future<void> _openMenu(WidgetTester tester) async {
  expect(_menuTrigger, findsOneWidget, reason: 'Comment options button');
  await tester.ensureVisible(_menuTrigger);
  await tester.pumpAndSettle();
  await tester.tap(_menuTrigger);
  await tester.pumpAndSettle();
}

/// The open menu's item labels, in menu order.
List<String> _menuItemTexts(WidgetTester tester) {
  return [
    for (final item in find.byType(MenuItemButton).evaluate())
      find
          .descendant(
            of: find.byWidget(item.widget),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .first,
  ];
}

final _sheet = find.byType(BottomSheet);

Future<void> _openSelectTextSheet(WidgetTester tester) async {
  await _openMenu(tester);
  expect(find.text('Select text'), findsOneWidget, reason: 'menu item');
  await tester.tap(find.text('Select text'));
  await tester.pumpAndSettle();
  // A nested SelectionContainer registers with its SelectionArea in a
  // post-frame flush; pump one more frame before the first gesture.
  await tester.pump();
  expect(_sheet, findsOneWidget, reason: 'the Select text sheet');
}

/// Every paragraph whose plain text contains [text].
Finder _richTextContaining(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText &&
      widget.text.toPlainText(includeSemanticsLabels: false).contains(text),
);

/// The paragraph inside [scope] whose plain text contains [text].
RenderParagraph _paragraphIn(WidgetTester tester, Finder scope, String text) {
  final finder = find.descendant(
    of: scope,
    matching: _richTextContaining(text),
  );
  expect(finder, findsOneWidget, reason: 'paragraph holding "$text"');
  return tester.renderObject<RenderParagraph>(finder);
}

/// Global rect covering [text] inside the paragraph in [scope] holding it.
Rect _textRectIn(WidgetTester tester, Finder scope, String text) {
  final paragraph = _paragraphIn(tester, scope, text);
  final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final start = plain.indexOf(text);
  final local = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + text.length),
      )
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

/// Global rect covering [text] inside the sheet's own paragraph.
Rect _sheetTextRect(WidgetTester tester, String text) =>
    _textRectIn(tester, _sheet, text);

/// Global rect of the sheet's scroll viewport around the paragraph holding
/// [text].
Rect _sheetViewport(WidgetTester tester, String text) {
  final paragraphFinder = find.descendant(
    of: _sheet,
    matching: _richTextContaining(text),
  );
  final scrollable = find.ancestor(
    of: paragraphFinder,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsWidgets, reason: 'a scroll view in the sheet');
  return tester.getRect(scrollable.first);
}

bool _contains(Rect outer, Rect inner) =>
    inner.top >= outer.top - 0.5 &&
    inner.bottom <= outer.bottom + 0.5 &&
    inner.left >= outer.left - 0.5 &&
    inner.right <= outer.right + 0.5;

Future<void> _longPressSheetWord(WidgetTester tester, String word) async {
  await tester.longPressAt(_sheetTextRect(tester, word).center);
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

/// Global rects of the Material selection handles currently drawn: non-zero
/// opacity and following a connected leader.
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
      if (widget is CompositedTransformFollower &&
          !widget.showWhenUnlinked &&
          widget.link.leader == null) {
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

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  setUp(_setUpProviders);

  group('Select text menu item', () {
    testWidgets('signed in with a parent post: items start Share, Copy link, '
        'Select text', (tester) async {
      await _pumpCard(tester, _shortComment(), parentPost: _parentPost());
      await _openMenu(tester);

      expect(_menuItemTexts(tester).take(3).toList(), [
        'Share',
        'Copy link',
        'Select text',
      ]);
    }, variant: android);

    testWidgets('signed out with no parent post: the menu holds exactly '
        'Select text', (tester) async {
      _signOut();
      await _pumpCard(tester, _shortComment());
      await _openMenu(tester);

      expect(_menuItemTexts(tester), ['Select text']);
    }, variant: android);

    testWidgets('no Select text where the comment has no text to select', (
      tester,
    ) async {
      final rows =
          <
            ({
              String name,
              CommentView comment,
              PostView? parentPost,
              bool signedIn,
              bool isCollapsed,
              bool replyPreview,
              List<String>? expectedItems,
            })
          >[
            (
              name: 'image-only, signed in with a parent post',
              comment: _imageOnlyComment(),
              parentPost: _parentPost(),
              signedIn: true,
              isCollapsed: false,
              replyPreview: false,
              expectedItems: const ['Share', 'Copy link'],
            ),
            (
              name: 'image-only, signed out with no parent post',
              comment: _imageOnlyComment(),
              parentPost: null,
              signedIn: false,
              isCollapsed: false,
              replyPreview: false,
              expectedItems: null,
            ),
            (
              name: 'deleted',
              comment: _deletedComment(),
              parentPost: _parentPost(),
              signedIn: true,
              isCollapsed: false,
              replyPreview: false,
              expectedItems: null,
            ),
            (
              name: 'removed',
              comment: _removedComment(),
              parentPost: _parentPost(),
              signedIn: true,
              isCollapsed: false,
              replyPreview: false,
              expectedItems: null,
            ),
            (
              name: 'collapsed',
              comment: _shortComment(),
              parentPost: _parentPost(),
              signedIn: true,
              isCollapsed: true,
              replyPreview: false,
              expectedItems: null,
            ),
            (
              name: 'reply preview, signed out',
              comment: _shortComment(),
              parentPost: null,
              signedIn: false,
              isCollapsed: false,
              replyPreview: true,
              expectedItems: null,
            ),
            (
              name: 'reply preview, signed in',
              comment: _shortComment(),
              parentPost: null,
              signedIn: true,
              isCollapsed: false,
              replyPreview: true,
              expectedItems: const [
                'Block @sheet.author.test',
                'Report comment',
              ],
            ),
          ];

      for (final row in rows) {
        if (row.signedIn) {
          _signIn();
        } else {
          _signOut();
        }
        await _pumpCard(
          tester,
          row.comment,
          parentPost: row.parentPost,
          isCollapsed: row.isCollapsed,
          wrapCard: row.replyPreview
              ? (card) => ContentOnlySelectionScope(child: card)
              : null,
        );

        final expectedItems = row.expectedItems;
        if (expectedItems == null) {
          expect(_menuTrigger, findsNothing, reason: '${row.name}: trigger');
        } else {
          await _openMenu(tester);
          expect(
            _menuItemTexts(tester),
            containsAll(expectedItems),
            reason: '${row.name}: menu items',
          );
        }
        expect(
          find.text('Select text'),
          findsNothing,
          reason: '${row.name}: Select text',
        );

        // Unmount so the next row starts from a fresh card and closed menu.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }, variant: android);
  });

  group('Select text sheet', () {
    testWidgets('a long comment opens a capped, scrollable sheet', (
      tester,
    ) async {
      await _pumpCard(tester, _longComment(), parentPost: _parentPost());
      await _openSelectTextSheet(tester);

      final sheetHeight = tester.getSize(_sheet).height;
      expect(sheetHeight, lessThanOrEqualTo(810));
      expect(sheetHeight, greaterThan(506));

      final viewport = _sheetViewport(tester, 'Line 40.');
      expect(
        _contains(viewport, _sheetTextRect(tester, 'Line 1.')),
        isTrue,
        reason: '"Line 1." is inside the sheet viewport',
      );
      expect(
        _sheetTextRect(tester, 'Line 40.').top,
        greaterThanOrEqualTo(viewport.bottom),
        reason: '"Line 40." starts below the sheet viewport',
      );

      // Two bounded upward drags that start and end inside the sheet.
      final sheetRect = tester.getRect(_sheet);
      final start = Offset(sheetRect.center.dx, sheetRect.bottom - 40);
      for (var i = 0; i < 2; i++) {
        await tester.dragFrom(start, const Offset(0, -300));
        await tester.pumpAndSettle();
      }

      expect(
        _contains(
          _sheetViewport(tester, 'Line 40.'),
          _sheetTextRect(tester, 'Line 40.'),
        ),
        isTrue,
        reason: '"Line 40." is inside the sheet viewport after scrolling',
      );
      expect(_visibleHandleRects(tester), isEmpty, reason: 'handles');
      expect(find.text('Copy'), findsNothing, reason: 'toolbar Copy');
      expect(find.text('Select all'), findsNothing, reason: 'toolbar');
    }, variant: android);

    testWidgets('long-press "agree", Select all, Copy copies only the body '
        'with the spoiler masked', (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpCard(tester, _shortComment(), parentPost: _parentPost());
      await _openSelectTextSheet(tester);

      await _longPressSheetWord(tester, 'agree');
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [
        'Earlier point here\nI agree with this.\n\nThe ending is xxxxxxx',
      ]);
    }, variant: android);

    testWidgets('long-press "point" and drag the end handle to the end of '
        '"agree" copies across the quote and the paragraph', (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpCard(tester, _shortComment(), parentPost: _parentPost());
      await _openSelectTextSheet(tester);

      final agree = _sheetTextRect(tester, 'agree');
      await _longPressSheetWord(tester, 'point');
      final handles = await _pumpUntilHandlesVisible(tester);
      // The end handle is the one further right; its anchor is its top-left
      // corner, on the current end selection point.
      final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);

      final target = Offset(agree.right, agree.bottom);
      await tester.dragFrom(endHandle.center, target - endHandle.topLeft);
      await tester.pumpAndSettle();

      await _tapToolbar(tester, 'Copy');

      expect(copied, ['point here\nI agree']);
    }, variant: android);
  });
  group('Select text sheet spoilers', () {
    testWidgets('a spoiler revealed in the card starts hidden in the sheet '
        'and a tap in the sheet reveals it there', (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpCard(tester, _shortComment(), parentPost: _parentPost());

      final card = find.byType(CommentCard);
      await tester.tapAt(_textRectIn(tester, card, 'xxxxxxx').center);
      await tester.pumpAndSettle();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
      expect(
        find.descendant(
          of: card,
          matching: _richTextContaining('The ending is Rosebud'),
        ),
        findsOneWidget,
        reason: 'the card revealed its spoiler',
      );

      await _openSelectTextSheet(tester);
      await _longPressSheetWord(tester, 'agree');
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [
        'Earlier point here\nI agree with this.\n\nThe ending is xxxxxxx',
      ]);

      await tester.tapAt(_sheetTextRect(tester, 'xxxxxxx').center);
      await tester.pumpAndSettle();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
      await _longPressSheetWord(tester, 'agree');
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [
        'Earlier point here\nI agree with this.\n\nThe ending is xxxxxxx',
        'Earlier point here\nI agree with this.\n\nThe ending is Rosebud',
      ]);
    }, variant: android);
  });

  group('Select text sheet dismissal', () {
    testWidgets('dismissing the sheet with a selection leaves only the card', (
      tester,
    ) async {
      final rows =
          <({String name, Future<void> Function(WidgetTester tester) dismiss})>[
            (
              name: 'tap the barrier above the sheet',
              dismiss: (tester) async {
                expect(
                  tester.getRect(_sheet).top,
                  greaterThan(40),
                  reason: 'room above the sheet for the barrier tap',
                );
                await tester.tapAt(const Offset(200, 20));
              },
            ),
            (
              name: 'drag the handle bar down by 500 px',
              dismiss: (tester) async {
                final sheetRect = tester.getRect(_sheet);
                await tester.dragFrom(
                  Offset(sheetRect.center.dx, sheetRect.top + 14),
                  const Offset(0, 500),
                );
              },
            ),
            (
              name: 'system back',
              dismiss: (tester) async {
                await tester.binding.handlePopRoute();
              },
            ),
          ];

      for (final row in rows) {
        await _pumpCard(tester, _shortComment(), parentPost: _parentPost());
        await _openSelectTextSheet(tester);
        // "ending" keeps the toolbar clear of the handle bar at the top.
        await _longPressSheetWord(tester, 'ending');
        await _pumpUntilHandlesVisible(tester);
        expect(find.text('Copy'), findsOneWidget, reason: '${row.name}: Copy');
        expect(
          _richTextContaining('I agree with this.'),
          findsNWidgets(2),
          reason: '${row.name}: card and sheet both show the body',
        );

        await row.dismiss(tester);
        await tester.pumpAndSettle();

        expect(_sheet, findsNothing, reason: '${row.name}: sheet');
        expect(
          _visibleHandleRects(tester),
          isEmpty,
          reason: '${row.name}: handles',
        );
        expect(find.text('Copy'), findsNothing, reason: '${row.name}: Copy');
        expect(
          find.text('Select all'),
          findsNothing,
          reason: '${row.name}: Select all',
        );
        expect(
          _richTextContaining('I agree with this.'),
          findsOneWidget,
          reason: '${row.name}: only the card shows the body',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }, variant: android);
  });

  group('Comment thread long-press', () {
    testWidgets('long-press "agree" in the card collapses and selects '
        'nothing', (tester) async {
      _captureClipboard(tester);
      final toggled = <String>[];
      final comment = _shortComment();
      await _pumpApp(
        tester,
        CommentThread(
          thread: ThreadViewComment(comment: comment),
          sessionStamp: null,
          currentTime: _currentTime,
          parentPost: _parentPost(),
          onCollapseToggle: toggled.add,
        ),
      );

      await tester.longPressAt(
        _textRectIn(tester, find.byType(CommentCard), 'agree').center,
      );
      await tester.pumpAndSettle();

      expect(toggled, [
        'at://did:plc:sheetauthor/social.coves.community.comment/3ksheet01',
      ]);
      expect(_visibleHandleRects(tester), isEmpty, reason: 'handles');
      expect(find.text('Copy'), findsNothing, reason: 'toolbar Copy');
      expect(find.text('Select all'), findsNothing, reason: 'toolbar');
    }, variant: android);
  });

  group('Select text sheet contents', () {
    testWidgets('semantics in the sheet hold the body and none of the '
        "comment's chrome", (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCard(tester, _shortComment(), parentPost: _parentPost());
      await _openSelectTextSheet(tester);

      final sheetLabels = <String>[];
      void collect(SemanticsNode node) {
        sheetLabels.add(node.label);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(tester.getSemantics(_sheet));
      for (final element
          in find
              .descendant(of: _sheet, matching: find.byType(RichText))
              .evaluate()) {
        collect(tester.getSemantics(find.byWidget(element.widget)));
      }
      // A paragraph holding a tap recognizer (the spoiler) is split into
      // child nodes, so the body is read from the whole sheet subtree.
      expect(
        sheetLabels,
        contains(contains('I agree with this.')),
        reason: 'a sheet node announces the body',
      );
      expect(
        sheetLabels.where((label) => label.contains('sheet.author.test')),
        isEmpty,
        reason: 'no author handle in the sheet',
      );
      expect(
        sheetLabels.where(
          (label) =>
              label.contains('Upvote comment') ||
              label.contains('Downvote comment'),
        ),
        isEmpty,
        reason: 'no vote controls in the sheet',
      );
      expect(
        find.descendant(of: _sheet, matching: find.text('5h')),
        findsNothing,
        reason: 'no timestamp in the sheet',
      );
      expect(
        find.descendant(of: _sheet, matching: find.text('3')),
        findsNothing,
        reason: 'no score in the sheet',
      );
      semantics.dispose();
    }, variant: android);

    testWidgets('a placed image shows in the sheet, the gallery does not, '
        'and Copy leaves the image out', (tester) async {
      final copied = _captureClipboard(tester);
      await _pumpCard(tester, _placedImageComment(), parentPost: _parentPost());
      const placedKey = Key('rich-text-image-1');
      const galleryKey = Key('comment-images-embed');
      expect(find.byKey(placedKey), findsOneWidget, reason: 'card placement');
      expect(find.byKey(galleryKey), findsOneWidget, reason: 'card gallery');

      await _openSelectTextSheet(tester);

      expect(
        find.descendant(of: _sheet, matching: find.byKey(placedKey)),
        findsOneWidget,
        reason: 'the placed image in the sheet',
      );
      expect(
        find.descendant(of: _sheet, matching: find.byKey(galleryKey)),
        findsNothing,
        reason: 'no gallery in the sheet',
      );

      await _longPressSheetWord(tester, 'Look');
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, ['Look at this\nNice']);
    }, variant: android);
  });
}
