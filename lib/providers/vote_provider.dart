import 'package:flutter/foundation.dart';

import '../services/api_exceptions.dart';
import '../services/vote_service.dart';
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
  })  : _voteService = voteService,
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

  /// Get vote state for a post
  VoteState? getVoteState(String postUri) => _votes[postUri];

  /// Check if a post is liked/upvoted
  bool isLiked(String postUri) =>
      _votes[postUri]?.direction == 'up' &&
      !(_votes[postUri]?.deleted ?? false);

  /// Check if a request is pending for a post
  bool isPending(String postUri) => _pendingRequests[postUri] ?? false;

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
    final currentState = previousState;

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
      _votes[postUri] = VoteState(
        direction: direction,
        deleted: false,
      );
    }
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
        _votes[postUri] = VoteState(
          direction: direction,
          deleted: true,
        );
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
      // Extract rkey from vote URI if available
      // URI format: at://did:plc:xyz/social.coves.interaction.vote/3kby...
      String? rkey;
      if (voteUri != null) {
        final parts = voteUri.split('/');
        if (parts.isNotEmpty) {
          rkey = parts.last;
        }
      }

      _votes[postUri] = VoteState(
        direction: voteDirection,
        uri: voteUri,
        rkey: rkey,
        deleted: false,
      );
    } else {
      _votes.remove(postUri);
    }
    // Don't notify listeners - this is just initial state
  }

  /// Clear all vote state (e.g., on sign out)
  void clear() {
    _votes.clear();
    _pendingRequests.clear();
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
  /// "at://did:plc:xyz/social.coves.interaction.vote/3kby...")
  final String? rkey;

  /// Whether the vote has been deleted
  final bool deleted;
}
