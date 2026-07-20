import 'dart:async' show Timer, unawaited;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../services/api_exceptions.dart';
import '../services/comment_service.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// Comments Provider
///
/// Manages comment state and fetching logic for a specific post.
/// Each provider instance is bound to a single post (immutable postUri/postCid).
/// Supports sorting (hot/top/new), pagination, vote integration, scroll position,
/// and draft text preservation.
///
/// IMPORTANT: Provider instances are managed by CommentsProviderCache which
/// handles LRU eviction and sign-out cleanup. Do not create directly in widgets.
///
/// IMPORTANT: Accepts AuthProvider reference to fetch fresh access
/// tokens before each authenticated request (critical for atProto OAuth
/// token rotation).
class CommentsProvider with ChangeNotifier {
  CommentsProvider(
    this._authProvider, {
    required String postUri,
    required String postCid,
    CovesApiService? apiService,
    VoteProvider? voteProvider,
    CommentService? commentService,
  }) : _postUri = postUri,
       _postCid = postCid,
       _voteProvider = voteProvider,
       _commentService = commentService {
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
  }

  /// Maximum comment length in characters (matches backend limit)
  /// Note: This counts Unicode grapheme clusters, so emojis count correctly
  static const int maxCommentLength = 10000;

  /// Default staleness threshold for background refresh
  static const Duration stalenessThreshold = Duration(minutes: 5);

  final AuthProvider _authProvider;
  late final CovesApiService _apiService;
  final VoteProvider? _voteProvider;
  final CommentService? _commentService;

  // Post context - immutable per provider instance
  final String _postUri;
  final String _postCid;

  // Comment state
  List<ThreadViewComment> _comments = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;

  // Collapsed thread state - stores URIs of collapsed comments
  final Set<String> _collapsedComments = {};

  // Comment URIs with an in-flight "load more replies" subtree fetch
  final Set<String> _loadingMoreReplies = {};

  // Scroll position state (replaces ScrollStateService for this post)
  double _scrollPosition = 0;

  // Draft reply text - stored per-parent-URI (null key = top-level reply to post)
  // This allows users to have separate drafts for different comments within the same post
  final Map<String?, String> _drafts = {};

  // Staleness tracking for background refresh
  DateTime? _lastRefreshTime;

  // Comment configuration
  String _sort = 'hot';
  String? _timeframe;

  // Flag to track if a refresh should be scheduled after current load
  bool _pendingRefresh = false;

  // Time update mechanism for periodic UI refreshes
  Timer? _timeUpdateTimer;
  final ValueNotifier<DateTime?> _currentTimeNotifier = ValueNotifier(null);

  bool _isDisposed = false;

  void _safeNotifyListeners() {
    if (_isDisposed) return;
    notifyListeners();
  }

  // Getters
  String get postUri => _postUri;
  String get postCid => _postCid;
  List<ThreadViewComment> get comments => _comments;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get sort => _sort;
  String? get timeframe => _timeframe;
  ValueNotifier<DateTime?> get currentTimeNotifier => _currentTimeNotifier;
  Set<String> get collapsedComments => Set.unmodifiable(_collapsedComments);
  Set<String> get loadingMoreReplies => Set.unmodifiable(_loadingMoreReplies);
  double get scrollPosition => _scrollPosition;
  DateTime? get lastRefreshTime => _lastRefreshTime;

  /// Get draft text for a specific parent URI
  ///
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  /// Returns the draft text, or empty string if no draft exists
  String getDraft({String? parentUri}) => _drafts[parentUri] ?? '';

  /// Legacy getters for backward compatibility
  /// @deprecated Use getDraft(parentUri: ...) instead
  String get draftText => _drafts.values.firstOrNull ?? '';
  String? get draftParentUri => _drafts.keys.firstOrNull;

  /// Check if cached data is stale and should be refreshed in background
  bool get isStale {
    if (_lastRefreshTime == null) {
      return true;
    }
    return DateTime.now().difference(_lastRefreshTime!) > stalenessThreshold;
  }

  /// Save scroll position (called on every scroll event)
  void saveScrollPosition(double position) {
    _scrollPosition = position;
    // No notifyListeners - this is passive state save
  }

  /// Save draft reply text
  ///
  /// [text] - The draft text content
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  ///
  /// Each parent URI gets its own draft, so switching between replies
  /// preserves drafts for each context.
  void saveDraft(String text, {String? parentUri}) {
    if (text.trim().isEmpty) {
      // Remove empty drafts to avoid clutter
      _drafts.remove(parentUri);
    } else {
      _drafts[parentUri] = text;
    }
    // No notifyListeners - this is passive state save
  }

  /// Clear draft text for a specific parent (call after successful submission)
  ///
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  void clearDraft({String? parentUri}) {
    _drafts.remove(parentUri);
  }

  /// Toggle collapsed state for a comment thread
  ///
  /// When collapsed, the comment's replies are hidden from view.
  /// Long-pressing the same comment again will expand the thread.
  void toggleCollapsed(String uri) {
    if (_collapsedComments.contains(uri)) {
      _collapsedComments.remove(uri);
    } else {
      _collapsedComments.add(uri);
    }
    _safeNotifyListeners();
  }

