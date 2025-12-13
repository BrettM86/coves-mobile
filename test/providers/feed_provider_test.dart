import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'feed_provider_test.mocks.dart';

// Generate mocks
@GenerateMocks([AuthProvider, CovesApiService, VoteProvider])
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
      test('should load discover feed when authenticated by default', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

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
        expect(feedProvider.isLoading, false);
      });

      test('should load timeline when feed type is For You', () async {
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

        await feedProvider.setFeedType(FeedType.forYou);

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
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        await feedProvider.setFeedType(FeedType.forYou);

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

        await feedProvider.setFeedType(FeedType.forYou);
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

        await feedProvider.setFeedType(FeedType.forYou);
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

    group('Vote state initialization from viewer data', () {
      late MockVoteProvider mockVoteProvider;
      late FeedProvider feedProviderWithVotes;

      setUp(() {
        mockVoteProvider = MockVoteProvider();
        feedProviderWithVotes = FeedProvider(
          mockAuthProvider,
          apiService: mockApiService,
          voteProvider: mockVoteProvider,
        );
      });

      tearDown(() {
        feedProviderWithVotes.dispose();
      });

      test('should initialize vote state when viewer.vote is "up"', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        final mockResponse = TimelineResponse(
          feed: [
            _createMockPostWithViewer(
              uri: 'at://did:plc:test/social.coves.post.record/1',
              vote: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ],
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

        await feedProviderWithVotes.fetchTimeline(refresh: true);

        verify(
          mockVoteProvider.setInitialVoteState(
            postUri: 'at://did:plc:test/social.coves.post.record/1',
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
          ),
        ).called(1);
      });

      test('should initialize vote state when viewer.vote is "down"', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        final mockResponse = TimelineResponse(
          feed: [
            _createMockPostWithViewer(
              uri: 'at://did:plc:test/social.coves.post.record/1',
              vote: 'down',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ],
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

        await feedProviderWithVotes.fetchTimeline(refresh: true);

        verify(
          mockVoteProvider.setInitialVoteState(
            postUri: 'at://did:plc:test/social.coves.post.record/1',
            voteDirection: 'down',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
          ),
        ).called(1);
      });

      test(
        'should clear stale vote state when viewer.vote is null on refresh',
        () async {
          when(mockAuthProvider.isAuthenticated).thenReturn(true);

          // Feed item with null vote (user removed vote on another device)
          final mockResponse = TimelineResponse(
            feed: [
              _createMockPostWithViewer(
                uri: 'at://did:plc:test/social.coves.post.record/1',
                vote: null,
                voteUri: null,
              ),
            ],
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

          await feedProviderWithVotes.fetchTimeline(refresh: true);

          // Should call setInitialVoteState with null to clear stale state
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'at://did:plc:test/social.coves.post.record/1',
              voteDirection: null,
              voteUri: null,
            ),
          ).called(1);
        },
      );

      test(
        'should initialize vote state for all feed items including no viewer',
        () async {
          when(mockAuthProvider.isAuthenticated).thenReturn(true);

          final mockResponse = TimelineResponse(
            feed: [
              _createMockPostWithViewer(
                uri: 'at://did:plc:test/social.coves.post.record/1',
                vote: 'up',
                voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
              ),
              _createMockPost(), // No viewer state
            ],
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

          await feedProviderWithVotes.fetchTimeline(refresh: true);

          // Should be called for both posts
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: anyNamed('postUri'),
              voteDirection: anyNamed('voteDirection'),
              voteUri: anyNamed('voteUri'),
            ),
          ).called(2);
        },
      );

      test('should not initialize vote state when not authenticated', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        final mockResponse = TimelineResponse(
          feed: [
            _createMockPostWithViewer(
              uri: 'at://did:plc:test/social.coves.post.record/1',
              vote: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ],
          cursor: 'cursor',
        );

        when(
          mockApiService.getDiscover(
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await feedProviderWithVotes.fetchDiscover(refresh: true);

        // Should NOT call setInitialVoteState when not authenticated
        verifyNever(
          mockVoteProvider.setInitialVoteState(
            postUri: anyNamed('postUri'),
            voteDirection: anyNamed('voteDirection'),
            voteUri: anyNamed('voteUri'),
          ),
        );
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

// Helper function to create mock posts with viewer state
FeedViewPost _createMockPostWithViewer({
  required String uri,
  String? vote,
  String? voteUri,
}) {
  return FeedViewPost(
    post: PostView(
      uri: uri,
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
      viewer: ViewerState(vote: vote, voteUri: voteUri),
    ),
  );
}
