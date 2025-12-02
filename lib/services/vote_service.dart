import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../models/coves_session.dart';
import 'api_exceptions.dart';

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
///
/// TODO: Backend vote endpoints need to be implemented:
/// - POST /xrpc/social.coves.feed.vote.create
/// - POST /xrpc/social.coves.feed.vote.delete
/// - GET /xrpc/social.coves.feed.vote.list (or included in feed response)
class VoteService {
  VoteService({
    Future<CovesSession?> Function()? sessionGetter,
    String? Function()? didGetter,
    Future<bool> Function()? tokenRefresher,
    Future<void> Function()? signOutHandler,
    Dio? dio,
  }) : _sessionGetter = sessionGetter,
       _didGetter = didGetter,
       _tokenRefresher = tokenRefresher,
       _signOutHandler = signOutHandler {
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

    // Add 401 retry interceptor (same pattern as CovesApiService)
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Fetch fresh token before each request
          final session = await _sessionGetter?.call();
          if (session != null) {
            options.headers['Authorization'] = 'Bearer ${session.token}';
            if (kDebugMode) {
              debugPrint('🔐 VoteService: Adding fresh Authorization header');
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                '⚠️ VoteService: Session getter returned null - '
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
              debugPrint(
                '🔄 VoteService: 401 detected, attempting token refresh...',
              );
            }

            // Check if we already retried this request (prevent infinite loop)
            if (error.requestOptions.extra['retried'] == true) {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ VoteService: Request already retried after token refresh, '
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
                  debugPrint(
                    '✅ VoteService: Token refresh successful, retrying request',
                  );
                }

                // Get the new session
                final newSession = await _sessionGetter?.call();

                if (newSession != null) {
                  // Mark this request as retried to prevent infinite loops
                  error.requestOptions.extra['retried'] = true;

                  // Update the Authorization header with the new token
                  error.requestOptions.headers['Authorization'] =
                      'Bearer ${newSession.token}';

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
                debugPrint(
                  '❌ VoteService: Token refresh failed, signing out user',
                );
              }
              if (_signOutHandler != null) {
                await _signOutHandler();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ VoteService: Error during token refresh: $e');
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
            debugPrint('❌ VoteService API Error: ${error.message}');
            if (error.response != null) {
              debugPrint('   Status: ${error.response?.statusCode}');
              debugPrint('   Data: ${error.response?.data}');
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  final Future<CovesSession?> Function()? _sessionGetter;
  final String? Function()? _didGetter;
  final Future<bool> Function()? _tokenRefresher;
  final Future<void> Function()? _signOutHandler;
  late final Dio _dio;

  /// Collection name for vote records
  static const String voteCollection = 'social.coves.feed.vote';

  /// Get all votes for the current user
  ///
  /// TODO: This needs a backend endpoint to list user's votes.
  /// For now, returns empty map - votes will be fetched with feed data.
  ///
  /// Returns:
  /// - `Map<String, VoteInfo>` where key is the post URI
  /// - Empty map if not authenticated or no votes found
  Future<Map<String, VoteInfo>> getUserVotes() async {
    try {
      final userDid = _didGetter?.call();
      if (userDid == null || userDid.isEmpty) {
        return {};
      }

      final session = await _sessionGetter?.call();
      if (session == null) {
        return {};
      }

      // TODO: Implement backend endpoint for listing user votes
      // For now, vote state should come from feed responses
      if (kDebugMode) {
        debugPrint(
          '⚠️ getUserVotes: Backend endpoint not yet implemented. '
          'Vote state should come from feed responses.',
        );
      }

      return {};
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to load user votes: $e');
      }
      return {};
    }
  }

  /// Create or toggle vote
  ///
  /// Sends vote request to the Coves backend, which proxies to the user's PDS.
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [postCid]: Content ID of the post (for strong reference)
  /// - [direction]: Vote direction - "up" for like/upvote, "down" for downvote
  /// - [existingVoteRkey]: Optional rkey from cached state
  /// - [existingVoteDirection]: Optional direction from cached state
  ///
  /// Returns:
  /// - VoteResponse with uri/cid/rkey if created
  /// - VoteResponse with deleted=true if toggled off
  ///
  /// Throws:
  /// - ApiException for API errors
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
    String? existingVoteRkey,
    String? existingVoteDirection,
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

      // Determine if this is a toggle (delete) or create
      final isToggleOff =
          existingVoteRkey != null && existingVoteDirection == direction;

      if (isToggleOff) {
        // Delete existing vote
        return _deleteVote(session: session, rkey: existingVoteRkey);
      }

      // If switching direction, delete old vote first
      if (existingVoteRkey != null && existingVoteDirection != null) {
        if (kDebugMode) {
          debugPrint('   Switching vote direction - deleting old vote first');
        }
        await _deleteVote(session: session, rkey: existingVoteRkey);
      }

      // Create new vote via backend
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

      if (uri == null || cid == null) {
        throw ApiException('Invalid response from server - missing uri or cid');
      }

      // Extract rkey from URI
      final rkey = uri.split('/').last;

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
    } on Exception catch (e) {
      throw ApiException('Failed to create vote: $e');
    }
  }

  /// Delete vote via backend
  Future<VoteResponse> _deleteVote({
    required CovesSession session,
    required String rkey,
  }) async {
    try {
      // Note: Authorization header is added by the interceptor
      await _dio.post<void>(
        '/xrpc/social.coves.feed.vote.delete',
        data: {'rkey': rkey},
      );

      if (kDebugMode) {
        debugPrint('✅ Vote deleted');
      }

      return const VoteResponse(deleted: true);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Delete vote failed: ${e.message}');
      }

      throw ApiException(
        'Failed to delete vote: ${e.message}',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
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

/// Existing Vote
///
/// Represents a vote that already exists on the PDS.
class ExistingVote {
  const ExistingVote({required this.direction, required this.rkey});

  /// Vote direction ("up" or "down")
  final String direction;

  /// Record key for deletion
  final String rkey;
}

/// Vote Info
///
/// Information about a user's vote on a post, returned from getUserVotes().
class VoteInfo {
  const VoteInfo({
    required this.direction,
    required this.voteUri,
    required this.rkey,
  });

  /// Vote direction ("up" or "down")
  final String direction;

  /// AT-URI of the vote record
  final String voteUri;

  /// Record key (rkey) - last segment of URI
  final String rkey;
}
