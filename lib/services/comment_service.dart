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

  /// Delete a comment
  ///
  /// Deletes a comment. Only the comment author can delete.
  /// Requires authentication.
  ///
  /// Parameters:
  /// - [uri]: AT-URI of the comment to delete
  ///
  /// Throws:
  /// - AuthenticationException if not authenticated
  /// - ApiException with 'You can only delete your own comments' if not the comment author
  /// - ApiException for other errors
  Future<void> deleteComment({required String uri}) async {
    try {
      final session = await _sessionGetter?.call();

      if (session == null) {
        throw AuthenticationException(
          'User not authenticated - no session available',
        );
      }

      if (kDebugMode) {
        debugPrint('🗑️ Deleting comment: $uri');
      }

      await _dio.post<Map<String, dynamic>>(
        '/xrpc/social.coves.community.comment.delete',
        data: {'uri': uri},
      );

      if (kDebugMode) {
        debugPrint('✅ Comment deleted successfully');
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Comment deletion failed: ${e.message}');
      }

      if (e.response?.statusCode == 401) {
        throw AuthenticationException(
          'Authentication failed. Please sign in again.',
          originalError: e,
        );
      }

      if (e.response?.statusCode == 403) {
        throw ApiException(
          'You can only delete your own comments',
          statusCode: 403,
          originalError: e,
        );
      }

      if (e.response?.statusCode == 404) {
        throw NotFoundException(
          'Comment not found. It may have already been deleted.',
          originalError: e,
        );
      }

      // Handle network-level errors
      if (e.response == null) {
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.connectionError:
            throw NetworkException(
              'Network error. Please check your connection.',
              originalError: e,
            );
          default:
            break;
        }
      }

      throw ApiException(
        'Failed to delete comment: ${e.message}',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    } on AuthenticationException {
      rethrow;
    } on NotFoundException {
      rethrow;
    } on NetworkException {
      rethrow;
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Delete comment failed with unexpected error: $e');
      }
      throw ApiException('Failed to delete comment: $e', originalError: e);
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
