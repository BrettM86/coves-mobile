import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/oauth_config.dart';
import '../models/comment.dart';
import '../models/post.dart';
import 'api_exceptions.dart';

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
  CovesApiService({Future<String?> Function()? tokenGetter, Dio? dio})
    : _tokenGetter = tokenGetter {
    _dio =
        dio ??
        Dio(
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
                  '⚠️ Token getter returned null - '
                  'making unauthenticated request',
                );
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                '⚠️ No token getter provided - '
                'making unauthenticated request',
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

    // Add logging interceptor AFTER auth (so it can see the
    // Authorization header)
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
  /// - [timeframe]: 'hour', 'day', 'week', 'month', 'year', 'all'
  ///   (default: 'day' for top sort)
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
          '✅ Timeline fetched: '
          '${response.data['feed']?.length ?? 0} posts',
        );
      }

      return TimelineResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e, 'timeline');
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
          '✅ Discover feed fetched: '
          '${response.data['feed']?.length ?? 0} posts',
        );
      }

      return TimelineResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e, 'discover feed');
    }
  }

  /// Get comments for a post (authenticated)
  ///
  /// Fetches threaded comments for a specific post.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [postUri]: Post URI (required)
  /// - [sort]: 'hot', 'top', or 'new' (default: 'hot')
  /// - [timeframe]: 'hour', 'day', 'week', 'month', 'year', 'all'
  /// - [depth]: Maximum nesting depth for replies (default: 10)
  /// - [limit]: Number of comments per page (default: 50, max: 100)
  /// - [cursor]: Pagination cursor from previous response
  Future<CommentsResponse> getComments({
    required String postUri,
    String sort = 'hot',
    String? timeframe,
    int depth = 10,
    int limit = 50,
    String? cursor,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching comments: postUri=$postUri, sort=$sort');
      }

      final queryParams = <String, dynamic>{
        'post': postUri,
        'sort': sort,
        'depth': depth,
        'limit': limit,
      };

      if (timeframe != null) {
        queryParams['timeframe'] = timeframe;
      }

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get(
        '/xrpc/social.coves.community.comment.getComments',
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint(
          '✅ Comments fetched: '
          '${response.data['comments']?.length ?? 0} comments',
        );
      }

      return CommentsResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e, 'comments');
    }
  }

  /// Handle Dio exceptions with specific error types
  ///
  /// Converts generic DioException into specific typed exceptions
  /// for better error handling throughout the app.
  Never _handleDioException(DioException e, String operation) {
    if (kDebugMode) {
      debugPrint('❌ Failed to fetch $operation: ${e.message}');
      if (e.response != null) {
        debugPrint('   Status: ${e.response?.statusCode}');
        debugPrint('   Data: ${e.response?.data}');
      }
    }

    // Handle specific HTTP status codes
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final message =
          e.response!.data?['error'] ?? e.response!.data?['message'];

      if (statusCode != null) {
        if (statusCode == 401) {
          throw AuthenticationException(
            message?.toString() ??
                'Authentication failed. Token expired or invalid',
            originalError: e,
          );
        } else if (statusCode == 404) {
          throw NotFoundException(
            message?.toString() ??
                'Resource not found. PDS or content may not exist',
            originalError: e,
          );
        } else if (statusCode >= 500) {
          throw ServerException(
            message?.toString() ?? 'Server error. Please try again later',
            statusCode: statusCode,
            originalError: e,
          );
        } else {
          // Other HTTP errors
          throw ApiException(
            message?.toString() ?? 'Request failed: ${e.message}',
            statusCode: statusCode,
            originalError: e,
          );
        }
      } else {
        // No status code in response
        throw ApiException(
          message?.toString() ?? 'Request failed: ${e.message}',
          originalError: e,
        );
      }
    }

    // Handle network-level errors (no response from server)
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        throw NetworkException(
          'Connection timeout. Please check your internet connection',
          originalError: e,
        );
      case DioExceptionType.connectionError:
        // Could be federation issue if it's a PDS connection failure
        if (e.message?.contains('Failed host lookup') ?? false) {
          throw FederationException(
            'Failed to connect to PDS. Server may be unreachable',
            originalError: e,
          );
        }
        throw NetworkException(
          'Network error. Please check your internet connection',
          originalError: e,
        );
      case DioExceptionType.badResponse:
        // Already handled above by response status code check
        throw ApiException(
          'Bad response from server: ${e.message}',
          statusCode: e.response?.statusCode,
          originalError: e,
        );
      case DioExceptionType.cancel:
        throw ApiException('Request cancelled', originalError: e);
      default:
        throw ApiException('Unknown error: ${e.message}', originalError: e);
    }
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
