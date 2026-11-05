// The screens that open ReplyScreen forward its images embed, with the
// intended parent, to CommentsProvider.createComment.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

const _postUri = 'at://did:plc:author/social.coves.community.post/post';
const _postCid = 'post-cid';
const _commentUri = 'at://did:plc:author/social.coves.community.comment/first';
const _commentCid = 'cid-first';

ThreadViewComment _thread() => ThreadViewComment(
  comment: CommentView(
    uri: _commentUri,
    cid: _commentCid,
    record: const CommentRecord(content: 'Comment first'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    post: CommentRef(uri: _postUri, cid: _postCid),
    stats: const CommentStats(),
  ),
);

FeedViewPost _post() => FeedViewPost(
  post: PostView(
    uri: _postUri,
    cid: _postCid,
    rkey: 'post',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: 'Reply wiring post'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 1),
  ),
);

const _embed = ImagesEmbedInput(
  images: [
    EmbedImageInput(
      blob: {
        r'$type': 'blob',
        'ref': {r'$link': 'bafkrei-reply'},
        'mimeType': 'image/jpeg',
        'size': 1234,
      },
      alt: 'a cat',
    ),
  ],
);

/// Taps the comment card's own bottom-left padding, clear of the author
/// link, the body text, the menu and the vote controls.
Future<void> _tapComment(WidgetTester tester) async {
  final card = find.byType(CommentCard).first;
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getBottomLeft(card) + const Offset(30, -4));
  await tester.pumpAndSettle();
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
    ).thenAnswer(
      (_) async => CommentsResponse(post: null, comments: [_thread()]),
    );
    when(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: anyNamed('content'),
        contentFacets: anyNamed('contentFacets'),
        embed: anyNamed('embed'),
      ),
    ).thenAnswer(
      (_) async => const CreateCommentResponse(
        uri: 'at://did:plc:viewer/social.coves.community.comment/posted',
        cid: 'cid-posted',
      ),
    );
  });

  tearDown(() {
    cache.dispose();
    blocks.dispose();
  });

  Widget app(Widget home) => MultiProvider(
    providers: [
      Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VoteProvider>.value(value: votes),
      ChangeNotifierProvider<BlockProvider>.value(value: blocks),
      Provider<CommentsProviderCache>.value(value: cache),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );

  Widget postDetail() => PostDetailScreen(sessionStamp: null, post: _post());

  final rows =
      <
        ({
          String name,
          Future<void> Function(WidgetTester tester) open,
          String parentUri,
          String parentCid,
        })
      >[
        (
          name: 'PostDetailScreen reply to the post',
          open: (tester) async {
            await tester.pumpWidget(app(postDetail()));
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(PostActionBar),
                matching: find.text('Comment'),
              ),
            );
            await tester.pumpAndSettle();
          },
          parentUri: _postUri,
          parentCid: _postCid,
        ),
        (
          name: 'PostDetailScreen reply to a comment',
          open: (tester) async {
            await tester.pumpWidget(app(postDetail()));
            await tester.pumpAndSettle();
            await _tapComment(tester);
          },
          parentUri: _commentUri,
          parentCid: _commentCid,
        ),
        (
          name: 'FocusedThreadScreen reply to the anchor',
          open: (tester) async {
            final provider = cache.acquireProvider(
              postUri: _postUri,
              postCid: _postCid,
            );
            addTearDown(() => cache.releaseProvider(_postUri));
            await tester.pumpWidget(
              app(
                FocusedThreadScreen(
                  thread: _thread(),
                  ancestors: const [],
                  commentsProvider: provider,
                  parentPost: _post().post,
                ),
              ),
            );
            await tester.pumpAndSettle();
            await _tapComment(tester);
          },
          parentUri: _commentUri,
          parentCid: _commentCid,
        ),
      ];

  for (final row in rows) {
    testWidgets('B8 ${row.name} passes the reply screen embed and the parent '
        'to createComment', (tester) async {
      // The card awaits a haptic before calling onTap; answer the platform
      // channel so that await completes under the test binding.
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

      await row.open(tester);
      final composer = find.byType(ReplyScreen);
      expect(composer, findsOneWidget, reason: 'the reply screen opened');

      Object? failure;
      unawaited(
        tester
            .widget<ReplyScreen>(composer)
            .onSubmit('', const [], _embed)
            .then<void>((_) {}, onError: (Object error) => failure = error),
      );
      // Lets the provider's post-create refresh and its bounded indexing
      // retries run out.
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      final captured = verify(
        commentService.createComment(
          rootUri: _postUri,
          rootCid: _postCid,
          parentUri: captureAnyNamed('parentUri'),
          parentCid: captureAnyNamed('parentCid'),
          content: '',
          contentFacets: anyNamed('contentFacets'),
          embed: captureAnyNamed('embed'),
        ),
      ).captured;
      expect(captured, [row.parentUri, row.parentCid, same(_embed)]);
      expect(failure, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // The released provider stays cached with its periodic timestamp
      // timer running; dispose it before the test's timer invariant runs.
      cache.clearAll();
    });
  }
}
