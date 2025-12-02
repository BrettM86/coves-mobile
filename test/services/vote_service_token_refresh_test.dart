import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoteService - Token Refresh on 401', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late VoteService voteService;

    // Track token refresh and sign-out calls
    int tokenRefreshCallCount = 0;
    int signOutCallCount = 0;
    CovesSession currentSession = const CovesSession(
      token: 'initial-token',
      did: 'did:plc:test123',
      sessionId: 'session123',
    );
    bool shouldRefreshSucceed = true;

    // Mock session getter
    Future<CovesSession?> mockSessionGetter() async {
      return currentSession;
    }

    // Mock DID getter
    String? mockDidGetter() {
      return currentSession.did;
    }

    // Mock token refresher
    Future<bool> mockTokenRefresher() async {
      tokenRefreshCallCount++;
      if (shouldRefreshSucceed) {
        // Simulate successful refresh by updating the session
        currentSession = const CovesSession(
          token: 'refreshed-token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );
        return true;
      }
      return false;
    }

    // Mock sign-out handler
    Future<void> mockSignOutHandler() async {
      signOutCallCount++;
    }

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);

      // Reset counters and state
      tokenRefreshCallCount = 0;
      signOutCallCount = 0;
      currentSession = const CovesSession(
        token: 'initial-token',
        did: 'did:plc:test123',
        sessionId: 'session123',
      );
      shouldRefreshSucceed = true;

      voteService = VoteService(
        dio: dio,
        sessionGetter: mockSessionGetter,
        didGetter: mockDidGetter,
        tokenRefresher: mockTokenRefresher,
        signOutHandler: mockSignOutHandler,
      );
    });

    test('should call token refresher on 401 response and retry once', () async {
      // This test verifies the interceptor detects 401, calls the refresher,
      // and only retries ONCE to prevent infinite loops.

      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // Mock will always return 401 (simulates scenario where even refresh doesn't help)
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.create',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        data: {
          'subject': {
            'uri': postUri,
            'cid': postCid,
          },
          'direction': 'up',
        },
      );

      // Make the request and expect it to fail (mock keeps returning 401)
      expect(
        () => voteService.createVote(
          postUri: postUri,
          postCid: postCid,
          direction: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify token refresh was called exactly once (proves interceptor works)
      expect(tokenRefreshCallCount, 1);

      // Verify token was updated by refresher
      expect(currentSession.token, 'refreshed-token');

      // Verify user was signed out after retry failed (proves retry limit works)
      expect(signOutCallCount, 1);
    });

    test('should sign out user if token refresh fails', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // Set refresh to fail
      shouldRefreshSucceed = false;

      // First request with expired token returns 401
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.create',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        data: {
          'subject': {
            'uri': postUri,
            'cid': postCid,
          },
          'direction': 'up',
        },
      );

      // Make the request and expect it to fail
      expect(
        () => voteService.createVote(
          postUri: postUri,
          postCid: postCid,
          direction: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify token refresh was attempted
      expect(tokenRefreshCallCount, 1);

      // Verify user was signed out after refresh failure
      expect(signOutCallCount, 1);
    });

    test('should handle 401 gracefully when no refresher is provided',
        () async {
      // Create a NEW dio instance to avoid sharing interceptors
      final dioNoRefresh = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      final dioAdapterNoRefresh = DioAdapter(dio: dioNoRefresh);

      // Create vote service without refresh capability
      final voteServiceNoRefresh = VoteService(
        dio: dioNoRefresh,
        sessionGetter: mockSessionGetter,
        didGetter: mockDidGetter,
        // No tokenRefresher provided
        // No signOutHandler provided
      );

      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // Request returns 401
      dioAdapterNoRefresh.onPost(
        '/xrpc/social.coves.feed.vote.create',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        data: {
          'subject': {
            'uri': postUri,
            'cid': postCid,
          },
          'direction': 'up',
        },
      );

      // Make the request and expect it to fail
      expect(
        () => voteServiceNoRefresh.createVote(
          postUri: postUri,
          postCid: postCid,
          direction: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify refresh was NOT called (no refresher provided)
      expect(tokenRefreshCallCount, 0);

      // Verify sign-out was NOT called (no handler provided)
      expect(signOutCallCount, 0);
    });

    test('should handle non-401 errors normally without refresh', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // Request returns 500 server error
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.create',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'Database connection failed',
        }),
        data: {
          'subject': {
            'uri': postUri,
            'cid': postCid,
          },
          'direction': 'up',
        },
      );

      // Make the request and expect it to fail
      expect(
        () => voteService.createVote(
          postUri: postUri,
          postCid: postCid,
          direction: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify refresh was NOT called (not a 401)
      expect(tokenRefreshCallCount, 0);

      // Verify sign-out was NOT called
      expect(signOutCallCount, 0);
    });

    test('should handle 401 on vote delete and retry', () async {
      const rkey = 'abc123';

      // Mock will always return 401
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.delete',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        data: {
          'rkey': rkey,
        },
      );

      // Create vote with existing vote (will trigger delete)
      expect(
        () => voteService.createVote(
          postUri: 'at://did:plc:test/social.coves.post.record/123',
          postCid: 'bafy123',
          direction: 'up',
          existingVoteRkey: rkey,
          existingVoteDirection: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify token refresh was called
      expect(tokenRefreshCallCount, 1);

      // Verify user was signed out after retry failed
      expect(signOutCallCount, 1);
    });

    test('should throw ApiException when session is null', () async {
      // Create service that returns null session
      final voteServiceNoSession = VoteService(
        dio: dio,
        sessionGetter: () async => null,
        didGetter: () => null,
        tokenRefresher: mockTokenRefresher,
        signOutHandler: mockSignOutHandler,
      );

      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // Make the request and expect it to fail before even calling the API
      expect(
        () => voteServiceNoSession.createVote(
          postUri: postUri,
          postCid: postCid,
          direction: 'up',
        ),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Token refresh should NOT be attempted (request never made it to the API)
      expect(tokenRefreshCallCount, 0);
      expect(signOutCallCount, 0);
    });

    test('should use fresh token from session on each request', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const postCid = 'bafy123';

      // First request succeeds
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.create',
        (server) => server.reply(200, {
          'uri': 'at://did:plc:test/social.coves.feed.vote/xyz',
          'cid': 'bafy456',
        }),
        data: {
          'subject': {
            'uri': postUri,
            'cid': postCid,
          },
          'direction': 'up',
        },
      );

      // Make first request
      await voteService.createVote(
        postUri: postUri,
        postCid: postCid,
        direction: 'up',
      );

      // Update session (simulate token rotation)
      currentSession = const CovesSession(
        token: 'rotated-token',
        did: 'did:plc:test123',
        sessionId: 'session123',
      );

      // Second request should use the new token
      dioAdapter.onPost(
        '/xrpc/social.coves.feed.vote.delete',
        (server) => server.reply(200, {}),
        data: {
          'rkey': 'xyz',
        },
      );

      // Make second request (delete vote)
      await voteService.createVote(
        postUri: postUri,
        postCid: postCid,
        direction: 'up',
        existingVoteRkey: 'xyz',
        existingVoteDirection: 'up',
      );

      // Verify no refresh was needed (tokens were valid)
      expect(tokenRefreshCallCount, 0);
    });
  });
}
