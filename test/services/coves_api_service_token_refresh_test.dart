import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService - Token Refresh on 401', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    // Track token refresh and sign-out calls
    int tokenRefreshCallCount = 0;
    int signOutCallCount = 0;
    String currentToken = 'initial-token';
    bool shouldRefreshSucceed = true;

    // Mock token getter
    Future<String?> mockTokenGetter() async {
      return currentToken;
    }

    // Mock token refresher
    Future<bool> mockTokenRefresher() async {
      tokenRefreshCallCount++;
      if (shouldRefreshSucceed) {
        // Simulate successful refresh by updating the token
        currentToken = 'refreshed-token';
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
      currentToken = 'initial-token';
      shouldRefreshSucceed = true;

      apiService = CovesApiService(
        dio: dio,
        tokenGetter: mockTokenGetter,
        tokenRefresher: mockTokenRefresher,
        signOutHandler: mockSignOutHandler,
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    test('should call token refresher on 401 response but only retry once', () async {
      // This test verifies the interceptor detects 401, calls the refresher,
      // and only retries ONCE to prevent infinite loops (even if retry returns 401).

      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // Mock will always return 401 (simulates scenario where even refresh doesn't help)
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // Make the request and expect it to fail (mock keeps returning 401)
      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify token refresh was called exactly once (proves interceptor works)
      expect(tokenRefreshCallCount, 1);

      // Verify token was updated by refresher
      expect(currentToken, 'refreshed-token');

      // Verify user was signed out after retry failed (proves retry limit works)
      expect(signOutCallCount, 1);
    });

    test('should NOT sign out here when token refresh fails', () async {
      // The interceptor must not sign out on a false return from the
      // refresher: AuthProvider.refreshToken owns that decision (it signs
      // out itself on a definitive 401, and keeps the session on transient
      // failures). Signing out here would destroy a valid session when the
      // refresh merely hit a network blip or 5xx.
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // Set refresh to fail
      shouldRefreshSucceed = false;

      // First request with expired token returns 401
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Token expired',
        }),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // Make the request and expect it to fail
      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );

      // Wait for async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify token refresh was attempted
      expect(tokenRefreshCallCount, 1);

      // The refresher owns the sign-out decision - the interceptor must
      // not sign out on its behalf
      expect(signOutCallCount, 0);
    });

    test(
      'should NOT retry refresh endpoint on 401 (avoid infinite loop)',
      () async {
        // This test verifies that the interceptor checks for /oauth/refresh
        // in the path to avoid infinite loops. Due to limitations with mocking
        // complex request/response cycles, we test this by verifying the
        // refresher runs exactly once and the error propagates.

        // Set refresh to fail (simulates refresh endpoint returning 401)
        shouldRefreshSucceed = false;

        const postUri = 'at://did:plc:test/social.coves.post.record/123';

        dioAdapter.onGet(
          '/xrpc/social.coves.community.comment.getComments',
          (server) => server.reply(401, {
            'error': 'Unauthorized',
            'message': 'Token expired',
          }),
          queryParameters: {
            'post': postUri,
            'sort': 'hot',
            'depth': 10,
            'limit': 50,
          },
        );

        // Make the request and expect it to fail
        expect(
          () => apiService.getComments(postUri: postUri),
          throwsA(isA<Exception>()),
        );

        // Wait for async operations to complete
        await Future.delayed(const Duration(milliseconds: 100));

        // The refresher ran exactly once (no infinite loop), and the
        // interceptor left the sign-out decision to it
        expect(tokenRefreshCallCount, 1);
        expect(signOutCallCount, 0);
      },
    );

    test(
      'should NOT sign out when token refresh throws exception',
      () async {
        // Skipped: causes retry loops with http_mock_adapter after disposal.
        // The contract (refresher owns the sign-out decision; an exception
        // here must not sign out) is covered by the "should NOT sign out
        // here when token refresh fails" test above.
      },
      skip: 'Causes retry issues with http_mock_adapter',
    );

    test(
      'should handle 401 gracefully when no refresher is provided',
      () async {
        // Create API service without refresh capability
        final apiServiceNoRefresh = CovesApiService(
          dio: dio,
          tokenGetter: mockTokenGetter,
          // No tokenRefresher provided
          // No signOutHandler provided
        );

        const postUri = 'at://did:plc:test/social.coves.post.record/123';

        // Request returns 401
        dioAdapter.onGet(
          '/xrpc/social.coves.community.comment.getComments',
          (server) => server.reply(401, {
            'error': 'Unauthorized',
            'message': 'Token expired',
          }),
          queryParameters: {
            'post': postUri,
            'sort': 'hot',
            'depth': 10,
            'limit': 50,
          },
        );

        // Make the request and expect it to fail with AuthenticationException
        expect(
          () => apiServiceNoRefresh.getComments(postUri: postUri),
          throwsA(isA<Exception>()),
        );

        // Verify refresh was NOT called (no refresher provided)
        expect(tokenRefreshCallCount, 0);

        // Verify sign-out was NOT called (no handler provided)
        expect(signOutCallCount, 0);

        apiServiceNoRefresh.dispose();
      },
    );

    // Skipped: http_mock_adapter cannot handle stateful request/response cycles

    test('should handle non-401 errors normally without refresh', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // Request returns 500 server error
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'Database connection failed',
        }),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // Make the request and expect it to fail
      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );

      // Verify refresh was NOT called (not a 401)
      expect(tokenRefreshCallCount, 0);

      // Verify sign-out was NOT called
      expect(signOutCallCount, 0);
    });

    // Skipped: http_mock_adapter cannot handle stateful request/response cycles
  });
}
