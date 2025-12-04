import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../models/coves_session.dart';
import '../providers/vote_provider.dart' show VoteState;
import 'api_exceptions.dart';
import 'auth_interceptor.dart';

/// Vote Service
///
/// Handles vote/like interactions through the Coves backend.
///
/// **Architecture with Backend OAuth**:
/// With sealed tokens, the client cannot write directly to the user's PDS
/// (no DPoP keys available). Instead, votes go through the Coves backend:
///
/// Mobile Client → Coves Backend (sealed token) → User's PDS (DPoP)
///
/// The backend:
/// 1. Unseals the token to get the actual access/refresh tokens
/// 2. Uses stored DPoP keys to sign requests
/// 3. Writes to the user's PDS on their behalf
/// 4. Handles toggle logic (creating, deleting, or switching vote direction)
///
/// **Backend Endpoints**:
/// - POST /xrpc/social.coves.feed.vote.create - Creates, toggles, or switches
///   votes
class VoteService {
  VoteService({
    Future<CovesSession?> Function()? sessionGetter,
    String? Function()? didGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) : _sessionGetter = sessionGetter,
       _didGetter = didGetter {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: EnvironmentConfig.current.apiUrl,
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

    // Add shared 401 retry interceptor
    _dio.interceptors.add(
      createAuthInterceptor(
        sessionGetter: sessionGetter,
        tokenRefresher: tokenRefresher,
        signOutHandler: signOutHandler,
        serviceName: 'VoteService',
        dio: _dio,
      ),
    );
  }

  final Future<CovesSession?> Function()? _sessionGetter;
  final String? Function()? _didGetter;
  late final Dio _dio;

  /// Collection name for vote records
  static const String voteCollection = 'social.coves.feed.vote';

  /// Create or toggle vote
  ///
  /// Sends vote request to the Coves backend, which handles toggle logic.
  /// The backend will create a vote if none exists, or toggle it off if
  /// voting the same direction again.
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [postCid]: Content ID of the post (for strong reference)
  /// - [direction]: Vote direction - "up" for like/upvote, "down" for downvote
  ///
  /// Returns:
  /// - VoteResponse with uri/cid/rkey if vote was created
  /// - VoteResponse with deleted=true if vote was toggled off (empty uri/cid)
  ///
  /// Throws:
  /// - ApiException for API errors
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    try {
      final userDid = _didGetter?.call();
      final session = await _sessionGetter?.call();

      if (userDid == null || userDid.isEmpty) {
        throw ApiException('User not authenticated - no DID available');
      }

      if (session == null) {
        throw ApiException('User not authenticated - no session available');
      }

      if (kDebugMode) {
        debugPrint('🗳️ Creating vote via backend');
        debugPrint('   Post: $postUri');
        debugPrint('   Direction: $direction');
      }

      // Send vote request to backend
      // Note: Authorization header is added by the interceptor
      final response = await _dio.post<Map<String, dynamic>>(
        '/xrpc/social.coves.feed.vote.create',
        data: {
          'subject': {'uri': postUri, 'cid': postCid},
          'direction': direction,
        },
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Invalid response from server - no data');
      }

      final uri = data['uri'] as String?;
      final cid = data['cid'] as String?;

      // If uri/cid are empty, the backend toggled off an existing vote
      if (uri == null || uri.isEmpty || cid == null || cid.isEmpty) {
        if (kDebugMode) {
          debugPrint('✅ Vote toggled off (deleted)');
        }
        return const VoteResponse(deleted: true);
      }

      // Extract rkey from URI using shared utility
      final rkey = VoteState.extractRkeyFromUri(uri);

      if (kDebugMode) {
        debugPrint('✅ Vote created: $uri');
      }

      return VoteResponse(uri: uri, cid: cid, rkey: rkey, deleted: false);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Vote failed: ${e.message}');
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
        'Failed to create vote: ${e.message}',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException('Failed to create vote: $e');
    }
  }
}

/// Vote Response
///
/// Response from createVote operation.
class VoteResponse {
  const VoteResponse({this.uri, this.cid, this.rkey, required this.deleted});

  /// AT-URI of the created vote record
  final String? uri;

  /// Content ID of the vote record
  final String? cid;

  /// Record key (rkey) of the vote - last segment of URI
  final String? rkey;

  /// Whether the vote was deleted (toggled off)
  final bool deleted;
}
