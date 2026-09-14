import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/feed_state.dart';
import '../models/post.dart';
import '../services/api_exceptions.dart';
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
    required this._apiService,
    VoteProvider? voteProvider,
    CommunitySubscriptionProvider? subscriptionProvider,
    ViewerStateHydrator? hydrator,
    DateTime Function()? clock,
  }) : _authProvider = authProvider,
       _clock = clock ?? DateTime.now,
       _hydrator =
           hydrator ??
           ViewerStateHydrator(
             authProvider: authProvider,
             voteProvider: voteProvider,
             subscriptionProvider: subscriptionProvider,
           ) {
    _authDid = _authProvider.did;

    // Feed responses contain viewer state and cannot cross identities.
    _authProvider.addListener(_onAuthChanged);
  }

  /// Handle authentication state changes
  void _onAuthChanged() {
    if (_isDisposed) {
      return;
    }

    final isAuthenticated = _authProvider.isAuthenticated;
    final authDid = _authProvider.did;

    if (_authDid != authDid) {
      FeedType.values.forEach(_invalidateRequests);
      _feedStates.clear();

      if (!isAuthenticated) {
        _currentFeedType = FeedType.discover;
      }

      _authDid = authDid;
      notifyListeners();
      return;
    }

    _authDid = authDid;
  }

  final AuthProvider _authProvider;
  final CovesApiService _apiService;
  final DateTime Function() _clock;

  /// Seeds vote/subscription state from each response. Injected app-wide;
  /// when omitted, built from the raw vote/subscription providers this
  /// constructor still accepts.
  final ViewerStateHydrator _hydrator;

  String? _authDid;
  bool _isDisposed = false;

  // Per-feed state storage
  final Map<FeedType, FeedState> _feedStates = {};
  final Map<FeedType, int> _requestGenerations = {};
  final Set<FeedType> _pageOneRetryTargets = {};
  final Map<FeedType, DateTime> _cooldownDeadlines = {};

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
    if (_isDisposed) {
      return;
    }

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
    if (_isDisposed) {
      return;
    }

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
    if (_isDisposed) {
      return;
    }

    // Cancel existing timer if any
    _timeUpdateTimer?.cancel();

    // Update current time immediately
    _currentTime = DateTime.now();
    notifyListeners();

    // Set up periodic updates (every minute)
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_isDisposed) {
        return;
      }
      _currentTime = DateTime.now();
      notifyListeners();
    });

    if (kDebugMode) {
      debugPrint('⏰ Started periodic time updates for feed timestamps');
    }
  }

  /// Stop periodic time updates
  void stopTimeUpdates() {
    if (_isDisposed) {
      return;
    }

    _stopTimeUpdates();
  }

  void _stopTimeUpdates() {
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
    if (_isDisposed) {
      return;
    }

    // For You requires authentication - fall back to Discover if not
    if (type == FeedType.forYou && _authProvider.isAuthenticated) {
      await _fetchTimeline(type, refresh: refresh);
    } else {
      await _fetchDiscover(type, refresh: refresh);
    }

    if (_isDisposed) {
      return;
    }

    // Start time updates when feed is loaded
    final state = getState(type);
    if (state.posts.isNotEmpty && _timeUpdateTimer == null) {
      startTimeUpdates();
    }
  }

  /// Load more posts for a feed (pagination)
  Future<void> loadMore(FeedType type) async {
    if (_isDisposed) {
      return;
    }

    final state = getState(type);

    if (state.error != null ||
        state.loadMoreError != null ||
        !state.hasMore ||
        state.isLoadingMore) {
      return;
    }

    await loadFeed(type);
  }

  Future<void> retryLoadMore(FeedType type) async {
    if (_isDisposed) {
      return;
    }

    final state = getState(type);
    final cooldownDeadline = _cooldownDeadlines[type];
    if (cooldownDeadline != null) {
      final remaining = cooldownDeadline.difference(_clock());
      if (remaining > Duration.zero) {
        _feedStates[type] = state.copyWith(
          loadMoreError: _cooldownMessage(remaining),
        );
        notifyListeners();
        return;
      }
      _cooldownDeadlines.remove(type);
    }

    if (!state.hasMore || state.isLoading || state.isLoadingMore) {
      return;
    }

    if (state.loadMoreError != null) {
      _feedStates[type] = state.copyWith(loadMoreError: null);
      notifyListeners();
    }
    await loadFeed(type);
  }

  /// Common feed fetching logic (DRY principle - eliminates code
  /// duplication)
  Future<void> _fetchFeed({
    required FeedType type,
    required bool refresh,
    required Future<TimelineResponse> Function(String? cursor) fetcher,
    required String feedName,
    required bool isDiscoverHot,
  }) async {
    final currentState = getState(type);

    if (!refresh && (currentState.isLoading || currentState.isLoadingMore)) {
      return;
    }

    if (refresh) {
      _cooldownDeadlines.remove(type);
    }

    final requestGeneration = _beginRequest(type);
    final isPageOneRetry = !refresh && _pageOneRetryTargets.contains(type);
    final requestedCursor = refresh || isPageOneRetry
        ? null
        : currentState.cursor;

    // Capture session identity before fetch to detect any auth change
    // (sign-out, or sign-in as different user) during the request
    final sessionDidBeforeFetch = _authProvider.did;

    try {
      if (refresh) {
        // Start loading, keep existing data visible
        _feedStates[type] = currentState.copyWith(
          isLoading: true,
          isLoadingMore: false,
          error: null,
          loadMoreError: null,
        );
      } else {
        // Pagination
        _feedStates[type] = currentState.copyWith(
          isLoadingMore: true,
          loadMoreError: null,
        );
      }
      notifyListeners();

      TimelineResponse response;
      var replacePosts = refresh || isPageOneRetry;
      try {
        response = await fetcher(requestedCursor);
      } on ApiException catch (error) {
        if (!_ownsRequest(type, requestGeneration, sessionDidBeforeFetch)) {
          return;
        }
        if (!refresh &&
            !isPageOneRetry &&
            requestedCursor != null &&
            isDiscoverHot &&
            error.statusCode == 400 &&
            error.errorCode == 'InvalidCursor') {
          _pageOneRetryTargets.add(type);
          _feedStates[type] = getState(type)
              .copyWith(cursor: null, hasMore: true, loadMoreError: null);
          notifyListeners();
          response = await fetcher(null);
          replacePosts = true;
        } else {
          rethrow;
        }
      }

      if (!_ownsRequest(type, requestGeneration, sessionDidBeforeFetch)) {
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
      final existing = replacePosts
          ? const <FeedViewPost>[]
          : currentState.posts;
      final newPosts = [
        ...existing,
        ..._withoutDuplicates(response.feed, existing),
      ];

      final hasMore = response.cursor != null;

      _pageOneRetryTargets.remove(type);
      _cooldownDeadlines.remove(type);
      _feedStates[type] = currentState.copyWith(
        posts: newPosts,
        cursor: response.cursor,
        hasMore: hasMore,
        error: null,
        loadMoreError: null,
        isLoading: false,
        isLoadingMore: false,
        lastRefreshTime: refresh
            ? DateTime.now()
            : currentState.lastRefreshTime,
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
      if (!_ownsRequest(type, requestGeneration, sessionDidBeforeFetch)) {
        return;
      }

      final failedState = getState(type);
      if (!refresh) {
        var message = e.toString();
        if (isDiscoverHot &&
            e is ApiException &&
            e.statusCode == 503 &&
            e.errorCode == 'DiscoverUnavailable' &&
            (e.retryAfterSeconds ?? 0) > 0) {
          final duration = Duration(seconds: e.retryAfterSeconds!);
          _cooldownDeadlines[type] = _clock().add(duration);
          message = _cooldownMessage(duration);
        }
        _feedStates[type] = failedState.copyWith(
          loadMoreError: message,
          isLoading: false,
          isLoadingMore: false,
        );
      } else {
        _feedStates[type] = failedState.copyWith(
          error: e.toString(),
          isLoading: false,
          isLoadingMore: false,
        );
      }

      if (kDebugMode) {
        debugPrint('❌ Failed to fetch $feedName: $e');
      }
    } finally {
      // Defense-in-depth: a non-Exception error (e.g. a TypeError from
      // malformed JSON) bypasses the `on Exception` catch above and would
      // otherwise leave isLoading/isLoadingMore stuck true forever.
      // Guarantee the flags are cleared so the feed can retry.
      final latestState = _feedStates[type];
      if (_ownsRequest(type, requestGeneration, sessionDidBeforeFetch) &&
          latestState != null &&
          (latestState.isLoading || latestState.isLoadingMore)) {
        _feedStates[type] = latestState.copyWith(
          isLoading: false,
          isLoadingMore: false,
        );
      }
      if (_ownsRequest(type, requestGeneration, sessionDidBeforeFetch)) {
        notifyListeners();
      }
    }
  }

  int _beginRequest(FeedType type) {
    final generation = (_requestGenerations[type] ?? 0) + 1;
    _requestGenerations[type] = generation;
    return generation;
  }

  bool _ownsRequest(FeedType type, int generation, String? authDid) {
    return !_isDisposed &&
        _requestGenerations[type] == generation &&
        _authProvider.did == authDid;
  }

  void _invalidateRequests(FeedType type) {
    _requestGenerations[type] = (_requestGenerations[type] ?? 0) + 1;
    _pageOneRetryTargets.remove(type);
    _cooldownDeadlines.remove(type);
  }

  static String _cooldownMessage(Duration remaining) {
    final seconds =
        (remaining.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
    return 'Try again in $seconds seconds';
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
    final sort = _sort;
    final timeframe = _timeframe;

    return _fetchFeed(
      type: type,
      refresh: refresh,
      fetcher: (cursor) => _apiService.getTimeline(
        sort: sort,
        timeframe: timeframe,
        cursor: cursor,
      ),
      feedName: 'Timeline',
      isDiscoverHot: false,
    );
  }

  /// Fetch discover feed (public)
  ///
  /// Fetches the public discover feed.
  /// Does not require authentication.
  Future<void> _fetchDiscover(FeedType type, {bool refresh = false}) {
    final sort = _sort;
    final timeframe = _timeframe;

    return _fetchFeed(
      type: type,
      refresh: refresh,
      fetcher: (cursor) => _apiService.getDiscover(
        sort: sort,
        timeframe: timeframe,
        cursor: cursor,
      ),
      feedName: 'Discover',
      isDiscoverHot: type == FeedType.discover && sort == 'hot',
    );
  }

  /// Change sort order
  void setSort(String newSort, {String? newTimeframe}) {
    if (_isDisposed) {
      return;
    }

    if (_sort == newSort && _timeframe == newTimeframe) {
      return;
    }

    _sort = newSort;
    _timeframe = newTimeframe;
    for (final type in FeedType.values) {
      _invalidateRequests(type);
      _pageOneRetryTargets.add(type);
      final state = _feedStates[type];
      if (state != null) {
        _feedStates[type] = state.copyWith(
          cursor: null,
          hasMore: true,
          isLoading: false,
          isLoadingMore: false,
          loadMoreError: null,
        );
      }
    }
    notifyListeners();
  }

  /// Retry loading after error for a specific feed
  Future<void> retry(FeedType type) async {
    if (_isDisposed) {
      return;
    }

    final currentState = getState(type);
    _feedStates[type] = currentState.copyWith(error: null);
    notifyListeners();

    await loadFeed(type, refresh: true);
  }

  /// Clear error for a specific feed
  void clearError(FeedType type) {
    if (_isDisposed) {
      return;
    }

    final currentState = getState(type);
    _feedStates[type] = currentState.copyWith(error: null);
    notifyListeners();
  }

  /// Reset feed state for a specific feed
  void reset(FeedType type) {
    if (_isDisposed) {
      return;
    }

    _invalidateRequests(type);
    _feedStates[type] = FeedState.initial();
    notifyListeners();
  }

  /// Reset all feeds
  void resetAll() {
    if (_isDisposed) {
      return;
    }

    FeedType.values.forEach(_invalidateRequests);
    _feedStates.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    FeedType.values.forEach(_invalidateRequests);
    // Stop time updates and cancel timer
    _stopTimeUpdates();
    // Remove auth listener to prevent memory leaks
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}
