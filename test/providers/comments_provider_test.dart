import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'comments_provider_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([AuthProvider, CovesApiService, VoteProvider, CommentService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommentsProvider', () {
    const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
    const testPostCid = 'test-post-cid';

    late CommentsProvider commentsProvider;
    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;
    late MockVoteProvider mockVoteProvider;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();
      mockVoteProvider = MockVoteProvider();

      // Default: user is authenticated
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(
        mockAuthProvider.getAccessToken(),
      ).thenAnswer((_) async => 'test-token');

      commentsProvider = CommentsProvider(
        mockAuthProvider,
        postUri: testPostUri,
        postCid: testPostCid,
        apiService: mockApiService,
        voteProvider: mockVoteProvider,
      );
    });

    tearDown(() {
      commentsProvider.dispose();
    });

    group('loadComments', () {
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

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.comments.length, 2);
        expect(commentsProvider.hasMore, true);
        expect(commentsProvider.error, null);
        expect(commentsProvider.isLoading, false);
      });

      test('should handle empty comments response', () async {
        final mockResponse = CommentsResponse(post: {}, comments: []);

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments();

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.hasMore, false);
      });

      // Note: "reset state when loading different post" test removed
      // Providers are now immutable per post - use CommentsProviderCache
      // to get separate providers for different posts

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

        // Start first load
        final firstFuture = commentsProvider.loadComments(refresh: true);

        // Try to load again while still loading - should schedule a refresh
        await commentsProvider.loadComments(refresh: true);

        await firstFuture;
        // Wait a bit for the pending refresh to execute
        await Future.delayed(const Duration(milliseconds: 200));

        // Should have called API twice - once for initial load, once for pending refresh
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).called(2);
      });

      test(
        'should initialize vote state from viewer data when authenticated',
        () async {
          final mockComments = [_createMockThreadComment('comment1')];

          final mockResponse = CommentsResponse(
            post: {},
            comments: mockComments,
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

          await commentsProvider.loadComments(refresh: true);

          expect(commentsProvider.comments.length, 1);
          expect(commentsProvider.error, null);
        },
      );

      test('should not initialize vote state when not authenticated', () async {
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        final mockResponse = CommentsResponse(
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
        ).thenAnswer((_) async => mockResponse);

        await commentsProvider.loadComments(refresh: true);

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
        );

        when(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer((_) async => initialResponse);

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.sort, 'hot');

        // Change sort option
        final newSortResponse = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadComment('comment2'),
            _createMockThreadComment('comment3'),
          ],
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

        await commentsProvider.setSortOption('new');

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

        await commentsProvider.loadComments(refresh: true);

        // Try to set same sort option
        await commentsProvider.setSortOption('hot');

        // Should only have been called once (initial load)
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
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

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.comments.length, 1);

        // Refresh
        final refreshResponse = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadComment('comment2'),
            _createMockThreadComment('comment3'),
          ],
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

      // Note: "should not refresh if no post loaded" test removed
      // Providers now always have a post URI at construction time
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

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.hasMore, true);

        // Load more
        final moreResponse = CommentsResponse(
          post: {},
          comments: [_createMockThreadComment('comment2')],
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

        await commentsProvider.loadComments(refresh: true);

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

      // Note: "should not load more if no post loaded" test removed
      // Providers now always have a post URI at construction time
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

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.error, isNotNull);

        // Retry with success
        final successResponse = CommentsResponse(
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
        ).thenAnswer((_) async => successResponse);

        await commentsProvider.retry();

        expect(commentsProvider.error, null);
        expect(commentsProvider.comments.length, 1);
      });
    });

    // Note: "Auth state changes" group removed
    // Sign-out cleanup is now handled by CommentsProviderCache which disposes
    // all cached providers when the user signs out. Individual providers no
    // longer have a reset() method.

    group('Time updates', () {
      test('should start time updates when comments are loaded', () async {
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

        expect(commentsProvider.currentTimeNotifier.value, null);

        await commentsProvider.loadComments(refresh: true);

        expect(commentsProvider.currentTimeNotifier.value, isNotNull);
      });

      test('should stop time updates on dispose', () async {
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

        await commentsProvider.loadComments(refresh: true);

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

        await commentsProvider.loadComments(refresh: true);

        expect(notificationCount, greaterThan(0));
      });

      test('should manage loading states correctly', () async {
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
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return response;
        });

        final loadFuture = commentsProvider.loadComments(refresh: true);

        // Should be loading
        expect(commentsProvider.isLoading, true);

        await loadFuture;

        // Should not be loading anymore
        expect(commentsProvider.isLoading, false);
      });
    });

    group('Vote state initialization from viewer data', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should initialize vote state when viewer.vote is "up"', () async {
        final response = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadCommentWithViewer(
              uri: 'comment1',
              vote: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ],
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

        await commentsProvider.loadComments(refresh: true);

        verify(
          mockVoteProvider.setInitialVoteState(
            postUri: 'comment1',
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
          ),
        ).called(1);
      });

      test('should initialize vote state when viewer.vote is "down"', () async {
        final response = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadCommentWithViewer(
              uri: 'comment1',
              vote: 'down',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ],
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

        await commentsProvider.loadComments(refresh: true);

        verify(
          mockVoteProvider.setInitialVoteState(
            postUri: 'comment1',
            voteDirection: 'down',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
          ),
        ).called(1);
      });

      test(
        'should clear stale vote state when viewer.vote is null on refresh',
        () async {
          final response = CommentsResponse(
            post: {},
            comments: [
              _createMockThreadCommentWithViewer(
                uri: 'comment1',
                vote: null,
                voteUri: null,
              ),
            ],
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

          await commentsProvider.loadComments(refresh: true);

          // Should call setInitialVoteState with null to clear stale state
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'comment1',
              voteDirection: null,
              voteUri: null,
            ),
          ).called(1);
        },
      );

      test(
        'should initialize vote state recursively for nested replies',
        () async {
          final response = CommentsResponse(
            post: {},
            comments: [
              _createMockThreadCommentWithViewer(
                uri: 'parent-comment',
                vote: 'up',
                voteUri: 'at://did:plc:test/social.coves.feed.vote/vote-parent',
                replies: [
                  _createMockThreadCommentWithViewer(
                    uri: 'reply-comment',
                    vote: 'down',
                    voteUri:
                        'at://did:plc:test/social.coves.feed.vote/vote-reply',
                  ),
                ],
              ),
            ],
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

          await commentsProvider.loadComments(refresh: true);

          // Should initialize vote state for both parent and reply
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'parent-comment',
              voteDirection: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote-parent',
            ),
          ).called(1);

          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'reply-comment',
              voteDirection: 'down',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote-reply',
            ),
          ).called(1);
        },
      );

      test('should initialize vote state for deeply nested replies', () async {
        final response = CommentsResponse(
          post: {},
          comments: [
            _createMockThreadCommentWithViewer(
              uri: 'level-0',
              vote: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote-0',
              replies: [
                _createMockThreadCommentWithViewer(
                  uri: 'level-1',
                  vote: 'up',
                  voteUri: 'at://did:plc:test/social.coves.feed.vote/vote-1',
                  replies: [
                    _createMockThreadCommentWithViewer(
                      uri: 'level-2',
                      vote: 'down',
                      voteUri:
                          'at://did:plc:test/social.coves.feed.vote/vote-2',
                    ),
                  ],
                ),
              ],
            ),
          ],
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

        await commentsProvider.loadComments(refresh: true);

        // Should initialize vote state for all 3 levels
        verify(
          mockVoteProvider.setInitialVoteState(
            postUri: anyNamed('postUri'),
            voteDirection: anyNamed('voteDirection'),
            voteUri: anyNamed('voteUri'),
          ),
        ).called(3);
      });

      test(
        'should only initialize vote state for new comments on pagination',
        () async {
          // First page: comment1 with upvote
          final page1Response = CommentsResponse(
            post: {},
            comments: [
              _createMockThreadCommentWithViewer(
                uri: 'comment1',
                vote: 'up',
                voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
              ),
            ],
            cursor: 'cursor1',
          );

          // Second page: comment2 with downvote
          final page2Response = CommentsResponse(
            post: {},
            comments: [
              _createMockThreadCommentWithViewer(
                uri: 'comment2',
                vote: 'down',
                voteUri: 'at://did:plc:test/social.coves.feed.vote/vote2',
              ),
            ],
          );

          // First call returns page 1
          when(
            mockApiService.getComments(
              postUri: anyNamed('postUri'),
              sort: anyNamed('sort'),
              timeframe: anyNamed('timeframe'),
              depth: anyNamed('depth'),
              limit: anyNamed('limit'),
              cursor: null,
            ),
          ).thenAnswer((_) async => page1Response);

          // Second call (with cursor) returns page 2
          when(
            mockApiService.getComments(
              postUri: anyNamed('postUri'),
              sort: anyNamed('sort'),
              timeframe: anyNamed('timeframe'),
              depth: anyNamed('depth'),
              limit: anyNamed('limit'),
              cursor: 'cursor1',
            ),
          ).thenAnswer((_) async => page2Response);

          // Load first page (refresh)
          await commentsProvider.loadComments(refresh: true);

          // Verify comment1 vote initialized
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'comment1',
              voteDirection: 'up',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote1',
            ),
          ).called(1);

          // Clear previous verifications
          clearInteractions(mockVoteProvider);

          // Load second page (pagination, not refresh)
          await commentsProvider.loadMoreComments();

          // Should ONLY initialize vote state for comment2 (new comments)
          // NOT re-initialize comment1 (which would wipe optimistic votes)
          verify(
            mockVoteProvider.setInitialVoteState(
              postUri: 'comment2',
              voteDirection: 'down',
              voteUri: 'at://did:plc:test/social.coves.feed.vote/vote2',
            ),
          ).called(1);

          // Verify comment1 was NOT re-initialized during pagination
          verifyNever(
            mockVoteProvider.setInitialVoteState(
              postUri: 'comment1',
              voteDirection: anyNamed('voteDirection'),
              voteUri: anyNamed('voteUri'),
            ),
          );
        },
      );
    });

    group('Collapsed comments', () {
      test('should toggle collapsed state for a comment', () {
        const commentUri = 'at://did:plc:test/comment/123';

        // Initially not collapsed
        expect(commentsProvider.isCollapsed(commentUri), false);
        expect(commentsProvider.collapsedComments.isEmpty, true);

        // Toggle to collapsed
        commentsProvider.toggleCollapsed(commentUri);

        expect(commentsProvider.isCollapsed(commentUri), true);
        expect(commentsProvider.collapsedComments.contains(commentUri), true);

        // Toggle back to expanded
        commentsProvider.toggleCollapsed(commentUri);

        expect(commentsProvider.isCollapsed(commentUri), false);
        expect(commentsProvider.collapsedComments.contains(commentUri), false);
      });

      test('should track multiple collapsed comments', () {
        const comment1 = 'at://did:plc:test/comment/1';
        const comment2 = 'at://did:plc:test/comment/2';
        const comment3 = 'at://did:plc:test/comment/3';

        commentsProvider
          ..toggleCollapsed(comment1)
          ..toggleCollapsed(comment2);

        expect(commentsProvider.isCollapsed(comment1), true);
        expect(commentsProvider.isCollapsed(comment2), true);
        expect(commentsProvider.isCollapsed(comment3), false);
        expect(commentsProvider.collapsedComments.length, 2);
      });

      test('should notify listeners when collapse state changes', () {
        var notificationCount = 0;
        commentsProvider.addListener(() {
          notificationCount++;
        });

        commentsProvider.toggleCollapsed('at://did:plc:test/comment/1');
        expect(notificationCount, 1);

        commentsProvider.toggleCollapsed('at://did:plc:test/comment/1');
        expect(notificationCount, 2);
      });

      // Note: "clear collapsed state on reset" test removed
      // Providers no longer have a reset() method - they are disposed entirely
      // when evicted from cache or on sign-out

      test('collapsedComments getter returns unmodifiable set', () {
        commentsProvider.toggleCollapsed('at://did:plc:test/comment/1');

        final collapsed = commentsProvider.collapsedComments;

        // Attempting to modify should throw
        expect(
          () => collapsed.add('at://did:plc:test/comment/2'),
          throwsUnsupportedError,
        );
      });

      // Note: "clear collapsed state on post change" test removed
      // Providers are now immutable per post - each post gets its own provider
      // with its own collapsed state. Use CommentsProviderCache to get different
      // providers for different posts.
    });

    group('createComment', () {
      late MockCommentService mockCommentService;
      late CommentsProvider providerWithCommentService;

      setUp(() {
        mockCommentService = MockCommentService();

        // Setup mock API service for loadComments
        final mockResponse = CommentsResponse(
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
        ).thenAnswer((_) async => mockResponse);

        providerWithCommentService = CommentsProvider(
          mockAuthProvider,
          postUri: testPostUri,
          postCid: testPostCid,
          apiService: mockApiService,
          voteProvider: mockVoteProvider,
          commentService: mockCommentService,
        );
      });

      tearDown(() {
        providerWithCommentService.dispose();
      });

      test('should throw ValidationException for empty content', () async {
        // First load comments to set up post context
        await providerWithCommentService.loadComments(refresh: true);

        expect(
          () => providerWithCommentService.createComment(content: ''),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });

      test(
        'should throw ValidationException for whitespace-only content',
        () async {
          await providerWithCommentService.loadComments(refresh: true);

          expect(
            () =>
                providerWithCommentService.createComment(content: '   \n\t  '),
            throwsA(isA<ValidationException>()),
          );
        },
      );

      test(
        'should throw ValidationException for content exceeding limit',
        () async {
          await providerWithCommentService.loadComments(refresh: true);

          // Create a string longer than 10000 characters
          final longContent = 'a' * 10001;

          expect(
            () =>
                providerWithCommentService.createComment(content: longContent),
            throwsA(
              isA<ValidationException>().having(
                (e) => e.message,
                'message',
                contains('too long'),
              ),
            ),
          );
        },
      );

      test('should count emoji correctly in character limit', () async {
        await providerWithCommentService.loadComments(refresh: true);

        // Each emoji should count as 1 character, not 2-4 bytes
        // 9999 'a' chars + 1 emoji = 10000 chars (should pass)
        final contentAtLimit = '${'a' * 9999}😀';

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/abc',
            cid: 'cid123',
          ),
        );

        // This should NOT throw
        await providerWithCommentService.createComment(content: contentAtLimit);

        verify(
          mockCommentService.createComment(
            rootUri: testPostUri,
            rootCid: testPostCid,
            parentUri: testPostUri,
            parentCid: testPostCid,
            content: contentAtLimit,
          ),
        ).called(1);
      });

      // Note: "should throw ApiException when no post loaded" test removed
      // Post context is now always provided via constructor - this case can't occur

      test('should throw ApiException when no CommentService', () async {
        // Create provider without CommentService
        final providerWithoutService = CommentsProvider(
          mockAuthProvider,
          postUri: testPostUri,
          postCid: testPostCid,
          apiService: mockApiService,
          voteProvider: mockVoteProvider,
        );

        expect(
          () => providerWithoutService.createComment(content: 'Test comment'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('CommentService not available'),
            ),
          ),
        );

        providerWithoutService.dispose();
      });

      test('should create top-level comment (reply to post)', () async {
        await providerWithCommentService.loadComments(refresh: true);

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/abc',
            cid: 'cid123',
          ),
        );

        await providerWithCommentService.createComment(
          content: 'This is a test comment',
        );

        // Verify the comment service was called with correct parameters
        // Root and parent should both be the post for top-level comments
        verify(
          mockCommentService.createComment(
            rootUri: testPostUri,
            rootCid: testPostCid,
            parentUri: testPostUri,
            parentCid: testPostCid,
            content: 'This is a test comment',
          ),
        ).called(1);
      });

      test('should create nested comment (reply to comment)', () async {
        await providerWithCommentService.loadComments(refresh: true);

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/reply1',
            cid: 'cidReply',
          ),
        );

        // Create a parent comment to reply to
        final parentComment = _createMockThreadComment('parent-comment');

        await providerWithCommentService.createComment(
          content: 'This is a nested reply',
          parentComment: parentComment,
        );

        // Root should still be the post, but parent should be the comment
        verify(
          mockCommentService.createComment(
            rootUri: testPostUri,
            rootCid: testPostCid,
            parentUri: 'parent-comment',
            parentCid: 'cid-parent-comment',
            content: 'This is a nested reply',
          ),
        ).called(1);
      });

      test('should trim content before sending', () async {
        await providerWithCommentService.loadComments(refresh: true);

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/abc',
            cid: 'cid123',
          ),
        );

        await providerWithCommentService.createComment(
          content: '  Hello world!  ',
        );

        // Verify trimmed content was sent
        verify(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: 'Hello world!',
          ),
        ).called(1);
      });

      test('should refresh comments after successful creation', () async {
        await providerWithCommentService.loadComments(refresh: true);

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/abc',
            cid: 'cid123',
          ),
        );

        await providerWithCommentService.createComment(content: 'Test comment');

        // Should have called getComments twice - once for initial load,
        // once for refresh after comment creation
        verify(
          mockApiService.getComments(
            postUri: anyNamed('postUri'),
            sort: anyNamed('sort'),
            timeframe: anyNamed('timeframe'),
            depth: anyNamed('depth'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).called(2);
      });

      test('should rethrow exception from CommentService', () async {
        await providerWithCommentService.loadComments(refresh: true);

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenThrow(ApiException('Network error'));

        expect(
          () =>
              providerWithCommentService.createComment(content: 'Test comment'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Network error'),
            ),
          ),
        );
      });

      test('should accept content at exactly max length', () async {
        await providerWithCommentService.loadComments(refresh: true);

        final contentAtLimit = 'a' * CommentsProvider.maxCommentLength;

        when(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
          ),
        ).thenAnswer(
          (_) async => const CreateCommentResponse(
            uri: 'at://did:plc:test/comment/abc',
            cid: 'cid123',
          ),
        );

        // Should not throw
        await providerWithCommentService.createComment(content: contentAtLimit);

        verify(
          mockCommentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: contentAtLimit,
          ),
        ).called(1);
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
      stats: CommentStats(score: 10, upvotes: 12, downvotes: 2),
    ),
  );
}

// Helper function to create mock comments with viewer state and optional replies
ThreadViewComment _createMockThreadCommentWithViewer({
  required String uri,
  String? vote,
  String? voteUri,
  List<ThreadViewComment>? replies,
}) {
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
      stats: CommentStats(score: 10, upvotes: 12, downvotes: 2),
      viewer: CommentViewerState(vote: vote, voteUri: voteUri),
    ),
    replies: replies,
  );
}
