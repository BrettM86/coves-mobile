import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/comment.dart';
import '../models/feed_state.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/api_exceptions.dart';
import '../services/comment_service.dart';
import '../services/coves_api_service.dart';
import '../services/viewer_state_hydrator.dart';
import '../utils/cursor_pagination_controller.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// User Profile Provider
///
/// Manages state for user profile pages including profile data and
/// author posts feed. Supports viewing both own profile and other users.
///
/// The [CovesApiService] is injected (shared app-wide, owned by main.dart)
/// and must not be disposed here. Its auth callbacks are bound to the
/// app-level [AuthProvider], so they stay valid across auth state changes.
class UserProfileProvider with ChangeNotifier {
  UserProfileProvider(
    AuthProvider authProvider, {
    required CovesApiService apiService,
    required CommentService commentService,
    VoteProvider? voteProvider,
    ViewerStateHydrator? hydrator,
  }) : _authProvider = authProvider,
       _apiService = apiService,
       _commentService = commentService,
       _hydrator =
           hydrator ??
           ViewerStateHydrator(
             authProvider: authProvider,
             voteProvider: voteProvider,
           ) {
    // The two feeds are the same cursor-pagination state machine with
    // different fetchers; the controllers own items/cursor/loading/errors
    // and this provider projects them onto the FeedState / CommentsState
    // the screens already read.
    _postsController = CursorPaginationController<FeedViewPost>(
      fetchPage: _fetchPostsPage,
      onPageLoaded: _hydratePostVotes,
      errorMapper: _postsErrorMessage,
      // Server-side cursor drift hands back overlapping pages; the list
      // keys its rows by this same URI and asserts on duplicates.
      idOf: (feedItem) => feedItem.post.uri,
      onUnexpectedError: _reportUnexpected,
    )..addListener(_syncPostsState);

    _commentsController = CursorPaginationController<CommentView>(
      fetchPage: _fetchCommentsPage,
      onPageLoaded: _hydrateCommentVotes,
      errorMapper: _commentsErrorMessage,
      idOf: (comment) => comment.uri,
      onUnexpectedError: _reportUnexpected,
    )..addListener(_syncCommentsState);

    // Listen to auth state changes
    _authProvider.addListener(_onAuthChanged);
  }

  late final CursorPaginationController<FeedViewPost> _postsController;
  late final CursorPaginationController<CommentView> _commentsController;

