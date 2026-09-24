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
import '../services/profile_cache.dart';
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
    required this._apiService,
    required this._commentService,
    required this._profileCache,
    VoteProvider? voteProvider,
    ViewerStateHydrator? hydrator,
  }) : _authProvider = authProvider,
       _lastSignedInDid = _signedInDid(authProvider),
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
    _profileCache.addPutListener(_onProfileCached);
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

  final AuthProvider _authProvider;

  /// The signed-in DID the last auth notification left, or null when signed
  /// out. Only a change to it resets this provider.
  String? _lastSignedInDid;

  static String? _signedInDid(AuthProvider authProvider) =>
      authProvider.isAuthenticated ? authProvider.did : null;

  /// Seeds vote state from each page this provider loads. Injected app-wide
  /// (where it also carries a subscription provider, which this surface
  /// deliberately never uses - see [_hydratePostVotes]); when omitted, built
  /// from the raw vote provider this constructor still accepts.
  final ViewerStateHydrator _hydrator;

  final CommentService _commentService;

  /// App-level cache shared with every other profile screen's provider.
  final ProfileCache _profileCache;

  final CovesApiService _apiService;

  // Profile state
  UserProfile? _profile;
  bool _isLoadingProfile = false;

  /// Bumped by [clearProfile], the session reset and [dispose]; a profile
  /// load that started under an older value was superseded and is dropped
  /// (a save's refresh after dispose still reaches the cache).
  int _profileLoadGeneration = 0;

  /// The [ProfileCache.nextRequestSequence] of the in-flight profile load;
  /// a sibling put older than it does not cancel that load.
  int _profileRequestSequence = 0;
  String? _profileError;
  String? _currentProfileDid;

  // Posts feed state — a projection of _postsController, rebuilt whenever
  // the controller notifies (reusing the FeedState pattern the screens read)
  FeedState _postsState = FeedState.initial();
  DateTime? _postsLastRefreshTime;

  // Comments feed state — a projection of _commentsController
  CommentsState _commentsState = CommentsState.initial();

  // Getters
  UserProfile? get profile => _profile;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;
  String? get currentProfileDid => _currentProfileDid;
  FeedState get postsState => _postsState;
  CommentsState get commentsState => _commentsState;

  /// Check if currently viewing own profile
  bool get isOwnProfile {
    if (_currentProfileDid == null) {
      return false;
    }
    return _currentProfileDid == _authProvider.did;
  }

  /// Handle auth state changes
  void _onAuthChanged() {
    // Reset view state on sign-out or an account switch; the shared
    // ProfileCache clears itself. Other notifications change nothing.
    final signedInDid = _signedInDid(_authProvider);
    if (signedInDid == _lastSignedInDid) {
      return;
    }
    _lastSignedInDid = signedInDid;

    // A screen that was showing or loading a profile, or showing an error,
    // gets an actionable error instead of a blank page.
    final hadProfileState =
        _profile != null || _isLoadingProfile || _profileError != null;
    _profileLoadGeneration++;
    _isLoadingProfile = false;
    _profile = null;
    _resetFeeds();
    _currentProfileDid = null;
    _profileError = hadProfileState
        ? 'Your session changed. Retry to reload this profile.'
        : null;
    notifyListeners();
  }

  /// Load profile for a user
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  /// - [forceRefresh]: Bypass cache and fetch fresh data
  Future<void> loadProfile(String actor, {bool forceRefresh = false}) =>
      _loadProfile(actor, forceRefresh: forceRefresh);

  /// [loadProfile] body. [isSaveRefresh] marks [updateProfile]'s follow-up
  /// fetch, whose result still reaches the shared cache after [dispose].
  Future<void> _loadProfile(
    String actor, {
    required bool forceRefresh,
    bool isSaveRefresh = false,
  }) async {
    // Check cache first (updates LRU access order)
    final cachedProfile = _profileCache.get(actor);
    if (cachedProfile != null && !forceRefresh) {
      _profile = cachedProfile;
      _currentProfileDid = cachedProfile.did;
      _profileError = null;
      notifyListeners();
      return;
    }

    if (_isLoadingProfile) {
      return;
    }

    _isLoadingProfile = true;
    _profileError = null;
    _currentProfileDid = actor.startsWith('did:') ? actor : null;
    notifyListeners();

    final loadGeneration = _profileLoadGeneration;
    final cacheGeneration = _profileCache.generation;
    final requestSequence = _profileCache.nextRequestSequence();
    _profileRequestSequence = requestSequence;
    try {
      // A superseded load's success or failure must not reach this state.
      final UserProfile profile;
      try {
        profile = await _apiService.getProfile(actor: actor);
      } on Exception {
        if (loadGeneration != _profileLoadGeneration) {
          if (kDebugMode) {
            debugPrint('⚠️ Dropped failure of superseded profile load: $actor');
          }
          return;
        }
        rethrow;
      }
      if (loadGeneration != _profileLoadGeneration) {
        // A saved profile outlives the screen that saved it: after dispose
        // it is still published to siblings, without touching this
        // provider's state. The cache ignores it if a newer request already
        // put that DID.
        if (isSaveRefresh &&
            _disposed &&
            _profileCache.generation == cacheGeneration) {
          _profileCache.put(profile, requestSequence: requestSequence);
          return;
        }
        if (kDebugMode) {
          debugPrint('⚠️ Dropped superseded profile load: $actor');
        }
        return;
      }

      // Set before the cache put so this provider's own put listener sees
      // the instance it already holds and skips it, and so a failure after
      // the fetch cannot leave the loading flag set.
      _profile = profile;
      _currentProfileDid = profile.did;
      _isLoadingProfile = false;
      _profileError = null;

      // A response fetched for a previous session carries that viewer's
      // state, so it must not enter the cache the new session reads.
      if (_profileCache.generation == cacheGeneration) {
        _profileCache.put(profile, requestSequence: requestSequence);
      } else if (kDebugMode) {
        debugPrint('⚠️ Skipped caching profile from an old session: $actor');
      }

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
    await loadPosts();
  }

  /// The posts footer's Retry: clears the pagination error and tries again.
  Future<void> retryLoadMorePosts() => _postsController.retryLoadMore();

  /// The comments footer's Retry.
  Future<void> retryLoadMoreComments() => _commentsController.retryLoadMore();

  Future<CursorPage<FeedViewPost>> _fetchPostsPage(String? cursor) async {
    final actor = _currentProfileDid;
    if (actor == null) {
      throw ApiException('No profile loaded');
    }

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
    if (error is AuthenticationException) {
      return 'Please sign in to view posts';
    }
    if (error is NotFoundException) {
      return 'User not found';
    }
    if (error is NetworkException) {
      return 'Network error. Check your connection.';
    }
    if (error is ApiException) {
      return error.message;
    }
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
    await loadComments();
  }

  Future<CursorPage<CommentView>> _fetchCommentsPage(String? cursor) async {
    final actor = _currentProfileDid;
    if (actor == null) {
      throw ApiException('No profile loaded');
    }

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
    if (error is NotFoundException) {
      return 'User not found';
    }
    if (error is NetworkException) {
      return 'Network error. Check your connection.';
    }
    if (error is ApiException) {
      return error.message;
    }
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
    _profileLoadGeneration++;
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
    await _loadProfile(
      _currentProfileDid!,
      forceRefresh: true,
      isSaveRefresh: true,
    );

    if (kDebugMode) {
      debugPrint('✅ Profile updated and refreshed');
    }
  }

  /// Adopts a profile a sibling provider put in the shared cache when it
  /// is for the DID this provider is showing. No fetch; the only cache
  /// access is reading the put's request sequence.
  ///
  /// - While a load is in flight, a put from a request that started later
  ///   wins: the load is dropped. An older put is ignored and the load
  ///   continues.
  /// - While a profile is showing, the put replaces it and clears a failed
  ///   refresh's error.
  /// - With no profile and no load (the error screen), the put is ignored;
  ///   the screen's Retry reruns the full load.
  void _onProfileCached(UserProfile cachedProfile) {
    if (_currentProfileDid == null ||
        cachedProfile.did != _currentProfileDid ||
        identical(cachedProfile, _profile)) {
      return;
    }
    if (_isLoadingProfile) {
      final putSequence = _profileCache.requestSequenceOf(cachedProfile.did);
      if (putSequence == null || putSequence < _profileRequestSequence) {
        return;
      }
      _profileLoadGeneration++;
      _isLoadingProfile = false;
    } else if (_profile == null) {
      return;
    }
    _profile = cachedProfile;
    _profileError = null;
    notifyListeners();
  }

  /// The edit route borrows this provider and can outlive its screen, so a
  /// save that completes after dispose still refreshes the shared cache for
  /// sibling screens (see [_loadProfile]); this provider's own state updates
  /// and notifications are skipped.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _profileLoadGeneration++;
    _authProvider.removeListener(_onAuthChanged);
    _profileCache.removePutListener(_onProfileCached);
    _postsController.dispose();
    _commentsController.dispose();
    super.dispose();
  }
}
