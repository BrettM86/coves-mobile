import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/media/image_error.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_image_cache_manager.dart';
import '../test_helpers/test_mocks.dart';

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

/// Bounded stand-in for pumpAndSettle: the carousel images may stay loading
/// forever, so a settle is never awaited unbounded.
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

void _expectNoSelectionUi(WidgetTester tester) {
  expect(_visibleHandleRects(tester), isEmpty, reason: 'selection handles');
  expect(find.text('Copy'), findsNothing);
  expect(find.text('Select all'), findsNothing);
}

// 2025-01-01T00:00Z; the month and day are the defaults.
final _createdAt = DateTime.utc(2025);
final _currentTime = DateTime.utc(2025, 1, 1, 3);

const _handle = 'field.author.test';
const _commentBody = 'Distinct comment body text';

FeedViewPost _post({
  required String uri,
  required String title,
  required String text,
  required PostEmbed embed,
  bool sensitive = false,
  int score = 0,
  int commentCount = 0,
}) => FeedViewPost(
  post: PostView(
    uri: uri,
    cid: 'cid-${uri.split('/').last}',
    rkey: uri.split('/').last,
    author: AuthorView(did: 'did:plc:author', handle: _handle),
    community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
    createdAt: _createdAt,
    indexedAt: _createdAt,
    record: PostRecord(
      title: title,
      content: text,
      labels: sensitive ? const ['nsfw'] : const [],
    ),
    stats: PostStats(
      upvotes: score,
      downvotes: 0,
      score: score,
      commentCount: commentCount,
    ),
    embed: embed,
  ),
);

const _sensitiveUri = 'at://did:plc:author/social.coves.community.post/harbour';

/// Fixture 5(a): a self-labelled sensitive post with an external embed
/// carrying a three-image carousel and one source, upvote count 7.
FeedViewPost _sensitiveCarouselPost() => _post(
  uri: _sensitiveUri,
  title: 'Harbour cleanup photos',
  text: 'We filled six bags.',
  sensitive: true,
  score: 7,
  commentCount: 1,
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

/// Fixture 5(b): a post sharing a Bluesky post with a body of its own.
FeedViewPost _quotePost() => _post(
  uri: 'at://did:plc:author/social.coves.community.post/quote',
  title: 'Quote post title',
  text: 'Quote post body.',
  embed: PostEmbed.fromJson({
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
      'author': {'did': 'did:plc:quoted', 'handle': 'quoted.bsky.social'},
      'replyCount': 0,
      'repostCount': 0,
      'likeCount': 0,
      'hasMedia': false,
      'mediaCount': 0,
      'unavailable': false,
    },
  }),
);

/// The single loaded comment on 5(a): one reply exists on the server but is
/// not loaded, so collapsing shows a `+1` badge.
CommentsResponse _sensitiveComments() => CommentsResponse(
  post: null,
  comments: [
    ThreadViewComment(
      comment: CommentView(
        uri: 'at://did:plc:commenter/social.coves.community.comment/c1',
        cid: 'cid-c1',
        record: const CommentRecord(content: _commentBody),
        createdAt: _createdAt,
        indexedAt: _createdAt,
        author: AuthorView(did: 'did:plc:commenter', handle: 'commenter.test'),
        post: CommentRef(uri: _sensitiveUri, cid: 'cid-harbour'),
        stats: const CommentStats(replyCount: 1),
      ),
    ),
  ],
);

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late CommentsResponse commentsResponse;

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    when(auth.isAuthenticated).thenReturn(false);
    when(auth.did).thenReturn(null);
    when(votes.isLiked(any)).thenReturn(false);
    when(votes.getVoteState(any)).thenReturn(null);
    when(votes.isPending(any)).thenReturn(false);
    when(votes.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
    );
    commentsResponse = CommentsResponse(post: null, comments: []);
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((_) async => commentsResponse);
  });

  /// Mounts the real PostDetailScreen for [post] on a 400x900 phone, lets
  /// the comments load, then pins the clock.
  Future<void> pumpScreen(WidgetTester tester, FeedViewPost post) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          Provider<StreamableService>.value(value: StreamableService()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
        ],
        child: ImageCacheScope(
          cacheManager: FakeImageCacheManager(),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: PostDetailScreen(sessionStamp: null, post: post),
          ),
        ),
      ),
    );
    await _settle(tester);
    cache.peekProvider(post.post.uri)!.currentTimeNotifier.value = _currentTime;
    await tester.pump();
    // A nested SelectionContainer registers with its SelectionArea in a
    // post-frame flush; pump one more frame before the first gesture.
    await tester.pump();
  }

  /// Mounts 5(a) and reveals it with the sensitive banner.
  Future<void> pumpRevealedSensitive(WidgetTester tester) async {
    commentsResponse = _sensitiveComments();
    await pumpScreen(tester, _sensitiveCarouselPost());
    await tester.tap(find.byKey(const Key('sensitive-content-banner')));
    await _settle(tester);
  }

  void testScreen(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        cache.dispose();
        blocks.dispose();
      }
    }, variant: android);
  }

  testScreen('5(a) revealed sensitive post: Select all + Copy copies only '
      'the title and the body', (tester) async {
    final copied = _captureClipboard(tester);
    await pumpRevealedSensitive(tester);

    // The excluded content is on screen, so leaving it out of the clipboard
    // means the region excluded it, not that it never rendered.
    expect(find.text('We filled six bags.', findRichText: true), findsWidgets);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text(_commentBody, findRichText: true), findsWidgets);
    expect(
      find.descendant(of: find.byType(PostActionBar), matching: find.text('7')),
      findsOneWidget,
    );
    expect(find.text('@$_handle'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('sources.example.net'), findsOneWidget);

    await _longPressWord(tester, 'We filled six bags.', 'six');
    await _tapToolbar(tester, 'Select all');
    await _tapToolbar(tester, 'Copy');

    expect(copied, ['Harbour cleanup photos\nWe filled six bags.']);
  });

  testScreen('5(b) post sharing a Bluesky post: Select all + Copy copies only '
      'the title and the body', (tester) async {
    final copied = _captureClipboard(tester);
    await pumpScreen(tester, _quotePost());

    expect(find.text('Quoted bluesky words', findRichText: true), findsWidgets);

    await _longPressWord(tester, 'Quote post body.', 'body');
    await _tapToolbar(tester, 'Select all');
    await _tapToolbar(tester, 'Copy');

    expect(copied, ['Quote post title\nQuote post body.']);
  });

  testScreen('long-pressing a comment on 5(a) collapses it and starts no '
      'selection', (tester) async {
    // Answers the haptic call the long-press awaits; an unmocked platform
    // channel never replies under fake async.
    _captureClipboard(tester);
    await pumpRevealedSensitive(tester);
    final comment = find.text(_commentBody, findRichText: true);
    await tester.ensureVisible(comment.first);
    await _settle(tester);
    expect(find.text('+1'), findsNothing);

    await tester.longPress(comment.first);
    await _settle(tester);

    expect(find.text(_commentBody, findRichText: true), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    _expectNoSelectionUi(tester);
  });
}
