import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../models/coves_session.dart';
import '../models/post.dart';
import 'api_exceptions.dart';
import 'auth_interceptor.dart';
import 'retry_interceptor.dart';

/// Comment Service
///
/// Handles comment creation through the Coves backend.
///
/// **Architecture with Backend OAuth**:
/// With sealed tokens, the client cannot write directly to the user's PDS
/// (no DPoP keys available). Instead, comments go through the Coves backend:
///
/// Mobile Client → Coves Backend (sealed token) → User's PDS (DPoP)
///
/// The backend:
/// 1. Unseals the token to get the actual access/refresh tokens
/// 2. Uses stored DPoP keys to sign requests
/// 3. Writes to the user's PDS on their behalf
///
/// **Backend Endpoint**:
/// - POST /xrpc/social.coves.community.comment.create
class CommentService {
  CommentService({
    Future<CovesSession?> Function()? sessionGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) : _sessionGetter = sessionGetter {
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
        serviceName: 'CommentService',
      ),
    );

    // Add shared 401 retry interceptor
    _dio.interceptors.add(
      createAuthInterceptor(
        sessionGetter: sessionGetter,
        tokenRefresher: tokenRefresher,
        signOutHandler: signOutHandler,
        serviceName: 'CommentService',
        dio: _dio,
      ),
    );
  }

  final Future<CovesSession?> Function()? _sessionGetter;
  late final Dio _dio;

  /// Create a comment
  ///
  /// Sends comment request to the Coves backend, which writes to the
  /// user's PDS.
  ///
  /// Parameters:
  /// - [rootUri]: AT-URI of the root post (always the original post)
  /// - [rootCid]: CID of the root post
  /// - [parentUri]: AT-URI of the parent (post or comment)
  /// - [parentCid]: CID of the parent
  /// - [content]: Comment text content
  ///
  /// Returns:
  /// - CreateCommentResponse with uri and cid of the created comment
  ///
  /// Throws:
  /// - ApiException for API errors
  /// - AuthenticationException for auth failures
  Future<CreateCommentResponse> createComment({
    required String rootUri,
    required String rootCid,
    required String parentUri,
    required String parentCid,
    required String content,
    List<RichTextFacet>? contentFacets,
  }) async {
    try {
      final session = await _sessionGetter?.call();

      if (session == null) {
        throw AuthenticationException(
          'User not authenticated - no session available',
        );
      }

      if (kDebugMode) {
        debugPrint('💬 Creating comment via backend');
        debugPrint('   Root: $rootUri');
        debugPrint('   Parent: $parentUri');
        debugPrint('   Content length: ${content.length}');
      }

      // Send comment request to backend
      // Note: Authorization header is added by the interceptor
      // Note: Use 'facets' field name to match atProto lexicon convention
      final response = await _dio.post<Map<String, dynamic>>(
        '/xrpc/social.coves.community.comment.create',
        data: {
          'reply': {
            'root': {'uri': rootUri, 'cid': rootCid},
            'parent': {'uri': parentUri, 'cid': parentCid},
          },
          'content': content,
          if (contentFacets != null && contentFacets.isNotEmpty)
            'facets': contentFacets.map((f) => f.toJson()).toList(),
        },
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Invalid response from server - no data');
      }

      final uri = data['uri'] as String?;
      final cid = data['cid'] as String?;

      if (uri == null || uri.isEmpty || cid == null || cid.isEmpty) {
        throw ApiException('Invalid response from server - missing uri or cid');
      }

      if (kDebugMode) {
        debugPrint('✅ Comment created: $uri');
      }

      return CreateCommentResponse(uri: uri, cid: cid);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Comment creation failed: ${e.message}');
        debugPrint('   Status: ${e.response?.statusCode}');
        debugPrint('   Data: ${e.response?.data}');
      }

      if (e.response?.statusCode == 401) {
        throw AuthenticationException(
          'Authentication failed. Please sign in again.',
          originalError: e,
        );
      }

      throw ApiException(
        'Failed to create comment: ${e.message}',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    } on AuthenticationException {
      rethrow;
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException('Failed to create comment: $e');
    }
  }
}

/// Response from comment creation
class CreateCommentResponse {
  const CreateCommentResponse({required this.uri, required this.cid});

  /// AT-URI of the created comment record
  final String uri;

  /// CID of the created comment record
  final String cid;
}