  /// Check if a specific comment is collapsed
  bool isCollapsed(String uri) => _collapsedComments.contains(uri);

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

  /// Load comments for this provider's post
  ///
  /// Parameters:
  /// - [refresh]: Whether to refresh from the beginning (true) or paginate (false)
  Future<void> loadComments({bool refresh = false}) async {
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
      _safeNotifyListeners();

      if (kDebugMode) {
        debugPrint('📡 Fetching comments: sort=$_sort, postUri=$_postUri');
      }

      final response = await _apiService.getComments(
        postUri: _postUri,
        sort: _sort,
        timeframe: _timeframe,
        cursor: refresh ? null : _cursor,
      );

      if (_isDisposed) return;

      // Only update state after successful fetch
      if (refresh) {
        _comments = response.comments;
        _lastRefreshTime = DateTime.now();
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
      if (_isDisposed) return;
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch comments: $e');
      }
    } finally {
      if (_isDisposed) return;
      _isLoading = false;
      _isLoadingMore = false;
      _safeNotifyListeners();

      // If a refresh was scheduled during this load, execute it now
      if (_pendingRefresh) {
        if (kDebugMode) {
          debugPrint('🔄 Executing pending refresh');
        }
        _pendingRefresh = false;
        // Schedule refresh without awaiting to avoid blocking
        // This is intentional - we want the refresh to happen asynchronously
        unawaited(loadComments(refresh: true));
      }
    }
  }

  /// Refresh comments (pull-to-refresh)
  ///
  /// Reloads comments from the beginning for the current post.
  Future<void> refreshComments() async {
    await loadComments(refresh: true);
  }

  /// Load more comments (pagination)
  Future<void> loadMoreComments() async {
    if (!_hasMore || _isLoadingMore) {
      return;
    }
    await loadComments();
  }

  /// Load more replies for a specific comment ("Load more replies" button)
  ///
  /// Fetches the subtree rooted at [commentUri] via the getComments
  /// `parentRkey` parameter and merges it into the in-memory comment tree.
  /// This surfaces replies hidden by the per-parent sibling cap or the
  /// nesting-depth cutoff of the original thread fetch.
  ///
  /// Returns the freshly fetched subtree so callers (e.g. the focused
  /// thread screen) can render it even when the node is no longer present
  /// in the top-level tree. Returns null if a fetch for the same comment is
  /// already in flight or the server returned no subtree.
  ///
  /// Throws ApiException/AuthenticationException on network or auth errors.
  Future<ThreadViewComment?> loadMoreReplies(String commentUri) async {
    if (_loadingMoreReplies.contains(commentUri)) {
      return null;
    }

    // rkey is the last path segment of the comment AT-URI. Note: Uri.parse
    // cannot handle at:// URIs (the DID's colons look like an invalid port).
    final segments = commentUri.split('/');
    final rkey = segments.length > 1 ? segments.last : '';
    if (rkey.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ loadMoreReplies: malformed comment URI: $commentUri');
      }
      return null;
    }

    _loadingMoreReplies.add(commentUri);
    _safeNotifyListeners();

    try {
      final response = await _apiService.getComments(
        postUri: _postUri,
        sort: _sort,
        timeframe: _timeframe,
        parentRkey: rkey,
      );

      if (_isDisposed || response.comments.isEmpty) {
        return null;
      }

      // The response contains the subtree rooted at the requested comment as
      // its sole top-level entry. The cursor paginates the parent's direct
      // replies; if present there are more direct replies beyond this page.
      final subtree = response.comments.first.copyWith(
        hasMore: response.cursor != null,
      );

      _comments = _replaceNode(_comments, subtree);

      // Initialize vote state for the newly fetched replies
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        _initializeCommentVoteState(subtree);
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Loaded replies subtree for $rkey '
          '(${subtree.replies?.length ?? 0} direct replies)',
        );
      }

      return subtree;
    } finally {
      if (!_isDisposed) {
        _loadingMoreReplies.remove(commentUri);
        _safeNotifyListeners();
      }
    }
  }

  /// Returns a copy of [nodes] with the node matching [replacement]'s URI
  /// replaced by [replacement]. Leaves the tree untouched when absent.
  List<ThreadViewComment> _replaceNode(
    List<ThreadViewComment> nodes,
    ThreadViewComment replacement,
  ) {
    return nodes.map((node) => node.replaceDescendant(replacement)).toList();
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
    _safeNotifyListeners();

    // Reload comments with new sort
    try {
      await loadComments(refresh: true);
      return true;
    } on Exception catch (e) {
      if (_isDisposed) return false;
      // Revert to previous sort option on failure
      _sort = previousSort;
      _safeNotifyListeners();

      if (kDebugMode) {
        debugPrint('Failed to apply sort option: $e');
      }

      return false;
    }
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

  /// Create a comment on the current post or as a reply to another comment
  ///
  /// Parameters:
  /// - [content]: The comment text content
  /// - [parentComment]: Optional parent comment for nested replies.
  ///   If null, this is a top-level reply to the post.
  ///
  /// The reply reference structure:
  /// - Root: Always points to the original post (_postUri, _postCid)
  /// - Parent: Points to the post (top-level) or the parent comment (nested)
  ///
  /// After successful creation, refreshes the comments list.
  ///
  /// Throws:
  /// - ValidationException if content is empty or too long
  /// - ApiException if CommentService is not available or no post is loaded
  /// - ApiException for API errors
  Future<void> createComment({
    required String content,
    List<RichTextFacet>? contentFacets,
    ThreadViewComment? parentComment,
  }) async {
    // Validate content
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      throw ValidationException('Comment cannot be empty');
    }

    // Use characters.length for proper Unicode/emoji counting
    final charCount = trimmedContent.characters.length;
    if (charCount > maxCommentLength) {
      throw ValidationException(
        'Comment too long ($charCount characters). '
        'Maximum is $maxCommentLength characters.',
      );
    }

    if (_commentService == null) {
      throw ApiException('CommentService not available');
    }

    // Root is always the original post
    final rootUri = _postUri;
    final rootCid = _postCid;

    // Parent depends on whether this is a top-level or nested reply
    final String parentUri;
    final String parentCid;

    if (parentComment != null) {
      // Nested reply - parent is the comment being replied to
      parentUri = parentComment.comment.uri;
      parentCid = parentComment.comment.cid;
    } else {
      // Top-level reply - parent is the post
      parentUri = rootUri;
      parentCid = rootCid;
    }

    if (kDebugMode) {
      debugPrint('💬 Creating comment');
      debugPrint('   Root: $rootUri');
      debugPrint('   Parent: $parentUri');
      debugPrint('   Is nested: ${parentComment != null}');
    }

    try {
      final response = await _commentService.createComment(
        rootUri: rootUri,
        rootCid: rootCid,
        parentUri: parentUri,
        parentCid: parentCid,
        content: trimmedContent,
        contentFacets: contentFacets,
      );

      if (kDebugMode) {
        debugPrint('✅ Comment created: ${response.uri}');
      }

      // Refresh comments to show the new comment. The AppView indexes new
      // comments asynchronously (firehose), so the first refresh can race
      // indexing and miss the comment we just created — retry briefly until
      // it shows up. Bounded so a comment that legitimately falls outside
      // the first page (deep pagination) can't loop forever.
      await refreshComments();
      var attempt = 0;
      while (attempt < 3 && !_treeContainsUri(_comments, response.uri)) {
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        await refreshComments();
      }

      // Deep replies can sit past the per-parent sibling cap or the depth
      // cutoff of the top-level refresh. Pull the parent's subtree so the
      // new reply is merged into the tree at its correct position.
      if (parentComment != null && !_treeContainsUri(_comments, response.uri)) {
        try {
          await loadMoreReplies(parentComment.comment.uri);
        } on Exception catch (e) {
          // The comment was created successfully; failing to hydrate the
          // subtree is not fatal — the reply is reachable via load-more.
          if (kDebugMode) {
            debugPrint('⚠️ Failed to hydrate reply subtree: $e');
          }
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create comment: $e');
      }
      rethrow;
    }
  }

  /// Whether [nodes] (or any of their nested replies) contain a comment
  /// with the given [uri].
  bool _treeContainsUri(List<ThreadViewComment> nodes, String uri) {
    for (final node in nodes) {
      if (node.comment.uri == uri) {
        return true;
      }
      final replies = node.replies;
      if (replies != null && _treeContainsUri(replies, uri)) {
        return true;
      }
    }
    return false;
  }

  /// Delete a comment
  ///
  /// Deletes a comment and refreshes the comment list.
  /// Only the comment author can delete their comments.
  ///
  /// Parameters:
  /// - [commentUri]: AT-URI of the comment to delete
  ///
  /// Throws:
  /// - ApiException if CommentService is not available
  /// - AuthenticationException if not authenticated
  /// - ApiException for API errors
  Future<void> deleteComment({required String commentUri}) async {
    if (_commentService == null) {
      throw ApiException('CommentService not available');
    }

    if (kDebugMode) {
      debugPrint('🗑️ Deleting comment: $commentUri');
    }

    try {
      await _commentService.deleteComment(uri: commentUri);

      if (kDebugMode) {
        debugPrint('✅ Comment deleted, refreshing comments');
      }

      // Refresh comments to reflect deletion
      await refreshComments();
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to delete comment: $e');
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
    await loadComments(refresh: true);
  }

  /// Clear error
  void clearError() {
    _error = null;
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Stop time updates and cancel timer (also sets value to null)
    stopTimeUpdates();
    // Dispose API service
    _apiService.dispose();
    // Dispose the ValueNotifier last
    _currentTimeNotifier.dispose();
    super.dispose();
  }
}
