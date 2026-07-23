import 'dart:async';

import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'vote_provider_test.mocks.dart';

// Generate mocks for VoteService and AuthProvider
@GenerateMocks([VoteService, AuthProvider])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoteProvider', () {
    late VoteProvider voteProvider;
    late MockVoteService mockVoteService;
    late MockAuthProvider mockAuthProvider;

    setUp(() {
      mockVoteService = MockVoteService();
      mockAuthProvider = MockAuthProvider();

      // Default: user is authenticated
      when(mockAuthProvider.isAuthenticated).thenReturn(true);

      voteProvider = VoteProvider(
        voteService: mockVoteService,
        authProvider: mockAuthProvider,
      );
    });

    tearDown(() {
      voteProvider.dispose();
    });

    group('toggleVote', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
      const testPostCid = 'bafy2bzacepostcid123';

      test('should create vote with optimistic update', () async {
        // Mock successful API response
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );

        var notificationCount = 0;
        voteProvider.addListener(() {
          notificationCount++;
        });

        // Initially not liked
        expect(voteProvider.isLiked(testPostUri), false);

        // Toggle vote
        final wasLiked = await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Should return true (vote created)
        expect(wasLiked, true);

        // Should be liked now
        expect(voteProvider.isLiked(testPostUri), true);

        // Should have notified listeners twice (optimistic + server response)
        expect(notificationCount, greaterThanOrEqualTo(2));

        // Vote state should be correct
        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'up');
        expect(voteState?.uri, 'at://did:plc:test/social.coves.feed.vote/456');
        expect(voteState?.deleted, false);
      });

      test('should remove vote when toggled off', () async {
        // First, set up initial vote state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Mock API response for toggling off
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) async => const VoteResponse(deleted: true));

        // Toggle vote off
        final wasLiked = await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Should return false (vote removed)
        expect(wasLiked, false);

        // Should not be liked anymore
        expect(voteProvider.isLiked(testPostUri), false);

        // Vote state should be marked as deleted
        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.deleted, true);
      });

      test('should rollback on API error', () async {
        // Set up initial state (not voted)
        expect(voteProvider.isLiked(testPostUri), false);

        // Mock API failure
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenThrow(ApiException('Network error', statusCode: 500));

        var notificationCount = 0;
        voteProvider.addListener(() {
          notificationCount++;
        });

        // Try to toggle vote
        expect(
          () => voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          ),
          throwsA(isA<ApiException>()),
        );

        // Should rollback to initial state (not liked)
        await Future.delayed(Duration.zero); // Wait for async completion
        expect(voteProvider.isLiked(testPostUri), false);
        expect(voteProvider.getVoteState(testPostUri), null);

        // Should have notified listeners (optimistic + rollback)
        expect(notificationCount, greaterThanOrEqualTo(2));
      });

      test('should rollback to previous state on error', () async {
        // Set up initial voted state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        final initialState = voteProvider.getVoteState(testPostUri);
        expect(voteProvider.isLiked(testPostUri), true);

        // Mock API failure when trying to toggle off
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenThrow(NetworkException('Connection failed'));

        // Try to toggle vote off
        expect(
          () => voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          ),
          throwsA(isA<ApiException>()),
        );

        // Should rollback to initial liked state
        await Future.delayed(Duration.zero); // Wait for async completion
        expect(voteProvider.isLiked(testPostUri), true);
        expect(voteProvider.getVoteState(testPostUri)?.uri, initialState?.uri);
      });

      test('should prevent concurrent requests for same post', () async {
        // Mock slow API response
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          );
        });

        // Start first request
        final future1 = voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Try to start second request before first completes
        final result2 = await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Second request should be ignored
        expect(result2, false);

        // First request should complete normally
        final result1 = await future1;
        expect(result1, true);

        // Should have only called API once
        verify(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).called(1);
      });

      test('should handle downvote direction', () async {
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );

        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
          direction: 'down',
        );

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'down');
        expect(voteState?.deleted, false);

        // Should not be "liked" (isLiked checks for 'up' direction)
        expect(voteProvider.isLiked(testPostUri), false);
      });
    });

    group('setInitialVoteState', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

      test('should set initial vote state from API data', () {
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'up');
        expect(voteState?.uri, 'at://did:plc:test/social.coves.feed.vote/456');
        expect(voteState?.deleted, false);
      });

      test('should set initial vote state with "down" direction', () {
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'down',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        // Should not be "liked" (isLiked checks for 'up' direction)
        expect(voteProvider.isLiked(testPostUri), false);

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'down');
        expect(voteState?.uri, 'at://did:plc:test/social.coves.feed.vote/456');
        expect(voteState?.deleted, false);
      });

      test('should extract rkey from voteUri', () {
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/3kbyxyz123',
        );

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.rkey, '3kbyxyz123');
      });

      test('should handle voteUri being null', () {
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
        );

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'up');
        expect(voteState?.uri, null);
        expect(voteState?.rkey, null);
        expect(voteState?.deleted, false);
      });

      test('should remove vote state when voteDirection is null', () {
        // First set a vote
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Then clear it
        voteProvider.setInitialVoteState(postUri: testPostUri);

        expect(voteProvider.isLiked(testPostUri), false);
        expect(voteProvider.getVoteState(testPostUri), null);
      });

      test('should clear stale vote state when refreshing with null vote', () {
        // Simulate initial state from previous session
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Simulate refresh where server returns viewer.vote = null
        // (user removed vote on another device)
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: null,
        );

        // Vote should be cleared
        expect(voteProvider.isLiked(testPostUri), false);
        expect(voteProvider.getVoteState(testPostUri), null);
      });

      test('should clear stale score adjustment on refresh', () async {
        // Simulate optimistic upvote that created a +1 adjustment
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );

        // Create vote - this sets _scoreAdjustments[testPostUri] = +1
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: 'bafy2bzacepostcid123',
        );

        // Verify adjustment exists
        const serverScore = 10;
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 11);

        // Now simulate a feed refresh - server returns fresh score (11)
        // which already includes the vote. The adjustment should be cleared.
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        // After refresh, adjustment should be cleared (server score is truth)
        // If we pass the NEW server score (11), we should get 11, not 12
        const freshServerScore = 11;
        expect(
          voteProvider.getAdjustedScore(testPostUri, freshServerScore),
          11,
        );
      });

      test('should not notify listeners when setting initial state', () {
        var notificationCount = 0;
        voteProvider
          ..addListener(() {
            notificationCount++;
          })
          ..setInitialVoteState(
            postUri: testPostUri,
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
          );

        // Should NOT notify listeners (silent initialization)
        expect(notificationCount, 0);
      });
    });

    group('VoteState.extractRkeyFromUri', () {
      test('should extract rkey from valid AT-URI', () {
        expect(
          VoteState.extractRkeyFromUri(
            'at://did:plc:test/social.coves.feed.vote/3kbyxyz123',
          ),
          '3kbyxyz123',
        );
      });

      test('should return null for null uri', () {
        expect(VoteState.extractRkeyFromUri(null), null);
      });

      test('should handle URI with no path segments', () {
        expect(VoteState.extractRkeyFromUri(''), '');
      });

      test('should handle complex rkey values', () {
        expect(
          VoteState.extractRkeyFromUri(
            'at://did:plc:abc123xyz/social.coves.feed.vote/3lbp7kw2abc',
          ),
          '3lbp7kw2abc',
        );
      });
    });

    group('clear', () {
      test('should clear all vote state', () {
        const post1 = 'at://did:plc:test/social.coves.post.record/1';
        const post2 = 'at://did:plc:test/social.coves.post.record/2';

        // Set up multiple votes
        voteProvider
          ..setInitialVoteState(
            postUri: post1,
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/1',
          )
          ..setInitialVoteState(
            postUri: post2,
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/2',
          );

        expect(voteProvider.isLiked(post1), true);
        expect(voteProvider.isLiked(post2), true);

        // Clear all
        voteProvider.clear();

        // Should have no votes
        expect(voteProvider.isLiked(post1), false);
        expect(voteProvider.isLiked(post2), false);
        expect(voteProvider.getVoteState(post1), null);
        expect(voteProvider.getVoteState(post2), null);
      });

      test('should notify listeners when cleared', () {
        var notificationCount = 0;
        voteProvider
          ..addListener(() {
            notificationCount++;
          })
          ..clear();

        expect(notificationCount, 1);
      });
    });

    group('isPending', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
      const testPostCid = 'bafy2bzacepostcid123';

      test('should return true while request is in progress', () async {
        // Mock slow API response
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          );
        });

        expect(voteProvider.isPending(testPostUri), false);

        // Start request
        final future = voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Give it time to set pending flag
        await Future.delayed(const Duration(milliseconds: 10));

        // Should be pending now
        expect(voteProvider.isPending(testPostUri), true);

        // Wait for completion
        await future;

        // Should not be pending anymore
        expect(voteProvider.isPending(testPostUri), false);
      });

      test('should return false for posts with no pending request', () {
        const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
        expect(voteProvider.isPending(testPostUri), false);
      });
    });

    group('Score adjustments', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
      const testPostCid = 'bafy2bzacepostcid123';

      test('should adjust score when creating upvote', () async {
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );

        // Initial score from server
        const serverScore = 10;

        // Before vote, adjustment should be 0
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 10);

        // Create upvote
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Should have +1 adjustment (upvote added)
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 11);
      });

      test('should adjust score when removing upvote', () async {
        // Set initial state with upvote
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) async => const VoteResponse(deleted: true));

        const serverScore = 10;

        // Before removing, adjustment should be 0 (server knows about upvote)
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 10);

        // Remove upvote
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        // Should have -1 adjustment (upvote removed)
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 9);
      });

      test('should adjust score when creating downvote', () async {
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.feed.vote/456',
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );

        const serverScore = 10;

        // Create downvote
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
          direction: 'down',
        );

        // Should have -1 adjustment (downvote added)
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 9);
      });

      test(
        'should adjust score when switching from upvote to downvote',
        () async {
          // Set initial state with upvote
          voteProvider.setInitialVoteState(
            postUri: testPostUri,
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
          );

          when(
            mockVoteService.createVote(
              postUri: anyNamed('postUri'),
              postCid: anyNamed('postCid'),
              direction: anyNamed('direction'),
            ),
          ).thenAnswer(
            (_) async => const VoteResponse(
              uri: 'at://did:plc:test/social.coves.feed.vote/789',
              cid: 'bafy789',
              rkey: '789',
              deleted: false,
            ),
          );

          const serverScore = 10;

          // Switch to downvote
          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
            direction: 'down',
          );

          // Should have -2 adjustment (remove +1, add -1)
          expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 8);
        },
      );

      test(
        'should adjust score when switching from downvote to upvote',
        () async {
          // Set initial state with downvote
          voteProvider.setInitialVoteState(
            postUri: testPostUri,
            voteDirection: 'down',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
          );

          when(
            mockVoteService.createVote(
              postUri: anyNamed('postUri'),
              postCid: anyNamed('postCid'),
              direction: anyNamed('direction'),
            ),
          ).thenAnswer(
            (_) async => const VoteResponse(
              uri: 'at://did:plc:test/social.coves.feed.vote/789',
              cid: 'bafy789',
              rkey: '789',
              deleted: false,
            ),
          );

          const serverScore = 10;

          // Switch to upvote
          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );

          // Should have +2 adjustment (remove -1, add +1)
          expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 12);
        },
      );

      test('should rollback score adjustment on error', () async {
        const serverScore = 10;

        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenThrow(ApiException('Network error', statusCode: 500));

        // Try to vote (will fail)
        expect(
          () => voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          ),
          throwsA(isA<ApiException>()),
        );

        await Future.delayed(Duration.zero);

        // Adjustment should be rolled back to 0
        expect(voteProvider.getAdjustedScore(testPostUri, serverScore), 10);
      });

      test('should clear score adjustments when clearing all state', () {
        const testPostUri1 = 'at://did:plc:test/social.coves.post.record/1';
        const testPostUri2 = 'at://did:plc:test/social.coves.post.record/2';

        // Manually set some adjustments (simulating votes)
        voteProvider
          ..setInitialVoteState(
            postUri: testPostUri1,
            voteDirection: 'up',
            voteUri: 'at://did:plc:test/social.coves.feed.vote/1',
          )
          ..clear();

        // Adjustments should be cleared (back to 0)
        expect(voteProvider.getAdjustedScore(testPostUri1, 10), 10);
        expect(voteProvider.getAdjustedScore(testPostUri2, 5), 5);
      });
    });

    group('reconcileVoteState', () {
      const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
      const testPostCid = 'bafy2bzacepostcid123';
      const testVoteUri = 'at://did:plc:test/social.coves.feed.vote/456';

      void stubCreateVote({bool deleted = false}) {
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer(
          (_) async => VoteResponse(
            uri: deleted ? null : testVoteUri,
            cid: deleted ? null : 'bafy123',
            rkey: deleted ? null : '456',
            deleted: deleted,
          ),
        );
      }

      test(
        'should clear stale adjustment when server confirms the like '
        '(double-count bug)',
        () async {
          stubCreateVote();

          // Like: server score 0 + optimistic adjustment = 1.
          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );
          expect(voteProvider.getAdjustedScore(testPostUri, 0), 1);

          // Focused-thread hydration re-delivers the node with fresh stats:
          // server score is now 1 (includes the vote) and viewer confirms it.
          voteProvider.reconcileVoteState(
            postUri: testPostUri,
            serverVoteDirection: 'up',
            serverVoteUri: testVoteUri,
          );

          // Without reconciliation this showed 2 (1 + stale adjustment).
          expect(voteProvider.getAdjustedScore(testPostUri, 1), 1);
          expect(voteProvider.isLiked(testPostUri), true);
        },
      );

      test(
        'should keep optimistic state when server has not indexed the vote',
        () async {
          stubCreateVote();

          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );

          // Server snapshot predates the vote: no viewer state, score 0.
          voteProvider.reconcileVoteState(postUri: testPostUri);

          // Stale server score + kept adjustment still renders correctly.
          expect(voteProvider.getAdjustedScore(testPostUri, 0), 1);
          expect(voteProvider.isLiked(testPostUri), true);
        },
      );

      test(
        'should keep the unlike when the server still reports the old vote '
        '(delete not yet indexed)',
        () async {
          // Liked at load time (server counted it, no adjustment).
          voteProvider.setInitialVoteState(
            postUri: testPostUri,
            voteDirection: 'up',
            voteUri: testVoteUri,
          );

          stubCreateVote(deleted: true);

          // Unlike: adjustment -1 against the old server score of 1.
          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );

          // Snapshot predates the unlike: server still says 'up', score 1.
          voteProvider.reconcileVoteState(
            postUri: testPostUri,
            serverVoteDirection: 'up',
            serverVoteUri: testVoteUri,
          );

          // Mismatch (local unliked vs server 'up') - the unlike must be
          // kept, not resurrected, and the -1 adjustment preserved.
          expect(voteProvider.isLiked(testPostUri), false);
          expect(voteProvider.getAdjustedScore(testPostUri, 1), 0);
        },
      );

      test('should reconcile a downvote the same as an upvote', () async {
        stubCreateVote();

        // Downvote: server score 5 + optimistic -1 = 4.
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
          direction: 'down',
        );
        expect(voteProvider.getAdjustedScore(testPostUri, 5), 4);

        // Server catches up: score 4 includes the downvote, viewer confirms.
        voteProvider.reconcileVoteState(
          postUri: testPostUri,
          serverVoteDirection: 'down',
          serverVoteUri: testVoteUri,
        );

        expect(voteProvider.getAdjustedScore(testPostUri, 4), 4);
        expect(voteProvider.getVoteState(testPostUri)?.direction, 'down');

        // A mismatching snapshot (server still 'up' from before a switch)
        // must not clear anything.
        voteProvider.reconcileVoteState(
          postUri: testPostUri,
          serverVoteDirection: 'up',
          serverVoteUri: testVoteUri,
        );
        expect(voteProvider.getVoteState(testPostUri)?.direction, 'down');
      });

      test(
        'should clear adjustment when server confirms an unlike',
        () async {
          // Liked at load time (server already counted it, no adjustment).
          voteProvider.setInitialVoteState(
            postUri: testPostUri,
            voteDirection: 'up',
            voteUri: testVoteUri,
          );

          stubCreateVote(deleted: true);

          // Unlike: adjustment -1 on the old server score of 1.
          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );
          expect(voteProvider.getAdjustedScore(testPostUri, 1), 0);

          // Fresh stats: server processed the unlike (score 0, no viewer
          // vote) - matches local effective state, so reconcile clears.
          voteProvider.reconcileVoteState(postUri: testPostUri);

          expect(voteProvider.getAdjustedScore(testPostUri, 0), 0);
          expect(voteProvider.isLiked(testPostUri), false);
        },
      );

      test('should do nothing while a vote request is in flight', () async {
        final completer = Completer<VoteResponse>();
        when(
          mockVoteService.createVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) => completer.future);

        // Start a vote but don't let it complete.
        final pending = voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );
        expect(voteProvider.isPending(testPostUri), true);

        // A snapshot arriving now predates the in-flight vote; even a
        // "matching" viewer state must not clear the optimistic adjustment.
        voteProvider.reconcileVoteState(
          postUri: testPostUri,
          serverVoteDirection: 'up',
          serverVoteUri: testVoteUri,
        );
        expect(voteProvider.getAdjustedScore(testPostUri, 0), 1);

        completer.complete(
          const VoteResponse(
            uri: testVoteUri,
            cid: 'bafy123',
            rkey: '456',
            deleted: false,
          ),
        );
        await pending;
      });

      test(
        'should prefer the locally known vote URI over a stale snapshot',
        () async {
          stubCreateVote();

          await voteProvider.toggleVote(
            postUri: testPostUri,
            postCid: testPostCid,
          );

          // Sibling-page snapshot carries an older vote record URI.
          voteProvider.reconcileVoteState(
            postUri: testPostUri,
            serverVoteDirection: 'up',
            serverVoteUri: 'at://did:plc:test/social.coves.feed.vote/OLD',
          );

          expect(voteProvider.getVoteState(testPostUri)?.uri, testVoteUri);
          expect(voteProvider.getVoteState(testPostUri)?.rkey, '456');
        },
      );

      test('should notify listeners when it clears an adjustment', () async {
        stubCreateVote();
        await voteProvider.toggleVote(
          postUri: testPostUri,
          postCid: testPostCid,
        );

        var notificationCount = 0;
        voteProvider
          ..addListener(() => notificationCount++)
          ..reconcileVoteState(
            postUri: testPostUri,
            serverVoteDirection: 'up',
            serverVoteUri: testVoteUri,
          );
        expect(notificationCount, 1);

        // Reconciling again is a no-op (no adjustment left) - no notify.
        voteProvider.reconcileVoteState(
          postUri: testPostUri,
          serverVoteDirection: 'up',
          serverVoteUri: testVoteUri,
        );
        expect(notificationCount, 1);
      });
    });

    group('Auth state listener', () {
      test('should clear votes when user signs out', () {
        const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

        // Set up vote state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Simulate sign out by changing auth state
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        // Trigger the auth listener by calling it directly
        // (In real app, this would be triggered by
        // AuthProvider.notifyListeners)
        voteProvider.clear();

        // Votes should be cleared
        expect(voteProvider.isLiked(testPostUri), false);
        expect(voteProvider.getVoteState(testPostUri), null);
      });

      test('should not clear votes when user is still authenticated', () {
        const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

        // Set up vote state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.feed.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Auth state remains authenticated
        when(mockAuthProvider.isAuthenticated).thenReturn(true);

        // Votes should NOT be cleared
        expect(voteProvider.isLiked(testPostUri), true);
      });
    });
  });
}
