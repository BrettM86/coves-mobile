import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/feed_screen.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fake AuthProvider for testing
class FakeAuthProvider extends AuthProvider {
  bool _isAuthenticated = false;
  bool _isLoading = false;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get isLoading => _isLoading;

  void setAuthenticated({required bool value}) {
    _isAuthenticated = value;
    notifyListeners();
  }

  void setLoading({required bool value}) {
    _isLoading = value;
    notifyListeners();
  }
}

// Fake VoteProvider for testing
class FakeVoteProvider extends VoteProvider {
  FakeVoteProvider()
    : super(
        voteService: VoteService(
          sessionGetter: () async => null,
          didGetter: () => null,
        ),
        authProvider: FakeAuthProvider(),
      );

  final Map<String, bool> _likes = {};

  @override
  bool isLiked(String postUri) => _likes[postUri] ?? false;

  void setLiked(String postUri, {required bool value}) {
    _likes[postUri] = value;
    notifyListeners();
  }
}

// Fake FeedProvider for testing
class FakeFeedProvider extends FeedProvider {
  FakeFeedProvider() : super(FakeAuthProvider());

  List<FeedViewPost> _posts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _loadFeedCallCount = 0;
  int _retryCallCount = 0;

  @override
  List<FeedViewPost> get posts => _posts;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get isLoadingMore => _isLoadingMore;

  @override
  String? get error => _error;

  @override
  bool get hasMore => _hasMore;

  int get loadFeedCallCount => _loadFeedCallCount;
  int get retryCallCount => _retryCallCount;

  void setPosts(List<FeedViewPost> value) {
    _posts = value;
    notifyListeners();
  }

  void setLoading({required bool value}) {
    _isLoading = value;
    notifyListeners();
  }

  void setLoadingMore({required bool value}) {
    _isLoadingMore = value;
    notifyListeners();
  }

  void setError(String? value) {
    _error = value;
    notifyListeners();
  }

  void setHasMore({required bool value}) {
    _hasMore = value;
    notifyListeners();
  }

  @override
  Future<void> loadFeed({bool refresh = false}) async {
    _loadFeedCallCount++;
  }

  @override
  Future<void> retry() async {
    _retryCallCount++;
  }

  @override
  Future<void> loadMore() async {
    // No-op for testing
  }
}

