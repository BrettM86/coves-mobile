import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/coves_session.dart';

/// Creates a Dio interceptor that handles authentication and automatic
/// token refresh on 401 errors.
///
/// This shared utility eliminates duplication between VoteService and
/// CommentService by providing a single implementation of:
/// - Adding Authorization headers with fresh tokens on each request
/// - Automatic retry with token refresh on 401 responses
/// - Sign-out handling when refresh fails
///
/// Usage:
/// ```dart
/// _dio.interceptors.add(
///   createAuthInterceptor(
///     sessionGetter: () async => authProvider.session,
///     tokenRefresher: authProvider.refreshToken,
///     signOutHandler: authProvider.signOut,
///     serviceName: 'MyService',
///   ),
/// );
/// ```
InterceptorsWrapper createAuthInterceptor({
  required Future<CovesSession?> Function()? sessionGetter,
  required Future<bool> Function()? tokenRefresher,
  required Future<void> Function()? signOutHandler,
  required String serviceName,
  required Dio dio,
}) {
  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Fetch fresh token before each request
      final session = await sessionGetter?.call();
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.token}';
        if (kDebugMode) {
          debugPrint('🔐 $serviceName: Adding fresh Authorization header');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '⚠️ $serviceName: Session getter returned null - '
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

            // Get the new session
            final newSession = await sessionGetter?.call();

            if (newSession != null) {
              // Mark this request as retried to prevent infinite loops
              error.requestOptions.extra['retried'] = true;

              // Update the Authorization header with the new token
              error.requestOptions.headers['Authorization'] =
                  'Bearer ${newSession.token}';

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

          // Refresh failed, sign out the user
          if (kDebugMode) {
            debugPrint(
              '❌ $serviceName: Token refresh failed, signing out user',
            );
          }
          if (signOutHandler != null) {
            await signOutHandler();
          }
        } on Exception catch (e) {
          if (kDebugMode) {
            debugPrint('❌ $serviceName: Error during token refresh: $e');
          }
          // Only sign out if we haven't already (avoid double sign-out)
          // Check if this is a DioException from a retried request
          final isRetriedRequest =
              e is DioException &&
              e.response?.statusCode == 401 &&
              e.requestOptions.extra['retried'] == true;

          if (!isRetriedRequest && signOutHandler != null) {
            await signOutHandler();
          }
        }
      }

      // Log the error for debugging
      if (kDebugMode) {
        debugPrint('❌ $serviceName API Error: ${error.message}');
        if (error.response != null) {
          debugPrint('   Status: ${error.response?.statusCode}');
          debugPrint('   Data: ${error.response?.data}');
        }
      }
      return handler.next(error);
    },
  );
}
