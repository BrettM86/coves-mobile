import 'dart:convert';

import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
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
/// **DPoP Authentication**:
/// atProto PDSs require DPoP (Demonstrating Proof of Possession) authentication.
/// Uses OAuthSession.fetchHandler which automatically handles:
/// - Authorization: DPoP <access_token>
/// - DPoP: <proof> (signed JWT proving key possession)
/// - Automatic token refresh on expiry
/// - Nonce management for replay protection
class VoteService {
  VoteService({
    Future<OAuthSession?> Function()? sessionGetter,
    String? Function()? didGetter,
    String? Function()? pdsUrlGetter,
  })  : _sessionGetter = sessionGetter,
        _didGetter = didGetter,
        _pdsUrlGetter = pdsUrlGetter;

  final Future<OAuthSession?> Function()? _sessionGetter;
  final String? Function()? _didGetter;
  final String? Function()? _pdsUrlGetter;

  /// Collection name for vote records
  static const String voteCollection = 'social.coves.feed.vote';

  /// Get all votes for the current user
  ///
  /// Queries the user's PDS for all their vote records and returns a map
  /// of post URI -> vote info. This is used to initialize vote state when
  /// loading the feed.
  ///
  /// Returns:
  /// - Map<String, VoteInfo> where key is the post URI
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

      final votes = <String, VoteInfo>{};
      String? cursor;

      // Paginate through all vote records
      do {
        final url = cursor == null
            ? '/xrpc/com.atproto.repo.listRecords?repo=$userDid&collection=$voteCollection&limit=100'
            : '/xrpc/com.atproto.repo.listRecords?repo=$userDid&collection=$voteCollection&limit=100&cursor=$cursor';

        final response = await session.fetchHandler(url, method: 'GET');

        if (response.statusCode != 200) {
          if (kDebugMode) {
            debugPrint('⚠️  Failed to list votes: ${response.statusCode}');
          }
          break;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final records = data['records'] as List<dynamic>?;

        if (records != null) {
          for (final record in records) {
            final recordMap = record as Map<String, dynamic>;
            final value = recordMap['value'] as Map<String, dynamic>?;
            final uri = recordMap['uri'] as String?;

            if (value == null || uri == null) {
              continue;
            }

            final subject = value['subject'] as Map<String, dynamic>?;
            final direction = value['direction'] as String?;

            if (subject == null || direction == null) {
              continue;
            }

            final subjectUri = subject['uri'] as String?;
            if (subjectUri != null) {
              // Extract rkey from vote URI
              final rkey = uri.split('/').last;

              votes[subjectUri] = VoteInfo(
                direction: direction,
                voteUri: uri,
                rkey: rkey,
              );
            }
          }
        }

        cursor = data['cursor'] as String?;
      } while (cursor != null);

      if (kDebugMode) {
        debugPrint('📊 Loaded ${votes.length} votes from PDS');
      }

      return votes;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️  Failed to load user votes: $e');
      }
      return {};
    }
  }

  /// Create or toggle vote
  ///
  /// Implements smart toggle logic:
  /// 1. Query PDS for existing vote on this post (or use cached state)
  /// 2. If exists with same direction → Delete (toggle off)
  /// 3. If exists with different direction → Delete old + Create new
  /// 4. If no existing vote → Create new
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post (e.g.,
  ///   "at://did:plc:xyz/social.coves.post.record/abc123")
  /// - [postCid]: Content ID of the post (for strong reference)
  /// - [direction]: Vote direction - "up" for like/upvote, "down" for downvote
  /// - [existingVoteRkey]: Optional rkey from cached state (avoids O(n) lookup)
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
      // Use cached state if available to avoid O(n) PDS lookup
      ExistingVote? existingVote;
      if (existingVoteRkey != null && existingVoteDirection != null) {
        existingVote = ExistingVote(
          direction: existingVoteDirection,
          rkey: existingVoteRkey,
        );
        if (kDebugMode) {
          debugPrint('   Using cached vote state (avoiding PDS lookup)');
        }
      } else {
        existingVote = await _findExistingVote(
          userDid: userDid,
          postUri: postUri,
        );
      }

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
          rkey: existingVote.rkey,
        );
      }

      // Step 2: Create new vote
      final response = await _createVote(
        userDid: userDid,
        postUri: postUri,
        postCid: postCid,
        direction: direction,
      );

      if (kDebugMode) {
        debugPrint('✅ Vote created: ${response.uri}');
      }

      return response;
    } on Exception catch (e) {
      throw ApiException('Failed to create vote: $e');
    }
  }

  /// Find existing vote for a post
  ///
  /// Queries the user's PDS to check if they've already voted on this post.
  /// Uses cursor-based pagination to search through all vote records, not just
  /// the first 100. This prevents duplicate votes when users have voted on
  /// more than 100 posts.
  ///
  /// Returns ExistingVote with direction and rkey if found, null otherwise.
  Future<ExistingVote?> _findExistingVote({
    required String userDid,
    required String postUri,
  }) async {
    try {
      final session = await _sessionGetter?.call();
      if (session == null) {
        return null;
      }

      // Paginate through all vote records using cursor
      String? cursor;
      const pageSize = 100;

      do {
        // Build URL with cursor if available
        final url = cursor == null
            ? '/xrpc/com.atproto.repo.listRecords?repo=$userDid&collection=$voteCollection&limit=$pageSize&reverse=true'
            : '/xrpc/com.atproto.repo.listRecords?repo=$userDid&collection=$voteCollection&limit=$pageSize&reverse=true&cursor=$cursor';

        final response = await session.fetchHandler(url, method: 'GET');

        if (response.statusCode != 200) {
          if (kDebugMode) {
            debugPrint('⚠️  Failed to list votes: ${response.statusCode}');
          }
          return null;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final records = data['records'] as List<dynamic>?;

        // Search current page for matching vote
        if (records != null) {
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
              // Format: at://did:plc:xyz/social.coves.feed.vote/3kby...
              final rkey = uri.split('/').last;

              return ExistingVote(direction: direction, rkey: rkey);
            }
          }
        }

        // Get cursor for next page
        cursor = data['cursor'] as String?;
      } while (cursor != null);

      // Vote not found after searching all pages
      return null;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️  Failed to list votes: $e');
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
    required String postUri,
    required String postCid,
    required String direction,
  }) async {
    final session = await _sessionGetter?.call();
    if (session == null) {
      throw ApiException('User not authenticated - no session available');
    }

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

    final requestBody = jsonEncode({
      'repo': userDid,
      'collection': voteCollection,
      'record': record,
    });

    // Use session's fetchHandler for DPoP-authenticated request
    final response = await session.fetchHandler(
      '/xrpc/com.atproto.repo.createRecord',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to create vote: ${response.statusCode} - ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final uri = data['uri'] as String?;
    final cid = data['cid'] as String?;

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
    required String rkey,
  }) async {
    final session = await _sessionGetter?.call();
    if (session == null) {
      throw ApiException('User not authenticated - no session available');
    }

    final requestBody = jsonEncode({
      'repo': userDid,
      'collection': voteCollection,
      'rkey': rkey,
    });

    // Use session's fetchHandler for DPoP-authenticated request
    final response = await session.fetchHandler(
      '/xrpc/com.atproto.repo.deleteRecord',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to delete vote: ${response.statusCode} - ${response.body}',
        statusCode: response.statusCode,
      );
    }
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
