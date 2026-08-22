import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/feed_state.dart';
import '../models/post.dart';
import '../services/coves_api_service.dart';
import '../services/viewer_state_hydrator.dart';
import 'auth_provider.dart';
import 'community_subscription_provider.dart';
import 'vote_provider.dart';

/// Feed types available in the app
enum FeedType {
  /// All posts across the network
  discover,

  /// Posts from subscribed communities (authenticated only)
  forYou,
}

/// Multi-Feed Provider
///
/// Manages independent state for multiple feeds (Discover and For You).
/// Each feed maintains its own posts, scroll position, and pagination state.
///
/// The [CovesApiService] is injected (shared app-wide, owned by main.dart)
/// and must not be disposed here.
class MultiFeedProvider with ChangeNotifier {
  MultiFeedProvider(
    AuthProvider authProvider, {
    required CovesApiService apiService,
    VoteProvider? voteProvider,
    CommunitySubscriptionProvider? subscriptionProvider,
    ViewerStateHydrator? hydrator,
  })  : _authProvider = authProvider,
        _apiService = apiService,
        _hydrator = hydrator ??
            ViewerStateHydrator(
              authProvider: authProvider,
              voteProvider: voteProvider,
              subscriptionProvider: subscriptionProvider,
            ) {
    // Track initial auth state
    _wasAuthenticated = _authProvider.isAuthenticated;

    // Listen to auth state changes and clear For You feed on sign-out
    // This prevents privacy bug where logged-out users see their
    // private timeline until they manually refresh.
    _authProvider.addListener(_onAuthChanged);
  }

  /// Handle authentication state changes
  ///
  /// Only clears For You feed when transitioning from authenticated to
  /// unauthenticated (actual sign-out), not when staying unauthenticated
  /// (e.g., failed sign-in attempt). This prevents unnecessary API calls.
  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;

