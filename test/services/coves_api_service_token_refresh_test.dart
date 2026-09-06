import 'package:coves_flutter/services/api_exceptions.dart';
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
    var tokenRefreshCallCount = 0;
    var signOutCallCount = 0;
    var currentToken = 'initial-token';
    var shouldRefreshSucceed = true;
    var shouldRefreshThrow = false;

    // Mock token getter
    Future<String?> mockTokenGetter() async {
      return currentToken;
    }

    // Mock token refresher
    Future<bool> mockTokenRefresher() async {
      tokenRefreshCallCount++;
      if (shouldRefreshThrow) {
        throw StateError('Token refresh unavailable');
      }
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
      shouldRefreshThrow = false;

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

    test('refreshes on 401 and retries only once', () async {
      // This test verifies the interceptor detects 401, calls the refresher,
      // and only retries once, even when that retry also returns 401.

      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // Always return 401 to simulate refresh not fixing the request.
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
      await expectLater(
        apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );

      // Verify token refresh was called exactly once (proves interceptor works)
      expect(tokenRefreshCallCount, 1);

      // Verify token was updated by refresher
      expect(currentToken, 'refreshed-token');

      // A failed retry signs the user out once.
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
      await expectLater(
        apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );

      // Verify token refresh was attempted
      expect(tokenRefreshCallCount, 1);

      // The refresher owns the sign-out decision - the interceptor must
      // not sign out on its behalf
      expect(signOutCallCount, 0);
    });

    // The refresh-endpoint guard (401 from /oauth/refresh must not trigger
    // another refresh) is tested directly in auth_interceptor_test.dart —
    // a previous test here claimed to cover it but only duplicated the
    // refresh-failure scenario above without driving that path.

    test('should NOT sign out when token refresh throws exception', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      shouldRefreshThrow = true;
      var requestCount = 0;
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.next(options);
          },
        ),
      );
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

      await expectLater(
        apiService.getComments(postUri: postUri),
        throwsA(
          isA<AuthenticationException>().having(
            (error) =>
                (error.originalError as DioException).response?.statusCode,
            'original response status',
            401,
          ),
        ),
      );

      expect(requestCount, 1);
      expect(tokenRefreshCallCount, 1);
      expect(signOutCallCount, 0);
      expect(currentToken, 'initial-token');
    });

    test(
      'should handle 401 gracefully when no refresher is provided',
      () async {
        // Use a separate client so the setUp service's refresh interceptor
        // cannot run on the service that intentionally has no refresher.
        final dioWithoutRefresh = Dio(
          BaseOptions(baseUrl: 'https://api.test.coves.social'),
        );
        final adapterWithoutRefresh = DioAdapter(dio: dioWithoutRefresh);
        final apiServiceNoRefresh = CovesApiService(
          dio: dioWithoutRefresh,
          tokenGetter: mockTokenGetter,
          // No tokenRefresher provided
          // No signOutHandler provided
        );

        const postUri = 'at://did:plc:test/social.coves.post.record/123';

        // Request returns 401
        adapterWithoutRefresh.onGet(
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
        await expectLater(
          apiServiceNoRefresh.getComments(postUri: postUri),
          throwsA(isA<Exception>()),
        );

        // Verify refresh was NOT called (no refresher provided)
        expect(tokenRefreshCallCount, 0);

        // Verify sign-out was NOT called (no handler provided)
        expect(signOutCallCount, 0);

        apiServiceNoRefresh.dispose();
      },
    );

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
      await expectLater(
        apiService.getComments(postUri: postUri),
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
