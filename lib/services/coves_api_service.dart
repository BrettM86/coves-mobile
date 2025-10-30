import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/oauth_config.dart';
import '../models/post.dart';

/// Coves API Service
///
/// Handles authenticated requests to the Coves backend.
/// Uses dio for HTTP requests with automatic token management.
///
/// IMPORTANT: Accepts a tokenGetter function to fetch fresh access tokens
/// before each authenticated request. This is critical because atProto OAuth
/// rotates tokens automatically (~1 hour expiry), and caching tokens would
/// cause 401 errors after the first token expires.
class CovesApiService {

  CovesApiService({Future<String?> Function()? tokenGetter})
    : _tokenGetter = tokenGetter {
    _dio = Dio(
      BaseOptions(
        baseUrl: OAuthConfig.apiUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Add auth interceptor FIRST to add bearer token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Fetch fresh token before each request (critical for atProto OAuth)
          if (_tokenGetter != null) {
            final token = await _tokenGetter();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
              if (kDebugMode) {
                debugPrint('🔐 Adding fresh Authorization header');
              }
            } else {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ Token getter returned null - making unauthenticated request',
                );
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                '⚠️ No token getter provided - making unauthenticated request',
              );
            }
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          if (kDebugMode) {
            debugPrint('❌ API Error: ${error.message}');
            if (error.response != null) {
              debugPrint('   Status: ${error.response?.statusCode}');
              debugPrint('   Data: ${error.response?.data}');
            }
          }
          return handler.next(error);
        },
      ),
    );

    // Add logging interceptor AFTER auth (so it can see the Authorization header)
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => debugPrint(obj.toString()),
        ),
      );
    }
  }
  late final Dio _dio;
  final Future<String?> Function()? _tokenGetter;

  /// Get timeline feed (authenticated, personalized)
  ///
  /// Fetches posts from communities the user is subscribed to.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [sort]: 'hot', 'top', or 'new' (default: 'hot')
  /// - [timeframe]: 'hour', 'day', 'week', 'month', 'year', 'all' (default: 'day' for top sort)
  /// - [limit]: Number of posts per page (default: 15, max: 50)
  /// - [cursor]: Pagination cursor from previous response
  Future<TimelineResponse> getTimeline({
    String sort = 'hot',
    String? timeframe,
    int limit = 15,
    String? cursor,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching timeline: sort=$sort, limit=$limit');
      }

      final queryParams = <String, dynamic>{'sort': sort, 'limit': limit};

      if (timeframe != null) {
        queryParams['timeframe'] = timeframe;
      }

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get(
        '/xrpc/social.coves.feed.getTimeline',
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint(
          '✅ Timeline fetched: ${response.data['feed']?.length ?? 0} posts',
        );
      }

      return TimelineResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch timeline: ${e.message}');
      }
      rethrow;
    }
  }

  /// Get discover feed (public, no auth required)
  ///
  /// Fetches posts from all communities for exploration.
  /// Does not require authentication.
  Future<TimelineResponse> getDiscover({
    String sort = 'hot',
    String? timeframe,
    int limit = 15,
    String? cursor,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching discover feed: sort=$sort, limit=$limit');
      }

      final queryParams = <String, dynamic>{'sort': sort, 'limit': limit};

      if (timeframe != null) {
        queryParams['timeframe'] = timeframe;
      }

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get(
        '/xrpc/social.coves.feed.getDiscover',
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint(
          '✅ Discover feed fetched: ${response.data['feed']?.length ?? 0} posts',
        );
      }

      return TimelineResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch discover feed: ${e.message}');
      }
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
