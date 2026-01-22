import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../models/comment.dart';
import '../models/community.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import 'api_exceptions.dart';
import 'retry_interceptor.dart';

/// Coves API Service
///
/// Handles authenticated requests to the Coves backend.
/// Uses dio for HTTP requests with automatic token management.
///
/// IMPORTANT: Accepts a tokenGetter function to fetch fresh access tokens
/// before each authenticated request. This is critical because atProto OAuth
/// rotates tokens automatically (~1 hour expiry), and caching tokens would
/// cause 401 errors after the first token expires.
///
/// Features automatic token refresh on 401 responses:
/// - When a 401 is received, attempts to refresh the token
/// - Retries the original request with the new token
/// - If refresh fails, signs out the user
class CovesApiService {
  CovesApiService({
    Future<String?> Function()? tokenGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) : _tokenGetter = tokenGetter,
       _tokenRefresher = tokenRefresher,
       _signOutHandler = signOutHandler {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: EnvironmentConfig.current.apiUrl,
            // Shorter timeout with retries for mobile network resilience
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

    // Add retry interceptor FIRST for transient network errors
    // (connection timeouts, mobile network flakiness)
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        maxRetries: 2,
        serviceName: 'CovesApiService',
      ),
    );

    // Add auth interceptor to add bearer token
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
        onError: (error, handler) async {
          // Handle 401 errors with automatic token refresh
          if (error.response?.statusCode == 401 && _tokenRefresher != null) {
            if (kDebugMode) {
              debugPrint('🔄 401 detected, attempting token refresh...');
            }

            // Don't retry the refresh endpoint itself (avoid infinite loop)
            final isRefreshEndpoint = error.requestOptions.path.contains(
              '/oauth/refresh',
            );
            if (isRefreshEndpoint) {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ Refresh endpoint returned 401, signing out user',
                );
              }
              // Refresh endpoint failed, sign out the user
              if (_signOutHandler != null) {
                await _signOutHandler();
              }
              return handler.next(error);
            }

