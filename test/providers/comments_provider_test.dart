import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'comments_provider_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([AuthProvider, CovesApiService, VoteProvider, VoteService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommentsProvider', () {
    late CommentsProvider commentsProvider;
    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;
    late MockVoteProvider mockVoteProvider;
    late MockVoteService mockVoteService;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();
      mockVoteProvider = MockVoteProvider();
      mockVoteService = MockVoteService();

      // Default: user is authenticated
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.getAccessToken())
          .thenAnswer((_) async => 'test-token');

      commentsProvider = CommentsProvider(
        mockAuthProvider,
        apiService: mockApiService,
        voteProvider: mockVoteProvider,
        voteService: mockVoteService,
      );
    });

    tearDown(() {
      commentsProvider.dispose();
    });

    group('loadComments', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should load comments successfully', () async {
        final mockComments = [
          _createMockThreadComment('comment1'),
          _createMockThreadComment('comment2'),
        ];

        final mockResponse = CommentsResponse(
          post: {},
          comments: mockComments,
          cursor: 'next-cursor',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 2);
        expect(commentsProvider.hasMore, true);
        expect(commentsProvider.error, null);
        expect(commentsProvider.isLoading, false);
      });

      test('should handle empty comments response', () async {
        final mockResponse = CommentsResponse(
          post: {},
          comments: [],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.isEmpty, true);
        expect(commentsProvider.hasMore, false);
        expect(commentsProvider.error, null);
      });

      test('should handle network errors', () async {
        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenThrow(Exception('Network error'));

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.error, isNotNull);
        expect(commentsProvider.error, contains('Network error'));
        expect(commentsProvider.isLoading, false);
        expect(commentsProvider.comments.isEmpty, true);
      });

      test('should handle timeout errors', () async {
        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenThrow(Exception('TimeoutException: Request timed out'));

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.error, isNotNull);
        expect(commentsProvider.isLoading, false);
      });

      test('should append comments when not refreshing', () async {
        // First load
        final firstResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 1);

        // Second load (pagination)
        final secondResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment2')],
          cursor: 'cursor-2',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: 'cursor-1',
          ),
        ).thenAnswer((_) async => secondResponse);

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: false,
        );

        expect(commentsProvider.comments.length, 2);
        expect(commentsProvider.comments[0].comment.uri, 'comment1');
        expect(commentsProvider.comments[1].comment.uri, 'comment2');
      });

      test('should replace comments when refreshing', () async {
        // First load
        final firstResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 1);

        // Refresh with new data
        final refreshResponse = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadComment('comment2'),
            _createMockThreadComment('comment3'),
          ],
          cursor: 'cursor-2',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => refreshResponse);

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 2);
        expect(commentsProvider.comments[0].comment.uri, 'comment2');
        expect(commentsProvider.comments[1].comment.uri, 'comment3');
      });

      test('should set hasMore to false when no cursor', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.hasMore, false);
      });

      test('should reset state when loading different post', () async {
        // Load first post
        final firstResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => firstResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 1);

        // Load different post
        const differentPostUri = 'at://did:plc:test/social.coves.post.record/456';
        final secondResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment2')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: differentPostUri,
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => secondResponse);

        await commentsProvider.loadComments(
          postUri: differentPostUri,
          refresh: true,
        );

        // Should have reset and loaded new comments
        expect(commentsProvider.comments.length, 1);
        expect(commentsProvider.comments[0].comment.uri, 'comment2');
      });

      test('should not load when already loading', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return response;
        });

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        // Start first load
        final firstFuture = commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        // Try to load again while still loading
        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        await firstFuture;

        // Should only have called API once
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).called(1);
      });

      test('should load vote state when authenticated', () async {
        final mockComments = [_createMockThreadComment('comment1')];

        final mockResponse = CommentsResponse(
          post: {},
          comments: mockComments,
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        final mockUserVotes = <String, VoteInfo>{
          'comment1': const VoteInfo(
            voteUri: 'at://did:plc:test/social.coves.feed.vote/123',
            direction: 'up',
            rkey: '123',
          ),
        };

        when(mockVoteService.getUserVotes()).thenAnswer((_) async => mockUserVotes);
        when(mockVoteProvider.loadInitialVotes(any)).thenReturn(null);

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        verify(mockVoteService.getUserVotes()).called(1);
        verify(mockVoteProvider.loadInitialVotes(mockUserVotes)).called(1);
      });

      test('should not load vote state when not authenticated', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        final mockResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        verifyNever(mockVoteService.getUserVotes());
        verifyNever(mockVoteProvider.loadInitialVotes(any));
      });

      test('should continue loading comments if vote loading fails', () async {
        final mockComments = [_createMockThreadComment('comment1')];

        final mockResponse = CommentsResponse(
          post: {},
          comments: mockComments,
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => mockResponse);

        when(mockVoteService.getUserVotes())
            .thenThrow(Exception('Vote service error'));

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        // Comments should still be loaded despite vote error
        expect(commentsProvider.comments.length, 1);
        expect(commentsProvider.error, null);
      });
    });

    group('setSortOption', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should change sort option and reload comments', () async {
        // Initial load with default sort
        final initialResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: 'hot',
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => initialResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.sort, 'hot');

        // Change sort option
        final newSortResponse = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadComment('comment2'),
            _createMockThreadComment('comment3'),
          ],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: 'new',
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => newSortResponse);

        commentsProvider.setSortOption('new');

        // Wait for async load to complete
        await Future.delayed(const Duration(milliseconds: 100));

        expect(commentsProvider.sort, 'new');
        verify(
          mockApiService.getComments(
            postUri: testPostUri,
            sort: 'new',
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
          ),
        ).called(1);
      });

      test('should not reload if sort option is same', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        // Try to set same sort option
        commentsProvider.setSortOption('hot');

        await Future.delayed(const Duration(milliseconds: 100));

        // Should only have been called once (initial load)
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: 'hot',
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).called(1);
      });
    });

    group('refreshComments', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should refresh comments for current post', () async {
        final initialResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => initialResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 1);

        // Refresh
        final refreshResponse = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadComment('comment2'),
            _createMockThreadComment('comment3'),
          ],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: testPostUri,
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => refreshResponse);

        await commentsProvider.refreshComments();

        expect(commentsProvider.comments.length, 2);
      });

      test('should not refresh if no post loaded', () async {
        await commentsProvider.refreshComments();

        verifyNever(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        );
      });
    });

    group('loadMoreComments', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should load more comments when hasMore is true', () async {
        // Initial load
        final initialResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: 'cursor-1',
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => initialResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.hasMore, true);

        // Load more
        final moreResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment2')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: testPostUri,
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: 'cursor-1',
          ),
        ).thenAnswer((_) async => moreResponse);

        await commentsProvider.loadMoreComments();

        expect(commentsProvider.comments.length, 2);
        expect(commentsProvider.hasMore, false);
      });

      test('should not load more when hasMore is false', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.hasMore, false);

        // Try to load more
        await commentsProvider.loadMoreComments();

        // Should only have been called once (initial load)
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).called(1);
      });

      test('should not load more if no post loaded', () async {
        await commentsProvider.loadMoreComments();

        verifyNever(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        );
      });
    });

    group('retry', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should retry after error', () async {
        // Simulate error
        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenThrow(Exception('Network error'));

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.error, isNotNull);

        // Retry with success
        final successResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => successResponse);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.retry();

        expect(commentsProvider.error, null);
        expect(commentsProvider.comments.length, 1);
      });
    });

    group('Auth state changes', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should clear comments on sign-out', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: testPostUri,
          refresh: true,
        );

        expect(commentsProvider.comments.length, 1);

        // Simulate sign-out
        when(mockAuthProvider.isAuthenticated).thenReturn(false);
        // Trigger listener manually since we're using a mock
        commentsProvider.reset();

        expect(commentsProvider.comments.isEmpty, true);
      });
    });

    group('Time updates', () {
      test('should start time updates when comments are loaded', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        expect(commentsProvider.currentTimeNotifier.value, null);

        await commentsProvider.loadComments(
          postUri: 'at://did:plc:test/social.coves.post.record/123',
          refresh: true,
        );

        expect(commentsProvider.currentTimeNotifier.value, isNotNull);
      });

      test('should stop time updates on dispose', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: 'at://did:plc:test/social.coves.post.record/123',
          refresh: true,
        );

        expect(commentsProvider.currentTimeNotifier.value, isNotNull);

        // Call stopTimeUpdates to stop the timer
        commentsProvider.stopTimeUpdates();

        // After stopping time updates, value should be null
        expect(commentsProvider.currentTimeNotifier.value, null);
      });
    });

    group('State management', () {
      test('should notify listeners on state change', () async {
        var notificationCount = 0;
        commentsProvider.addListener(() {
          notificationCount++;
        });

        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => response);

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        await commentsProvider.loadComments(
          postUri: 'at://did:plc:test/social.coves.post.record/123',
          refresh: true,
        );

        expect(notificationCount, greaterThan(0));
      });

      test('should manage loading states correctly', () async {
        final response = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment1')],
          cursor: null,
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return response;
        });

        when(mockVoteService.getUserVotes())
            .thenAnswer((_) async => <String, VoteInfo>{});

        final loadFuture = commentsProvider.loadComments(
          postUri: 'at://did:plc:test/social.coves.post.record/123',
          refresh: true,
        );

        // Should be loading
        expect(commentsProvider.isLoading, true);

        await loadFuture;

        // Should not be loading anymore
        expect(commentsProvider.isLoading, false);
      });
    });
  });
}

// Helper function to create mock comments
ThreadViewComment _createMockThreadComment(String uri) {
  return ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      content: 'Test comment content',
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      post: CommentRef(
        uri: 'at://did:plc:test/social.coves.post.record/123',
        cid: 'post-cid',
      ),
      stats: CommentStats(
        score: 10,
        upvotes: 12,
        downvotes: 2,
      ),
    ),
  );
}
