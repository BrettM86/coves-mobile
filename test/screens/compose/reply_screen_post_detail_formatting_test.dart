import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/test_mocks.dart';
import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import 'reply_screen_test_harness.dart' show describeFacet;

const _postUri = 'at://did:plc:author/social.coves.community.post/post';
const _postCid = 'post-cid';
const _parentUri = 'at://did:plc:author/social.coves.community.comment/parent';
const _replyUri = 'at://did:plc:viewer/social.coves.community.comment/reply';

ThreadViewComment _thread(
  String uri,
  CommentRecord record, {
  String authorDid = 'did:plc:author',
  List<ThreadViewComment>? replies,
}) {
  return ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: record,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: authorDid, handle: 'someone.test'),
      post: CommentRef(uri: _postUri, cid: _postCid),
      stats: const CommentStats(),
    ),
    replies: replies,
  );
}

/// The effective font weight of every character of the RichText that
/// renders exactly [text]
List<FontWeight?> _renderedWeights(WidgetTester tester, String text) {
  final finder = find.descendant(
    of: find.byType(CommentCard, skipOffstage: false),
    matching: find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
      skipOffstage: false,
    ),
  );
  expect(finder, findsOneWidget, reason: 'one comment renders "$text"');
  final weights = <FontWeight?>[];
  void visit(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (span is TextSpan) {
      weights.addAll(List.filled(span.text?.length ?? 0, style.fontWeight));
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }
  }

  visit(tester.widget<RichText>(finder).text, const TextStyle());
  return weights;
}

void main() {
  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late MockCommentService commentService;
  late BlockProvider blocks;
  late CommentsProviderCache cache;

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    commentService = MockCommentService();
    when(auth.isAuthenticated).thenReturn(true);
    when(auth.did).thenReturn('did:plc:viewer');
    when(votes.isLiked(any)).thenReturn(false);
    when(votes.getVoteState(any)).thenReturn(null);
    when(votes.isPending(any)).thenReturn(false);
    when(votes.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: commentService,
      apiService: api,
    );
  });

  testWidgets('a reply made bold from the post detail screen is sent with '
      'its bold facet and shows bold once the thread refetches', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // The card and the composer await haptics; answer the platform channel
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    const parentRecord = CommentRecord(content: 'Parent comment');
    var served = CommentsResponse(
      post: null,
      comments: [_thread(_parentUri, parentRecord)],
    );
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
    ).thenAnswer((_) async => served);

    final sent = <(String, String, List<String>)>[];
    when(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: anyNamed('content'),
        contentFacets: anyNamed('contentFacets'),
      ),
    ).thenAnswer((invocation) async {
      final content = invocation.namedArguments[#content] as String;
      final facets =
          invocation.namedArguments[#contentFacets] as List<RichTextFacet>? ??
          const [];
      sent.add((
        invocation.namedArguments[#parentUri] as String,
        content,
        facets.map(describeFacet).toList(),
      ));
      // The AppView serves the new comment with the facets it was sent
      served = CommentsResponse(
        post: null,
        comments: [
          _thread(
            _parentUri,
            parentRecord,
            replies: [
              _thread(
                _replyUri,
                CommentRecord(content: content, facets: facets),
                authorDid: 'did:plc:viewer',
              ),
            ],
          ),
        ],
      );
      return const CreateCommentResponse(uri: _replyUri, cid: 'reply-cid');
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailScreen(
            sessionStamp: null,
            post: FeedViewPost(
              post: PostView(
                uri: _postUri,
                cid: _postCid,
                rkey: 'post',
                author: AuthorView(
                  did: 'did:plc:author',
                  handle: 'author.test',
                ),
                community: CommunityRef(did: 'did:plc:community', name: 'test'),
                createdAt: DateTime(2025),
                indexedAt: DateTime(2025),
                record: const PostRecord(content: 'Formatting post'),
                stats: PostStats(
                  upvotes: 0,
                  downvotes: 0,
                  score: 0,
                  commentCount: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the parent card's own bottom-left padding, clear of the author
    // link, the body text, the menu and the vote controls
    await tester.ensureVisible(find.byType(CommentCard));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getBottomLeft(find.byType(CommentCard)) + const Offset(30, -4),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReplyScreen), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Shipping');
    await tester.pump();
    await focusField(
      tester,
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
    await tapButton(tester, 'Bold');
    await tester.tap(button('Send comment'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.$1, _parentUri);
    expect(sent.single.$2, 'Shipping');
    expect(sent.single.$3, [
      r'[0,8) [{"$type":"social.coves.richtext.facet#bold"}]',
    ]);
    expect(find.byType(ReplyScreen), findsNothing);
    expect(
      _renderedWeights(tester, 'Shipping'),
      List.filled(8, FontWeight.w700),
    );

    // Unmount before the shared cache is disposed; dispose inside the body
    // so the pending-timer and semantics-handle checks see them released.
    await tester.pumpWidget(const SizedBox.shrink());
    cache.dispose();
    blocks.dispose();
    semantics.dispose();
  });
}
