import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/fake_image_cache_manager.dart';
import 'reply_preview_fixtures.dart';
import 'reply_screen_test_harness.dart';

const _postBody = 'Distinctive parent post body for selection';
const _commentBody = 'Distinctive parent comment body for selection';

FeedViewPost _post() => FeedViewPost(
  post: PostView(
    uri: testPostUri,
    cid: testPostCid,
    rkey: '123',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: _postBody),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  ),
);

ThreadViewComment _comment() => ThreadViewComment(
  comment: CommentView(
    uri: 'at://did:plc:author/comment/1',
    cid: 'cid-comment-1',
    record: const CommentRecord(content: _commentBody),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    post: CommentRef(uri: testPostUri, cid: testPostCid),
    stats: const CommentStats(),
  ),
);

void main() {
  _contentOnlySelectionTests();

  testWidgets('long-pressing the reply context preview text offers Copy', (
    tester,
  ) async {
    final cases = <(String, String, ReplyScreen Function(ReplyScreenHarness))>[
      (
        'replying to a post',
        _postBody,
        (harness) => ReplyScreen(
          post: _post(),
          commentsProvider: harness.commentsProvider,
          onSubmit: (content, facets, embed) async {},
        ),
      ),
      (
        'replying to a comment',
        _commentBody,
        (harness) => ReplyScreen(
          comment: _comment(),
          commentsProvider: harness.commentsProvider,
          onSubmit: (content, facets, embed) async {},
        ),
      ),
    ];

    for (final (label, body, buildScreen) in cases) {
      final harness = ReplyScreenHarness();
      await harness.pumpBase(tester);
      unawaited(
        harness.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => buildScreen(harness)),
        ),
      );
      await tester.pumpAndSettle();

      final bodyText = find.textContaining(body, findRichText: true);
      expect(bodyText, findsOneWidget, reason: '$label: preview shows body');
      expect(
        find.text('Copy'),
        findsNothing,
        reason: '$label: no toolbar before the long-press',
      );

      await tester.longPress(bodyText);
      await tester.pumpAndSettle();

      expect(
        find.text('Copy'),
        findsOneWidget,
        reason:
            '$label: long-pressing the context preview text selects it '
            'and shows a Copy action',
      );

      // Tear down this case's tree before the next case
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    }
  });
}

// Content-only copy from the reply context preview: the post title and
// body, or the comment bodies, joined by one newline.

const _linkThumb = 'https://cdn.test/story-thumb.jpg';
const _removedImage = 'https://cdn.test/removed.jpg';

PostEmbed _linkEmbed() => PostEmbed.fromJson({
  r'$type': 'social.coves.embed.external#view',
  'external': {'uri': 'https://example.org/story', 'thumb': _linkThumb},
});

PostEmbed _blueskyEmbed() => PostEmbed.fromJson({
  r'$type': EmbedTypes.postView,
  'post': {
    'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
    'cid': 'bafyquotedcid',
  },
  'resolved': {
    'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
    'cid': 'bafyquotedcid',
    'text': 'Quoted bluesky words',
    'createdAt': '2025-01-01T00:00:00Z',
    'author': {'did': 'did:plc:quoted', 'handle': 'quoted.author.test'},
    'replyCount': 0,
    'repostCount': 0,
    'likeCount': 0,
    'hasMedia': false,
    'mediaCount': 0,
    'unavailable': false,
  },
});

PostEmbed _removedImageEmbed() => PostEmbed.fromJson({
  r'$type': 'social.coves.embed.images#view',
  'images': [
    {'thumb': _removedImage, 'fullsize': _removedImage},
  ],
});

/// Fixture D: seven comments, each the only reply of the one before.
ThreadViewComment _deepChain() {
  var thread = ThreadViewComment(
    comment: previewCommentView(
      id: 'depth6',
      body: 'Depth 6 body.',
      handle: 'depth6.commenter.test',
      replyCount: 2,
    ),
    replies: [
      ThreadViewComment(
        comment: previewCommentView(
          id: 'hidden',
          body: 'Hidden deep reply.',
          handle: 'hidden.commenter.test',
        ),
      ),
    ],
  );
  for (var depth = 5; depth >= 0; depth--) {
    thread = ThreadViewComment(
      comment: previewCommentView(
        id: 'depth$depth',
        body: 'Depth $depth body.',
        handle: 'depth$depth.commenter.test',
        replyCount: 1,
      ),
      replies: [thread],
      hasMore: depth == 0,
    );
  }
  return thread;
}

/// Captures every `Clipboard.setData` text; answers every other platform
/// call (haptics) with null. Install after [ReplyScreenHarness.pumpBase],
/// which installs its own handler.
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
  return copied;
}

/// Bounded stand-in for pumpAndSettle: preview images may stay loading
/// forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The paragraph whose plain text starts with [prefix].
Finder _paragraphFinder(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText &&
      widget.text.toPlainText(includeSemanticsLabels: false).startsWith(prefix),
);