  /// Everything the pagination controllers swallow: fetch failures the UI
  /// already reports, vote-hydration failures it does not, and failures of
  /// superseded requests.
  ///
  /// Typed [ApiException]s are skipped — they are the expected, already
  /// user-presentable failures (offline, 404, 401), and reporting them
  /// would drown the useful signal. A vote-hydration failure is exactly the
  /// kind of silent breakage that has shipped wrong vote state before, so
  /// it must reach crash reporting.
  void _reportUnexpected(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      return;
    }
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }

  AuthProvider _authProvider;

  /// Seeds vote state from each page this provider loads. Injected app-wide
  /// (where it also carries a subscription provider, which this surface
  /// deliberately never uses - see [_hydratePostVotes]); when omitted, built
  /// from the raw vote provider this constructor still accepts.
  ///
  /// Rebound whenever [_authProvider] changes - see [updateAuthProvider].
  ViewerStateHydrator _hydrator;

  final CommentService _commentService;

  /// Update auth provider reference (called by ChangeNotifierProxyProvider)
  ///
  /// The hydrator is rebound to the new instance, not just the listener.
  /// Its signed-in gate closes over whichever AuthProvider it was built
  /// with, and this provider's hydration used to consult `_authProvider`
  /// at call time - so leaving a stale hydrator here would silently keep
  /// gating on the previous session. main.dart asserts the instance never
  /// actually changes, but that assert is stripped in release.
  void updateAuthProvider(AuthProvider newAuth) {
    if (_authProvider != newAuth) {
      _authProvider.removeListener(_onAuthChanged);
      _authProvider = newAuth;
      _authProvider.addListener(_onAuthChanged);
      _hydrator = _hydrator.withAuthProvider(newAuth);
    }
  }

  final CovesApiService _apiService;

  // Profile state
  UserProfile? _profile;
  bool _isLoadingProfile = false;
  String? _profileError;
  String? _currentProfileDid;

  // Posts feed state — a projection of _postsController, rebuilt whenever
  // the controller notifies (reusing the FeedState pattern the screens read)
  FeedState _postsState = FeedState.initial();
  DateTime? _postsLastRefreshTime;

  // Comments feed state — a projection of _commentsController
  CommentsState _commentsState = CommentsState.initial();

  // LRU profile cache keyed by DID (max 50 entries)
  static const int _maxCacheSize = 50;
  final Map<String, UserProfile> _profileCache = {};
  final List<String> _cacheAccessOrder = [];

  /// Add profile to cache with LRU eviction
  void _cacheProfile(UserProfile profile) {
    final did = profile.did;

    // Remove from current position in access order
    _cacheAccessOrder.remove(did);

    // Add to end (most recently used)
    _cacheAccessOrder.add(did);
    _profileCache[did] = profile;

    // Evict oldest entries if over capacity
    while (_cacheAccessOrder.length > _maxCacheSize) {
      final oldestDid = _cacheAccessOrder.removeAt(0);
      _profileCache.remove(oldestDid);
    }
  }

  /// Get profile from cache (updates access order)
  UserProfile? _getCachedProfile(String did) {
    final profile = _profileCache[did];
    if (profile != null) {
      // Update access order (move to end)
      _cacheAccessOrder.remove(did);
      _cacheAccessOrder.add(did);
    }
    return profile;
  }

  // Getters
  UserProfile? get profile => _profile;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;
  String? get currentProfileDid => _currentProfileDid;
  FeedState get postsState => _postsState;
  CommentsState get commentsState => _commentsState;

  /// Check if currently viewing own profile
  bool get isOwnProfile {
    if (_currentProfileDid == null) return false;
    return _currentProfileDid == _authProvider.did;
  }

  /// Handle auth state changes
  void _onAuthChanged() {
    // Clear profile cache on sign-out to prevent stale data
    if (!_authProvider.isAuthenticated) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing profile cache');
      }
      _profileCache.clear();
      _cacheAccessOrder.clear();
      _profile = null;
      _resetFeeds();
      _currentProfileDid = null;
      notifyListeners();
    }
  }

  /// Load profile for a user
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  /// - [forceRefresh]: Bypass cache and fetch fresh data
  Future<void> loadProfile(String actor, {bool forceRefresh = false}) async {
    // Check cache first (updates LRU access order)
    final cachedProfile = _getCachedProfile(actor);
    if (cachedProfile != null && !forceRefresh) {
      _profile = cachedProfile;
      _currentProfileDid = cachedProfile.did;
      _profileError = null;
      notifyListeners();
      return;
    }

    if (_isLoadingProfile) return;

    _isLoadingProfile = true;
    _profileError = null;
    _currentProfileDid = actor.startsWith('did:') ? actor : null;
    notifyListeners();

    try {
      final profile = await _apiService.getProfile(actor: actor);

      // Cache by DID with LRU eviction
      _cacheProfile(profile);

      _profile = profile;
      _currentProfileDid = profile.did;
      _isLoadingProfile = false;
      _profileError = null;

      if (kDebugMode) {
        debugPrint('✅ Profile loaded: ${profile.displayNameOrHandle}');
      }
    } on NotFoundException {
      _isLoadingProfile = false;
      _profileError = 'User not found';
      _profile = null;

      if (kDebugMode) {
        debugPrint('❌ Profile not found: $actor');
      }
    } on AuthenticationException {
      _isLoadingProfile = false;
      _profileError = 'Please sign in to view this profile';

      if (kDebugMode) {
        debugPrint('❌ Auth required to load profile: $actor');
      }
    } on NetworkException catch (e) {
      _isLoadingProfile = false;
      _profileError = 'Network error. Check your connection.';

      if (kDebugMode) {
        debugPrint('❌ Network error loading profile: ${e.message}');
      }
    } on ApiException catch (e) {
      _isLoadingProfile = false;
      _profileError = e.message;

      if (kDebugMode) {
        debugPrint('❌ Failed to load profile: ${e.message}');
      }
    } on Exception catch (e) {
      // Catch-all for other exceptions
      _isLoadingProfile = false;
      _profileError = 'Failed to load profile. Please try again.';

      if (kDebugMode) {
        debugPrint('❌ Unexpected error loading profile: $e');
      }
    }

    notifyListeners();
  }

  /// Load posts by the current profile's author
  ///
  /// Parameters:
  /// - [refresh]: Reload from beginning instead of paginating
  Future<void> loadPosts({bool refresh = false}) async {
    if (_currentProfileDid == null) {
      // Set error state instead of silently returning
      _postsState = _postsState.copyWith(
        error: 'No profile loaded',
        isLoading: false,
        isLoadingMore: false,
      );
      notifyListeners();
      return;
    }

    if (!refresh) {
      await _postsController.loadMore();
      return;
    }

    // Only a refresh that actually landed its own page counts as "fresh
    // as of now": a failed one, or one a newer refresh superseded, must not
    // move the timestamp.
    final refreshed = await _postsController.refresh();
    if (refreshed) {
      _postsLastRefreshTime = DateTime.now();
      // The controller already notified with the new page; this second
      // sync exists only to project the timestamp stamped above (which the
      // controller knows nothing about) onto _postsState.
      _syncPostsState();
    }
  }

  /// Load more posts (pagination)
  ///
  /// Failures land on `postsState.loadMoreError`, never on
  /// `postsState.error`: a pagination hiccup must not blank a profile that
  /// already has posts on screen. While that error is showing the
  /// controller refuses further pages — use [retryLoadMorePosts] for the
  /// footer's Retry, otherwise the scroll trigger would re-fire the failing
  /// request on every scroll tick.
  Future<void> loadMorePosts() async {
    await loadPosts(refresh: false);
  }

  /// The posts footer's Retry: clears the pagination error and tries again.
  Future<void> retryLoadMorePosts() => _postsController.retryLoadMore();

  /// The comments footer's Retry.
  Future<void> retryLoadMoreComments() => _commentsController.retryLoadMore();

  Future<CursorPage<FeedViewPost>> _fetchPostsPage(String? cursor) async {
    final actor = _currentProfileDid;
    if (actor == null) throw ApiException('No profile loaded');

    final response = await _apiService.getAuthorPosts(
      actor: actor,
      cursor: cursor,
    );

    if (kDebugMode) {
      debugPrint('✅ Author posts page loaded: ${response.feed.length} posts');
    }

    return CursorPage<FeedViewPost>(
      items: response.feed,
      cursor: response.cursor,
    );
  }

  /// Apply viewer vote state so a liked post shows a lit heart even when
  /// the profile is its first surface this session.
  ///
  /// Votes ONLY: these feed items carry `community.viewer.subscribed` too,
  /// and this surface has never seeded it. `hydrateFeedVotesOnly` keeps that
  /// a deliberate choice even when the injected hydrator does know about
  /// subscriptions.
  ///
  /// The controller hands over only the deduplicated new items, so a
  /// cursor-drift duplicate's stale snapshot never lands here.
  Future<void> _hydratePostVotes(List<FeedViewPost> newPosts) async {
    _hydrator.hydrateFeedVotesOnly(newPosts);
  }

  String _postsErrorMessage(Object error) {
    // 404 means the actor doesn't exist (not "no posts") — an empty feed
    // comes back as an empty array.
    if (error is AuthenticationException) return 'Please sign in to view posts';
    if (error is NotFoundException) return 'User not found';
    if (error is NetworkException) {
      return 'Network error. Check your connection.';
    }
    if (error is ApiException) return error.message;
    return 'Failed to load posts. Please try again.';
  }

  void _syncPostsState() {
    _postsState = FeedState(
      posts: _postsController.items,
      cursor: _postsController.cursor,
      hasMore: _postsController.hasMore,
      isLoading: _postsController.isLoading,
      isLoadingMore: _postsController.isLoadingMore,
      error: _postsController.error,
      loadMoreError: _postsController.loadMoreError,
      scrollPosition: _postsState.scrollPosition,
      lastRefreshTime: _postsLastRefreshTime,
    );
    notifyListeners();
  }

  /// Load comments by the current profile's author
  ///
  /// Parameters:
  /// - [refresh]: Reload from beginning instead of paginating
  Future<void> loadComments({bool refresh = false}) async {
    if (_currentProfileDid == null) {
      _commentsState = _commentsState.copyWith(
        error: 'No profile loaded',
        isLoading: false,
        isLoadingMore: false,
      );
      notifyListeners();
      return;
    }

    if (refresh) {
      await _commentsController.refresh();
    } else {
      await _commentsController.loadMore();
    }
  }

  /// Load more comments (pagination)
  ///
  /// Failures land on `commentsState.loadMoreError`, never on
  /// `commentsState.error`.
  Future<void> loadMoreComments() async {
    await loadComments(refresh: false);
  }

  Future<CursorPage<CommentView>> _fetchCommentsPage(String? cursor) async {
    final actor = _currentProfileDid;
    if (actor == null) throw ApiException('No profile loaded');

    final response = await _apiService.getActorComments(
      actor: actor,
      cursor: cursor,
    );

    if (kDebugMode) {
      debugPrint(
        '✅ Author comments page loaded: ${response.comments.length} comments',
      );
    }

    return CursorPage<CommentView>(
      items: response.comments,
      cursor: response.cursor,
    );
  }

  /// Apply viewer vote state from the comments response. Safe on both
  /// refresh and pagination: the vote provider keeps an optimistic vote the
  /// appview has not indexed yet instead of adopting a stale snapshot.
  ///
  /// Actor comments come back as a flat list, so the flat traversal is the
  /// right one here - there are no nested replies to recurse into.
  Future<void> _hydrateCommentVotes(List<CommentView> newComments) async {
    _hydrator.hydrateComments(newComments);
  }

  String _commentsErrorMessage(Object error) {
    // 404 means the actor doesn't exist (not "no comments").
    if (error is AuthenticationException) {
      return 'Please sign in to view comments';
    }
    if (error is NotFoundException) return 'User not found';
    if (error is NetworkException) {
      return 'Network error. Check your connection.';
    }
    if (error is ApiException) return error.message;
    return 'Failed to load comments. Please try again.';
  }

  void _syncCommentsState() {
    _commentsState = CommentsState(
      comments: _commentsController.items,
      cursor: _commentsController.cursor,
      hasMore: _commentsController.hasMore,
      isLoading: _commentsController.isLoading,
      isLoadingMore: _commentsController.isLoadingMore,
      error: _commentsController.error,
      loadMoreError: _commentsController.loadMoreError,
    );
    notifyListeners();
  }

  /// Delete a comment from the user's profile comments
  ///
  /// Deletes a comment and removes it from the local comments list.
  /// Only the comment author can delete their comments.
  ///
  /// Parameters:
  /// - [commentUri]: AT-URI of the comment to delete
  ///
  /// Throws:
  /// - AuthenticationException if not authenticated
  /// - ApiException for API errors (including 403 for non-owner)
  Future<void> deleteComment({required String commentUri}) async {
    if (kDebugMode) {
      debugPrint('🗑️ Deleting comment from profile: $commentUri');
    }

    try {
      await _commentService.deleteComment(uri: commentUri);

      // Remove the comment from local state (the controller notifies, which
      // re-projects _commentsState)
      _commentsController.removeWhere((c) => c.uri == commentUri);

      if (kDebugMode) {
        debugPrint('✅ Comment deleted from profile');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to delete comment: $e');
      }
      rethrow;
    }
  }

  /// Clear current profile and reset state
  void clearProfile() {
    _profile = null;
    _currentProfileDid = null;
    _resetFeeds();
    _profileError = null;
    _isLoadingProfile = false;
    notifyListeners();
  }

  /// Drop both feeds back to their pre-load state, orphaning any in-flight
  /// page so it cannot land on the next profile.
  void _resetFeeds() {
    _postsController.reset();
    _commentsController.reset();
    _postsLastRefreshTime = null;
    _postsState = FeedState.initial();
    _commentsState = CommentsState.initial();
  }

  /// Set an error message directly (for cases like missing actor)
  void setError(String message) {
    _profileError = message;
    _isLoadingProfile = false;
    notifyListeners();
  }

  /// Retry loading profile after error
  ///
  /// Returns:
  /// - `true` if retry was initiated (profile DID was available)
  /// - `false` if no profile DID is available to retry
  ///
  /// Note: A return of `true` does not mean the profile loaded successfully,
  /// only that the retry attempt was started. Check [profileError] after
  /// the operation completes to determine if it succeeded.
  Future<bool> retryProfile() async {
    if (_currentProfileDid == null) {
      if (kDebugMode) {
        debugPrint('⚠️ retryProfile called but no profile DID available');
      }
      return false;
    }
    await loadProfile(_currentProfileDid!, forceRefresh: true);
    return true;
  }

  /// Retry loading posts after error
  Future<void> retryPosts() async {
    _postsState = _postsState.copyWith(error: null);
    notifyListeners();
    await loadPosts(refresh: true);
  }

  /// Retry loading comments after error
  Future<void> retryComments() async {
    _commentsState = _commentsState.copyWith(error: null);
    notifyListeners();
    await loadComments(refresh: true);
  }

  /// Update the current user's profile
  ///
  /// Only non-null parameters will be sent to the API.
  /// On success, force refreshes the profile from server to get updated URLs.
  ///
  /// Parameters:
  /// - [displayName]: New display name (optional)
  /// - [bio]: New bio text (optional)
  /// - [avatarBytes]: Avatar image bytes (optional)
  /// - [avatarMimeType]: Avatar MIME type (required if avatarBytes provided)
  /// - [bannerBytes]: Banner image bytes (optional)
  /// - [bannerMimeType]: Banner MIME type (required if bannerBytes provided)
  ///
  /// Throws [ApiException] on failure.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    Uint8List? bannerBytes,
    String? bannerMimeType,
  }) async {
    if (!isOwnProfile || _profile == null) {
      throw ApiException('Can only update own profile');
    }

    if (kDebugMode) {
      debugPrint('📝 Updating profile for: $_currentProfileDid');
    }

    await _apiService.updateProfile(
      displayName: displayName,
      bio: bio,
      avatarBytes: avatarBytes,
      avatarMimeType: avatarMimeType,
      bannerBytes: bannerBytes,
      bannerMimeType: bannerMimeType,
    );

    // Force refresh profile from server to get updated URLs
    await loadProfile(_currentProfileDid!, forceRefresh: true);

    if (kDebugMode) {
      debugPrint('✅ Profile updated and refreshed');
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _postsController.dispose();
    _commentsController.dispose();
    super.dispose();
  }
}
