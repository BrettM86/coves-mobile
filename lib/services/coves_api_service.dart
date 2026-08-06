import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../models/comment.dart';
import '../models/community.dart';
import '../models/post.dart';
import '../models/post_get_result.dart';
import '../models/user_profile.dart';
import 'api_exceptions.dart';
import 'auth_interceptor.dart';
import 'log_redaction.dart';
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
/// Features automatic token refresh on 401 responses (see
/// [createAuthInterceptor]):
/// - When a 401 is received, attempts to refresh the token
/// - Retries the original request with the new token
/// - If refresh fails, propagates the error - sign-out is owned by the
///   token refresher (AuthProvider.refreshToken); sign-out here happens
///   only when a 401 persists after a successful refresh
class CovesApiService {
  CovesApiService({
    Future<String?> Function()? tokenGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) {
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

    // Add shared auth interceptor (bearer token + 401 refresh/retry)
    _dio.interceptors.add(
      createAuthInterceptor(
        tokenGetter: tokenGetter,
        tokenRefresher: tokenRefresher,
        signOutHandler: signOutHandler,
        serviceName: 'CovesApiService',
        dio: _dio,
      ),
    );

    // Add logging interceptor AFTER auth (so it can see the
    // Authorization header). Tokens are redacted before printing —
    // credentials must never reach the logs, even in debug builds.
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => debugPrint(redactBearerTokens(obj.toString())),
        ),
      );
    }
  }

  /// Maximum number of URIs per [getPosts] call, per the
  /// social.coves.community.post.get lexicon (`uris` has `maxLength: 25`).
  static const int maxPostGetUris = 25;

  late final Dio _dio;

  /// Runs one API call with the shared error taxonomy.
  ///
  /// Every endpoint goes through here so error handling cannot drift:
  /// - [DioException] is mapped by [mapDioException] (the canonical mapper)
  /// - [ApiException]s thrown by [parse] (e.g. invalid response shape)
  ///   propagate untouched
  /// - anything else [parse] throws (FormatException, TypeError, ...)
  ///   becomes a generic parse [ApiException], so callers only ever see
  ///   the [ApiException] taxonomy
  ///
  /// [operation] is a human-readable label used in error messages and debug
  /// logs, e.g. 'fetch timeline'.
  Future<T> _request<T>({
    required String operation,
    required Future<Response<dynamic>> Function() send,
    required T Function(Object? data) parse,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📡 Starting: $operation');
      }

      final response = await send();
      final result = parse(response.data);

      if (kDebugMode) {
        debugPrint('✅ Succeeded: $operation');
      }

      return result;
    } on DioException catch (e) {
      throw mapDioException(e, operation: operation);
    } on ApiException {
      rethrow;
    } on Object catch (e) {
      // Object on purpose: Errors from [parse] (TypeError from a bad cast,
      // etc.) are deliberately degraded to a parse ApiException so callers
      // only ever see the ApiException taxonomy.
      if (kDebugMode) {
        debugPrint('❌ Error parsing $operation response: $e');
      }
      throw ApiException('Failed to parse server response', originalError: e);
    }
  }

  /// Casts a response body to a JSON object, throwing [FormatException]
  /// when the server returned something else.
  static Map<String, dynamic> _asJsonMap(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw FormatException('Expected Map but got ${data.runtimeType}');
    }
    return data;
  }

  /// Shared implementation for the three feed endpoints, which take the
  /// same parameters and return the same shape.
  Future<TimelineResponse> _getFeed(
    String path,
    String operation, {
    String? community,
    required String sort,
    String? timeframe,
    required int limit,
    String? cursor,
  }) {
    return _request(
      operation: operation,
      send: () => _dio.get(
        path,
        queryParameters: {
          if (community != null) 'community': community,
          'sort': sort,
          'limit': limit,
          if (timeframe != null) 'timeframe': timeframe,
          if (cursor != null) 'cursor': cursor,
        },
      ),
      parse: (data) => TimelineResponse.fromJson(_asJsonMap(data)),
    );
  }

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
  }) {
    return _getFeed(
      '/xrpc/social.coves.feed.getTimeline',
      'fetch timeline',
      sort: sort,
      timeframe: timeframe,
      limit: limit,
      cursor: cursor,
    );
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
  }) {
    return _getFeed(
      '/xrpc/social.coves.feed.getDiscover',
      'fetch discover feed',
      sort: sort,
      timeframe: timeframe,
      limit: limit,
      cursor: cursor,
    );
  }

  /// Get community feed (public, no auth required)
  ///
  /// Fetches posts from a specific community.
  /// Does not require authentication but optionally includes voter state
  /// when authenticated.
  ///
  /// Parameters:
  /// - [community]: Community DID or handle (required)
  /// - [sort]: 'hot', 'top', or 'new' (default: 'hot')
  /// - [timeframe]: 'hour', 'day', 'week', 'month', 'year', 'all'
  ///   (default: 'day' for top sort)
  /// - [limit]: Number of posts per page (default: 15, max: 50)
  /// - [cursor]: Pagination cursor from previous response
  Future<TimelineResponse> getCommunityFeed({
    required String community,
    String sort = 'hot',
    String? timeframe,
    int limit = 15,
    String? cursor,
  }) {
    return _getFeed(
      '/xrpc/social.coves.communityFeed.getCommunity',
      'fetch community feed',
      community: community,
      sort: sort,
      timeframe: timeframe,
      limit: limit,
      cursor: cursor,
    );
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
  /// - [parentRkey]: Record key of a comment within the post. When provided,
  ///   the response contains only the subtree rooted at that comment (the
  ///   comment itself as the sole top-level entry). Used to load more
  ///   replies past the per-parent sibling cap or the depth cutoff.
  Future<CommentsResponse> getComments({
    required String postUri,
    String sort = 'hot',
    String? timeframe,
    int depth = 10,
    int limit = 50,
    String? cursor,
    String? parentRkey,
  }) {
    return _request(
      operation: 'fetch comments',
      send: () => _dio.get(
        '/xrpc/social.coves.community.comment.getComments',
        queryParameters: {
          'post': postUri,
          'sort': sort,
          'depth': depth,
          'limit': limit,
          if (parentRkey != null && parentRkey.isNotEmpty)
            'parentRkey': parentRkey,
          if (timeframe != null) 'timeframe': timeframe,
          if (cursor != null) 'cursor': cursor,
        },
      ),
      parse: (data) => CommentsResponse.fromJson(_asJsonMap(data)),
    );
  }

  /// Get posts by AT-URI (public, optional auth)
  ///
  /// Batch-fetches post views for feed hydration and permalink/cold-load
  /// rendering. The social.coves.community.post.get lexicon guarantees the
  /// server returns posts in the same order as the input URIs.
  /// Posts that are deleted or never indexed come back as [PostGetNotFound]
  /// and blocked posts as [PostGetBlocked] instead of failing the whole
  /// batch. (Malformed URIs are rejected by the server with a 400
  /// InvalidRequest error, surfaced as an [ApiException].) Entries that fail
  /// to parse are likewise degraded to [PostGetNotFound].
  ///
  /// Parameters:
  /// - [uris]: 1 to [maxPostGetUris] post AT-URIs (throws [ArgumentError]
  ///   otherwise)
  // Kept `async` (like the other validating methods below) so validation
  // failures surface as failed Futures, not synchronous throws — callers
  // using .catchError or Future.wait must observe them asynchronously.
  Future<List<PostGetResult>> getPosts({required List<String> uris}) async {
    if (uris.isEmpty) {
      throw ArgumentError.value(uris, 'uris', 'must not be empty');
    }
    if (uris.length > maxPostGetUris) {
      throw ArgumentError.value(
        uris,
        'uris',
        'must not contain more than $maxPostGetUris URIs',
      );
    }

    return _request(
      operation: 'fetch posts',
      // atproto expects repeated `uris=a&uris=b` params; pin ListFormat.multi
      // explicitly so the required encoding can't change with Dio defaults.
      send: () => _dio.get(
        '/xrpc/social.coves.community.post.get',
        queryParameters: {'uris': uris},
        options: Options(listFormat: ListFormat.multi),
      ),
      parse: (data) {
        final posts = _asJsonMap(data)['posts'] as List<dynamic>? ?? [];

        final results = <PostGetResult>[];
        for (var i = 0; i < posts.length; i++) {
          final item = posts[i];
          try {
            results.add(PostGetResult.fromJson(item as Map<String, dynamic>));
          } on Object catch (e) {
            // Degrade a single malformed entry to notFound instead of failing
            // the whole batch. Read the uri defensively; fall back to the
            // corresponding input URI (server guarantees order).
            final fallbackUri =
                (item is Map && item['uri'] is String)
                    ? item['uri'] as String
                    : (i < uris.length ? uris[i] : '');
            if (kDebugMode) {
              debugPrint(
                '⚠️ Failed to parse post entry $i ($fallbackUri): $e',
              );
            }
            results.add(PostGetNotFound(fallbackUri));
          }
        }
        return results;
      },
    );
  }

  /// Get a single post by AT-URI (public, optional auth)
  ///
  /// Convenience wrapper around [getPosts] for permalink/cold-load rendering.
  /// Returns the first result whose uri matches [uri], or [PostGetNotFound]
  /// if the server response contains no entry for it.
  Future<PostGetResult> getPost(String uri) async {
    final results = await getPosts(uris: [uri]);
    for (final result in results) {
      if (result.uri == uri) {
        return result;
      }
    }
    return PostGetNotFound(uri);
  }

  /// List communities with optional filtering
  ///
  /// Fetches a list of communities with pagination support.
  /// Requires authentication when filtering by subscribed communities.
  ///
  /// Parameters:
  /// - [limit]: Number of communities per page (default: 50, max: 100)
  /// - [cursor]: Pagination cursor from previous response
  /// - [sort]: Sort order - 'popular', 'new', or 'alphabetical'
  ///   (default: 'popular')
  /// - [subscribed]: If true, only return communities the user is
  ///   subscribed to
  Future<CommunitiesResponse> listCommunities({
    int limit = 50,
    String? cursor,
    String sort = 'popular',
    bool? subscribed,
  }) {
    return _request(
      operation: 'fetch communities',
      send: () => _dio.get(
        '/xrpc/social.coves.community.list',
        queryParameters: {
          'limit': limit,
          'sort': sort,
          if (cursor != null) 'cursor': cursor,
          if (subscribed ?? false) 'subscribed': 'true',
        },
      ),
      parse: (data) => CommunitiesResponse.fromJson(_asJsonMap(data)),
    );
  }

  /// Get a single community by identifier
  ///
  /// Fetches community details by DID or handle.
  /// Does not require authentication.
  ///
  /// Parameters:
  /// - [community]: Community DID or handle (required)
  Future<CommunityView> getCommunity({required String community}) {
    return _request(
      operation: 'fetch community',
      send: () => _dio.get(
        '/xrpc/social.coves.community.get',
        queryParameters: {'community': community},
      ),
      parse: (data) => CommunityView.fromJson(_asJsonMap(data)),
    );
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
    List<RichTextFacet>? facets,
    ExternalEmbedInput? embed,
    List<String>? langs,
    SelfLabels? labels,
  }) {
    return _request(
      operation: 'create post',
      send: () => _dio.post(
        '/xrpc/social.coves.community.post.create',
        data: {
          'community': community,
          if (title != null) 'title': title,
          if (content != null) 'content': content,
          if (facets != null && facets.isNotEmpty)
            'facets': facets.map((f) => f.toJson()).toList(),
          if (embed != null) 'embed': embed.toJson(),
          if (langs != null && langs.isNotEmpty) 'langs': langs,
          if (labels != null) 'labels': labels.toJson(),
        },
      ),
      parse: (data) => CreatePostResponse.fromJson(_asJsonMap(data)),
    );
  }

  /// Delete a post
  ///
  /// Deletes a post from the community. Only the post author can delete.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [uri]: AT-URI of the post to delete
  ///
  /// Throws:
  /// - [AuthenticationException] if not authenticated (401)
  /// - [ApiException] with statusCode 403 if not the post author
  /// - [NotFoundException] if post doesn't exist (404)
  /// - [NetworkException] for connection issues
  Future<void> deletePost({required String uri}) {
    return _request(
      operation: 'delete post',
      send: () => _dio.post(
        '/xrpc/social.coves.community.post.delete',
        data: {'uri': uri},
      ),
      parse: (_) {},
    );
  }

  /// Create a new community
  ///
  /// Creates a new community with the given name, display name, and
  /// description. Requires authentication and admin privileges
  /// (backend enforces).
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
  }) {
    return _request(
      operation: 'create community',
      send: () => _dio.post(
        '/xrpc/social.coves.community.create',
        data: {
          'name': name,
          'displayName': displayName,
          'description': description,
          'visibility': visibility,
        },
      ),
      parse: (data) => CreateCommunityResponse.fromJson(_asJsonMap(data)),
    );
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
  /// - `AuthenticationException` if authentication is required/expired
  /// - `ApiException` for other API errors
  Future<UserProfile> getProfile({required String actor}) {
    return _request(
      operation: 'fetch profile',
      send: () => _dio.get(
        '/xrpc/social.coves.actor.getProfile',
        queryParameters: {'actor': actor},
      ),
      parse: (data) => UserProfile.fromJson(_asJsonMap(data)),
    );
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
  /// - `AuthenticationException` if authentication is required/expired
  /// - `ApiException` for other API errors
  Future<TimelineResponse> getAuthorPosts({
    required String actor,
    String? filter,
    String? community,
    int limit = 15,
    String? cursor,
  }) {
    return _request(
      operation: 'fetch actor posts',
      send: () => _dio.get(
        '/xrpc/social.coves.actor.getPosts',
        queryParameters: {
          'actor': actor,
          'limit': limit,
          if (filter != null) 'filter': filter,
          if (community != null) 'community': community,
          if (cursor != null) 'cursor': cursor,
        },
      ),
      parse: (data) => TimelineResponse.fromJson(_asJsonMap(data)),
    );
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
  }) {
    return _request(
      operation: 'fetch actor comments',
      send: () => _dio.get(
        '/xrpc/social.coves.actor.getComments',
        queryParameters: {
          'actor': actor,
          'limit': limit,
          if (community != null) 'community': community,
          if (cursor != null) 'cursor': cursor,
        },
      ),
      parse: (data) => ActorCommentsResponse.fromJson(_asJsonMap(data)),
    );
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
  Future<String> subscribeToCommunity({required String community}) {
    return _request(
      operation: 'subscribe to community',
      send: () => _dio.post(
        '/xrpc/social.coves.community.subscribe',
        data: {'community': community},
      ),
      parse: (data) {
        final uri = _asJsonMap(data)['uri'] as String?;
        if (uri == null || uri.isEmpty) {
          throw ApiException('Server returned invalid subscription response');
        }
        return uri;
      },
    );
  }

  /// Unsubscribe from a community
  ///
  /// Unsubscribes the authenticated user from a community.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [community]: Community DID or handle (required)
  Future<void> unsubscribeFromCommunity({required String community}) {
    return _request(
      operation: 'unsubscribe from community',
      send: () => _dio.post(
        '/xrpc/social.coves.community.unsubscribe',
        data: {'community': community},
      ),
      parse: (_) {},
    );
  }

  /// Block a user by DID. Returns the block record URI.
  Future<String> blockUser({required String actor}) => _performBlock(
        did: actor,
        didLabel: 'user',
        endpoint: '/xrpc/social.coves.actor.blockUser',
        dataKey: 'subject',
      );

  /// Unblock a user by DID.
  Future<void> unblockUser({required String actor}) => _performUnblock(
        did: actor,
        didLabel: 'user',
        endpoint: '/xrpc/social.coves.actor.unblockUser',
        dataKey: 'subject',
      );

  /// Block a community by DID. Returns the block record URI.
  Future<String> blockCommunity({required String community}) => _performBlock(
        did: community,
        didLabel: 'community',
        endpoint: '/xrpc/social.coves.community.blockCommunity',
        dataKey: 'community',
      );

  /// Unblock a community by DID.
  Future<void> unblockCommunity({required String community}) =>
      _performUnblock(
        did: community,
        didLabel: 'community',
        endpoint: '/xrpc/social.coves.community.unblockCommunity',
        dataKey: 'community',
      );

  /// Shared helper for block operations that return a record URI.
  Future<String> _performBlock({
    required String did,
    required String didLabel,
    required String endpoint,
    required String dataKey,
  }) async {
    if (did.isEmpty || !did.startsWith('did:')) {
      throw ApiException('Invalid $didLabel DID');
    }
    return _request(
      operation: 'block $didLabel',
      send: () => _dio.post(endpoint, data: {dataKey: did}),
      parse: (data) {
        final recordUri =
            (_asJsonMap(data)['block'] as Map<String, dynamic>)['recordUri']
                as String?;
        if (recordUri == null || recordUri.isEmpty) {
          throw ApiException('Server returned invalid block response');
        }
        return recordUri;
      },
    );
  }

  /// Shared helper for unblock operations.
  Future<void> _performUnblock({
    required String did,
    required String didLabel,
    required String endpoint,
    required String dataKey,
  }) async {
    if (did.isEmpty || !did.startsWith('did:')) {
      throw ApiException('Invalid $didLabel DID');
    }
    return _request(
      operation: 'unblock $didLabel',
      send: () => _dio.post(endpoint, data: {dataKey: did}),
      parse: (_) {},
    );
  }

  /// Update a community's profile (e.g., avatar)
  ///
  /// Updates a community's profile with a new avatar image.
  /// Requires authentication and admin privileges (backend enforces).
  ///
  /// Parameters:
  /// - [communityDid]: The DID of the community to update (required)
  /// - [imageBytes]: The avatar image bytes (required, max 1 MB)
  /// - [mimeType]: The MIME type of the image (required)
  ///   Supported: 'image/jpeg', 'image/png', 'image/webp'
  ///
  /// Returns [CreateCommunityResponse] with updated community info.
  ///
  /// Throws:
  /// - [ApiException] if image exceeds 1 MB or has unsupported MIME type
  /// - [AuthenticationException] if not authenticated
  /// - [ApiException] for other API errors
  Future<CreateCommunityResponse> updateCommunity({
    required String communityDid,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    // Validate image size (max 1 MB)
    const maxSizeBytes = 1024 * 1024; // 1 MB
    if (imageBytes.length > maxSizeBytes) {
      throw ApiException(
        'Image size exceeds maximum of 1 MB '
        '(${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)',
      );
    }
    _validateImageMimeType(mimeType);

    return _request(
      operation: 'update community',
      send: () => _dio.post(
        '/xrpc/social.coves.community.update',
        data: {
          'communityDid': communityDid,
          'avatarBlob': base64Encode(imageBytes),
          'avatarMimeType': mimeType,
        },
      ),
      parse: (data) => CreateCommunityResponse.fromJson(_asJsonMap(data)),
    );
  }

  /// Update the authenticated user's profile
  ///
  /// All parameters are optional - only non-null values will be sent to
  /// the API. This allows updating individual fields without affecting
  /// others.
  ///
  /// Parameters:
  /// - [displayName]: New display name (optional, max 64 chars)
  /// - [bio]: New bio text (optional, max 256 chars)
  /// - [avatarBytes]: Avatar image bytes (optional, max 1 MB)
  /// - [avatarMimeType]: Avatar MIME type (required if avatarBytes provided)
  /// - [bannerBytes]: Banner image bytes (optional, max 2 MB)
  /// - [bannerMimeType]: Banner MIME type (required if bannerBytes provided)
  ///
  /// Returns [UpdateProfileResponse] with URI and CID of updated profile.
  ///
  /// Throws:
  /// - [ApiException] if validation fails (size, MIME type, missing params)
  /// - [AuthenticationException] if not authenticated
  /// - [ApiException] for other API errors
  Future<UpdateProfileResponse> updateProfile({
    String? displayName,
    String? bio,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    Uint8List? bannerBytes,
    String? bannerMimeType,
  }) async {
    // Validate avatar if provided
    if (avatarBytes != null) {
      if (avatarMimeType == null) {
        throw ApiException('avatarMimeType required when avatarBytes provided');
      }
      const maxAvatarBytes = 1024 * 1024; // 1 MB
      if (avatarBytes.length > maxAvatarBytes) {
        throw ApiException(
          'Avatar size exceeds maximum of 1 MB '
          '(${(avatarBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)',
        );
      }
      _validateImageMimeType(avatarMimeType);
    }

    // Validate banner if provided
    if (bannerBytes != null) {
      if (bannerMimeType == null) {
        throw ApiException('bannerMimeType required when bannerBytes provided');
      }
      const maxBannerBytes = 2 * 1024 * 1024; // 2 MB
      if (bannerBytes.length > maxBannerBytes) {
        throw ApiException(
          'Banner size exceeds maximum of 2 MB '
          '(${(bannerBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)',
        );
      }
      _validateImageMimeType(bannerMimeType);
    }

    return _request(
      operation: 'update profile',
      send: () => _dio.post(
        '/xrpc/social.coves.actor.updateProfile',
        data: {
          if (displayName != null) 'displayName': displayName,
          if (bio != null) 'bio': bio,
          if (avatarBytes != null) ...{
            'avatarBlob': base64Encode(avatarBytes),
            'avatarMimeType': avatarMimeType,
          },
          if (bannerBytes != null) ...{
            'bannerBlob': base64Encode(bannerBytes),
            'bannerMimeType': bannerMimeType,
          },
        },
      ),
      parse: (data) => UpdateProfileResponse.fromJson(_asJsonMap(data)),
    );
  }

  /// Validate image MIME type for profile images
  void _validateImageMimeType(String mimeType) {
    const supportedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};
    if (!supportedMimeTypes.contains(mimeType)) {
      throw ApiException(
        'Unsupported image type: $mimeType. '
        'Supported types: ${supportedMimeTypes.join(', ')}',
      );
    }
  }

  /// Submit a report for content moderation
  ///
  /// Reports a post or comment to administrators for review.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [targetUri]: AT-URI of the content being reported (post or comment)
  /// - [reason]: Category of the report. Must be one of:
  ///   'spam', 'harassment', 'doxing', 'illegal', 'csam', 'other'
  /// - [explanation]: Optional description (max 1000 characters)
  ///
  /// Returns the report ID on success.
  ///
  /// Throws:
  /// - [AuthenticationException] if not authenticated
  /// - [ApiException] if validation fails or server error
  Future<int> submitReport({
    required String targetUri,
    required String reason,
    String? explanation,
  }) async {
    // Validate inputs before making API call
    const validReasons = {
      'spam',
      'harassment',
      'doxing',
      'illegal',
      'csam',
      'other',
    };

    if (targetUri.isEmpty || !targetUri.startsWith('at://')) {
      throw ApiException('Invalid target URI');
    }

    if (!validReasons.contains(reason)) {
      throw ApiException('Invalid report reason: $reason');
    }

    if (explanation != null && explanation.length > 1000) {
      throw ApiException(
        'Explanation exceeds maximum length of 1000 characters',
      );
    }

    return _request(
      operation: 'submit report',
      send: () => _dio.post(
        '/xrpc/social.coves.admin.submitReport',
        data: {
          'targetUri': targetUri,
          'reason': reason,
          if (explanation != null && explanation.isNotEmpty)
            'explanation': explanation,
        },
      ),
      parse: (data) {
        final reportId = _asJsonMap(data)['reportId'] as int?;
        if (reportId == null) {
          throw ApiException('Server returned invalid report response');
        }
        return reportId;
      },
    );
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}

/// Response from POST /xrpc/social.coves.actor.updateProfile
class UpdateProfileResponse {
  const UpdateProfileResponse({required this.uri, required this.cid});

  factory UpdateProfileResponse.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'];
    final cid = json['cid'];

    if (uri is! String || uri.isEmpty) {
      throw const FormatException(
        'UpdateProfileResponse: missing or invalid uri',
      );
    }
    if (cid is! String || cid.isEmpty) {
      throw const FormatException(
        'UpdateProfileResponse: missing or invalid cid',
      );
    }

    return UpdateProfileResponse(uri: uri, cid: cid);
  }

  final String uri;
  final String cid;
}