    // Only clear For You feed if transitioning from authenticated to
    // unauthenticated
    if (_wasAuthenticated && !isAuthenticated) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing For You feed');
      }
      // Clear For You feed state, keep Discover intact
      _feedStates.remove(FeedType.forYou);

      // Switch to Discover if currently on For You
      if (_currentFeedType == FeedType.forYou) {
        _currentFeedType = FeedType.discover;
      }

      notifyListeners();
    }

    // Update tracked state
    _wasAuthenticated = isAuthenticated;
  }

  final AuthProvider _authProvider;
  final CovesApiService _apiService;

  /// Seeds vote/subscription state from each response. Injected app-wide;
  /// when omitted, built from the raw vote/subscription providers this
  /// constructor still accepts.
  final ViewerStateHydrator _hydrator;

  // Track previous auth state to detect transitions
  bool _wasAuthenticated = false;

  // Per-feed state storage
  final Map<FeedType, FeedState> _feedStates = {};

  // Currently active feed
  FeedType _currentFeedType = FeedType.discover;

  // Feed configuration (shared across feeds)
  String _sort = 'hot';
  String? _timeframe;

  // Time update mechanism for periodic UI refreshes
  Timer? _timeUpdateTimer;
  DateTime? _currentTime;

  // Getters
  FeedType get currentFeedType => _currentFeedType;
  String get sort => _sort;
  String? get timeframe => _timeframe;
  DateTime? get currentTime => _currentTime;

  /// Check if For You feed is available (requires authentication)
  bool get isForYouAvailable => _authProvider.isAuthenticated;

  /// Get state for a specific feed (creates default if missing)
  FeedState getState(FeedType type) {
    return _feedStates[type] ?? FeedState.initial();
  }

  /// Set the current active feed type
  ///
  /// This just updates which feed is active, does NOT load data.
  /// The UI should call loadFeed() separately if needed.
  void setCurrentFeed(FeedType type) {
    if (_currentFeedType == type) {
      return;
    }

    // For You requires authentication
    if (type == FeedType.forYou && !_authProvider.isAuthenticated) {
      return;
    }

    _currentFeedType = type;
    notifyListeners();
  }

  /// Save scroll position for a feed (passive, no notifyListeners)
  ///
  /// This is called frequently during scrolling, so we don't trigger
  /// rebuilds. The scroll position is persisted in the feed state for
  /// restoration when the user switches back to this feed.
  void saveScrollPosition(FeedType type, double position) {
    final currentState = getState(type);
    _feedStates[type] = currentState.copyWith(scrollPosition: position);
    // Intentionally NOT calling notifyListeners() - this is a passive save
  }

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

  /// Load feed based on feed type
  ///
  /// This method encapsulates the business logic of deciding which feed
  /// to fetch based on the selected feed type.
  Future<void> loadFeed(FeedType type, {bool refresh = false}) async {
    // For You requires authentication - fall back to Discover if not
    if (type == FeedType.forYou && _authProvider.isAuthenticated) {
      await _fetchTimeline(type, refresh: refresh);
    } else {
      await _fetchDiscover(type, refresh: refresh);
    }

    // Start time updates when feed is loaded
    final state = getState(type);
    if (state.posts.isNotEmpty && _timeUpdateTimer == null) {
      startTimeUpdates();
    }
  }

  /// Load more posts for a feed (pagination)
  Future<void> loadMore(FeedType type) async {
    final state = getState(type);

    if (!state.hasMore || state.isLoadingMore) {
      return;
    }

    await loadFeed(type);
  }

  /// Common feed fetching logic (DRY principle - eliminates code
  /// duplication)
  Future<void> _fetchFeed({
    required FeedType type,
    required bool refresh,
    required Future<TimelineResponse> Function() fetcher,
    required String feedName,
  }) async {
    final currentState = getState(type);

    if (currentState.isLoading || currentState.isLoadingMore) {
      return;
    }

    // Capture session identity before fetch to detect any auth change
    // (sign-out, or sign-in as different user) during the request
    final sessionDidBeforeFetch = _authProvider.did;

    try {
      if (refresh) {
        // Start loading, keep existing data visible
        _feedStates[type] = currentState.copyWith(isLoading: true, error: null);
      } else {
        // Pagination
        _feedStates[type] = currentState.copyWith(isLoadingMore: true);
      }
      notifyListeners();

      final response = await fetcher();

      // SECURITY: If session changed during fetch, discard the response
      // to prevent cross-session data leaks. This handles:
      // - User signed out (DID became null)
      // - User signed out and back in as same user (unlikely but safe)
      // - User signed out and different user signed in (DID changed)
      // This is especially important for the For You feed which contains
      // private timeline data.
      if (type == FeedType.forYou &&
          sessionDidBeforeFetch != _authProvider.did) {
        if (kDebugMode) {
          debugPrint(
            '🔒 Discarding $feedName response - session changed during fetch',
          );
        }
        // Remove the feed state entirely (don't write back stale data)
        // _onAuthChanged already removed this, but ensure it stays removed
        _feedStates.remove(type);
        notifyListeners();
        return;
      }

      // Only update state after successful fetch.
      //
      // Always a new list instance so context.select rebuilds fire, and
      // always deduplicated by post URI: keyset pagination over a mutable
      // hot score is never perfectly stable, so a page can re-deliver a
      // post already on screen. feed_page keys rows by that same URI, so
      // an un-deduped append would render a second PostCard (and trip the
      // duplicate-key assertion in debug builds). Mirrors
      // CursorPaginationController's `idOf` guard.
      final existing = refresh
          ? const <FeedViewPost>[]
          : currentState.posts;
      final newPosts = [
        ...existing,
        ..._withoutDuplicates(response.feed, existing),
      ];

      final hasMore = response.cursor != null;

      _feedStates[type] = currentState.copyWith(
        posts: newPosts,
        cursor: response.cursor,
        hasMore: hasMore,
        error: null,
        isLoading: false,
        isLoadingMore: false,
        lastRefreshTime:
            refresh ? DateTime.now() : currentState.lastRefreshTime,
      );

      if (kDebugMode) {
        debugPrint('✅ $feedName loaded: ${newPosts.length} posts total');
      }

      // Seed votes and subscription state from the viewer data this
      // response carried.
      //
      // The RAW response feed is passed on purpose, not the deduplicated
      // `newPosts`: on cursor drift a page can re-deliver a post already on
      // screen, and while the list above drops that duplicate, this site
      // still hydrates it - a re-delivered post is a fresh server snapshot
      // of viewer state, and VoteProvider.applyServerVoteState already
      // guards an optimistic vote against being clobbered by it (covered by
      // multi_feed_provider_vote_regression_test). The
      // CursorPaginationController-backed sites drop it before hydrating.
      // Hydration also sits inside the try above, so a throw here lands on
      // the feed's error state - unlike the controller sites, which keep
      // the page and report. Both differences are deliberate and belong to
      // this caller, not to the hydrator.
      _hydrator.hydrateFeed(response.feed);
    } on Exception catch (e) {
      // SECURITY: Also check session change in error path to prevent
      // leaking stale data when a fetch fails after sign-out
      if (type == FeedType.forYou &&
          sessionDidBeforeFetch != _authProvider.did) {
        if (kDebugMode) {
          debugPrint(
            '🔒 Discarding $feedName error - session changed during fetch',
          );
        }
        _feedStates.remove(type);
        notifyListeners();
        return;
      }

      _feedStates[type] = currentState.copyWith(
        error: e.toString(),
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Failed to fetch $feedName: $e');
      }
    } finally {
      // Defense-in-depth: a non-Exception error (e.g. a TypeError from
      // malformed JSON) bypasses the `on Exception` catch above and would
      // otherwise leave isLoading/isLoadingMore stuck true forever.
      // Guarantee the flags are cleared so the feed can retry.
      final latestState = _feedStates[type];
      if (latestState != null &&
          (latestState.isLoading || latestState.isLoadingMore)) {
        _feedStates[type] = latestState.copyWith(
          isLoading: false,
          isLoadingMore: false,
        );
      }
      notifyListeners();
    }
  }

  /// [incoming] minus every post whose URI is already in [existing] or
  /// earlier in [incoming] itself. Same rule as
  /// CursorPaginationController's `idOf` dedup.
  static List<FeedViewPost> _withoutDuplicates(
    List<FeedViewPost> incoming,
    List<FeedViewPost> existing,
  ) {
    final seen = existing.map((p) => p.post.uri).toSet();
    return [
      for (final post in incoming)
        if (seen.add(post.post.uri)) post,
    ];
  }

  /// Fetch timeline feed (authenticated)
  ///
  /// Fetches the user's personalized timeline.
  /// Authentication is handled automatically via tokenGetter.
  Future<void> _fetchTimeline(FeedType type, {bool refresh = false}) {
    final currentState = getState(type);

    return _fetchFeed(
      type: type,
      refresh: refresh,
      fetcher:
          () => _apiService.getTimeline(
            sort: _sort,
            timeframe: _timeframe,
            cursor: refresh ? null : currentState.cursor,
          ),
      feedName: 'Timeline',
    );
  }

  /// Fetch discover feed (public)
  ///
  /// Fetches the public discover feed.
  /// Does not require authentication.
  Future<void> _fetchDiscover(FeedType type, {bool refresh = false}) {
    final currentState = getState(type);

    return _fetchFeed(
      type: type,
      refresh: refresh,
      fetcher:
          () => _apiService.getDiscover(
            sort: _sort,
            timeframe: _timeframe,
            cursor: refresh ? null : currentState.cursor,
          ),
      feedName: 'Discover',
    );
  }

  /// Change sort order
  void setSort(String newSort, {String? newTimeframe}) {
    _sort = newSort;
    _timeframe = newTimeframe;
    notifyListeners();
  }

  /// Retry loading after error for a specific feed
  Future<void> retry(FeedType type) async {
    final currentState = getState(type);
    _feedStates[type] = currentState.copyWith(error: null);
    notifyListeners();

    await loadFeed(type);
  }

  /// Clear error for a specific feed
  void clearError(FeedType type) {
    final currentState = getState(type);
    _feedStates[type] = currentState.copyWith(error: null);
    notifyListeners();
  }

  /// Reset feed state for a specific feed
  void reset(FeedType type) {
    _feedStates[type] = FeedState.initial();
    notifyListeners();
  }

  /// Reset all feeds
  void resetAll() {
    _feedStates.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    // Stop time updates and cancel timer
    stopTimeUpdates();
    // Remove auth listener to prevent memory leaks
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}
