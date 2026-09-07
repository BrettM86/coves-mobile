import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/123';
  const postCid = 'bafy-post-cid';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late CommentsProviderCache commentsCache;
  late List<({String postUri, String postCid, String direction})> voteRequests;

  FeedViewPost post() {
    return FeedViewPost(
      post: PostView(
        uri: postUri,
        cid: postCid,
        rkey: '123',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: const PostRecord(content: 'Vote adapter'),
        stats: PostStats(upvotes: 6, downvotes: 1, score: 5, commentCount: 0),
      ),
    );
  }

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    voteRequests = [];

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn('did:plc:viewer');
    when(mockVoteProvider.isLiked(postUri)).thenReturn(true);
    when(mockVoteProvider.getVoteState(postUri))
        .thenReturn(const VoteState(direction: 'up', deleted: false));
    when(mockVoteProvider.isPending(postUri)).thenReturn(true);
    when(mockVoteProvider.getAdjustedScore(postUri, 5)).thenReturn(6);
    when(
      mockVoteProvider.toggleVote(
        postUri: anyNamed('postUri'),
        postCid: anyNamed('postCid'),
        direction: anyNamed('direction'),
      ),
    ).thenAnswer((invocation) async {
      voteRequests.add((
        postUri: invocation.namedArguments[#postUri] as String,
        postCid: invocation.namedArguments[#postCid] as String,
        direction: invocation.namedArguments[#direction] as String,
      ));
      return true;
    });

    commentsCache = CommentsProviderCache(
      authProvider: mockAuthProvider,
      voteProvider: mockVoteProvider,
      commentService: MockCommentService(),
      apiService: MockCovesApiService(),
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<Object?>? hapticFuture,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) {
        if (hapticFuture != null &&
            methodCall.method == 'HapticFeedback.vibrate') {
          return hapticFuture;
        }
        return Future<Object?>.value();
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
      );
      commentsCache.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
          Provider<CommentsProviderCache>.value(value: commentsCache),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailScreen(post: post(), isOptimistic: true),
        ),
      ),
    );
    await tester.pump();
  }

  group('PostDetailScreen vote adapter', () {
    testWidgets('passes upvote, adjusted score, and pending lock to the bar', (
      tester,
    ) async {
      await pumpScreen(tester);

      final actionBar = tester.widget<PostActionBar>(
        find.byType(PostActionBar),
      );
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byTooltip('Remove downvote'), findsNothing);

      await tester.tap(find.byType(AnimatedHeartIcon));
      await tester.pumpAndSettle();

      expect(
        (
          upvoted: actionBar.isVoted,
          adjustedScore: actionBar.post.post.stats.score,
          pending: actionBar.isVotePending,
          pendingMutationCalls: voteRequests.length,
        ),
        (
          upvoted: true,
          adjustedScore: 6,
          pending: true,
          pendingMutationCalls: 0,
        ),
      );
    });

    testWidgets('authenticated detail upvote requests the up direction', (
      tester,
    ) async {
      when(mockVoteProvider.getVoteState(postUri)).thenReturn(null);
      when(mockVoteProvider.isPending(postUri)).thenReturn(false);
      await pumpScreen(tester);

      await tester.tap(find.byType(AnimatedHeartIcon));
      await tester.pumpAndSettle();

      expect(voteRequests, [
        (postUri: postUri, postCid: postCid, direction: 'up'),
      ]);
    });

    testWidgets(
      'starts detail upvote mutation before haptic feedback completes',
      (tester) async {
        when(mockVoteProvider.getVoteState(postUri)).thenReturn(null);
        when(mockVoteProvider.isPending(postUri)).thenReturn(false);
        final hapticGate = Completer<Object?>();
        addTearDown(() {
          if (!hapticGate.isCompleted) {
            hapticGate.complete(null);
          }
        });
        await pumpScreen(tester, hapticFuture: hapticGate.future);

        await tester.tap(find.byType(AnimatedHeartIcon));
        await tester.pump();

        try {
          expect(hapticGate.isCompleted, isFalse);
          expect(voteRequests, [
            (postUri: postUri, postCid: postCid, direction: 'up'),
          ]);
        } finally {
          if (!hapticGate.isCompleted) {
            hapticGate.complete(null);
          }
          await tester.pump();
        }
      },
    );
  });
}
