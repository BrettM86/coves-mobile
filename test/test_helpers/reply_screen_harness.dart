// A themed harness for ReplyScreen widget tests: a base route with the
// providers the reply screen reads, and ReplyScreen pushed on top so pops
// are visible.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'test_mocks.dart';

const replyHarnessPostUri = 'at://did:plc:test/social.coves.post.record/123';
const replyHarnessPostCid = 'test-post-cid';

/// The reply screen's submit callback.
typedef ReplySubmit = Future<void> Function(
  String content,
  List<RichTextFacet> facets,
  ImagesEmbedInput? embed,
);

/// Mocks, a real CommentsProvider for drafts, and the pump steps.
class ReplyScreenHarness {
  ReplyScreenHarness() {
    blockProvider = BlockProvider(apiService: api, authProvider: auth);
    // Signed-out rendering keeps CommentCard simple (no action menus)
    when(auth.isAuthenticated).thenReturn(false);
    when(auth.did).thenReturn('did:plc:testuser');
    when(vote.isLiked(any)).thenReturn(false);
    when(vote.getVoteState(any)).thenReturn(null);
    when(vote.isPending(any)).thenReturn(false);
    when(vote.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
    commentsProvider = CommentsProvider(
      auth,
      postUri: replyHarnessPostUri,
      postCid: replyHarnessPostCid,
      apiService: api,
      voteProvider: vote,
    );
  }

  final MockAuthProvider auth = MockAuthProvider();
  final MockCovesApiService api = MockCovesApiService();
  final MockVoteProvider vote = MockVoteProvider();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final BlockProvider blockProvider;
  late final CommentsProvider commentsProvider;

  void dispose() {
    commentsProvider.dispose();
    blockProvider.dispose();
  }

  /// A comment under the harness post to reply to.
  ThreadViewComment threadComment(String uri) => ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: CommentRecord(content: 'Parent comment for $uri'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      // No DID: the context preview then draws a plain circle instead of
      // fetching a default avatar, which these tests' real file IO would let
      // reach the platform cache plugins
      author: AuthorView(
        did: '',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      post: CommentRef(uri: replyHarnessPostUri, cid: replyHarnessPostCid),
      stats: const CommentStats(score: 10, upvotes: 12, downvotes: 2),
    ),
  );

  /// Pumps the base route under the app theme.
  Future<void> pumpBase(WidgetTester tester) async {
    // Without a mock handler, HapticFeedback.lightImpact() never completes
    // in widget tests
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: vote),
          ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
          Provider<CovesApiService>.value(value: api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('base route')),
        ),
      ),
    );
  }

  /// Pushes ReplyScreen for [comment] and settles the push, the draft
  /// restore and the delayed autofocus.
  Future<void> pushReply(
    WidgetTester tester, {
    required ThreadViewComment comment,
    ReplySubmit? onSubmit,
    ImagePreparer? imagePreparer,
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReplyScreen(
            comment: comment,
            commentsProvider: commentsProvider,
            imagePreparer: imagePreparer,
            onSubmit: onSubmit ?? (content, facets, embed) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Runs every listener added to [auth], as its notifyListeners would.
  /// Call it at most once per test: it captures through `verify`, which
  /// does not match the same calls again.
  void notifyAuthListeners() {
    final listeners = verify(auth.addListener(captureAny)).captured
        .cast<VoidCallback>();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Closes the top route with system back and lets its pop transition end.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  /// Closes the reply screen with its app-bar Cancel button.
  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }

  /// The Send pill's tap target (nearest GestureDetector around 'Send').
  GestureDetector sendButton(WidgetTester tester) =>
      tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('Send'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
}

/// The reply toolbar's Send control, found whether it shows 'Send' or the
/// in-flight spinner.
final replySendControl = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Send comment',
);

/// The reply toolbar's add-image control.
final replyAddImage = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Add image',
);
