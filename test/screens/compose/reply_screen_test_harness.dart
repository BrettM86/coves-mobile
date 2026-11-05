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
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

// Shared generated mockito mocks (real provider types) so provider lookups
// inside CommentThread/CommentCard resolve correctly.
import '../../test_helpers/facet_description.dart';
import '../../test_helpers/test_mocks.dart';

export '../../test_helpers/facet_description.dart' show describeFacet;

const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
const testPostCid = 'test-post-cid';

/// A ReplyScreen pushed over a base route, with a real [CommentsProvider]
/// over mocks. Create one per test in setUp and [dispose] it in tearDown.
class ReplyScreenHarness {
  ReplyScreenHarness() {
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );

    // Signed-out rendering keeps CommentCard simple (no action menus)
    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockAuthProvider.did).thenReturn('did:plc:testuser');
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);

    // Real CommentsProvider over mocks: drafts are pure local state, so no
    // API stubbing is needed (ReplyScreen never triggers loadComments)
    commentsProvider = CommentsProvider(
      mockAuthProvider,
      postUri: testPostUri,
      postCid: testPostCid,
      apiService: mockApiService,
      voteProvider: mockVoteProvider,
    );
  }

  final MockAuthProvider mockAuthProvider = MockAuthProvider();
  final MockCovesApiService mockApiService = MockCovesApiService();
  final MockVoteProvider mockVoteProvider = MockVoteProvider();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final BlockProvider blockProvider;
  late final CommentsProvider commentsProvider;

  void dispose() {
    commentsProvider.dispose();
    blockProvider.dispose();
  }

  /// Pumps a base route; ReplyScreen is pushed on top so pops are visible
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
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
          ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
          Provider<CovesApiService>.value(value: mockApiService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('base route')),
        ),
      ),
    );
  }

  Future<void> pushReply(
    WidgetTester tester, {
    required ThreadViewComment comment,
    Future<void> Function(
      String content,
      List<RichTextFacet> facets,
      ImagesEmbedInput? embed,
    )?
    onSubmit,
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReplyScreen(
            comment: comment,
            commentsProvider: commentsProvider,
            onSubmit: onSubmit ?? (content, facets, embed) async {},
          ),
        ),
      ),
    );
    // Settles the push animation, draft restore, and the delayed autofocus
    await tester.pumpAndSettle();
  }

  /// Pushes ReplyScreen editing [comment]; the harness's CommentsProvider
  /// is passed only when [withCommentsProvider]
  Future<void> pushEdit(
    WidgetTester tester, {
    required CommentView comment,
    required Future<void> Function(String content, List<RichTextFacet> facets)
    onSubmit,
    bool withCommentsProvider = false,
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReplyScreen(
            editing: comment,
            commentsProvider: withCommentsProvider ? commentsProvider : null,
            onSubmit: (content, facets, embed) => onSubmit(content, facets),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pushes a reply to [parentUri], recording every submission as its
  /// content and [describeFacet] of each facet
  Future<List<(String, List<String>)>> openRecordingReply(
    WidgetTester tester, {
    String parentUri = 'at://did:plc:author/comment/1',
  }) async {
    final submissions = <(String, List<String>)>[];
    await pumpBase(tester);
    await pushReply(
      tester,
      comment: createComment(parentUri),
      onSubmit: (content, facets, embed) async {
        submissions.add((content, facets.map(describeFacet).toList()));
      },
    );
    return submissions;
  }
}

ThreadViewComment createComment(String uri) {
  return ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: CommentRecord(content: 'Parent comment for $uri'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      post: CommentRef(uri: testPostUri, cid: testPostCid),
      stats: const CommentStats(score: 10, upvotes: 12, downvotes: 2),
    ),
  );
}

/// The Send pill's tap target (nearest GestureDetector around 'Send')
GestureDetector sendButton(WidgetTester tester) {
  return tester.widget<GestureDetector>(
    find
        .ancestor(of: find.text('Send'), matching: find.byType(GestureDetector))
        .first,
  );
}

/// Taps Send and pumps a bounded number of frames: the in-flight spinner
/// animates indefinitely, so pumpAndSettle would time out. Two frames
/// cover the mention lookup, the onSubmit call, and the rebuild.
Future<void> tapSendAndPumpUntilInFlight(WidgetTester tester) async {
  await tester.tap(find.text('Send'));
  await tester.pump();
  await tester.pump();
}

/// The controller of the screen's body field, which must be a
/// [FacetTextField]
FacetEditingController fieldController(WidgetTester tester) {
  expect(
    find.byType(FacetTextField),
    findsOneWidget,
    reason: 'the body field is a FacetTextField',
  );
  return tester.widget<FacetTextField>(find.byType(FacetTextField)).controller;
}

/// System back, then pumps past the reverse page transition (longer than
/// any default Material transition) so the reply route is removed and its
/// State disposed before the send settles
Future<void> systemBackAndFinishTransition(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}
