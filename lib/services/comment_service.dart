import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../models/coves_session.dart';
import '../models/post.dart';
import '../models/post_embed_input.dart';
import 'api_exceptions.dart';
import 'auth_interceptor.dart';
import 'coves_http.dart';
import 'retry_interceptor.dart';

/// Comment Service
///
/// Handles comment creation and deletion through the Coves backend.
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
/// **Backend Endpoints**:
/// - POST /xrpc/social.coves.community.comment.create
/// - POST /xrpc/social.coves.community.comment.delete
class CommentService {
  CommentService({
    required Object? Function() sessionKeyOf,
    Future<CovesSession?> Function()? sessionGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) : _sessionGetter = sessionGetter {
    _dio = dio ?? createCovesDio(headers: {'Content-Type': 'application/json'});

    // Add retry interceptor FIRST for transient network errors
    // (connection timeouts, mobile network flakiness)
    _dio.interceptors.add(
      RetryInterceptor(dio: _dio, serviceName: 'CommentService'),
    );

    // Add shared 401 retry interceptor
    _dio.interceptors.add(
      createAuthInterceptor(
        sessionKeyOf: sessionKeyOf,
        tokenGetter: () async => (await sessionGetter?.call())?.token,
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
    ImagesEmbedInput? embed,
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
          if (embed != null) 'embed': embed.toJson(),
        },
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Invalid response from server - no data');
      }

      final uri = data['uri'];
      final cid = data['cid'];

      // Type-check rather than cast: a non-string uri/cid raises a
      // TypeError - an Error, not an Exception - which would escape every
      // handler up the stack instead of surfacing as ApiException.
      if (uri is! String || uri.isEmpty || cid is! String || cid.isEmpty) {
        throw ApiException('Invalid response from server - missing uri or cid');
      }

      if (kDebugMode) {
        debugPrint('✅ Comment created: $uri');
      }

      return CreateCommentResponse(uri: uri, cid: cid);
    } on DioException catch (e) {
      throw mapDioException(e, operation: 'create comment');
    } on AuthenticationException {
      rethrow;
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException('Failed to create comment: $e');
    }
  }

  /// Update a comment's content
  ///
  /// The update procedure replaces the whole record, so the stored
  /// [record]'s embed, langs and labels are resent verbatim.
  ///
  /// Throws:
  /// - AuthenticationException if not authenticated
  /// - ApiException with statusCode 403 if not the comment author
  /// - NotFoundException if the comment no longer exists (404)
  /// - ApiException with statusCode 409 and errorCode
  ///   'ConcurrentModification' if the comment changed meanwhile
  /// - ApiException for other errors
  Future<UpdateCommentResponse> updateComment({
    required String uri,
    required String content,
    List<RichTextFacet>? facets,
    required CommentRecord record,
  }) async {
    try {
      final session = await _sessionGetter?.call();

      if (session == null) {
        throw AuthenticationException(
          'User not authenticated - no session available',
        );
      }

      if (kDebugMode) {
        debugPrint('✏️ Updating comment: $uri');
        debugPrint('   Content length: ${content.length}');
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/xrpc/social.coves.community.comment.update',
        data: {
          'uri': uri,
          'content': content,
          if (facets != null && facets.isNotEmpty)
            'facets': facets.map((f) => f.toJson()).toList(),
          if (record.embed != null) 'embed': record.embed,
          if (record.langs != null) 'langs': record.langs,
          if (record.labels != null) 'labels': record.labels,
        },
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Invalid response from server - no data');
      }

      final updatedUri = data['uri'];
      final cid = data['cid'];

      // Type-check rather than cast, as in createComment.
      if (updatedUri is! String ||
          updatedUri.isEmpty ||
          cid is! String ||
          cid.isEmpty) {
        throw ApiException('Invalid response from server - missing uri or cid');
      }

      if (kDebugMode) {
        debugPrint('✅ Comment updated: $updatedUri');
      }

      return UpdateCommentResponse(uri: updatedUri, cid: cid);
    } on DioException catch (e) {
      // No client copy for 403: the backend also returns it when the PDS
      // session fails, so the server's message and error code are kept.
      throw mapDioException(e, operation: 'update comment');
    } on AuthenticationException {
      rethrow;
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException('Failed to update comment: $e', originalError: e);
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
  /// - ApiException with 'You can only delete your own comments' if not
  ///   the comment author (403)
  /// - NotFoundException if the comment no longer exists (404)
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
      // Map first so every failure gets the standard (redacted) debug log,
      // then substitute friendlier copy for the two expected outcomes.
      final mapped = mapDioException(e, operation: 'delete comment');
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
      throw mapped;
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

/// Response from comment update
class UpdateCommentResponse {
  const UpdateCommentResponse({required this.uri, required this.cid});

  /// AT-URI of the updated comment record
  final String uri;

  /// CID of the new comment record version
  final String cid;
}
