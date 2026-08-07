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

    // Save current state for rollback on error. Key PRESENCE is saved
    // separately from the value: an adjustment key with value 0 (e.g. a
    // like then unlike, neither indexed yet) is what routes
    // [applyServerVoteState] into reconciliation, so a rollback that
    // dropped it would let the next stale snapshot resurrect the removed
    // vote.
    final previousState = _votes[postUri];
    final hadAdjustment = _scoreAdjustments.containsKey(postUri);
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

    void rollbackOptimisticUpdate() {
      if (previousState != null) {
        _votes[postUri] = previousState;
      } else {
        _votes.remove(postUri);
      }

      if (hadAdjustment) {
        _scoreAdjustments[postUri] = previousAdjustment;
      } else {
        _scoreAdjustments.remove(postUri);
      }

      notifyListeners();
    }

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

      rollbackOptimisticUpdate();
      rethrow;
      // Deliberately broad: a non-ApiException failure (a TypeError from a
      // malformed response, a StateError) must not strand the optimistic
      // vote — the leftover adjustment key would route every future
      // snapshot into reconciliation and the wrong state could persist for
      // the whole session.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to toggle vote (unexpected): $e');
      }

      rollbackOptimisticUpdate();
      rethrow;
    } finally {
      _pendingRequests.remove(postUri);
    }
  }

  /// Apply a server snapshot of the viewer's vote on [postUri].
  ///
  /// This is the only entry point for server-delivered vote state: every
  /// fetch path (initial load, pagination, refresh, thread hydration) calls
  /// it and the provider — not the caller — decides whether the snapshot may
  /// overwrite local state. No caller-side flag can make that call: "this
  /// surface did a full refresh" does not imply "the server has seen my last
  /// vote", because the appview indexes votes asynchronously via the
  /// firehose. The facts that decide it live here: whether a write is in
  /// flight, and whether this URI has an unreconciled local mutation (a
  /// score adjustment left by [toggleVote]).
  ///
  /// - Request in flight for this URI: ignore the snapshot, it predates the
  ///   write.
  /// - Local mutation outstanding: reconcile it
  ///   ([_reconcileServerVoteState]).
  /// - Otherwise: adopt the snapshot ([_adoptServerVoteState]).
  ///
  /// Caller contract: pass only snapshots the current response actually
  /// delivered. A cached or merge-preserved copy of an older snapshot must
  /// not be re-applied — once its URI has no outstanding adjustment it
  /// would be adopted verbatim and could roll the vote back to a state the
  /// server has since moved past.
  ///
  /// Parameters:
  /// - [postUri]: AT-URI of the post
  /// - [voteDirection]: Vote direction in the snapshot ("up", "down", null)
  /// - [voteUri]: AT-URI of the vote record in the snapshot
  void applyServerVoteState({
    required String postUri,
    String? voteDirection,
    String? voteUri,
  }) {
    if (_pendingRequests[postUri] ?? false) {
      return;
    }

    if (_scoreAdjustments.containsKey(postUri)) {
      _reconcileServerVoteState(
        postUri: postUri,
        serverVoteDirection: voteDirection,
        serverVoteUri: voteUri,
      );
    } else {
      _adoptServerVoteState(
        postUri: postUri,
        voteDirection: voteDirection,
        voteUri: voteUri,
      );
    }
  }

  /// Adopts the server snapshot verbatim for a post with no outstanding
  /// local mutation.
  ///
  /// A null [voteDirection] clears the local vote rather than being ignored:
  /// that is how a vote removed on another device lands here.
  void _adoptServerVoteState({
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

    // Defensive only: the router sends every URI with an adjustment key to
    // _reconcileServerVoteState, so no key can exist here. Double-count
    // protection lives in that routing, not in this removal.
    _scoreAdjustments.remove(postUri);

    // No notify: every fetch path applies snapshots right before its own
    // provider/setState notification, and the vote widgets re-read this
    // provider when their surface rebuilds. Reconciliation DOES notify when
    // it clears a non-zero adjustment, because there the displayed score
    // changes without the surface re-rendering its list.
  }

  /// Reconciles the server snapshot against an outstanding local mutation.
  ///
  /// The snapshot may or may not include a vote cast optimistically (the
  /// appview indexes votes asynchronously via the firehose), so the local
  /// score adjustment can only be cleared once the viewer state confirms
  /// the server has caught up:
  /// - Server viewer state matches the local effective state: the server
  ///   score already includes the vote — adopt server state and clear the
  ///   adjustment so it can't double-count.
  /// - Mismatch: assume the server is behind — keep the optimistic state and
  ///   adjustment (stale server score + adjustment still renders correctly).
  ///   A mismatch can also mean the server is AHEAD (vote changed from
  ///   another device); favoring local state is the safe default there, and
  ///   the cross-device change lands once the local mutation reconciles.
  ///   Accepted trade-off: if the server durably never reports the local
  ///   direction (vote removed by moderation, or a firehose event lost),
  ///   the mismatch — and the optimistic display — persist until sign-out
  ///   or [clear]. That beats the alternative: any time-bound or
  ///   refresh-bound escape hatch re-opens the clobber-your-own-vote bug
  ///   whenever indexing lag exceeds the bound.
  ///
  /// Snapshots that are merely stale rather than lagging (e.g. a sibling
  /// page preserved across a merge) are safe by the same rule: they either
  /// mismatch (optimistic state kept) or match with a net-zero adjustment
  /// relative to that snapshot (clearing changes nothing).
  void _reconcileServerVoteState({
    required String postUri,
    String? serverVoteDirection,
    String? serverVoteUri,
  }) {
    final local = _votes[postUri];
    final localDirection =
        (local == null || local.deleted) ? null : local.direction;

    if (localDirection != serverVoteDirection) {
      return;
    }

    if (serverVoteDirection != null) {
      // Prefer the locally known vote URI: it came from the most recent
      // createVote response, while the server snapshot may predate a
      // delete/re-vote cycle and still reference the old record.
      final voteUri = local?.uri ?? serverVoteUri;
      _votes[postUri] = VoteState(
        direction: serverVoteDirection,
        uri: voteUri,
        rkey: VoteState.extractRkeyFromUri(voteUri),
        deleted: false,
      );
    } else {
      _votes.remove(postUri);
    }

    final removedAdjustment = _scoreAdjustments.remove(postUri);
    if (removedAdjustment != null && removedAdjustment != 0) {
      // The displayed score changes (server score is now authoritative), so
      // widgets watching this provider must rebuild.
      notifyListeners();
    }
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
