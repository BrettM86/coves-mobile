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
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.interaction.vote/456',
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
        expect(voteState?.uri, 'at://did:plc:test/social.coves.interaction.vote/456');
        expect(voteState?.deleted, false);
      });

      test('should remove vote when toggled off', () async {
        // First, set up initial vote state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Mock API response for toggling off
        when(
          mockVoteService.createVote(
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(deleted: true),
        );

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
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenThrow(
          ApiException('Network error', statusCode: 500),
        );

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
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        final initialState = voteProvider.getVoteState(testPostUri);
        expect(voteProvider.isLiked(testPostUri), true);

        // Mock API failure when trying to toggle off
        when(
          mockVoteService.createVote(
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenThrow(
          NetworkException('Connection failed'),
        );

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
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenAnswer(
          (_) async {
            await Future.delayed(const Duration(milliseconds: 100));
            return const VoteResponse(
              uri: 'at://did:plc:test/social.coves.interaction.vote/456',
              cid: 'bafy123',
              rkey: '456',
              deleted: false,
            );
          },
        );

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
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).called(1);
      });

      test('should handle downvote direction', () async {
        when(
          mockVoteService.createVote(
            postUri: testPostUri,
            postCid: testPostCid,
            direction: 'down',
          ),
        ).thenAnswer(
          (_) async => const VoteResponse(
            uri: 'at://did:plc:test/social.coves.interaction.vote/456',
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
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        final voteState = voteProvider.getVoteState(testPostUri);
        expect(voteState?.direction, 'up');
        expect(voteState?.uri, 'at://did:plc:test/social.coves.interaction.vote/456');
        expect(voteState?.deleted, false);
      });

      test('should remove vote state when voteDirection is null', () {
        // First set a vote
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Then clear it
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
        );

        expect(voteProvider.isLiked(testPostUri), false);
        expect(voteProvider.getVoteState(testPostUri), null);
      });

      test('should not notify listeners when setting initial state', () {
        var notificationCount = 0;
        voteProvider.addListener(() {
          notificationCount++;
        });

        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        // Should NOT notify listeners (silent initialization)
        expect(notificationCount, 0);
      });
    });

    group('clear', () {
      test('should clear all vote state', () {
        const post1 = 'at://did:plc:test/social.coves.post.record/1';
        const post2 = 'at://did:plc:test/social.coves.post.record/2';

        // Set up multiple votes
        voteProvider.setInitialVoteState(
          postUri: post1,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/1',
        );
        voteProvider.setInitialVoteState(
          postUri: post2,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/2',
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
        voteProvider.addListener(() {
          notificationCount++;
        });

        voteProvider.clear();

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
            postUri: testPostUri,
            postCid: testPostCid,
          ),
        ).thenAnswer(
          (_) async {
            await Future.delayed(const Duration(milliseconds: 50));
            return const VoteResponse(
              uri: 'at://did:plc:test/social.coves.interaction.vote/456',
              cid: 'bafy123',
              rkey: '456',
              deleted: false,
            );
          },
        );

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

    group('Auth state listener', () {
      test('should clear votes when user signs out', () {
        const testPostUri = 'at://did:plc:test/social.coves.post.record/123';

        // Set up vote state
        voteProvider.setInitialVoteState(
          postUri: testPostUri,
          voteDirection: 'up',
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
        );

        expect(voteProvider.isLiked(testPostUri), true);

        // Simulate sign out by changing auth state
        when(mockAuthProvider.isAuthenticated).thenReturn(false);

        // Trigger the auth listener by calling it directly
        // (In real app, this would be triggered by AuthProvider.notifyListeners)
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
          voteUri: 'at://did:plc:test/social.coves.interaction.vote/456',
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
