import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/comment.dart';
import '../models/feed_state.dart';
import '../models/liked_item.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/api_exceptions.dart';
import '../services/comment_change_broadcast.dart';
import '../services/comment_service.dart';
import '../services/coves_api_service.dart';
import '../services/post_change_broadcast.dart';
import '../services/profile_cache.dart';
import '../services/viewer_state_hydrator.dart';
import '../utils/cursor_pagination_controller.dart';
import '../utils/error_messages.dart';
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
    required this._postChangeBroadcast,
    required Object? Function() sessionKeyOf,
    VoteProvider? voteProvider,
    ViewerStateHydrator? hydrator,
    this._commentChangeBroadcast,
  }) : _authProvider = authProvider,
       _lastSignedInDid = _signedInDid(authProvider),
       _hydrator =
           hydrator ??
           ViewerStateHydrator(
             authProvider: authProvider,
             voteProvider: voteProvider,
           ) {
    // The feeds are the same cursor-pagination state machine with
    // different fetchers; the controllers own items/cursor/loading/errors
    // and this provider projects them onto the FeedState / CommentsState
    // the screens already read.
    _postsController = CursorPaginationController<FeedViewPost>(
      fetchPage: _fetchPostsPage,
      onPageLoaded: _hydratePostViewerState,
      errorMapper: ErrorMessage.loadProfilePosts,
      // Server-side cursor drift hands back overlapping pages; the list
      // keys its rows by this same URI and asserts on duplicates.
      idOf: (feedItem) => feedItem.post.uri,
      onUnexpectedError: _reportUnexpected,
      sessionKeyOf: sessionKeyOf,
    )..addListener(_syncPostsState);

    // Liked posts and liked comments in one list, keyed by the liked
    // record's URI and hydrated like the posts and comments tabs.
    _likesController = CursorPaginationController<LikedItem>(
      fetchPage: _fetchLikesPage,
      onPageLoaded: _hydrateLikedViewerState,
      errorMapper: ErrorMessage.loadProfileLikes,
      idOf: (item) => item.uri,
      // The server drops deleted or blocked posts after paging, so a page
      // can come back empty with a cursor that still leads to more likes.
      followCursorPastEmptyPages: true,
      onUnexpectedError: _reportUnexpected,
      sessionKeyOf: sessionKeyOf,
    )..addListener(_syncLikesState);

    _commentsController = CursorPaginationController<CommentView>(
      fetchPage: _fetchCommentsPage,
      onPageLoaded: _hydrateCommentVotes,
      errorMapper: ErrorMessage.loadProfileComments,
      idOf: (comment) => comment.uri,
      onUnexpectedError: _reportUnexpected,
    )..addListener(_syncCommentsState);

    // Listen to auth state changes
    _authProvider.addListener(_onAuthChanged);
    _profileCache.addPutListener(_onProfileCached);
    _postChangeBroadcast.addPostChangeListener(_onPostChanged);
    _commentChangeBroadcast?.addCommentChangeListener(_onCommentChanged);
  }

  late final CursorPaginationController<FeedViewPost> _postsController;
  late final CursorPaginationController<LikedItem> _likesController;
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
  final PostChangeBroadcast _postChangeBroadcast;

  /// The signed-in DID the last auth notification left, or null when signed
  /// out. Only a change to it resets this provider.
  String? _lastSignedInDid;

  static String? _signedInDid(AuthProvider authProvider) =>
      authProvider.isAuthenticated ? authProvider.did : null;

  /// Seeds vote and community-subscription state from each page this
  /// provider loads. Injected app-wide (where it carries both providers);
  /// when omitted, built from the raw vote provider this constructor still
  /// accepts, so only votes are seeded.
  final ViewerStateHydrator _hydrator;

  final CommentService _commentService;

  /// App-owned; carries edits to and from other screens' providers and
  /// must not be disposed here.
  final CommentChangeBroadcast? _commentChangeBroadcast;

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

  // Likes feed state — a projection of _likesController
  LikesState _likesState = LikesState.initial();
  LikesFilter _likesFilter = LikesFilter.all;
  // Set when a likes load-more failed with InvalidCursor; cleared once a
  // page-one reload succeeds or the likes list restarts from page one.
  bool _likesRetryPageOne = false;

  // Comments feed state — a projection of _commentsController
  CommentsState _commentsState = CommentsState.initial();

  // Getters
  UserProfile? get profile => _profile;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;
  String? get currentProfileDid => _currentProfileDid;
  FeedState get postsState => _postsState;

  /// The session key the loaded posts were fetched under, for their admin
  /// tools; null before a page is loaded.
  Object? get postsSessionStamp => _postsController.sessionStamp;
  CommentsState get commentsState => _commentsState;

  /// The posts and comments the profile's owner has liked. Only ever
  /// loaded on the viewer's own profile: likes are private to their owner.
  LikesState get likesState => _likesState;

  /// Which liked items the Likes tab lists.
  LikesFilter get likesFilter => _likesFilter;

  /// Switches the Likes tab to [filter] and reloads it from the first
  /// page. The old filter's rows are dropped at once, and any page still in
  /// flight for it is discarded when it lands. No-op unless this is the
  /// viewer's own profile, or when [filter] is already selected.
  Future<void> setLikesFilter(LikesFilter filter) async {
    if (!isOwnProfile || filter == _likesFilter) {
      return;
    }
    _likesFilter = filter;
    _likesRetryPageOne = false;
    // The controller notifies, which re-projects _likesState.
    _likesController.reset();
    await _likesController.refresh();
  }

  /// The session key the loaded likes were fetched under, for their admin
  /// tools; null before a page is loaded.
  Object? get likesSessionStamp => _likesController.sessionStamp;

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
    // Reloading the profile already shown keeps its known DID, so
    // isOwnProfile stays stable while a handle-addressed refresh runs.
    final loadedProfile = _profile;
    final isReloadOfLoadedProfile =
        loadedProfile != null &&
        (loadedProfile.did == actor || loadedProfile.handle == actor);
    _currentProfileDid = isReloadOfLoadedProfile
        ? loadedProfile.did
        : (actor.startsWith('did:') ? actor : null);
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
    } on Exception catch (e) {
      _isLoadingProfile = false;
      _profileError = ErrorMessage.profile(e);
      // A missing actor leaves no profile to show.
      if (e is NotFoundException) {
        _profile = null;
      }

      if (kDebugMode) {
        debugPrint('❌ Failed to load profile $actor: $e');
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

  /// Seed viewer vote state so a liked post shows a lit heart even when the
  /// profile is its first surface this session.
  ///
  /// This also seeds community subscription state from
  /// `post.community.viewer.subscribed`, but the AppView does not send
  /// `viewer` on a post's `communityRef` today, so that part does nothing
  /// yet. Once the AppView sends it, the post card's Subscribe/Unsubscribe
  /// menu item will reflect it.
  ///
  /// The controller hands over only the deduplicated new items, so a
  /// cursor-drift duplicate's stale snapshot never lands here.
  Future<void> _hydratePostViewerState(List<FeedViewPost> newPosts) async {
    _hydrator.hydrateFeed(newPosts);
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

  /// Load the posts and comments the viewer has liked. Makes no request
  /// unless this is the viewer's own profile, since the server lists likes
  /// only to their owner.
  ///
  /// Parameters:
  /// - [refresh]: Reload from beginning instead of paginating
  Future<void> loadLikes({bool refresh = false}) async {
    if (!isOwnProfile) {
      return;
    }

    if (refresh) {
      _likesRetryPageOne = false;
      await _likesController.refresh();
    } else {
      await _likesController.loadMore();
    }
  }

  /// Load more likes (pagination). Failures land on
  /// `likesState.loadMoreError`, never on `likesState.error`.
  Future<void> loadMoreLikes() => loadLikes();

  /// The likes footer's Retry: clears the pagination error and tries again.
  /// A cursor the server rejected as InvalidCursor cannot succeed when
  /// resent, so that case reloads from the first page instead.
  Future<void> retryLoadMoreLikes() async {
    if (!isOwnProfile) {
      return;
    }
    final cause = _likesController.loadMoreErrorCause;
    if (cause is ApiException &&
        cause.statusCode == 400 &&
        cause.errorCode == 'InvalidCursor') {
      _likesRetryPageOne = true;
    }
    if (_likesRetryPageOne) {
      // Resending the rejected cursor cannot succeed; reload page one until
      // that succeeds.
      if (await _likesController.replaceFirstPageForLoadMore()) {
        _likesRetryPageOne = false;
      }
      return;
    }
    await _likesController.retryLoadMore();
  }

  /// Retry loading likes after a first-page error.
  Future<void> retryLikes() async {
    if (!isOwnProfile) {
      return;
    }
    _likesRetryPageOne = false;
    await _likesController.retry();
  }

  Future<CursorPage<LikedItem>> _fetchLikesPage(String? cursor) async {
    final actor = _currentProfileDid;
    if (actor == null) {
      throw ApiException('No profile loaded');
    }

    final response = await _apiService.getActorLikes(
      actor: actor,
      filter: _likesFilter,
      cursor: cursor,
    );

    if (kDebugMode) {
      debugPrint('✅ Likes page loaded: ${response.feed.length} items');
    }

    return CursorPage<LikedItem>(items: response.feed, cursor: response.cursor);
  }

  /// Seeds viewer state for each new liked post and liked comment, the
  /// same way the posts and comments tabs do.
  ///
  /// Posts and comments hydrate separately so one failing does not skip
  /// the other.
  Future<void> _hydrateLikedViewerState(List<LikedItem> newItems) async {
    try {
      _hydrator.hydrateFeed([
        for (final item in newItems)
          if (item case LikedPost(:final feedViewPost)) feedViewPost,
      ]);
    } on Object catch (e, stackTrace) {
      _reportUnexpected(e, stackTrace);
    }
    try {
      _hydrator.hydrateComments([
        for (final item in newItems)
          if (item case LikedComment(:final comment)) comment,
      ]);
    } on Object catch (e, stackTrace) {
      _reportUnexpected(e, stackTrace);
    }
  }

  void _syncLikesState() {
    _likesState = LikesState(
      items: _likesController.items,
      cursor: _likesController.cursor,
      hasMore: _likesController.hasMore,
      isLoading: _likesController.isLoading,
      isLoadingMore: _likesController.isLoadingMore,
      error: _likesController.error,
      loadMoreError: _likesController.loadMoreError,
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

  /// Edit one of the profile's comments
  ///
  /// Sends [comment]'s stored record so its embed, langs and labels survive
  /// the full-record replace, then patches the loaded item as it is when
  /// the save lands (so the edit survives pagination and keeps stats loaded
  /// meanwhile), returns it with the new content, facets and cid, and
  /// broadcasts it to other screens.
  ///
  /// Throws:
  /// - ApiException without a request if [comment] has no stored record
  /// - AuthenticationException if not authenticated
  /// - ApiException for API errors (the list is left unchanged)
  Future<CommentView> updateComment({
    required CommentView comment,
    required String content,
    List<RichTextFacet>? facets,
  }) async {
    final record = comment.record;
    if (record == null) {
      // Saving without it would drop the embed, langs and labels.
      throw ApiException('Cannot edit a comment without its record');
    }

    final UpdateCommentResponse response;
    try {
      response = await _commentService.updateComment(
        uri: comment.uri,
        content: content,
        facets: facets,
        record: record,
      );
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to update comment: $e');
      }
      rethrow;
    }

    final edited = record.withContent(content, facets);
    final updated =
        _applyCommentEdit(comment.uri, record: edited, cid: response.cid) ??
        comment.withEditedRecord(record: edited, cid: response.cid);
    _commentChangeBroadcast?.replaceComment(updated);

    return updated;
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

      // Remove the comment from local state (the controllers notify, which
      // re-projects _commentsState and _likesState)
      _commentsController.removeById(commentUri);
      _likesController.removeById(commentUri);

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

  /// Patches the loaded comment [uri], in the comments and in the likes,
  /// with [record] and [cid], keeping its own stats and viewer state (and a
  /// liked comment's root post); a tombstoned item is left alone. Returns
  /// the patched view, or null when nothing was patched.
  CommentView? _applyCommentEdit(
    String uri, {
    required CommentRecord record,
    required String cid,
  }) {
    if (_disposed) {
      return null;
    }
    CommentView? patched;
    final current = _loadedComment(uri);
    if (current != null && !current.isTombstoned) {
      // The controller notifies, which re-projects _commentsState. The
      // transform also re-applies to a first page that lands later.
      _commentsController.replaceItemById(
        uri,
        (item) => item.isTombstoned
            ? item
            : item.withEditedRecord(record: record, cid: cid),
      );
      patched = current.withEditedRecord(record: record, cid: cid);
    }
    final liked = _loadedLikedComment(uri);
    if (liked != null && !liked.isTombstoned) {
      _likesController.replaceItemById(
        uri,
        (item) => switch (item) {
          LikedComment(:final comment, :final post)
              when !comment.isTombstoned =>
            LikedComment(
              comment: comment.withEditedRecord(record: record, cid: cid),
              post: post,
            ),
          _ => item,
        },
      );
      patched ??= liked.withEditedRecord(record: record, cid: cid);
    }
    return patched;
  }

  CommentView? _loadedComment(String uri) =>
      _commentsController.items.where((c) => c.uri == uri).firstOrNull;

  CommentView? _loadedLikedComment(String uri) {
    for (final item in _likesController.items) {
      if (item case LikedComment(:final comment) when comment.uri == uri) {
        return comment;
      }
    }
    return null;
  }

  void _onCommentChanged(CommentView comment) {
    final record = comment.record;
    if (record == null) {
      return;
    }
    // Same cid: this provider's own edit, already applied.
    final current = _loadedComment(comment.uri);
    final liked = _loadedLikedComment(comment.uri);
    final isNewEdit =
        (current != null && current.cid != comment.cid) ||
        (liked != null && liked.cid != comment.cid);
    if (!isNewEdit) {
      return;
    }
    _applyCommentEdit(comment.uri, record: record, cid: comment.cid);
  }

  void _onPostChanged(PostChange change) {
    if (_disposed) {
      return;
    }
    switch (change) {
      case PostRemoved(:final uri):
        // The controllers notify, which re-projects the feed states.
        _postsController.removeById(uri);
        _likesController.removeById(uri);
      case PostReplaced(:final post):
        _postsController.replaceItemById(
          post.uri,
          (feedPost) => feedPost.copyWith(post: post),
        );
        _likesController.replaceItemById(
          post.uri,
          (item) => switch (item) {
            LikedPost(:final feedViewPost) => LikedPost(
              feedViewPost.copyWith(post: post),
            ),
            LikedComment() => item,
          },
        );
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

  /// Drop every feed back to their pre-load state, orphaning any in-flight
  /// page so it cannot land on the next profile.
  void _resetFeeds() {
    _postsController.reset();
    _likesController.reset();
    _likesFilter = LikesFilter.all;
    _likesRetryPageOne = false;
    _commentsController.reset();
    _postsLastRefreshTime = null;
    _postsState = FeedState.initial();
    _likesState = LikesState.initial();
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
    _postChangeBroadcast.removePostChangeListener(_onPostChanged);
    _commentChangeBroadcast?.removeCommentChangeListener(_onCommentChanged);
    _profileLoadGeneration++;
    _authProvider.removeListener(_onAuthChanged);
    _profileCache.removePutListener(_onProfileCached);
    _postsController.dispose();
    _likesController.dispose();
    _commentsController.dispose();
    super.dispose();
  }
}
