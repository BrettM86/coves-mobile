import 'dart:async' show Completer, Timer, unawaited;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../models/comment_thread_tree.dart';
import '../models/post.dart';
import '../services/api_exceptions.dart';
import '../services/comment_service.dart';
import '../services/coves_api_service.dart';
import '../services/viewer_state_hydrator.dart';
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
/// IMPORTANT: Accepts an AuthProvider so viewer-state hydration can tell
/// signed-in from signed-out. Fresh access tokens for the requests
/// themselves come from the shared CovesApiService's token callbacks.
class CommentsProvider with ChangeNotifier {
  CommentsProvider(
    AuthProvider authProvider, {
    required String postUri,
    required String postCid,
    required CovesApiService apiService,
    VoteProvider? voteProvider,
    CommentService? commentService,
    List<Duration>? indexingRetryDelays,
    ViewerStateHydrator? hydrator,
  }) : _postUri = postUri,
       _postCid = postCid,
       _apiService = apiService,
       _voteProvider = voteProvider,
       _commentService = commentService,
       _hydrator =
           hydrator ??
           ViewerStateHydrator(
             authProvider: authProvider,
             voteProvider: voteProvider,
           ),
       _indexingRetryDelays =
           indexingRetryDelays ?? _defaultIndexingRetryDelays;

  /// Maximum comment length in characters (matches backend limit)
  /// Note: This counts Unicode grapheme clusters, so emojis count correctly
  static const int maxCommentLength = 10000;

  /// Default staleness threshold for background refresh
  static const Duration stalenessThreshold = Duration(minutes: 5);

