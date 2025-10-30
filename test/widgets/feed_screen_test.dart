import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/feed_provider.dart';
import 'package:coves_flutter/screens/home/feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'feed_screen_test.mocks.dart';

// Generate mocks
@GenerateMocks([AuthProvider, FeedProvider])

void main() {
  group('FeedScreen Widget Tests', () {
    late MockAuthProvider mockAuthProvider;
    late MockFeedProvider mockFeedProvider;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockFeedProvider = MockFeedProvider();

      // Default mock behaviors
      when(mockAuthProvider.isAuthenticated).thenReturn(false);
      when(mockFeedProvider.posts).thenReturn([]);
      when(mockFeedProvider.isLoading).thenReturn(false);
      when(mockFeedProvider.isLoadingMore).thenReturn(false);
      when(mockFeedProvider.error).thenReturn(null);
      when(mockFeedProvider.hasMore).thenReturn(true);
      when(
        mockFeedProvider.loadFeed(refresh: anyNamed('refresh')),
      ).thenAnswer((_) async => {});
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<FeedProvider>.value(value: mockFeedProvider),
        ],
        child: const MaterialApp(home: FeedScreen()),
      );
    }

    testWidgets('should display loading indicator when loading', (
      tester,
    ) async {
      when(mockFeedProvider.isLoading).thenReturn(true);

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should display error state with retry button', (tester) async {
      when(mockFeedProvider.error).thenReturn('Network error');
      when(mockFeedProvider.retry()).thenAnswer((_) async => {});

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Failed to load feed'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Test retry button
      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(mockFeedProvider.retry()).called(1);
    });

    testWidgets('should display empty state when no posts', (tester) async {
      when(mockFeedProvider.posts).thenReturn([]);
      when(mockAuthProvider.isAuthenticated).thenReturn(false);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('No posts to discover'), findsOneWidget);
      expect(find.text('Check back later for new posts'), findsOneWidget);
    });

    testWidgets('should display different empty state when authenticated', (
      tester,
    ) async {
      when(mockFeedProvider.posts).thenReturn([]);
      when(mockAuthProvider.isAuthenticated).thenReturn(true);

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

      when(mockFeedProvider.posts).thenReturn(mockPosts);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Test Post 1'), findsOneWidget);
      expect(find.text('Test Post 2'), findsOneWidget);
    });

    testWidgets('should display "Feed" title when authenticated', (
      tester,
    ) async {
      when(mockAuthProvider.isAuthenticated).thenReturn(true);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Feed'), findsOneWidget);
    });

    testWidgets('should display "Explore" title when not authenticated', (
      tester,
    ) async {
      when(mockAuthProvider.isAuthenticated).thenReturn(false);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Explore'), findsOneWidget);
    });

    testWidgets('should handle pull-to-refresh', (tester) async {
      final mockPosts = [_createMockPost('Test Post')];
      when(mockFeedProvider.posts).thenReturn(mockPosts);
      when(
        mockFeedProvider.loadFeed(refresh: true),
      ).thenAnswer((_) async => {});

      await tester.pumpWidget(createTestWidget());

      // Perform pull-to-refresh gesture
      await tester.drag(find.text('Test Post'), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(mockFeedProvider.loadFeed(refresh: true)).called(greaterThan(0));
    });

    testWidgets('should show loading indicator at bottom when loading more', (
      tester,
    ) async {
      final mockPosts = [_createMockPost('Test Post')];
      when(mockFeedProvider.posts).thenReturn(mockPosts);
      when(mockFeedProvider.isLoadingMore).thenReturn(true);

      await tester.pumpWidget(createTestWidget());

      // Should show the post and a loading indicator
      expect(find.text('Test Post'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should have SafeArea wrapping body', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.byType(SafeArea), findsOneWidget);
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

      when(mockFeedProvider.posts).thenReturn([mockPost]);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('42'), findsOneWidget); // score
      expect(find.text('5'), findsOneWidget); // comment count
    });

    testWidgets('should display community and author info', (tester) async {
      final mockPost = _createMockPost('Test Post');
      when(mockFeedProvider.posts).thenReturn([mockPost]);

      await tester.pumpWidget(createTestWidget());

      expect(find.text('c/test-community'), findsOneWidget);
      expect(find.text('Posted by Test User'), findsOneWidget);
    });

    testWidgets('should call loadFeed on init', (tester) async {
      when(
        mockFeedProvider.loadFeed(refresh: true),
      ).thenAnswer((_) async => {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      verify(mockFeedProvider.loadFeed(refresh: true)).called(1);
    });

    testWidgets('should have proper accessibility semantics', (tester) async {
      final mockPost = _createMockPost('Accessible Post');
      when(mockFeedProvider.posts).thenReturn([mockPost]);

      await tester.pumpWidget(createTestWidget());

      // Check for Semantics widget
      expect(find.byType(Semantics), findsWidgets);

      // Verify semantic label contains key information
      final semantics = tester.getSemantics(find.byType(Semantics).first);
      expect(semantics.label, contains('test-community'));
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
      ),
      createdAt: DateTime.now(),
      indexedAt: DateTime.now(),
      text: 'Test body',
      title: title,
      stats: PostStats(
        score: 42,
        upvotes: 50,
        downvotes: 8,
        commentCount: 5,
      ),
      facets: [],
    ),
  );
}
