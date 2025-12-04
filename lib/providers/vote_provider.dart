import 'package:flutter/foundation.dart';

import '../services/api_exceptions.dart';
import '../services/vote_service.dart' show VoteService;
import 'auth_provider.dart';

/// Vote Provider
///
/// Manages vote state with optimistic UI updates.
/// Tracks local vote state keyed by post URI for instant feedback.
/// Automatically clears state when user signs out.
class VoteProvider with ChangeNotifier {
  VoteProvider({
    required VoteService voteService,
    required AuthProvider authProvider,
  }) : _voteService = voteService,
       _authProvider = authProvider {
    // Listen to auth state changes and clear votes on sign-out
    _authProvider.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    // Clear vote state when user signs out
    if (!_authProvider.isAuthenticated) {
      if (_votes.isNotEmpty) {
        clear();
        if (kDebugMode) {
          debugPrint('🧹 Cleared vote state on sign-out');
        }
      }
    }
  }

  final VoteService _voteService;
  final AuthProvider _authProvider;

  // Map of post URI -> vote state
  final Map<String, VoteState> _votes = {};

  // Map of post URI -> in-flight request flag
  final Map<String, bool> _pendingRequests = {};

  // Map of post URI -> score adjustment (for optimistic UI updates)
  // Tracks the local delta from the server's score
  final Map<String, int> _scoreAdjustments = {};

  /// Get vote state for a post
  VoteState? getVoteState(String postUri) => _votes[postUri];

  /// Check if a post is liked/upvoted
  bool isLiked(String postUri) =>
      _votes[postUri]?.direction == 'up' &&
      !(_votes[postUri]?.deleted ?? false);

  /// Check if a request is pending for a post
  bool isPending(String postUri) => _pendingRequests[postUri] ?? false;

  /// Get adjusted score for a post (server score + local optimistic adjustment)
  ///
  /// This allows the UI to show immediate feedback when users vote, even before
  /// the backend processes the vote and returns updated counts.
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [serverScore]: The score from the server (upvotes - downvotes)
  ///
  /// Returns: The adjusted score based on local vote state
  int getAdjustedScore(String postUri, int serverScore) {
    final adjustment = _scoreAdjustments[postUri] ?? 0;
    return serverScore + adjustment;
  }

  /// Toggle vote (like/unlike)
  ///
  /// Uses optimistic updates:
  /// 1. Immediately updates local state
  /// 2. Makes API call
  /// 3. Reverts on error
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [postCid]: Content ID of the post (for strong reference)
  /// - [direction]: Vote direction (defaults to "up" for like)
  ///
  /// Returns:
  /// - true if vote was created
  /// - false if vote was removed (toggled off)
  ///
  /// Throws:
  /// - ApiException if the request fails
  Future<bool> toggleVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    // Prevent concurrent requests for the same post
    if (_pendingRequests[postUri] ?? false) {
      if (kDebugMode) {
        debugPrint('⚠️ Vote request already in progress for $postUri');
      }
      return false;
    }

    // Save current state for rollback on error
    final previousState = _votes[postUri];
    final previousAdjustment = _scoreAdjustments[postUri] ?? 0;
    final currentState = previousState;

    // Calculate score adjustment for optimistic update
    var newAdjustment = previousAdjustment;

    if (currentState?.direction == direction &&
        !(currentState?.deleted ?? false)) {
      // Toggle off - removing vote
      if (direction == 'up') {
        newAdjustment -= 1; // Remove upvote
      } else {
        newAdjustment += 1; // Remove downvote
      }
    } else if (currentState?.direction != null &&
        currentState?.direction != direction &&
        !(currentState?.deleted ?? false)) {
      // Switching vote direction
      if (direction == 'up') {
        newAdjustment += 2; // Remove downvote (-1) and add upvote (+1)
      } else {
        newAdjustment -= 2; // Remove upvote (-1) and add downvote (+1)
      }
    } else {
      // Creating new vote (or re-creating after delete)
      if (direction == 'up') {
        newAdjustment += 1; // Add upvote
      } else {
        newAdjustment -= 1; // Add downvote
      }
    }

