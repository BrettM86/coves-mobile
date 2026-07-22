import 'dart:async';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fake AuthProvider for testing (same convention as feed_screen_test.dart)
class FakeAuthProvider extends AuthProvider {
  bool _isAuthenticated = false;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get isLoading => false;

  void setAuthenticated({required bool value}) {
    _isAuthenticated = value;
    notifyListeners();
  }
}

void main() {
  const testUri = 'at://did:plc:test/social.coves.community.post/abc123';

  /// Asserts a full-screen terminal state renders [title] in its app bar
  /// and once more in the body content (NotFoundError shows it in both).
  void expectScreenTitle(String title) {
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(title)),
      findsOneWidget,
      reason: 'app bar should show "$title"',
    );
    expect(
      find.descendant(of: find.byType(Center), matching: find.text(title)),
      findsOneWidget,
      reason: 'body should show "$title"',
    );
  }

  /// Pumps the loader with an injectable fetcher.
  ///
  /// No providers are needed: the loader only touches AuthProvider when
  /// building its default fetcher, which the injected one replaces.
  Future<void> pumpLoader(
    WidgetTester tester, {
    required PostFetcher fetchPost,
    String postUri = testUri,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailLoader(postUri: postUri, fetchPost: fetchPost),
      ),
    );
  }

  /// Builds a minimal PostView for success-path tests
  PostView createMockPostView() {
    return PostView(
      uri: testUri,
      cid: 'test-cid',
      rkey: 'abc123',
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      community: CommunityRef(
        did: 'did:plc:community',
        name: 'test-community',
        handle: 'test-community.community.coves.social',
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(
        content: 'Test body',
        title: 'Cold Loaded Post',
        facets: [],
      ),
      stats: PostStats(score: 42, upvotes: 50, downvotes: 8, commentCount: 5),
    );
  }

  testWidgets('shows loading state with back button while fetching', (
    tester,
  ) async {
    // Fetcher that never completes keeps the loader in its loading state
    final completer = Completer<PostGetResult>();
    await pumpLoader(tester, fetchPost: (_) => completer.future);

    expect(find.byType(FullScreenLoading), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    // Complete so the pending timer/future doesn't leak into other tests
    completer.complete(const PostGetNotFound(testUri));
    await tester.pumpAndSettle();
  });

  testWidgets('shows not-found state when post does not exist', (
    tester,
  ) async {
    await pumpLoader(
      tester,
      fetchPost: (_) async => const PostGetNotFound(testUri),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundError), findsOneWidget);
    expectScreenTitle('Post Not Found');
  });

  testWidgets('renders PostDetailScreen on successful fetch', (tester) async {
    final fakeAuthProvider = FakeAuthProvider();
    final voteProvider = VoteProvider(
      voteService: VoteService(
        sessionGetter: () async => null,
        didGetter: () => null,
      ),
      authProvider: fakeAuthProvider,
    );
    final commentsCache = CommentsProviderCache(
      authProvider: fakeAuthProvider,
      voteProvider: voteProvider,
      commentService: CommentService(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: voteProvider),
          Provider<CommentsProviderCache>.value(value: commentsCache),
        ],
        child: MaterialApp(
          home: PostDetailLoader(
            postUri: testUri,
            fetchPost: (_) async => PostGetSuccess(createMockPostView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The loader's job ends at handing the post to PostDetailScreen.
    // (The screen's comments fetch fails at the test HTTP layer and shows
    // its own error state, so post content assertions belong to screen
    // tests with a stubbed comments pipeline.)
    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(find.byType(NotFoundError), findsNothing);

    // Unmount explicitly: PostDetailScreen.dispose calls context.read,
    // which throws a debug-only FlutterError during tree finalization
    // (pre-existing issue in post_detail_screen.dart, out of scope here).
    // Absorb that one known error so it doesn't fail the test teardown.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(tester.takeException(), isA<FlutterError>());
    await tester.pumpAndSettle();
  });

  testWidgets('shows blocked-author message for blocked posts', (
    tester,
  ) async {
    await pumpLoader(
      tester,
      fetchPost:
          (_) async =>
              const PostGetBlocked(uri: testUri, blockedBy: BlockedBy.author),
    );
    await tester.pumpAndSettle();

    expectScreenTitle('Post Unavailable');
    expect(
      find.text("This post is from an account you've blocked."),
      findsOneWidget,
    );
  });

  testWidgets('shows moderator message for moderator-blocked posts', (
    tester,
  ) async {
    await pumpLoader(
      tester,
      fetchPost:
          (_) async => const PostGetBlocked(
            uri: testUri,
            blockedBy: BlockedBy.moderator,
          ),
    );
    await tester.pumpAndSettle();

    expectScreenTitle('Post Unavailable');
    expect(find.text('This post was removed by moderators.'), findsOneWidget);
  });

  testWidgets('shows generic blocked message for unknown blockedBy', (
    tester,
  ) async {
    await pumpLoader(
      tester,
      fetchPost:
          (_) async =>
              const PostGetBlocked(uri: testUri, blockedBy: BlockedBy.unknown),
    );
    await tester.pumpAndSettle();

    expectScreenTitle('Post Unavailable');
    expect(
      find.text("This post is unavailable because it's from a blocked "
          'source.'),
      findsOneWidget,
    );
  });

  testWidgets('shows error state with retry, and retry re-fetches', (
    tester,
  ) async {
    var fetchCount = 0;
    await pumpLoader(
      tester,
      fetchPost: (_) async {
        fetchCount++;
        if (fetchCount == 1) {
          throw NetworkException('No connection');
        }
        return const PostGetNotFound(testUri);
      },
    );
    await tester.pumpAndSettle();

    // First fetch failed - error state with retry button
    expect(fetchCount, 1);
    expect(find.byType(FullScreenError), findsOneWidget);
    expect(find.text('Failed to load post'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Retry re-invokes the fetcher; second attempt resolves to not-found
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fetchCount, 2);
    expectScreenTitle('Post Not Found');
  });

  testWidgets('5xx from the server shows error state with retry', (
    tester,
  ) async {
    // A server error is transient - the loader must offer a retry rather
    // than collapsing to not-found (which only 400 should)
    await pumpLoader(
      tester,
      fetchPost:
          (_) async => throw ServerException('Server error', statusCode: 500),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenError), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(NotFoundError), findsNothing);
  });

  testWidgets('a thrown Error surfaces as error state, not forever-spinner', (
    tester,
  ) async {
    // Errors (TypeError, ArgumentError, ...) are not Exceptions; without a
    // broad catch they'd escape the fire-and-forget fetch and leave the
    // loader stuck on the spinner
    await pumpLoader(
      tester,
      fetchPost: (_) async => throw ArgumentError('bad parse'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenLoading), findsNothing);
    expect(find.byType(FullScreenError), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('400 from the server shows not-found instead of retry', (
    tester,
  ) async {
    // Backend returns InvalidRequest (400) for malformed AT-URIs - retrying
    // can never succeed, so the loader must not offer a retry
    await pumpLoader(
      tester,
      fetchPost:
          (_) async => throw ApiException('Invalid URI', statusCode: 400),
    );
    await tester.pumpAndSettle();

    expectScreenTitle('Post Not Found');
    expect(find.byType(FullScreenError), findsNothing);
  });

  testWidgets('invalid URI shows not-found without calling the fetcher', (
    tester,
  ) async {
    var fetchCount = 0;
    await pumpLoader(
      tester,
      postUri: 'https://example.com/not-an-at-uri',
      fetchPost: (_) async {
        fetchCount++;
        return const PostGetNotFound(testUri);
      },
    );
    await tester.pumpAndSettle();

    expect(fetchCount, 0);
    expectScreenTitle('Post Not Found');
  });

  testWidgets('navigating to a new postUri refetches (didUpdateWidget)', (
    tester,
  ) async {
    const secondUri = 'at://did:plc:test/social.coves.community.post/def456';
    const loaderKey = ValueKey('loader');

    final fetchedUris = <String>[];
    // First URI's fetch never completes until we say so - lets us verify
    // the staleness guard below
    final firstFetch = Completer<PostGetResult>();

    Future<PostGetResult> fetchPost(String uri) {
      fetchedUris.add(uri);
      if (uri == testUri) {
        return firstFetch.future;
      }
      return Future.value(const PostGetNotFound(secondUri));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailLoader(
          key: loaderKey,
          postUri: testUri,
          fetchPost: fetchPost,
        ),
      ),
    );
    await tester.pump();
    expect(fetchedUris, [testUri]);

    // Same key/position: the State is reused, so didUpdateWidget must
    // detect the new URI and refetch
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailLoader(
          key: loaderKey,
          postUri: secondUri,
          fetchPost: fetchPost,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fetchedUris, [testUri, secondUri]);
    expectScreenTitle('Post Not Found');

    // Stale first fetch completing late must NOT overwrite the newer result
    firstFetch.complete(
      const PostGetBlocked(uri: testUri, blockedBy: BlockedBy.author),
    );
    await tester.pumpAndSettle();

    expectScreenTitle('Post Not Found');
    expect(find.text('Post Unavailable'), findsNothing);
  });

  testWidgets('default fetcher resolves AuthProvider without throwing', (
    tester,
  ) async {
    // No injected fetcher: the loader must build its own CovesApiService
    // from AuthProvider. The test HTTP client fails every request, so the
    // loader should land in a terminal (error or not-found) state - the
    // point is that it never throws ProviderNotFoundException or hangs.
    final fakeAuthProvider = FakeAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: fakeAuthProvider,
        child: const MaterialApp(home: PostDetailLoader(postUri: testUri)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FullScreenLoading), findsNothing);
    final reachedTerminalState =
        tester.any(find.byType(NotFoundError)) ||
        tester.any(find.byType(FullScreenError));
    expect(reachedTerminalState, isTrue);

    // Unmount to exercise disposal of the lazily created API service
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
  });

  group('PostDetailScreen.displayedCommentCount', () {
    // The server-side commentCount includes comments the viewer never sees
    // (deleted, blocked, filtered). Only a fully resolved-but-empty thread
    // may show the header's empty state.
    test('shows 0 when the thread resolved empty with no more pages', () {
      expect(
        PostDetailScreen.displayedCommentCount(
          serverCount: 7,
          isLoading: false,
          hasError: false,
          hasComments: false,
          hasMore: false,
        ),
        0,
      );
    });

    test('keeps the server count while loading', () {
      expect(
        PostDetailScreen.displayedCommentCount(
          serverCount: 7,
          isLoading: true,
          hasError: false,
          hasComments: false,
          hasMore: false,
        ),
        7,
      );
    });

    test('keeps the server count when loading errored', () {
      expect(
        PostDetailScreen.displayedCommentCount(
          serverCount: 7,
          isLoading: false,
          hasError: true,
          hasComments: false,
          hasMore: false,
        ),
        7,
      );
    });

    test('keeps the server count while more pages may exist', () {
      expect(
        PostDetailScreen.displayedCommentCount(
          serverCount: 7,
          isLoading: false,
          hasError: false,
          hasComments: false,
          hasMore: true,
        ),
        7,
      );
    });

    test('keeps the server count when comments rendered', () {
      expect(
        PostDetailScreen.displayedCommentCount(
          serverCount: 7,
          isLoading: false,
          hasError: false,
          hasComments: true,
          hasMore: false,
        ),
        7,
      );
    });
  });
}
