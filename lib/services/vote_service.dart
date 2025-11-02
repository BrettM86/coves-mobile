import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exceptions.dart';

/// Vote Service
///
/// Handles vote/like interactions by writing directly to the user's PDS.
/// This follows the atProto architecture where clients write to PDSs and
/// AppViews only index public data.
///
/// **Correct Architecture**:
/// Mobile Client → User's PDS (com.atproto.repo.createRecord)
///              ↓
///          Jetstream
///              ↓
/// Backend AppView (indexes vote events)
///
/// Uses these XRPC endpoints:
/// - com.atproto.repo.createRecord (create vote)
/// - com.atproto.repo.deleteRecord (delete vote)
/// - com.atproto.repo.listRecords (find existing votes)
///
/// **DPoP Authentication TODO**:
/// atProto PDSs require DPoP (Demonstrating Proof of Possession) authentication.
/// The current implementation uses a placeholder that will not work with real PDSs.
/// This needs to be implemented using OAuthSession's DPoP capabilities once
/// available in the atproto_oauth_flutter package.
///
/// Required for production:
/// - Authorization: DPoP <access_token>
/// - DPoP: <proof> (signed JWT proving key possession)
class VoteService {
  VoteService({
    Future<OAuthSession?> Function()? sessionGetter,
    String? Function()? didGetter,
    String? Function()? pdsUrlGetter,
  })  : _sessionGetter = sessionGetter,
        _didGetter = didGetter,
        _pdsUrlGetter = pdsUrlGetter {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // TODO: Add DPoP auth interceptor
    // atProto PDSs require DPoP authentication, not Bearer tokens
    // This needs implementation using OAuthSession's DPoP support
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // PLACEHOLDER: This does not implement DPoP authentication
          // and will fail on real PDSs with "Malformed token" errors
          if (_sessionGetter != null) {
            final session = await _sessionGetter();
            if (session != null) {
              // TODO: Generate DPoP proof and set headers:
              // options.headers['Authorization'] = 'DPoP ${session.accessToken}';
              // options.headers['DPoP'] = dpopProof;
              if (kDebugMode) {
                debugPrint('⚠️  DPoP authentication not yet implemented');
              }
            }
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (kDebugMode) {
            debugPrint('❌ PDS API Error: ${error.message}');
            debugPrint('   Status: ${error.response?.statusCode}');
            debugPrint('   Data: ${error.response?.data}');
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;
  final Future<OAuthSession?> Function()? _sessionGetter;
  final String? Function()? _didGetter;
  final String? Function()? _pdsUrlGetter;

  /// Collection name for vote records
  static const String voteCollection = 'social.coves.interaction.vote';

  /// Create or toggle vote
  ///
  /// Implements smart toggle logic:
  /// 1. Query PDS for existing vote on this post
  /// 2. If exists with same direction → Delete (toggle off)
  /// 3. If exists with different direction → Delete old + Create new
  /// 4. If no existing vote → Create new
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post (e.g.,
  ///   "at://did:plc:xyz/social.coves.post.record/abc123")
  /// - [postCid]: Content ID of the post (for strong reference)
  /// - [direction]: Vote direction - "up" for like/upvote, "down" for downvote
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
  }) async {
    try {
      // Get user's DID and PDS URL
      final userDid = _didGetter?.call();
      final pdsUrl = _pdsUrlGetter?.call();

      if (userDid == null || userDid.isEmpty) {
        throw ApiException('User not authenticated - no DID available');
      }

      if (pdsUrl == null || pdsUrl.isEmpty) {
        throw ApiException('PDS URL not available');
      }

      if (kDebugMode) {
        debugPrint('🗳️  Creating vote on PDS');
        debugPrint('   Post: $postUri');
        debugPrint('   Direction: $direction');
        debugPrint('   PDS: $pdsUrl');
      }

      // Step 1: Check for existing vote
      final existingVote = await _findExistingVote(
        userDid: userDid,
        pdsUrl: pdsUrl,
        postUri: postUri,
      );

      if (existingVote != null) {
        if (kDebugMode) {
          debugPrint('   Found existing vote: ${existingVote.direction}');
        }

        // If same direction, toggle off (delete)
        if (existingVote.direction == direction) {
          if (kDebugMode) {
            debugPrint('   Same direction - deleting vote');
          }
          await _deleteVote(
            userDid: userDid,
            pdsUrl: pdsUrl,
            rkey: existingVote.rkey,
          );
          return const VoteResponse(deleted: true);
        }

        // Different direction - delete old vote first
        if (kDebugMode) {
          debugPrint('   Different direction - switching vote');
        }
        await _deleteVote(
          userDid: userDid,
          pdsUrl: pdsUrl,
          rkey: existingVote.rkey,
        );
      }

      // Step 2: Create new vote
      final response = await _createVote(
        userDid: userDid,
        pdsUrl: pdsUrl,
        postUri: postUri,
        postCid: postCid,
        direction: direction,
      );

      if (kDebugMode) {
        debugPrint('✅ Vote created: ${response.uri}');
      }

      return response;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    } catch (e) {
      throw ApiException('Failed to create vote: $e');
    }
  }

  /// Find existing vote for a post
  ///
  /// Queries the user's PDS to check if they've already voted on this post.
  ///
  /// Returns ExistingVote with direction and rkey if found, null otherwise.
  Future<ExistingVote?> _findExistingVote({
    required String userDid,
    required String pdsUrl,
    required String postUri,
  }) async {
    try {
      // Query listRecords to find votes
      final response = await _dio.get<Map<String, dynamic>>(
        '$pdsUrl/xrpc/com.atproto.repo.listRecords',
        queryParameters: {
          'repo': userDid,
          'collection': voteCollection,
          'limit': 100,
          'reverse': true, // Most recent first
        },
      );

      if (response.data == null) {
        return null;
      }

      final records = response.data!['records'] as List<dynamic>?;
      if (records == null || records.isEmpty) {
        return null;
      }

      // Find vote for this specific post
      for (final record in records) {
        final recordMap = record as Map<String, dynamic>;
        final value = recordMap['value'] as Map<String, dynamic>?;

        if (value == null) {
          continue;
        }

        final subject = value['subject'] as Map<String, dynamic>?;
        if (subject == null) {
          continue;
        }

        final subjectUri = subject['uri'] as String?;
        if (subjectUri == postUri) {
          // Found existing vote!
          final direction = value['direction'] as String;
          final uri = recordMap['uri'] as String;

          // Extract rkey from URI
          // Format: at://did:plc:xyz/social.coves.interaction.vote/3kby...
          final rkey = uri.split('/').last;

          return ExistingVote(direction: direction, rkey: rkey);
        }
      }

      return null;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️  Failed to list votes: ${e.message}');
      }
      // Return null on error - assume no existing vote
      return null;
    }
  }

  /// Create vote record on PDS
  ///
  /// Calls com.atproto.repo.createRecord with the vote record.
  Future<VoteResponse> _createVote({
    required String userDid,
    required String pdsUrl,
    required String postUri,
    required String postCid,
    required String direction,
  }) async {
    // Build the vote record according to the lexicon
    final record = {
      r'$type': voteCollection,
      'subject': {
        'uri': postUri,
        'cid': postCid,
      },
      'direction': direction,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '$pdsUrl/xrpc/com.atproto.repo.createRecord',
      data: {
        'repo': userDid,
        'collection': voteCollection,
        'record': record,
      },
    );

    if (response.data == null) {
      throw ApiException('Empty response from PDS');
    }

    final uri = response.data!['uri'] as String?;
    final cid = response.data!['cid'] as String?;

    if (uri == null || cid == null) {
      throw ApiException('Invalid response from PDS - missing uri or cid');
    }

    // Extract rkey from URI
    final rkey = uri.split('/').last;

    return VoteResponse(
      uri: uri,
      cid: cid,
      rkey: rkey,
      deleted: false,
    );
  }

  /// Delete vote record from PDS
  ///
  /// Calls com.atproto.repo.deleteRecord to remove the vote.
  Future<void> _deleteVote({
    required String userDid,
    required String pdsUrl,
    required String rkey,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$pdsUrl/xrpc/com.atproto.repo.deleteRecord',
      data: {
        'repo': userDid,
        'collection': voteCollection,
        'rkey': rkey,
      },
    );
  }
}

/// Vote Response
///
/// Response from createVote operation.
class VoteResponse {
  const VoteResponse({
    this.uri,
    this.cid,
    this.rkey,
    required this.deleted,
  });

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
