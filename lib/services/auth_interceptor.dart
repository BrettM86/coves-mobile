import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'log_redaction.dart';

/// Creates a Dio interceptor that handles authentication and automatic
/// token refresh on 401 errors.
///
/// This shared utility is the single implementation used by
/// CovesApiService, VoteService, and CommentService of:
/// - Adding Authorization headers with fresh tokens on each request
///   (fetched per-request because atProto OAuth rotates tokens ~hourly;
///   caching a token would cause 401s after the first expiry)
/// - Automatic retry with token refresh on 401 responses
/// - Sign-out when a 401 persists after a successful refresh
///
/// Sign-out on refresh *failure* is deliberately NOT handled here: the
/// tokenRefresher (AuthProvider.refreshToken) owns that decision, because
/// only it can tell a definitive session rejection from a transient
/// network/server failure that must keep the session alive.
///
/// Usage:
/// ```dart
/// _dio.interceptors.add(
///   createAuthInterceptor(
///     tokenGetter: () async => authProvider.session?.token,
///     tokenRefresher: authProvider.refreshToken,
///     signOutHandler: authProvider.signOut,
///     serviceName: 'MyService',
///     dio: _dio,
///   ),
/// );
/// ```
InterceptorsWrapper createAuthInterceptor({
  required Future<String?> Function()? tokenGetter,
  required Future<bool> Function()? tokenRefresher,
  required Future<void> Function()? signOutHandler,
  required String serviceName,
  required Dio dio,
}) {
  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Fetch fresh token before each request
      final token = await tokenGetter?.call();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
        if (kDebugMode) {
          debugPrint('🔐 $serviceName: Adding fresh Authorization header');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '⚠️ $serviceName: No token available - '
            'making unauthenticated request',
          );
        }
      }
      return handler.next(options);
    },
    onError: (error, handler) async {
      // Handle 401 errors with automatic token refresh
      if (error.response?.statusCode == 401 && tokenRefresher != null) {
        if (kDebugMode) {
          debugPrint(
            '🔄 $serviceName: 401 detected, attempting token refresh...',
          );
        }

        // Don't retry the refresh endpoint itself (avoid infinite loop)
        final isRefreshEndpoint = error.requestOptions.path.contains(
          '/oauth/refresh',
        );
        if (isRefreshEndpoint) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ $serviceName: Refresh endpoint returned 401, '
              'signing out user',
            );
          }
          // Refresh endpoint failed, sign out the user
          if (signOutHandler != null) {
            await signOutHandler();
          }
          return handler.next(error);
        }

        // Check if we already retried this request (prevent infinite loop)
        if (error.requestOptions.extra['retried'] == true) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ $serviceName: Request already retried after token refresh, '
              'signing out user',
            );
          }
          // Already retried once, don't retry again
          if (signOutHandler != null) {
            await signOutHandler();
          }
          return handler.next(error);
        }

        try {
          // Attempt to refresh the token
          final refreshSucceeded = await tokenRefresher();

          if (refreshSucceeded) {
            if (kDebugMode) {
              debugPrint(
                '✅ $serviceName: Token refresh successful, retrying request',
              );
            }

            // Get the new token
            final newToken = await tokenGetter?.call();

            if (newToken != null) {
              // Mark this request as retried to prevent infinite loops
              error.requestOptions.extra['retried'] = true;

              // Update the Authorization header with the new token
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';

              // Retry the original request with the new token
              try {
                final response = await dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                // If retry failed with 401 and already retried, we already
                // signed out in the retry limit check above, so just pass
                // the error through without signing out again
                if (retryError.response?.statusCode == 401 &&
                    retryError.requestOptions.extra['retried'] == true) {
                  return handler.next(retryError);
                }
                // For other errors during retry, rethrow to outer catch
                rethrow;
              }
            }
          }

          // Refresh failed. Do NOT sign out here: the refresher owns that
          // decision and already signed out if the session was definitively
          // rejected. A false return may just mean a transient network
          // failure, and signing out would destroy a valid session.
          if (kDebugMode) {
            debugPrint(
              '❌ $serviceName: Token refresh failed, propagating error',
            );
          }
        } on Exception catch (e) {
          // Same rule as above: an exception here (from the refresher or
          // from retrying the original request) is not evidence the session
          // is dead, so never sign out - just propagate the error.
          if (kDebugMode) {
            debugPrint('❌ $serviceName: Error during token refresh: $e');
          }
        }
      }

      // Log the error for debugging
      if (kDebugMode) {
        debugPrint('❌ $serviceName API Error: ${error.message}');
        if (error.response != null) {
          debugPrint('   Status: ${error.response?.statusCode}');
          // Response data can echo credentials — redact before printing
          debugPrint(redactBearerTokens('   Data: ${error.response?.data}'));
        }
      }
      return handler.next(error);
    },
  );
}
