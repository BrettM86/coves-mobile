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
///     sessionKeyOf: () {
///       final session = authProvider.session;
///       return session == null
///           ? null
///           : (did: session.did, sessionId: session.sessionId);
///     },
///     tokenGetter: () async => authProvider.session?.token,
///     tokenRefresher: authProvider.refreshToken,
///     signOutHandler: authProvider.signOut,
///     serviceName: 'MyService',
///     dio: _dio,
///   ),
/// );
/// ```
InterceptorsWrapper createAuthInterceptor({
  required Object? Function() sessionKeyOf,
  required Future<String?> Function()? tokenGetter,
  required Future<bool> Function()? tokenRefresher,
  required Future<void> Function()? signOutHandler,
  required String serviceName,
  required Dio dio,
}) {
  const originSessionKey = 'coves.authOriginSession';
  bool ownsSession(RequestOptions options) =>
      options.extra.containsKey(originSessionKey) &&
      options.extra[originSessionKey] == sessionKeyOf();

  return InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Only automatic replays inherit the original operation's identity.
      // A caller manually reusing completed options starts a new operation.
      final automaticReplay =
          options.extra['retried'] == true ||
          (options.extra['retryCount'] as int? ?? 0) > 0;
      if (!automaticReplay || !options.extra.containsKey(originSessionKey)) {
        // Stamp synchronously, before the token getter can yield. A null
        // anonymous origin is a real stamp, distinct from an absent one.
        options.extra[originSessionKey] = sessionKeyOf();
      }
      if (!ownsSession(options)) {
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'The session changed before the request could be sent.',
          ),
        );
      }
      // Fetch fresh token before each request, within the originating session.
      final token = await tokenGetter?.call();
      if (!ownsSession(options)) {
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'The session changed before the request could be sent.',
          ),
        );
      }
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
        if (kDebugMode) {
          debugPrint('🔐 $serviceName: Adding fresh Authorization header');
        }
      } else {
        // A re-sent request (e.g. a RetryInterceptor retry of
        // err.requestOptions) still carries the previous account's token.
        options.headers.remove('Authorization');
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
      final privateNotification = isPrivateNotificationPath(
        error.requestOptions.path,
      );
      final notificationMetadata =
          '${error.requestOptions.method} '
          '${error.requestOptions.path.split('?').first} '
          '${error.response?.statusCode ?? 'no status'}';
      // Handle 401 errors with automatic token refresh
      if (error.response?.statusCode == 401 && tokenRefresher != null) {
        // Old requests cannot refresh or sign out the replacement session.
        if (!ownsSession(error.requestOptions)) {
          return handler.next(error);
        }
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
          if (!ownsSession(error.requestOptions)) {
            return handler.next(error);
          }

          if (refreshSucceeded) {
            if (kDebugMode) {
              debugPrint(
                '✅ $serviceName: Token refresh successful, retrying request',
              );
            }

            // Get the new token
            final newToken = await tokenGetter?.call();
            if (!ownsSession(error.requestOptions)) {
              return handler.next(error);
            }

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
                // The retry's own outcome is what the caller must see. A
                // second 401 was already signed out by the retry limit
                // check above (the retry re-entered this handler).
                return handler.next(retryError);
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
        } on Object catch (e) {
          // Same rule as above: an error from the refresher or token getter
          // is not evidence the session is dead, so never sign out - just
          // propagate the original 401. Object, not
          // Exception: a TypeError/StateError from the auth provider must
          // not escape this async handler, or it would bypass the error
          // taxonomy and surface as a misclassified network error instead
          // of the original 401.
          if (kDebugMode) {
            debugPrint(
              privateNotification
                  ? '❌ $serviceName: Error during token refresh: '
                        '$notificationMetadata'
                  : '❌ $serviceName: Error during token refresh: $e',
            );
          }
        }
      }

      // One brief line here; mapDioException prints the status and
      // redacted body when the owning service maps this error.
      if (kDebugMode) {
        debugPrint(
          privateNotification
              ? '❌ $serviceName API Error: $notificationMetadata'
              : '❌ $serviceName API Error: ${error.message}',
        );
      }
      return handler.next(error);
    },
  );
}
