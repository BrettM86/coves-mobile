// The gallery page carried from the feed reaches the post screen's gallery
// through the real route handover (loader, screen, header), and a page the
// reader swipes to in the post survives the header scrolling away and back.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const indicatorKey = Key('detail-images-page-indicator');

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late List<Completer<CommentsResponse>> requests;

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
    requests = [];
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
    ).thenAnswer((_) {
      final request = Completer<CommentsResponse>();
      requests.add(request);
      return request.future;
    });
  });

  FeedViewPost post({int imageCount = 3}) => FeedViewPost(
    post: PostView(
      uri: postUri,
      cid: 'post-cid',
      rkey: 'post',
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      record: const PostRecord(title: 'Gallery post', content: 'Photos'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 40),
      embed: ImagesPostEmbed(
        type: 'social.coves.embed.images#view',
        images: [
          for (var i = 0; i < imageCount; i++)
            EmbedImage(
              thumb: 'https://cdn.test/t$i.jpg',
              fullsize: 'https://cdn.test/f$i.jpg',
            ),
        ],
        data: const {},
      ),
    ),
  );

  CommentsResponse manyComments() => CommentsResponse(
    post: null,
    comments: [
      for (var i = 0; i < 40; i++)
        ThreadViewComment(
          comment: CommentView(
            uri: 'at://did:plc:author/social.coves.community.comment/c$i',
            cid: 'cid-c$i',
            record: CommentRecord(content: 'Comment number $i'),
            createdAt: DateTime(2025),
            indexedAt: DateTime(2025),
            author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
            post: CommentRef(uri: postUri, cid: 'post-cid'),
            stats: const CommentStats(),
          ),
        ),
    ],
  );

  int dotsIndex(WidgetTester tester) => tester
      .widget<MediaPageDots>(
        find.descendant(
          of: find.byKey(indicatorKey),
          matching: find.byType(MediaPageDots),
          matchRoot: true,
        ),
      )
      .index;

  testWidgets('opens on the handed-over page and keeps a swiped page after '
      'the post scrolls away and back', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailLoader(
            postUri: postUri,
            loadedPost: PostDetailRouteExtra(
              post: post(),
              sessionStamp: null,
              initialImageIndex: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(dotsIndex(tester), 2, reason: 'opens on the feed page');

    requests.single.complete(manyComments());
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('detail-images-embed')),
      const Offset(250, 0),
    );
    await tester.pumpAndSettle();
    expect(dotsIndex(tester), 1);

    final list = find.byType(CustomScrollView).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -1500));
      // Not settle: reaching the end starts a load-more spinner.
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      find.byKey(indicatorKey),
      findsNothing,
      reason: 'the post header has scrolled away and been disposed',
    );
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, 1500));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(dotsIndex(tester), 1, reason: 'the swiped page, not the feed one');

    await tester.pumpWidget(const SizedBox.shrink());
    for (final request in requests) {
      if (!request.isCompleted) {
        request.complete(CommentsResponse(post: null, comments: []));
      }
    }
    await tester.pump();
    cache.dispose();
    blocks.dispose();
  });

  testWidgets('an edit that leaves fewer images than the page the reader was '
      'on reopens the gallery on the first page', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final broadcast = PostChangeBroadcast();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: broadcast),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailLoader(
            postUri: postUri,
            loadedPost: PostDetailRouteExtra(
              post: post(),
              sessionStamp: null,
              initialImageIndex: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    requests.single.complete(manyComments());
    await tester.pumpAndSettle();
    expect(dotsIndex(tester), 2);

    final list = find.byType(CustomScrollView).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -1500));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(indicatorKey), findsNothing);

    // An edit published while the header is away keeps two images.
    broadcast.replacePost(post(imageCount: 2).post);
    await tester.pump();

    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, 1500));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeException(), isNull);
    expect(dotsIndex(tester), 0);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final request in requests) {
      if (!request.isCompleted) {
        request.complete(CommentsResponse(post: null, comments: []));
      }
    }
    await tester.pump();
    cache.dispose();
    blocks.dispose();
  });
}
