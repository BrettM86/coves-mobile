import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// Feed Provider
///
/// Manages feed state and fetching logic.
/// Supports both authenticated timeline and public discover feed.
///
/// IMPORTANT: Accepts AuthProvider reference to fetch fresh access
/// tokens before each authenticated request (critical for atProto OAuth
/// token rotation).
class FeedProvider with ChangeNotifier {
  FeedProvider(
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

    // [P0 FIX] Listen to auth state changes and clear feed on sign-out
    // This prevents privacy bug where logged-out users see their private
    // timeline until they manually refresh.
    _authProvider.addListener(_onAuthChanged);
  }

  /// Handle authentication state changes
  ///
  /// Only clears and reloads feed when transitioning from authenticated
  /// to unauthenticated (actual sign-out), not when staying unauthenticated
  /// (e.g., failed sign-in attempt). This prevents unnecessary API calls.
  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;

    // Only reload if transitioning from authenticated → unauthenticated
    if (_wasAuthenticated && !isAuthenticated && _posts.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing feed');
      }
      reset();
      // Automatically load the public discover feed
      loadFeed(refresh: true);
    }

    // Update tracked state
    _wasAuthenticated = isAuthenticated;
  }

  final AuthProvider _authProvider;
  late final CovesApiService _apiService;
  final VoteProvider? _voteProvider;

  // Track previous auth state to detect transitions
  bool _wasAuthenticated = false;

  // Feed state
  List<FeedViewPost> _posts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;

  // Feed configuration
  String _sort = 'hot';
  String? _timeframe;

  // Time update mechanism for periodic UI refreshes
  Timer? _timeUpdateTimer;
  DateTime? _currentTime;

  // Getters
  List<FeedViewPost> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get sort => _sort;
  String? get timeframe => _timeframe;
  DateTime? get currentTime => _currentTime;

  /// Start periodic time updates for "time ago" strings
  ///
  /// Updates currentTime every minute to trigger UI rebuilds for
  /// post timestamps. This ensures "5m ago" updates to "6m ago" without
  /// requiring user interaction.
  void startTimeUpdates() {
    // Cancel existing timer if any
    _timeUpdateTimer?.cancel();

    // Update current time immediately
    _currentTime = DateTime.now();
    notifyListeners();

    // Set up periodic updates (every minute)
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _currentTime = DateTime.now();
      notifyListeners();
    });

    if (kDebugMode) {
      debugPrint('⏰ Started periodic time updates for feed timestamps');
    }
  }

  /// Stop periodic time updates
  void stopTimeUpdates() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
    _currentTime = null;

    if (kDebugMode) {
      debugPrint('⏰ Stopped periodic time updates');
    }
  }

  /// Load feed based on authentication state (business logic
  /// encapsulation)
  ///
  /// This method encapsulates the business logic of deciding which feed
  /// to fetch. Previously this logic was in the UI layer (FeedScreen),
  /// violating clean architecture.
  Future<void> loadFeed({bool refresh = false}) async {
    if (_authProvider.isAuthenticated) {
      await fetchTimeline(refresh: refresh);
    } else {
      await fetchDiscover(refresh: refresh);
    }

    // Start time updates when feed is loaded
    if (_posts.isNotEmpty && _timeUpdateTimer == null) {
      startTimeUpdates();
    }
  }

  /// Common feed fetching logic (DRY principle - eliminates code
  /// duplication)
  Future<void> _fetchFeed({
    required bool refresh,
    required Future<TimelineResponse> Function() fetcher,
    required String feedName,
  }) async {
    if (_isLoading || _isLoadingMore) {
      return;
    }

    try {
      if (refresh) {
        _isLoading = true;
        // DON'T clear _posts, _cursor, or _hasMore yet
        // Keep existing data visible until refresh succeeds
        // This prevents transient failures from wiping the user's feed
        // and pagination state
        _error = null;
      } else {
        _isLoadingMore = true;
      }
      notifyListeners();

      final response = await fetcher();

      // Only update state after successful fetch
      if (refresh) {
        _posts = response.feed;
      } else {
        // Create new list instance to trigger context.select rebuilds
        // Using spread operator instead of addAll to ensure reference changes
        _posts = [..._posts, ...response.feed];
      }

      _cursor = response.cursor;
      _hasMore = response.cursor != null;
      _error = null;

      if (kDebugMode) {
        debugPrint('✅ $feedName loaded: ${_posts.length} posts total');
      }

      // Initialize vote state from viewer data in feed response
      // IMPORTANT: Call setInitialVoteState for ALL feed items, even when
      // viewer.vote is null. This ensures that if a user removed their vote
      // on another device, the local state is cleared on refresh.
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        for (final feedItem in response.feed) {
          final viewer = feedItem.post.viewer;
          _voteProvider.setInitialVoteState(
            postUri: feedItem.post.uri,
            voteDirection: viewer?.vote,
            voteUri: viewer?.voteUri,
          );
        }
      }
    } on Exception catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch $feedName: $e');
      }
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Fetch timeline feed (authenticated)
  ///
  /// Fetches the user's personalized timeline.
  /// Authentication is handled automatically via tokenGetter.
  Future<void> fetchTimeline({bool refresh = false}) => _fetchFeed(
    refresh: refresh,
    fetcher:
        () => _apiService.getTimeline(
          sort: _sort,
          timeframe: _timeframe,
          cursor: refresh ? null : _cursor,
        ),
    feedName: 'Timeline',
  );

  /// Fetch discover feed (public)
  ///
  /// Fetches the public discover feed.
  /// Does not require authentication.
  Future<void> fetchDiscover({bool refresh = false}) => _fetchFeed(
    refresh: refresh,
    fetcher:
        () => _apiService.getDiscover(
          sort: _sort,
          timeframe: _timeframe,
          cursor: refresh ? null : _cursor,
        ),
    feedName: 'Discover',
  );

  /// Load more posts (pagination)
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) {
      return;
    }
    await loadFeed();
  }

  /// Change sort order
  void setSort(String newSort, {String? newTimeframe}) {
    _sort = newSort;
    _timeframe = newTimeframe;
    notifyListeners();
  }

  /// Retry loading after error
  Future<void> retry() async {
    _error = null;
    await loadFeed(refresh: true);
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Reset feed state
  void reset() {
    _posts = [];
    _cursor = null;
    _hasMore = true;
    _error = null;
    _isLoading = false;
    _isLoadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Stop time updates and cancel timer
    stopTimeUpdates();
    // Remove auth listener to prevent memory leaks
    _authProvider.removeListener(_onAuthChanged);
    _apiService.dispose();
    super.dispose();
  }
}