            // Check if we already retried this request (prevent infinite loop)
            if (error.requestOptions.extra['retried'] == true) {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ Request already retried after token refresh, '
                  'signing out user',
                );
              }
              // Already retried once, don't retry again
              if (_signOutHandler != null) {
                await _signOutHandler();
              }
              return handler.next(error);
            }

            try {
              // Attempt to refresh the token
              final refreshSucceeded = await _tokenRefresher();

              if (refreshSucceeded) {
                if (kDebugMode) {
                  debugPrint('✅ Token refresh successful, retrying request');
                }

                // Get the new token
                final newToken =
                    _tokenGetter != null ? await _tokenGetter() : null;

                if (newToken != null) {
                  // Mark this request as retried to prevent infinite loops
                  error.requestOptions.extra['retried'] = true;

                  // Update the Authorization header with the new token
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $newToken';

                  // Retry the original request with the new token
                  try {
                    final response = await _dio.fetch(error.requestOptions);
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
                debugPrint('❌ Token refresh failed, signing out user');
              }
              if (_signOutHandler != null) {
                await _signOutHandler();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Error during token refresh: $e');
              }
              // Only sign out if we haven't already (avoid double sign-out)
              // Check if this is a DioException from a retried request
              final isRetriedRequest =
                  e is DioException &&
                  e.response?.statusCode == 401 &&
                  e.requestOptions.extra['retried'] == true;

              if (!isRetriedRequest && _signOutHandler != null) {
                await _signOutHandler();
              }
            }
          }

          // Log the error for debugging
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
  final Future<bool> Function()? _tokenRefresher;
  final Future<void> Function()? _signOutHandler;

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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing timeline response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing discover feed response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing comments response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// List communities with optional filtering
  ///
  /// Fetches a list of communities with pagination support.
  /// Requires authentication when filtering by subscribed communities.
  ///
  /// Parameters:
  /// - [limit]: Number of communities per page (default: 50, max: 100)
  /// - [cursor]: Pagination cursor from previous response
  /// - [sort]: Sort order - 'popular', 'new', or 'alphabetical' (default: 'popular')
  /// - [subscribed]: If true, only return communities the user is subscribed to
  Future<CommunitiesResponse> listCommunities({
    int limit = 50,
    String? cursor,
    String sort = 'popular',
    bool? subscribed,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
          '📡 Fetching communities: sort=$sort, limit=$limit, '
          'subscribed=$subscribed',
        );
      }

      final queryParams = <String, dynamic>{'limit': limit, 'sort': sort};

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      if (subscribed == true) {
        queryParams['subscribed'] = 'true';
      }

      final response = await _dio.get(
        '/xrpc/social.coves.community.list',
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint(
          '✅ Communities fetched: '
          '${response.data['communities']?.length ?? 0} communities',
        );
      }

      return CommunitiesResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      _handleDioException(e, 'communities');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing communities response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// Create a new post in a community
  ///
  /// Creates a new post with optional title, content, and embed.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [community]: Community identifier (required)
  /// - [title]: Post title (optional)
  /// - [content]: Post content (optional)
  /// - [embed]: External embed (link, image, etc.) (optional)
  /// - [langs]: Language codes for the post (optional)
  /// - [labels]: Self-applied content labels (optional)
  Future<CreatePostResponse> createPost({
    required String community,
    String? title,
    String? content,
    ExternalEmbedInput? embed,
    List<String>? langs,
    SelfLabels? labels,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Creating post in community: $community');
      }

      // Build request body with only non-null fields
      final requestBody = <String, dynamic>{'community': community};

      if (title != null) {
        requestBody['title'] = title;
      }

      if (content != null) {
        requestBody['content'] = content;
      }

      if (embed != null) {
        requestBody['embed'] = embed.toJson();
      }

      if (langs != null && langs.isNotEmpty) {
        requestBody['langs'] = langs;
      }

      if (labels != null) {
        requestBody['labels'] = labels.toJson();
      }

      final response = await _dio.post(
        '/xrpc/social.coves.community.post.create',
        data: requestBody,
      );

      if (kDebugMode) {
        debugPrint('✅ Post created successfully');
      }

      return CreatePostResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleDioException(e, 'create post');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating post: $e');
      }
      throw ApiException('Failed to create post', originalError: e);
    }
  }

  /// Create a new community
  ///
  /// Creates a new community with the given name, display name, and description.
  /// Requires authentication and admin privileges (backend enforces).
  ///
  /// Parameters:
  /// - [name]: DNS-valid unique identifier (e.g., "worldnews")
  /// - [displayName]: Human-readable display name (e.g., "World News")
  /// - [description]: Community description
  /// - [visibility]: Visibility level - 'public', 'unlisted', or 'private'
  ///   (default: 'public')
  Future<CreateCommunityResponse> createCommunity({
    required String name,
    required String displayName,
    required String description,
    String visibility = 'public',
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Creating community: $name ($displayName)');
      }

      final requestBody = <String, dynamic>{
        'name': name,
        'displayName': displayName,
        'description': description,
        'visibility': visibility,
      };

      final response = await _dio.post(
        '/xrpc/social.coves.community.create',
        data: requestBody,
      );

      if (kDebugMode) {
        debugPrint('✅ Community created successfully');
      }

      return CreateCommunityResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      _handleDioException(e, 'create community');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating community: $e');
      }
      throw ApiException('Failed to create community', originalError: e);
    }
  }

  /// Get user profile by DID or handle
  ///
  /// Fetches detailed profile information for a user.
  /// Works with both DID (did:plc:...) or handle (user.bsky.social).
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  ///
  /// Throws:
  /// - `NotFoundException` if the user does not exist
  /// - `UnauthorizedException` if authentication is required/expired
  /// - `ApiException` for other API errors
  Future<UserProfile> getProfile({required String actor}) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching profile for: $actor');
      }

      final response = await _dio.get(
        '/xrpc/social.coves.actor.getprofile',
        queryParameters: {'actor': actor},
      );

      if (kDebugMode) {
        debugPrint('✅ Profile fetched for: $actor');
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw FormatException('Expected Map but got ${data.runtimeType}');
      }
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      _handleDioException(e, 'profile'); // Never returns - always throws
    } on FormatException {
      rethrow;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing profile response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// Get posts by a specific actor
  ///
  /// Fetches posts created by a specific user using the dedicated
  /// actor posts endpoint.
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  /// - [filter]: Post filter type (optional):
  ///   - 'posts_with_replies': Include replies
  ///   - 'posts_no_replies': Exclude replies (default behavior)
  ///   - 'posts_with_media': Only posts with media attachments
  /// - [community]: Filter to posts in a specific community (optional)
  /// - [limit]: Number of posts per page (default: 15, max: 50)
  /// - [cursor]: Pagination cursor from previous response
  ///
  /// Throws:
  /// - `NotFoundException` if the actor does not exist
  /// - `UnauthorizedException` if authentication is required/expired
  /// - `ApiException` for other API errors
  Future<TimelineResponse> getAuthorPosts({
    required String actor,
    String? filter,
    String? community,
    int limit = 15,
    String? cursor,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching posts for actor: $actor');
      }

      final queryParams = <String, dynamic>{
        'actor': actor,
        'limit': limit,
      };

      if (filter != null) {
        queryParams['filter'] = filter;
      }

      if (community != null) {
        queryParams['community'] = community;
      }

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get(
        '/xrpc/social.coves.actor.getPosts',
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw FormatException('Expected Map but got ${data.runtimeType}');
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Actor posts fetched: '
          '${data['feed']?.length ?? 0} posts',
        );
      }

      return TimelineResponse.fromJson(data);
    } on DioException catch (e) {
      _handleDioException(e, 'actor posts'); // Never returns - always throws
    } on FormatException {
      rethrow;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing actor posts response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// Get comments by a specific actor
  ///
  /// Fetches comments created by a specific user for their profile page.
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  /// - [community]: Filter to comments in a specific community (optional)
  /// - [limit]: Number of comments per page (default: 50, max: 100)
  /// - [cursor]: Pagination cursor from previous response
  ///
  /// Throws:
  /// - `NotFoundException` if the actor does not exist
  /// - `AuthenticationException` if authentication is required/expired
  /// - `ApiException` for other API errors
  Future<ActorCommentsResponse> getActorComments({
    required String actor,
    String? community,
    int limit = 50,
    String? cursor,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Fetching comments for actor: $actor');
      }

      final queryParams = <String, dynamic>{
        'actor': actor,
        'limit': limit,
      };

      if (community != null) {
        queryParams['community'] = community;
      }

      if (cursor != null) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get(
        '/xrpc/social.coves.actor.getComments',
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw FormatException('Expected Map but got ${data.runtimeType}');
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Actor comments fetched: '
          '${data['comments']?.length ?? 0} comments',
        );
      }

      return ActorCommentsResponse.fromJson(data);
    } on DioException catch (e) {
      _handleDioException(e, 'actor comments');
    } on FormatException {
      rethrow;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing actor comments response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// Subscribe to a community
  ///
  /// Subscribes the authenticated user to a community.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [community]: Community DID or handle (required)
  ///
  /// Returns the subscription URI on success.
  Future<String> subscribeToCommunity({required String community}) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Subscribing to community: $community');
      }

      final response = await _dio.post(
        '/xrpc/social.coves.community.subscribe',
        data: {'community': community},
      );

      if (kDebugMode) {
        debugPrint('✅ Subscribed to community: $community');
      }

      final data = response.data as Map<String, dynamic>;
      final uri = data['uri'] as String?;
      if (uri == null || uri.isEmpty) {
        throw ApiException('Server returned invalid subscription response');
      }
      return uri;
    } on DioException catch (e) {
      _handleDioException(e, 'subscribe to community');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error subscribing to community: $e');
      }
      throw ApiException('Failed to subscribe to community', originalError: e);
    }
  }

  /// Unsubscribe from a community
  ///
  /// Unsubscribes the authenticated user from a community.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [community]: Community DID or handle (required)
  Future<void> unsubscribeFromCommunity({required String community}) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Unsubscribing from community: $community');
      }

      await _dio.post(
        '/xrpc/social.coves.community.unsubscribe',
        data: {'community': community},
      );

      if (kDebugMode) {
        debugPrint('✅ Unsubscribed from community: $community');
      }
    } on DioException catch (e) {
      _handleDioException(e, 'unsubscribe from community');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error unsubscribing from community: $e');
      }
      throw ApiException(
        'Failed to unsubscribe from community',
        originalError: e,
      );
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
      // Handle both JSON error responses and plain text responses
      String? message;
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        message = data['error'] as String? ?? data['message'] as String?;
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }

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
