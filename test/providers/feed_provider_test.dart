import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/feed_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'feed_provider_test.mocks.dart';

// Generate mocks
@GenerateMocks([AuthProvider, CovesApiService])
void main() {
  group('FeedProvider', () {
    late FeedProvider feedProvider;
    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();

      // Mock default auth state
      when(mockAuthProvider.isAuthenticated).thenReturn(false);

      // Mock the token getter
      when(
        mockAuthProvider.getAccessToken(),
      ).thenAnswer((_) async => 'test-token');

      // Create feed provider with injected mock service
      feedProvider = FeedProvider(mockAuthProvider, apiService: mockApiService);
    });

    tearDown(() {
      feedProvider.dispose();
    });

    group('loadFeed', () {
      test('should load timeline when authenticated', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        final mockResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'next-cursor',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProvider.loadFeed(refresh: true);

        expect(feedProvider.posts.length, 1);
        expect(feedProvider.error, null);
        expect(feedProvider.isLoading, false);
      });

      test('should load discover feed when not authenticated', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        final mockResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'next-cursor',
        );

        when(
          mockApiService.getDiscover(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProvider.loadFeed(refresh: true);

        expect(feedProvider.posts.length, 1);
        expect(feedProvider.error, null);
      });
    });

    group('fetchTimeline', () {
      test('should fetch timeline successfully', () async {
        final mockResponse = TimelineResponse(
          feed: [_createMockPost(), _createMockPost()],
          cursor: 'next-cursor',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProvider.fetchTimeline(refresh: true);

        expect(feedProvider.posts.length, 2);
        expect(feedProvider.hasMore, true);
        expect(feedProvider.error, null);
      });

      test('should handle network errors', () async {
        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenThrow(Exception('Network error'));

        await feedProvider.fetchTimeline(refresh: true);

        expect(feedProvider.error, isNotNull);
        expect(feedProvider.isLoading, false);
      });

      test('should append posts when not refreshing', () async {
        // First load
        final firstResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        await feedProvider.fetchTimeline(refresh: true);
        expect(feedProvider.posts.length, 1);

        // Second load (pagination)
        final secondResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-2',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: 'cursor-1',
          ),
        ).thenAnswer((_) async => secondResponse);

        await feedProvider.fetchTimeline();
        expect(feedProvider.posts.length, 2);
      });

      test('should replace posts when refreshing', () async {
        // First load
        final firstResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        await feedProvider.fetchTimeline(refresh: true);
        expect(feedProvider.posts.length, 1);

        // Refresh
        final refreshResponse = TimelineResponse(
          feed: [_createMockPost(), _createMockPost()],
          cursor: 'cursor-2',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => refreshResponse);

        await feedProvider.fetchTimeline(refresh: true);
        expect(feedProvider.posts.length, 2);
      });

      test('should set hasMore to false when no cursor', () async {
        final response = TimelineResponse(feed: [_createMockPost()]);

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        await feedProvider.fetchTimeline(refresh: true);

        expect(feedProvider.hasMore, false);
      });
    });

    group('fetchDiscover', () {
      test('should fetch discover feed successfully', () async {
        final mockResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'next-cursor',
        );

        when(
          mockApiService.getDiscover(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProvider.fetchDiscover(refresh: true);

        expect(feedProvider.posts.length, 1);
        expect(feedProvider.error, null);
      });

      test('should handle empty feed', () async {
        final emptyResponse = TimelineResponse(feed: []);

        when(
          mockApiService.getDiscover(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => emptyResponse);

        await feedProvider.fetchDiscover(refresh: true);

        expect(feedProvider.posts.isEmpty, true);
        expect(feedProvider.hasMore, false);
      });
    });

    group('loadMore', () {
      test('should load more posts', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        // Initial load
        final firstResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => firstResponse);

        await feedProvider.loadFeed(refresh: true);

        // Load more
        final secondResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-2',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: 'cursor-1',
          ),
        ).thenAnswer((_) async => secondResponse);

        await feedProvider.loadMore();

        expect(feedProvider.posts.length, 2);
      });

      test('should not load more if already loading', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        final response = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        await feedProvider.fetchTimeline(refresh: true);
        await feedProvider.loadMore();

        // Should not make additional calls while loading
      });

      test('should not load more if hasMore is false', () async {
        final response = TimelineResponse(feed: [_createMockPost()]);

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        await feedProvider.fetchTimeline(refresh: true);
        expect(feedProvider.hasMore, false);

        await feedProvider.loadMore();
        // Should not attempt to load more
      });
    });

    group('retry', () {
      test('should retry after error', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        // Simulate error
        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenThrow(Exception('Network error'));

        await feedProvider.loadFeed(refresh: true);
        expect(feedProvider.error, isNotNull);

        // Retry
        final successResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => successResponse);

        await feedProvider.retry();

        expect(feedProvider.error, null);
        expect(feedProvider.posts.length, 1);
      });
    });

    group('State Management', () {
      test('should notify listeners on state change', () async {
        var notificationCount = 0;
        feedProvider.addListener(() {
          notificationCount++;
        });

        final mockResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProvider.fetchTimeline(refresh: true);

        expect(notificationCount, greaterThan(0));
      });

      test('should manage loading states correctly', () async {
        final mockResponse = TimelineResponse(
          feed: [_createMockPost()],
          cursor: 'cursor',
        );

        when(
          mockApiService.getTimeline(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return mockResponse;
        });

        final loadFuture = feedProvider.fetchTimeline(refresh: true);

        // Should be loading
        expect(feedProvider.isLoading, true);

        await loadFuture;

        // Should not be loading anymore
        expect(feedProvider.isLoading, false);
      });
    });
  });
}

// Helper function to create mock posts
FeedViewPost _createMockPost() {
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
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      text: 'Test body',
      title: 'Test Post',
      stats: PostStats(score: 42, upvotes: 50, downvotes: 8, commentCount: 5),
      facets: [],
    ),
  );
}