  /// Default backoff schedule while waiting for the AppView to index a
  /// newly created comment (~1-2s firehose lag). Injectable via the
  /// constructor so tests don't need real delays.
  static const List<Duration> _defaultIndexingRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1200),
  ];

  final CovesApiService _apiService;
  final VoteProvider? _voteProvider;

  /// Seeds vote state from each comments response. Injected by the cache
  /// that builds these providers; when omitted, built from the raw vote
  /// provider this constructor still accepts.
  final ViewerStateHydrator _hydrator;

  final CommentService? _commentService;
  final List<Duration> _indexingRetryDelays;

  // Post context - immutable per provider instance
  final String _postUri;
  final String _postCid;

  // Comment state
  List<ThreadViewComment> _comments = [];

  /// The current thread as a value tree, for lookup and node replacement.
  ///
  /// Cheap to build per use: [CommentThreadTree] wraps [_comments] by
  /// reference instead of copying it.
  CommentThreadTree get _tree => CommentThreadTree(_comments);

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isQuietLoading = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;

  // Bumped whenever the whole tree is replaced (refresh/sort change/delete).
  // In-flight subtree fetches capture it at start and discard their response
  // if it changed, so a stale subtree is never merged into a newer tree.
  int _treeGeneration = 0;

  // Collapsed thread state - stores URIs of collapsed comments
  final Set<String> _collapsedComments = {};

  // In-flight "load more replies" subtree fetches, keyed by comment URI.
  // Duplicate calls for the same URI get the existing future back so every
  // caller receives the real result instead of null.
  final Map<String, Future<ThreadViewComment?>> _loadingMoreReplies = {};

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

  /// Comment URIs with an in-flight "load more replies" subtree fetch
  /// (for spinner state in the UI).
  Set<String> get loadingMoreReplies =>
      Set.unmodifiable(_loadingMoreReplies.keys);
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
  /// - [quiet]: When refreshing, don't flip [isLoading] (no full-list loading
  ///   flicker). Used for background retries while waiting for the AppView to
  ///   index a newly created comment.
  Future<void> loadComments({bool refresh = false, bool quiet = false}) async {
    // If already loading, schedule a refresh to happen after current load
    if (_isLoading || _isLoadingMore || _isQuietLoading) {
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
        if (quiet) {
          // Internal re-entrancy guard only - not exposed via isLoading, so
          // the UI keeps showing the current tree while we refresh behind it.
          _isQuietLoading = true;
        } else {
          _isLoading = true;
        }
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
        // The whole tree was replaced - invalidate in-flight subtree fetches
        // so they don't merge stale data into the new tree.
        _treeGeneration++;
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

      // Apply viewer vote state from the comments response. Safe for
      // comments already on screen (a duplicate across pages keeps its
      // optimistic vote), so refresh and pagination share one path - on
      // refresh _comments is response.comments anyway.
      _hydrator.hydrateCommentTree(response.comments);

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
      _isQuietLoading = false;
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
  /// nesting-depth cutoff of the original thread fetch. When the node
  /// already has a [ThreadViewComment.repliesCursor] (a previous page was
  /// fetched), the cursor is sent and the new page of direct replies is
  /// appended instead of replacing what's already loaded.
  ///
  /// Returns the merged subtree so callers (e.g. the focused thread screen)
  /// can render it even when the node is no longer present in the top-level
  /// tree. If a fetch for the same comment is already in flight, the
  /// EXISTING future is returned, so every caller gets the real result.
  /// Returns null when the server returned no/mismatched subtree (the
  /// node's hasMore/cursor are cleared on an empty response so the UI stops
  /// offering a load-more that can never succeed), when the response became
  /// stale (tree refreshed or sort changed mid-flight), or when the
  /// provider was disposed.
  ///
  /// Throws [ArgumentError] for a malformed comment URI (programmer error).
  /// Throws ApiException/AuthenticationException on network or auth errors.
  Future<ThreadViewComment?> loadMoreReplies(String commentUri) {
    final inFlight = _loadingMoreReplies[commentUri];
    if (inFlight != null) {
      return inFlight;
    }

    // rkey is the last path segment of the comment AT-URI. Note: Uri.parse
    // cannot handle at:// URIs (the DID's colons look like an invalid port).
    final segments = commentUri.split('/');
    final rkey = segments.length > 1 ? segments.last : '';
    if (rkey.isEmpty) {
      throw ArgumentError.value(
        commentUri,
        'commentUri',
        'malformed comment AT-URI',
      );
    }

    // Register the in-flight future BEFORE starting the work: the fetch can
    // fail synchronously, and _doLoadMoreReplies' cleanup must always run
    // after the map entry exists or the entry would leak forever.
    final completer = Completer<ThreadViewComment?>();
    _loadingMoreReplies[commentUri] = completer.future;
    _safeNotifyListeners();
    completer.complete(_doLoadMoreReplies(commentUri, rkey));
    return completer.future;
  }

  Future<ThreadViewComment?> _doLoadMoreReplies(
    String commentUri,
    String rkey,
  ) async {
    // Capture staleness markers before the fetch: if the tree is wholesale
    // replaced (refresh/delete) or the sort changes while we're in flight,
    // this response no longer belongs to what's on screen.
    final startGeneration = _treeGeneration;
    final startSort = _sort;

    // Pass the stored cursor (if any) so a node with more than one page of
    // direct replies advances through pages instead of refetching page 1.
    //
    // Captured BEFORE the fetch, while the existing node is looked up AFTER
    // it: a concurrent refetch can drop the node while this page is in
    // flight, and the two observations are then allowed to disagree. Pinned
    // by a test - do not collapse them into one lookup.
    final requestCursor = _tree.findByUri(commentUri)?.repliesCursor;

    try {
      final response = await _apiService.getComments(
        postUri: _postUri,
        sort: _sort,
        timeframe: _timeframe,
        parentRkey: rkey,
        cursor: requestCursor,
      );

      if (_isDisposed) {
        return null;
      }

      if (_treeGeneration != startGeneration || _sort != startSort) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ loadMoreReplies: discarding stale subtree for $rkey '
            '(tree refreshed or sort changed mid-flight)',
          );
        }
        return null;
      }

      final existingNode = _tree.findByUri(commentUri);

      if (response.comments.isEmpty) {
        // Nothing to load - clear the node's pagination state so the
        // "load more" affordance disappears instead of spinning forever.
        //
        // Deliberately BEFORE the anchoring guard below, and with no
        // changed-check of its own: the outer condition is what keeps this
        // a genuine no-op for a node with nothing to clear.
        if (existingNode != null &&
            (existingNode.hasMore || existingNode.repliesCursor != null)) {
          final cleared = existingNode.copyWith(
            hasMore: false,
            repliesCursor: null,
          );
          _comments = _tree.replaceNode(cleared).tree.nodes;
        }
        return null;
      }

      // Contract guard: the response must contain the subtree rooted at the
      // requested comment as its sole top-level entry.
      final fresh = response.comments.first;
      if (fresh.comment.uri != commentUri) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ loadMoreReplies: response anchored at ${fresh.comment.uri}, '
            'expected $commentUri - discarding',
          );
        }
        return null;
      }

      // The response cursor paginates this node's direct replies; if
      // present there are more direct replies beyond this page.
      final subtree = CommentThreadTree.subtreeFromResponse(
        fresh: fresh,
        existingNode: existingNode,
        requestCursor: requestCursor,
        responseCursor: response.cursor,
      );

      final merge = _tree.replaceNode(subtree);
      if (merge.replaced) {
        _comments = merge.tree.nodes;
      } else {
        // The walk changed nothing. Usually that means the node is not in
        // the top-level tree at all (e.g. below the depth cap, when the
        // focused thread screen calls this) - but the merge is also a no-op
        // if the subtree were already the instance sitting there, and the
        // walk cannot tell the two apart. Either way the returned subtree
        // is still useful to the caller.
        if (kDebugMode) {
          debugPrint(
            'ℹ️ loadMoreReplies: nothing in the top-level tree changed for '
            '$commentUri - returning the subtree unmerged',
          );
        }
      }

      // Apply viewer vote state from [fresh] - the nodes this response
      // actually delivered - NOT from the merged subtree. The merge
      // preserves earlier-hydrated branches whose snapshots are old;
      // re-applying those could roll back a vote the server has since
      // confirmed through another surface (they were applied when their
      // own response arrived, which is enough). Nodes with an optimistic
      // vote the server has not indexed yet are protected either way.
      _hydrator.hydrateCommentTree([fresh]);

      if (kDebugMode) {
        debugPrint(
          '✅ Loaded replies subtree for $rkey '
          '(${subtree.replies?.length ?? 0} direct replies)',
        );
      }

      return subtree;
    } finally {
      if (!_isDisposed) {
        // Map.remove returns the (already-settled) future; nothing to await.
        unawaited(_loadingMoreReplies.remove(commentUri));
        _safeNotifyListeners();
      }
    }
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

      // Surface the new comment. The AppView indexes new comments
      // asynchronously (firehose lag ~1-2s), so the first fetch can race
      // indexing and miss the comment we just created — retry briefly with
      // backoff until it shows up. Bounded so a comment that legitimately
      // falls outside the first page (deep pagination) can't loop forever.
      if (parentComment == null ||
          _tree.containsUri(parentComment.comment.uri)) {
        // Parent is visible in the top-level tree (or this is a top-level
        // reply): a refresh can surface the new comment. Retries use the
        // quiet path so the full list doesn't flicker into a loading state
        // on every attempt.
        await refreshComments();
        var attempt = 0;
        while (!_isDisposed &&
            attempt < _indexingRetryDelays.length &&
            !_tree.containsUri(response.uri)) {
          await Future<void>.delayed(_indexingRetryDelays[attempt]);
          attempt++;
          if (_isDisposed) {
            break;
          }
          await loadComments(refresh: true, quiet: true);
        }

        // Deep replies can still sit past the per-parent sibling cap or the
        // depth cutoff of the top-level refresh. Pull the parent's subtree
        // so the new reply is merged into the tree at its correct position.
        if (parentComment != null &&
            !_isDisposed &&
            !_tree.containsUri(response.uri)) {
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
      } else {
        // The parent is NOT in the top-level tree (below the depth cap):
        // full refreshes can never surface the new reply, so retry the
        // parent's subtree fetch instead, verifying against the RETURNED
        // subtree (the merge into the top-level tree is a no-op here).
        var subtree = await _tryLoadReplySubtree(parentUri);
        var attempt = 0;
        while (!_isDisposed &&
            attempt < _indexingRetryDelays.length &&
            (subtree == null || subtree.findByUri(response.uri) == null)) {
          await Future<void>.delayed(_indexingRetryDelays[attempt]);
          attempt++;
          if (_isDisposed) {
            break;
          }
          subtree = await _tryLoadReplySubtree(parentUri);
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create comment: $e');
      }
      rethrow;
    }
  }

  /// Fetches the subtree rooted at [parentUri], swallowing fetch errors.
  ///
  /// Used by the post-create verification loop: the comment was already
  /// created successfully, so a failed hydration attempt is not fatal.
  Future<ThreadViewComment?> _tryLoadReplySubtree(String parentUri) async {
    try {
      return await loadMoreReplies(parentUri);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to hydrate reply subtree: $e');
      }
      return null;
    }
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
    // Dispose the ValueNotifier last
    _currentTimeNotifier.dispose();
    super.dispose();
  }
}