    // Optimistic update
    if (currentState?.direction == direction &&
        !(currentState?.deleted ?? false)) {
      // Toggle off - mark as deleted
      _votes[postUri] = VoteState(
        direction: direction,
        uri: currentState?.uri,
        rkey: currentState?.rkey,
        deleted: true,
      );
    } else {
      // Create or switch direction
      _votes[postUri] = VoteState(direction: direction, deleted: false);
    }

    // Apply score adjustment
    _scoreAdjustments[postUri] = newAdjustment;
    notifyListeners();

    // Mark request as pending
    _pendingRequests[postUri] = true;

    try {
      // Make API call
      final response = await _voteService.createVote(
        postUri: postUri,
        postCid: postCid,
        direction: direction,
      );

      // Update with server response
      if (response.deleted) {
        // Vote was removed
        _votes[postUri] = VoteState(direction: direction, deleted: true);
      } else {
        // Vote was created or updated
        _votes[postUri] = VoteState(
          direction: direction,
          uri: response.uri,
          rkey: response.rkey,
          deleted: false,
        );
      }

      notifyListeners();
      return !response.deleted;
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to toggle vote: ${e.message}');
      }

      // Rollback optimistic update
      if (previousState != null) {
        _votes[postUri] = previousState;
      } else {
        _votes.remove(postUri);
      }

      // Rollback score adjustment
      if (previousAdjustment != 0) {
        _scoreAdjustments[postUri] = previousAdjustment;
      } else {
        _scoreAdjustments.remove(postUri);
      }

      notifyListeners();

      rethrow;
    } finally {
      _pendingRequests.remove(postUri);
    }
  }

  /// Initialize vote state from post data
  ///
  /// Call this when loading posts to populate initial vote state
  /// from the backend's viewer state.
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [voteDirection]: Current vote direction ("up", "down", or null)
  /// - [voteUri]: AT-URI of the vote record
  void setInitialVoteState({
    required String postUri,
    String? voteDirection,
    String? voteUri,
  }) {
    if (voteDirection != null) {
      _votes[postUri] = VoteState(
        direction: voteDirection,
        uri: voteUri,
        rkey: VoteState.extractRkeyFromUri(voteUri),
        deleted: false,
      );
    } else {
      _votes.remove(postUri);
    }

    // IMPORTANT: Clear any stale score adjustment for this post.
    // When we receive fresh data from the server (via feed/comments refresh),
    // the server's score already reflects the actual vote state. Any local
    // delta from a previous optimistic update is now stale and would cause
    // double-counting (e.g., server score already includes +1, plus our +1).
    _scoreAdjustments.remove(postUri);

    // Don't notify listeners - this is just initial state
  }

  /// Clear all vote state (e.g., on sign out)
  void clear() {
    _votes.clear();
    _pendingRequests.clear();
    _scoreAdjustments.clear();
    notifyListeners();
  }
}

/// Vote State
///
/// Represents the current vote state for a post.
class VoteState {
  const VoteState({
    required this.direction,
    this.uri,
    this.rkey,
    required this.deleted,
  });

  /// Vote direction ("up" or "down")
  final String direction;

  /// AT-URI of the vote record (null if not yet created)
  final String? uri;

  /// Record key (rkey) of the vote - needed for deletion
  /// This is the last segment of the AT-URI (e.g., "3kby..." from
  /// "at://did:plc:xyz/social.coves.feed.vote/3kby...")
  final String? rkey;

  /// Whether the vote has been deleted
  final bool deleted;

  /// Extract rkey (record key) from an AT-URI
  ///
  /// AT-URI format: at://did:plc:xyz/social.coves.feed.vote/3kby...
  /// Returns the last segment (rkey) or null if URI is null/invalid.
  static String? extractRkeyFromUri(String? uri) {
    if (uri == null) return null;
    final parts = uri.split('/');
    return parts.isNotEmpty ? parts.last : null;
  }
}
