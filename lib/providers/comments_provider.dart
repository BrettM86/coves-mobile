import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// Comments Provider
///
/// Manages comment state and fetching logic for a specific post.
/// Supports sorting (hot/top/new), pagination, and vote integration.
///
/// IMPORTANT: Accepts AuthProvider reference to fetch fresh access
/// tokens before each authenticated request (critical for atProto OAuth
/// token rotation).
class CommentsProvider with ChangeNotifier {
  CommentsProvider(
    this._authProvider, {
    CovesApiService? apiService,
    VoteProvider? voteProvider,
  }) : _voteProvider = voteProvider {
    // Use injected service (for testing) or create new one (for production)
    // Pass token getter, refresh handler, and sign out handler to API service
    // for automatic fresh token retrieval and automatic token refresh on 401
    _apiService =
        apiService ??
        CovesApiService(
          tokenGetter: _authProvider.getAccessToken,
          tokenRefresher: _authProvider.refreshToken,
          signOutHandler: _authProvider.signOut,
        );

    // Track initial auth state
    _wasAuthenticated = _authProvider.isAuthenticated;

    // Listen to auth state changes and clear comments on sign-out
    _authProvider.addListener(_onAuthChanged);
  }

  /// Handle authentication state changes
  ///
  /// Clears comment state when user signs out to prevent privacy issues.
  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;

