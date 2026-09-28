import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/comments_header.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

/// One getComments request the screen made, held open until the test
/// completes it.
class _CommentsRequest {
  _CommentsRequest({required this.cursor, required this.sort});

  final String? cursor;
  final String sort;
  final Completer<CommentsResponse> completer = Completer<CommentsResponse>();
}

void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const firstCursor = 'cursor-page-2';
  const sortFailureMessage = 'Failed to change sort order. Please try again.';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late List<_CommentsRequest> requests;

  ThreadViewComment thread(String rkey) {
    return ThreadViewComment(
      comment: CommentView(
        uri: 'at://did:plc:author/social.coves.community.comment/$rkey',
        cid: 'cid-$rkey',
        record: CommentRecord(content: 'Comment $rkey'),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: postUri, cid: postCid),
        stats: const CommentStats(),
      ),
    );
  }

  CommentsResponse page(String prefix, int count, {String? cursor}) {
    return CommentsResponse(
      post: null,
      cursor: cursor,
      comments: List.generate(count, (index) => thread('$prefix-$index')),
    );
  }

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    when(auth.isAuthenticated).thenReturn(false);
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
    ).thenAnswer((invocation) {
      final request = _CommentsRequest(
        cursor: invocation.namedArguments[#cursor] as String?,
        sort: invocation.namedArguments[#sort] as String? ?? 'hot',
      );
      requests.add(request);
      return request.completer.future;
    });
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VoteProvider>.value(value: votes),
      ChangeNotifierProvider<BlockProvider>.value(value: blocks),
      Provider<CommentsProviderCache>.value(value: cache),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: PostDetailScreen(
        post: FeedViewPost(
          post: PostView(
            uri: postUri,
            cid: postCid,
            rkey: 'post',
            author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
            community: CommunityRef(did: 'did:plc:community', name: 'test'),
            createdAt: DateTime(2025),
            indexedAt: DateTime(2025),
            record: const PostRecord(content: 'Pagination footer post'),
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 83,
            ),
          ),
        ),
      ),
    ),
  );

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// A fetch result reaches the provider a few microtask hops after the
  /// completer fires, which can be after the next frame; pump twice so the
  /// screen has rebuilt from it.
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Jump to the end of the lazy list; the extent is an estimate until the
  /// tail has been laid out, so repeat until it stops moving.
  Future<void> scrollToBottom(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final scroll = position(tester);
      if (scroll.pixels >= scroll.maxScrollExtent) {
        break;
      }
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
    }
  }

  /// Drag up at the bottom of the list, as a user would keep pulling for
  /// more after the footer appears.
  Future<void> dragAtBottom(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await scrollToBottom(tester);
  }

  Finder footerRetry() => find.descendant(
    of: find.byType(InlineError),
    matching: find.text('Retry'),
  );

  Future<void> tapFooterRetry(WidgetTester tester) async {
    await tester.ensureVisible(footerRetry());
    await tester.pump();
    await tester.tap(footerRetry());
    await tester.pump();
  }

  /// Open the CommentsHeader sort dropdown and pick [label].
  Future<void> selectSort(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(CommentsHeader),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Mount the screen and land [firstPage] as the first-page response.
  Future<CommentsProvider> openWithFirstPage(
    WidgetTester tester,
    CommentsResponse firstPage,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(requests, hasLength(1), reason: 'the screen loads the first page');
    expect(requests.single.cursor, isNull);
    requests.single.completer.complete(firstPage);
    await tester.pumpAndSettle();
    return cache.peekProvider(postUri)!;
  }

  void testScreen(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Unmount before disposing the shared cache, then settle anything
        // the test left in flight so no provider work outlives the test.
        await tester.pumpWidget(const SizedBox.shrink());
        for (final request in requests) {
          if (!request.completer.isCompleted) {
            request.completer.complete(page('teardown', 0));
          }
        }
        await tester.pump();
        cache.dispose();
        blocks.dispose();
      }
    });
  }

  testScreen(
    'W1: a failed load-more shows a footer error that stops the scroll '
    'trigger and whose Retry refetches the same cursor',
    (tester) async {
      final comments = await openWithFirstPage(
        tester,
        page('first', 80, cursor: firstCursor),
      );

      await scrollToBottom(tester);
      expect(requests, hasLength(2), reason: 'reaching the bottom loads more');
      expect(requests[1].cursor, firstCursor);

      requests[1].completer.completeError(ApiException('Load more failed'));
      await flush(tester);
      await scrollToBottom(tester);

      expect(comments.loadMoreError, isNotNull);
      expect(comments.error, isNull);
      expect(find.byType(FullScreenError), findsNothing);
      expect(
        find.byType(InlineError),
        findsOneWidget,
        reason: 'the load-more failure must be shown in the list footer',
      );

      for (var drag = 0; drag < 4; drag++) {
        await dragAtBottom(tester);
      }
      expect(
        requests,
        hasLength(2),
        reason: 'scrolling at the bottom must not re-fire the failed page',
      );

      await tapFooterRetry(tester);
      expect(requests, hasLength(3), reason: 'Retry issues one request');
      expect(requests[2].cursor, firstCursor);

      await dragAtBottom(tester);
      expect(
        requests,
        hasLength(3),
        reason: 'a retry in flight is not duplicated by scrolling',
      );

      requests[2].completer.complete(page('second', 3));
      await flush(tester);
      await scrollToBottom(tester);

      expect(find.byType(InlineError), findsNothing);
      expect(comments.loadMoreError, isNull);
      expect(find.text('Comment second-2'), findsOneWidget);
      expect(find.byType(FullScreenError), findsNothing);
    },
  );

  testScreen(
    'W2: a failed pull-to-refresh with comments on screen shows a footer '
    'error whose Retry refetches the first page',
    (tester) async {
      final comments = await openWithFirstPage(tester, page('first', 80));
      expect(comments.hasMore, isFalse);

      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(requests, hasLength(2), reason: 'pull-to-refresh fetches');
      expect(requests[1].cursor, isNull);

      requests[1].completer.completeError(ApiException('Refresh failed'));
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      expect(comments.error, isNotNull);
      expect(comments.loadMoreError, isNull);
      expect(find.byType(FullScreenError), findsNothing);
      expect(find.byType(InlineError), findsOneWidget);

      await tapFooterRetry(tester);
      expect(
        requests,
        hasLength(3),
        reason: 'the refresh-error footer Retry must refetch the first page',
      );
      expect(requests[2].cursor, isNull);
    },
  );

  testScreen('W2b: a failed provider refresh with more pages available shows a '
      'footer error whose Retry refetches the first page', (tester) async {
    final comments = await openWithFirstPage(
      tester,
      page('first', 1, cursor: firstCursor),
    );

    unawaited(comments.refreshComments());
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests[1].cursor, isNull);

    requests[1].completer.completeError(ApiException('Refresh failed'));
    await flush(tester);

    expect(comments.error, isNotNull);
    expect(find.byType(FullScreenError), findsNothing);
    expect(find.byType(InlineError), findsOneWidget);

    await tapFooterRetry(tester);
    final retried = requests.skip(2).toList();
    expect(
      retried.map((request) => request.cursor),
      [null],
      reason:
          'the refresh-error footer Retry must refetch the first page, '
          'not the next one',
    );
  });

  testScreen(
    'W3: with both a refresh error and a load-more error the footer shows '
    'one error whose Retry goes through load-more',
    (tester) async {
      final comments = await openWithFirstPage(
        tester,
        page('first', 80, cursor: firstCursor),
      );

      unawaited(comments.refreshComments());
      await tester.pump();
      expect(requests, hasLength(2));
      requests[1].completer.completeError(ApiException('Refresh failed'));
      await flush(tester);
      expect(comments.error, isNotNull);

      await scrollToBottom(tester);
      expect(requests, hasLength(3), reason: 'reaching the bottom loads more');
      expect(requests[2].cursor, firstCursor);
      requests[2].completer.completeError(ApiException('Load more failed'));
      await flush(tester);
      await scrollToBottom(tester);

      expect(comments.error, isNotNull);
      expect(comments.loadMoreError, isNotNull);
      expect(find.byType(FullScreenError), findsNothing);
      expect(find.byType(InlineError), findsOneWidget);

      await tapFooterRetry(tester);
      expect(
        requests,
        hasLength(4),
        reason: 'the load-more error takes precedence and its Retry refetches',
      );
      expect(requests[3].cursor, firstCursor);
    },
  );

  testScreen(
    'W4a: a failed current sort change shows the sort failure snackbar',
    (tester) async {
      final comments = await openWithFirstPage(
        tester,
        page('first', 5, cursor: firstCursor),
      );

      await selectSort(tester, 'Top');
      expect(requests, hasLength(2));
      expect(requests[1].sort, 'top');
      expect(requests[1].cursor, isNull);

      requests[1].completer.completeError(ApiException('Sort failed'));
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(sortFailureMessage), findsOneWidget);
      expect(comments.sort, 'hot');
      expect(find.byType(InlineError), findsNothing);
      expect(find.byType(FullScreenError), findsNothing);
    },
  );

  testScreen(
    'W4c: the sort failure snackbar Retry refetches the first page with the '
    'sort that failed',
    (tester) async {
      await openWithFirstPage(tester, page('first', 5, cursor: firstCursor));

      await selectSort(tester, 'Top');
      expect(requests, hasLength(2));
      requests[1].completer.completeError(ApiException('Sort failed'));
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(sortFailureMessage), findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await tester.pump();

      expect(
        requests,
        hasLength(3),
        reason: 'the snackbar Retry issues one request',
      );
      expect(requests[2].sort, 'top');
      expect(requests[2].cursor, isNull);
    },
  );

  testScreen('W4b:a sort change superseded by a newer successful one shows no '
      'snackbar', (tester) async {
    final comments = await openWithFirstPage(
      tester,
      page('first', 5, cursor: firstCursor),
    );

    await selectSort(tester, 'Top');
    expect(requests, hasLength(2));
    expect(requests[1].sort, 'top');

    await selectSort(tester, 'New');
    expect(requests, hasLength(3));
    expect(requests[2].sort, 'new');

    requests[1].completer.completeError(ApiException('Superseded sort failed'));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(sortFailureMessage), findsNothing);

    requests[2].completer.complete(page('newest', 5));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text(sortFailureMessage), findsNothing);
    expect(comments.sort, 'new');
    expect(find.text('Comment newest-0'), findsOneWidget);
    expect(find.byType(InlineError), findsNothing);
  });

  testScreen('W5: a failed first load shows the full-screen error', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(requests, hasLength(1));

    requests.single.completer.completeError(ApiException('First load failed'));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenError), findsOneWidget);
    expect(find.byType(InlineError), findsNothing);
  });

  group('error messages follow the failure type', () {
    const networkMessage = 'No connection. Please check your internet.';
    const serverMessage = 'Server error. Please try again later.';

    Finder textIn(Type errorWidget, String message) => find.descendant(
      of: find.byType(errorWidget),
      matching: find.text(message),
    );

    testScreen(
      'W6a: a load-more that fails with no connection says so in the footer',
      (tester) async {
        final comments = await openWithFirstPage(
          tester,
          page('first', 80, cursor: firstCursor),
        );

        await scrollToBottom(tester);
        expect(
          requests,
          hasLength(2),
          reason: 'reaching the bottom loads more',
        );
        expect(requests[1].cursor, firstCursor);

        requests[1].completer.completeError(
          NetworkException('Connection refused'),
        );
        await flush(tester);
        await scrollToBottom(tester);

        expect(comments.loadMoreError, isNotNull);
        expect(find.byType(InlineError), findsOneWidget);
        expect(
          textIn(InlineError, networkMessage),
          findsOneWidget,
          reason: 'the footer must describe a network failure as one',
        );
      },
    );

    testScreen(
      'W6b: a refresh that fails with no connection says so in the footer',
      (tester) async {
        final comments = await openWithFirstPage(tester, page('first', 1));

        unawaited(comments.refreshComments());
        await tester.pump();
        expect(requests, hasLength(2));
        expect(requests[1].cursor, isNull);

        requests[1].completer.completeError(
          NetworkException('Connection refused'),
        );
        await flush(tester);

        expect(comments.error, isNotNull);
        expect(find.byType(FullScreenError), findsNothing);
        expect(find.byType(InlineError), findsOneWidget);
        expect(
          textIn(InlineError, networkMessage),
          findsOneWidget,
          reason: 'the footer must describe a network failure as one',
        );
      },
    );

    testScreen(
      'W6c: a first load that fails with a server error says so full-screen',
      (tester) async {
        await tester.pumpWidget(app());
        await tester.pump();
        expect(requests, hasLength(1));

        requests.single.completer.completeError(
          ServerException('Internal server error', statusCode: 500),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FullScreenError), findsOneWidget);
        expect(
          textIn(FullScreenError, serverMessage),
          findsOneWidget,
          reason: 'the full-screen error must describe a server failure as one',
        );
      },
    );
  });
}