/// The rendered paragraph whose plain text starts with [prefix].
RenderParagraph _paragraph(WidgetTester tester, String prefix) {
  final finder = _paragraphFinder(prefix);
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
  // The screen opens scrolled to the composer, so a long preview starts
  // above the viewport.
  await tester.ensureVisible(_paragraphFinder(prefix));
  await _settle(tester);
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

/// Global rects of the Material selection handles currently drawn: non-zero
/// opacity, and following a connected leader.
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

/// The author handle in the post preview's footer. The header shows the
/// same handle first in the tree, so the footer's is the last match.
Finder _footerAuthorHandle() => find.text('@$previewPostAuthorHandle').last;

void _expectNoSelectionUi(WidgetTester tester) {
  expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
  expect(find.text('Copy'), findsNothing);
  expect(find.text('Select all'), findsNothing);
}

void _contentOnlySelectionTests() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  /// Mounts the reply screen over [post] or [comment] on a 400x[height]
  /// phone with a fixed clock, and returns the clipboard capture.
  Future<List<String>> openReply(
    WidgetTester tester, {
    FeedViewPost? post,
    ThreadViewComment? comment,
    FakeImageCacheManager? cacheManager,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final harness = ReplyScreenHarness();
    addTearDown(harness.dispose);
    harness.commentsProvider.currentTimeNotifier.value = previewCurrentTime;
    await harness.pumpBase(
      tester,
      cacheManager: cacheManager ?? FakeImageCacheManager(),
    );
    final copied = _captureClipboard(tester);
    unawaited(
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReplyScreen(
            post: post,
            comment: comment,
            commentsProvider: harness.commentsProvider,
            onSubmit: (content, facets, embed) async {},
          ),
        ),
      ),
    );
    await _settle(tester);
    // A nested SelectionContainer registers with its SelectionArea in a
    // post-frame flush; pump one more frame before the first gesture.
    await tester.pump();
    return copied;
  }

  void testReply(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }, variant: android);
  }

  final postRows =
      <
        String,
        ({
          FeedViewPost post,
          FakeImageCacheManager? cacheManager,
          Future<void> Function(WidgetTester tester) prepare,
        })
      >{
        '(a) plain post': (
          post: previewPost(),
          cacheManager: null,
          prepare: (tester) async {},
        ),
        '(b) external link embed': (
          post: previewPost(embed: _linkEmbed()),
          cacheManager: null,
          prepare: (tester) async {
            expect(find.text('example.org'), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(PostCard),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CachedNetworkImage &&
                      widget.imageUrl == _linkThumb,
                ),
              ),
              findsOneWidget,
              reason: 'the link thumbnail renders',
            );
          },
        ),
        '(c) Bluesky embed': (
          post: previewPost(embed: _blueskyEmbed()),
          cacheManager: null,
          prepare: (tester) async {
            expect(
              find.textContaining('Quoted bluesky words', findRichText: true),
              findsWidgets,
            );
            expect(
              find.textContaining('quoted.author.test', findRichText: true),
              findsWidgets,
            );
          },
        ),
        '(d) self-labelled sensitive, revealed': (
          post: previewPost(sensitive: true),
          cacheManager: null,
          prepare: (tester) async {
            await tester.tap(find.byKey(const Key('sensitive-content-banner')));
            await _settle(tester);
            expect(
              find.text(previewPostText, findRichText: true),
              findsWidgets,
            );
          },
        ),
        '(e) image that fails as removed': (
          post: previewPost(embed: _removedImageEmbed()),
          cacheManager: FakeImageCacheManager(
            errors: {
              _removedImage: const HttpExceptionWithStatus(404, 'not found'),
            },
          ),
          prepare: (tester) async {
            for (var i = 0; i < 20; i++) {
              if (find.text('Image removed').evaluate().isNotEmpty) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(find.text('Image removed'), findsOneWidget);
          },
        ),
      };

  for (final MapEntry(key: row, value: fixture) in postRows.entries) {
    testReply('B1 $row: Select all + Copy in the post preview copies only '
        'the title and the body', (tester) async {
      final copied = await openReply(
        tester,
        post: fixture.post,
        cacheManager: fixture.cacheManager,
      );
      await fixture.prepare(tester);
      // The excluded parts are on screen, so their absence from the
      // clipboard means the region excluded them.
      expect(find.text('@$previewPostAuthorHandle'), findsWidgets);
      expect(find.text('5h'), findsWidgets);

      await _selectAllAndCopy(tester, previewPostText, 'body');

      expect(copied, ['Preview post title\nPreview post body text.']);
    });
  }

  final commentRows =
      <
        String,
        ({
          ThreadViewComment thread,
          String expected,
          FakeImageCacheManager? cacheManager,
        })
      >{
        'C': (
          thread: previewCommentChain(),
          expected: 'First comment body.\nNested reply body.',
          cacheManager: null,
        ),
        'C with the nested reply deleted': (
          thread: previewCommentChain(nestedDeleted: true),
          expected: 'First comment body.',
          cacheManager: null,
        ),
        'C with a gallery image that fails as removed': (
          thread: previewCommentChain(firstEmbed: _removedImageEmbed()),
          expected: 'First comment body.\nNested reply body.',
          cacheManager: FakeImageCacheManager(
            errors: {
              _removedImage: const HttpExceptionWithStatus(404, 'not found'),
            },
          ),
        ),
      };

  for (final MapEntry(key: row, value: fixture) in commentRows.entries) {
    testReply('B2 $row: Select all + Copy in the comment preview copies only '
        'the comment bodies', (tester) async {
      final copied = await openReply(
        tester,
        comment: fixture.thread,
        cacheManager: fixture.cacheManager,
      );
      expect(find.text('@first.commenter.test'), findsOneWidget);
      expect(find.text('5h'), findsWidgets);
      if (row == 'C with the nested reply deleted') {
        expect(find.text('[Deleted by user]'), findsOneWidget);
      }
      if (row == 'C with a gallery image that fails as removed') {
        for (var i = 0; i < 20; i++) {
          if (find.text('Image removed').evaluate().isNotEmpty) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('Image removed'), findsOneWidget);
      }

      await _selectAllAndCopy(tester, 'First comment body.', 'First');

      expect(copied, [fixture.expected]);
    });
  }

  testReply('B4 long-pressing the empty middle of the comment action row '
      'starts no selection', (tester) async {
    await openReply(tester, comment: previewCommentChain());
    // The Spacer between the comment menu and the vote buttons of the
    // first comment: empty space no child claims.
    final spacer = find
        .descendant(
          of: find.byType(CommentCard).first,
          matching: find.byType(Spacer),
        )
        .first;
    await tester.ensureVisible(spacer);
    await _settle(tester);
    expect(tester.getSize(spacer).width, greaterThan(48));

    await tester.longPressAt(tester.getCenter(spacer));
    await _settle(tester);

    _expectNoSelectionUi(tester);
  });

  testReply('B3 dragging the end handle from "body" in the first comment to '
      r'the end of "Nested" copies "body.\nNested"', (tester) async {
    final copied = await openReply(tester, comment: previewCommentChain());

    final nested = _wordRect(tester, 'Nested reply body.', 'Nested');
    await _longPressWord(tester, 'First comment body.', 'body');
    final handles = await _pumpUntilHandlesVisible(tester);
    // The end handle is the one further right; its anchor is its top-left
    // corner, on the current end selection point.
    final endHandle = handles.reduce((a, b) => a.left >= b.left ? a : b);

    final target = Offset(nested.right, nested.bottom);
    await tester.dragFrom(endHandle.center, target - endHandle.topLeft);
    await _settle(tester);

    await _tapToolbar(tester, 'Copy');

    expect(copied, ['body.\nNested']);
  });

  testReply('B7 deep chain D: Select all + Copy copies the seven bodies '
      'without the thread links or the hidden reply', (tester) async {
    // Tall enough that the whole chain and the toolbar after Select all,
    // which sits below the selection, stay on screen.
    final copied = await openReply(tester, comment: _deepChain(), height: 1600);
    expect(find.text('Read 2 more replies'), findsOneWidget);
    expect(find.text('Load more replies'), findsOneWidget);
    expect(find.textContaining('Hidden deep reply.'), findsNothing);

    await _selectAllAndCopy(tester, 'Depth 0 body.', 'body');

    const expected =
        'Depth 0 body.\nDepth 1 body.\nDepth 2 body.\nDepth 3 body.\n'
        'Depth 4 body.\nDepth 5 body.\nDepth 6 body.';
    expect(copied, [expected]);
  });

  testReply('B7 deep chain D: long-pressing "Read 2 more replies" starts no '
      'selection', (tester) async {
    await openReply(tester, comment: _deepChain());
    final link = find.text('Read 2 more replies');
    await tester.ensureVisible(link);
    await _settle(tester);

    await tester.longPress(link);
    await _settle(tester);

    _expectNoSelectionUi(tester);
  });

  testReply('B4 long-pressing the author handle in the post preview footer '
      'starts no selection', (tester) async {
    await openReply(tester, post: previewPost());
    final handle = _footerAuthorHandle();
    await tester.ensureVisible(handle);
    await _settle(tester);

    await tester.longPress(handle);
    await _settle(tester);

    _expectNoSelectionUi(tester);
  });

  testReply('B6 the post preview footer keeps the author handle semantics '
      'node with its label and tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await openReply(tester, post: previewPost());

      final node = tester.getSemantics(
        find.descendant(
          of: _footerAuthorHandle(),
          matching: find.byType(RichText),
        ),
      );
      final data = node.getSemanticsData();
      expect(data.label, '@preview.author.test');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });
}