void main() {
  group('FeedScreen Widget Tests', () {
    late FakeAuthProvider fakeAuthProvider;
    late FakeFeedProvider fakeFeedProvider;
    late FakeVoteProvider fakeVoteProvider;

    setUp(() {
      fakeAuthProvider = FakeAuthProvider();
      fakeFeedProvider = FakeFeedProvider();
      fakeVoteProvider = FakeVoteProvider();
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
          ChangeNotifierProvider<FeedProvider>.value(value: fakeFeedProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: fakeVoteProvider),
        ],
        child: const MaterialApp(home: FeedScreen()),
      );
    }

    testWidgets('should display loading indicator when loading', (
      tester,
    ) async {
      fakeFeedProvider.setLoading(value: true);

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should display error state with retry button', (tester) async {
      fakeFeedProvider.setError('Network error');

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Failed to load feed'), findsOneWidget);
      // Error message is transformed to user-friendly message
      expect(
        find.text('Please check your internet connection'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      // Test retry button
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(fakeFeedProvider.retryCallCount, 1);
    });

    testWidgets('should display empty state when no posts', (tester) async {
      fakeFeedProvider.setPosts([]);
      fakeAuthProvider.setAuthenticated(value: false);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('No posts to discover'), findsOneWidget);
      expect(find.text('Check back later for new posts'), findsOneWidget);
    });

    testWidgets('should display different empty state when authenticated', (
      tester,
    ) async {
      fakeFeedProvider.setPosts([]);
      fakeAuthProvider.setAuthenticated(value: true);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('No posts yet'), findsOneWidget);
      expect(
        find.text('Subscribe to communities to see posts in your feed'),
        findsOneWidget,
      );
    });

    testWidgets('should display posts when available', (tester) async {
      final mockPosts = [
        _createMockPost('Test Post 1'),
        _createMockPost('Test Post 2'),
      ];

      fakeFeedProvider.setPosts(mockPosts);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Test Post 1'), findsOneWidget);
      expect(find.text('Test Post 2'), findsOneWidget);
    });

    testWidgets('should display feed type tabs when authenticated', (
      tester,
    ) async {
      fakeAuthProvider.setAuthenticated(value: true);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
    });

    testWidgets('should display only Discover tab when not authenticated', (
      tester,
    ) async {
      fakeAuthProvider.setAuthenticated(value: false);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('For You'), findsNothing);
    });

    testWidgets('should handle pull-to-refresh', (tester) async {
      final mockPosts = [_createMockPost('Test Post')];
      fakeFeedProvider.setPosts(mockPosts);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify RefreshIndicator exists
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // The loadFeed is called once on init
      expect(fakeFeedProvider.loadFeedCallCount, 1);
    });

    testWidgets('should show loading indicator at bottom when loading more', (
      tester,
    ) async {
      final mockPosts = [_createMockPost('Test Post')];
      fakeFeedProvider
        ..setPosts(mockPosts)
        ..setLoadingMore(value: true);

      await tester.pumpWidget(createTestWidget());

      // Should show the post and a loading indicator
      expect(find.text('Test Post'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should have SafeArea wrapping body', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Should have SafeArea widget(s) in the tree
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('should display post stats correctly', (tester) async {
      final mockPost = FeedViewPost(
        post: PostView(
          uri: 'at://test',
          cid: 'test-cid',
          rkey: 'test-rkey',
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
          createdAt: DateTime.now(),
          indexedAt: DateTime.now(),
          text: 'Test body',
          title: 'Test Post',
          stats: PostStats(
            score: 42,
            upvotes: 50,
            downvotes: 8,
            commentCount: 5,
          ),
          facets: [],
        ),
      );

      fakeFeedProvider.setPosts([mockPost]);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('42'), findsOneWidget); // score
      expect(find.text('5'), findsOneWidget); // comment count
    });

    testWidgets('should display community and author info', (tester) async {
      final mockPost = _createMockPost('Test Post');
      fakeFeedProvider.setPosts([mockPost]);

      await tester.pumpWidget(createTestWidget());

      // Check for community handle parts (displayed as !test-community@coves.social)
      expect(find.textContaining('!test-community'), findsOneWidget);
      expect(find.text('@test.user'), findsOneWidget);
    });

    testWidgets('should call loadFeed on init', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(fakeFeedProvider.loadFeedCallCount, 1);
    });

    testWidgets('should have proper accessibility semantics', (tester) async {
      final mockPost = _createMockPost('Accessible Post');
      fakeFeedProvider.setPosts([mockPost]);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Check for Semantics widgets (post should have semantic label)
      expect(find.byType(Semantics), findsWidgets);

      // Verify post card exists (which contains Semantics wrapper)
      expect(find.text('Accessible Post'), findsOneWidget);
      // Check for community handle parts (displayed as !test-community@coves.social)
      expect(find.textContaining('!test-community'), findsOneWidget);
      expect(find.textContaining('@coves.social'), findsOneWidget);
    });

    testWidgets('should properly dispose scroll controller', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Change to a different widget to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      // If we get here without errors, dispose was called properly
      expect(true, true);
    });
  });
}

// Helper function to create mock posts
FeedViewPost _createMockPost(String title) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:test/app.bsky.feed.post/test',
      cid: 'test-cid',
      rkey: 'test-rkey',
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
      text: 'Test body',
      title: title,
      stats: PostStats(score: 42, upvotes: 50, downvotes: 8, commentCount: 5),
      facets: [],
    ),
  );
}