    // Only clear if transitioning from authenticated → unauthenticated
    if (_wasAuthenticated && !isAuthenticated && _comments.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing comments');
      }
      reset();
    }

    // Update tracked state
    _wasAuthenticated = isAuthenticated;
  }

  final AuthProvider _authProvider;
  late final CovesApiService _apiService;
  final VoteProvider? _voteProvider;

  // Track previous auth state to detect transitions
  bool _wasAuthenticated = false;

  // Comment state
  List<ThreadViewComment> _comments = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;

  // Current post URI being viewed
  String? _postUri;

  // Comment configuration
  String _sort = 'hot';
  String? _timeframe;

  // Flag to track if a refresh should be scheduled after current load
  bool _pendingRefresh = false;

  // Time update mechanism for periodic UI refreshes
  Timer? _timeUpdateTimer;
  final ValueNotifier<DateTime?> _currentTimeNotifier = ValueNotifier(null);

  // Getters
  List<ThreadViewComment> get comments => _comments;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get sort => _sort;
  String? get timeframe => _timeframe;
  ValueNotifier<DateTime?> get currentTimeNotifier => _currentTimeNotifier;

  /// Start periodic time updates for "time ago" strings
  ///
  /// Updates currentTime every minute to trigger UI rebuilds for
  /// comment timestamps. This ensures "5m ago" updates to "6m ago" without
  /// requiring user interaction.
  ///
  /// Uses ValueNotifier to avoid triggering full provider rebuilds.
  void startTimeUpdates() {
    // Cancel existing timer if any
    _timeUpdateTimer?.cancel();

    // Update current time immediately
    _currentTimeNotifier.value = DateTime.now();

    // Set up periodic updates (every minute)
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _currentTimeNotifier.value = DateTime.now();
    });

    if (kDebugMode) {
      debugPrint('⏰ Started periodic time updates for comment timestamps');
    }
  }

  /// Stop periodic time updates
  void stopTimeUpdates() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
    _currentTimeNotifier.value = null;

    if (kDebugMode) {
      debugPrint('⏰ Stopped periodic time updates');
    }
  }

  /// Load comments for a specific post
  Future<void> loadComments({
    required String postUri,
    bool refresh = false,
  }) async {
    // If loading for a different post, reset state
    if (postUri != _postUri) {
      reset();
      _postUri = postUri;
    }

    // If already loading, schedule a refresh to happen after current load
    if (_isLoading || _isLoadingMore) {
      if (refresh) {
        _pendingRefresh = true;
        if (kDebugMode) {
          debugPrint(
            '⏳ Load in progress - scheduled refresh for after completion',
          );
        }
      }
      return;
    }

    try {
      if (refresh) {
        _isLoading = true;
        _error = null;
        _pendingRefresh = false; // Clear any pending refresh
      } else {
        _isLoadingMore = true;
      }
      notifyListeners();

      if (kDebugMode) {
        debugPrint('📡 Fetching comments: sort=$_sort, postUri=$postUri');
      }

      final response = await _apiService.getComments(
        postUri: postUri,
        sort: _sort,
        timeframe: _timeframe,
        cursor: refresh ? null : _cursor,
      );

      // Only update state after successful fetch
      if (refresh) {
        _comments = response.comments;
      } else {
        // Create new list instance to trigger rebuilds
        _comments = [..._comments, ...response.comments];
      }

      _cursor = response.cursor;
      _hasMore = response.cursor != null;
      _error = null;

      if (kDebugMode) {
        debugPrint('✅ Comments loaded: ${_comments.length} comments total');
      }

      // Initialize vote state from viewer data in comments response
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        if (refresh) {
          // On refresh, initialize all comments - server data is truth
          _comments.forEach(_initializeCommentVoteState);
        } else {
          // On pagination, only initialize newly fetched comments to avoid
          // overwriting optimistic vote state on existing comments
          response.comments.forEach(_initializeCommentVoteState);
        }
      }

      // Start time updates when comments are loaded
      if (_comments.isNotEmpty && _timeUpdateTimer == null) {
        startTimeUpdates();
      }
    } on Exception catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch comments: $e');
      }
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();

      // If a refresh was scheduled during this load, execute it now
      if (_pendingRefresh && _postUri != null) {
        if (kDebugMode) {
          debugPrint('🔄 Executing pending refresh');
        }
        _pendingRefresh = false;
        // Schedule refresh without awaiting to avoid blocking
        // This is intentional - we want the refresh to happen asynchronously
        unawaited(loadComments(postUri: _postUri!, refresh: true));
      }
    }
  }

  /// Refresh comments (pull-to-refresh)
  ///
  /// Reloads comments from the beginning for the current post.
  Future<void> refreshComments() async {
    if (_postUri == null) {
      if (kDebugMode) {
        debugPrint('⚠️ Cannot refresh - no post loaded');
      }
      return;
    }
    await loadComments(postUri: _postUri!, refresh: true);
  }

  /// Load more comments (pagination)
  Future<void> loadMoreComments() async {
    if (!_hasMore || _isLoadingMore || _postUri == null) {
      return;
    }
    await loadComments(postUri: _postUri!);
  }

  /// Change sort order
  ///
  /// Updates the sort option and triggers a refresh of comments.
  /// Available options: 'hot', 'top', 'new'
  ///
  /// Returns true if sort change succeeded, false if reload failed.
  /// On failure, reverts to previous sort option.
  Future<bool> setSortOption(String newSort) async {
    if (_sort == newSort) {
      return true;
    }

    final previousSort = _sort;
    _sort = newSort;
    notifyListeners();

    // Reload comments with new sort
    if (_postUri != null) {
      try {
        await loadComments(postUri: _postUri!, refresh: true);
        return true;
      } on Exception catch (e) {
        // Revert to previous sort option on failure
        _sort = previousSort;
        notifyListeners();

        if (kDebugMode) {
          debugPrint('Failed to apply sort option: $e');
        }

        return false;
      }
    }

    return true;
  }

  /// Vote on a comment
  ///
  /// Delegates to VoteProvider for optimistic updates and API calls.
  /// The VoteProvider handles:
  /// - Optimistic UI updates
  /// - API call to user's PDS
  /// - Rollback on error
  ///
  /// Parameters:
  /// - [commentUri]: AT-URI of the comment
  /// - [commentCid]: Content ID of the comment
  /// - [voteType]: Vote direction ('up' or 'down')
  ///
  /// Returns:
  /// - true if vote was created
  /// - false if vote was removed (toggled off)
  Future<bool> voteOnComment({
    required String commentUri,
    required String commentCid,
    String voteType = 'up',
  }) async {
    if (_voteProvider == null) {
      throw Exception('VoteProvider not available');
    }

    try {
      final result = await _voteProvider.toggleVote(
        postUri: commentUri,
        postCid: commentCid,
        direction: voteType,
      );

      if (kDebugMode) {
        debugPrint('✅ Comment vote ${result ? 'created' : 'removed'}');
      }

      return result;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to vote on comment: $e');
      }
      rethrow;
    }
  }

  /// Initialize vote state for a comment and its replies recursively
  ///
  /// Extracts viewer vote data from comment and initializes VoteProvider state.
  /// Handles nested replies recursively.
  ///
  /// IMPORTANT: Always calls setInitialVoteState, even when viewer.vote is
  /// null. This ensures that if a user removed their vote on another device,
  /// the local state is cleared on refresh.
  void _initializeCommentVoteState(ThreadViewComment threadComment) {
    final viewer = threadComment.comment.viewer;
    _voteProvider!.setInitialVoteState(
      postUri: threadComment.comment.uri,
      voteDirection: viewer?.vote,
      voteUri: viewer?.voteUri,
    );

    // Recursively initialize vote state for replies
    threadComment.replies?.forEach(_initializeCommentVoteState);
  }

  /// Retry loading after error
  Future<void> retry() async {
    _error = null;
    if (_postUri != null) {
      await loadComments(postUri: _postUri!, refresh: true);
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Reset comment state
  void reset() {
    _comments = [];
    _cursor = null;
    _hasMore = true;
    _error = null;
    _isLoading = false;
    _isLoadingMore = false;
    _postUri = null;
    _pendingRefresh = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Stop time updates and cancel timer (also sets value to null)
    stopTimeUpdates();
    // Remove auth listener to prevent memory leaks
    _authProvider.removeListener(_onAuthChanged);
    _apiService.dispose();
    // Dispose the ValueNotifier last
    _currentTimeNotifier.dispose();
    super.dispose();
  }
}
