import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../models/post_get_result.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/comments_provider_cache.dart';
import '../../services/coves_api_service.dart';
import '../../services/post_change_broadcast.dart';
import '../../services/viewer_state_hydrator.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/error_messages.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../utils/post_web_link.dart';
import '../../utils/responsive_utils.dart';
import '../../utils/web_link_builder.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/comments_header.dart';
import '../../widgets/community_avatar.dart';
import '../../widgets/detailed_post_view.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_action_bar.dart';
import '../../widgets/post_options_menu.dart';
import '../../widgets/share_button.dart';
import '../../widgets/status_bar_overlay.dart';
import '../../widgets/tappable_community.dart';
import '../compose/reply_screen.dart';
import 'focused_thread_screen.dart';

const _commentThreadMaxDepth = 6;

/// Shown when getComments reports RootNotFound: the post was removed or
/// deleted after it was opened.
const _postUnavailableCopy = 'This post is no longer available';

bool _isCommentDisplayable(
  Iterable<ThreadViewComment> comments,
  String targetUri,
  Set<String> collapsedComments,
) {
  bool visit(ThreadViewComment thread, int depth) {
    if (thread.comment.uri == targetUri) {
      return true;
    }
    if (depth >= _commentThreadMaxDepth ||
        collapsedComments.contains(thread.comment.uri)) {
      return false;
    }
    return thread.replies?.any((reply) => visit(reply, depth + 1)) ?? false;
  }

  return comments.any((thread) => visit(thread, 0));
}

/// Whether [VoteProvider] holds the post's vote state for the signed-in
/// account, which decides whether the action bar's vote can act.
enum _PostVoteHydration {
  /// The post's vote state came for the signed-in account.
  current,

  /// The signed-in account changed and the post's refetch for it is in
  /// flight.
  loading,

  /// The post's refetch for the signed-in account failed. Retry fetches it
  /// again.
  failed,
}

/// Post Detail Screen
///
/// Displays a full post with its comments.
/// Architecture: Standalone screen for route destination and PageView child.
///
/// Features:
/// - Full post display (reuses PostCard widget)
/// - Sort selector (Hot/Top/New) using dropdown
/// - Comment list with ListView.builder for performance
/// - Pull-to-refresh with RefreshIndicator
/// - Loading, empty, and error states
/// - Automatic comment loading on screen init
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    required this.post,
    required this.sessionStamp,
    this.isOptimistic = false,
    this.focusCommentUri,
    this.onPostRemoved,
    super.key,
  });

  /// Post to display (passed via route extras)
  final FeedViewPost post;

  /// The session the post was loaded under; null denies admin tools.
  final Object? sessionStamp;

  /// Called when the shown post is removed, so the owner (the
  /// post detail loader) can show the server's answer in its place.
  final VoidCallback? onPostRemoved;

  /// Optional AT-URI of a comment to scroll to and highlight after the
  /// thread loads (e.g. tapping one of your comments on your profile).
  ///
  /// If the comment isn't in the loaded top-level tree (later page, or
  /// beyond the nesting cutoff), its subtree is fetched and opened in a
  /// [FocusedThreadScreen] on top of this one instead.
  final String? focusCommentUri;

  /// Whether this is an optimistic post (just created, not yet indexed)
  /// When true, skips initial comment load since we know there are no comments
  final bool isOptimistic;

  /// The comment count to display in the comments header.
  ///
  /// The server-side [serverCount] includes comments the viewer never sees
  /// (deleted, blocked, filtered). When the thread resolved successfully but
  /// nothing is renderable (not loading, no error, no comments, no further
  /// pages), returns 0 so the header shows its empty state instead of a
  /// count over an empty list. In every other state the server count stands.
  @visibleForTesting
  static int displayedCommentCount({
    required int serverCount,
    required bool isLoading,
    required bool hasError,
    required bool hasComments,
    required bool hasMore,
  }) {
    final resolvedEmpty = !isLoading && !hasError && !hasComments && !hasMore;
    return resolvedEmpty ? 0 : serverCount;
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  // ScrollController created lazily; explicit comment focus overrides
  // restoration.
  late ScrollController _scrollController;
  // Borrows _scrollController; throttles the load-more trigger.
  late PaginationScrollListener _paginationListener;
  final GlobalKey _commentsHeaderKey = GlobalKey();

  // Cached provider from CommentsProviderCache
  late CommentsProvider _commentsProvider;
  CommentsProviderCache? _commentsCache;

  // Stored for dispose: a context.read there throws a FlutterError (an
  // Error, which the old `on Exception` guard missed) when the tree is
  // being finalized and the provider ancestor is already deactivated.
  AuthProvider? _authProvider;

  // The DID this screen last saw. Only a change from a DID to none is a
  // sign-out; AuthProvider also notifies for a sign-in starting or being
  // cancelled and for token refreshes, which leave the DID as it was.
  String? _signedInDid;

  // Counts the DID changes this screen has seen, so a post fetched for one
  // account is not applied after another change.
  int _accountChangeGeneration = 0;

  // Voting on the post is disabled unless this is current: a vote request
  // against another account's vote state can delete the account's vote.
  _PostVoteHydration _postVoteHydration = _PostVoteHydration.current;

  // Track initialization state
  bool _isInitialized = false;

  // Track if provider has been invalidated (e.g., by sign-out)
  bool _providerInvalidated = false;

  // Deep-link comment focus: attached to the target CommentCard by
  // CommentThread so it can be scrolled into view once built.
  final GlobalKey _focusedCommentKey = GlobalKey();
  bool _focusPending = false;
  bool _focusInProgress = false;

  /// The shown post: [PostDetailScreen.post] until a replacement of the same
  /// post is published, such as one carrying a new server NSFW label.
  late FeedViewPost _post;
  late final PostChangeBroadcast _postChangeBroadcast;

  /// Set once the viewer's delete of the shown post is accepted while detail
  /// is the current route and detail is leaving, so the removal it broadcasts
  /// does not reload the route on its way out. Left unset when another route
  /// is above detail, so the broadcast reloads detail as "Post Not Found".
  bool _leavingAfterDelete = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _postChangeBroadcast = context.read<PostChangeBroadcast>();
    _postChangeBroadcast.addPostChangeListener(_onPostChanged);
    // ScrollController and provider initialization moved to
    // didChangeDependencies
    // where we have access to context for synchronous provider acquisition
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize provider synchronously on first call (has context access)
    // This ensures cached data is available for the first build, avoiding
    // the flash from loading state → content → scroll position jump
    if (!_isInitialized) {
      _initializeProviderSync();
    }
  }

  /// Listen for auth state changes to handle sign-out
  void _setupAuthListener() {
    _authProvider = context.read<AuthProvider>();
    _signedInDid = _authProvider!.did;
    _authProvider!.addListener(_onAuthChanged);
  }

  /// Handle a change of signed-in account: sign-out pops the screen; a
  /// sign-in or account switch moves it to the thread for the new account
  /// and refetches the post's vote for that account.
  void _onAuthChanged() {
    if (!mounted) {
      return;
    }

    final previousDid = _signedInDid;
    final signedInDid = _authProvider!.did;
    _signedInDid = signedInDid;

    if (previousDid == signedInDid || !_isInitialized || _providerInvalidated) {
      return;
    }
    _accountChangeGeneration++;

    if (signedInDid != null) {
      _reacquireProvider();
      unawaited(_refreshPostVote());
      return;
    }

    // If user signed out while viewing this screen, navigate back
    // The CommentsProviderCache has already disposed our provider
    _providerInvalidated = true;

    if (kDebugMode) {
      debugPrint('🚪 User signed out - cleaning up PostDetailScreen');
    }

    // Remove listener from provider (it's disposed but this is safe)
    try {
      _commentsProvider.removeListener(_onProviderChanged);
    } on Exception {
      // Provider already disposed - expected
    }

    // Navigate back to feed
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Move to the cache's provider for the newly signed-in account and load
  /// its thread.
  ///
  /// The cache disposed the old provider and dropped this screen's pin when
  /// the DID changed, so the pin acquired here is the only one to release.
  void _reacquireProvider() {
    _commentsProvider.removeListener(_onProviderChanged);
    setState(() {
      _commentsProvider = _commentsCache!.acquireProvider(
        postUri: _post.post.uri,
        postCid: _post.post.cid,
      );
    });
    _commentsProvider.addListener(_onProviderChanged);

    // As on first mount: an optimistic post is not indexed yet.
    if (!widget.isOptimistic) {
      _commentsProvider.loadComments(refresh: true);
    }
  }

  /// Fetch the post under the newly signed-in session and apply its vote.
  ///
  /// The post this screen shows carries the previous session's viewer state
  /// (none, when it was loaded signed out), and the comments provider
  /// hydrates only comments. The action bar's vote always sends a create,
  /// which the server toggles off when the account already voted that way,
  /// so a tap against the previous session's state can delete the account's
  /// vote. Voting stays disabled from the DID change (this runs
  /// synchronously up to the fetch) until the vote for this account lands.
  ///
  /// The response is dropped if the screen is gone, signed out, or the DID
  /// changed again while the request was in flight. On a failed request
  /// voting stays disabled and Retry is offered.
  Future<void> _refreshPostVote() async {
    // As in [_reacquireProvider]: an optimistic post is not indexed yet.
    if (widget.isOptimistic) {
      return;
    }
    final generation = _accountChangeGeneration;
    final fetchPost = context.read<CovesApiService>().getPost;
    final hydrator = ViewerStateHydrator(
      authProvider: _authProvider!,
      voteProvider: context.read<VoteProvider>(),
    );
    setState(() => _postVoteHydration = _PostVoteHydration.loading);

    bool isSuperseded() =>
        !mounted ||
        _providerInvalidated ||
        generation != _accountChangeGeneration;

    try {
      final result = await fetchPost(_post.post.uri);
      if (isSuperseded()) {
        return;
      }
      if (result is PostGetSuccess) {
        // VoteProvider does not notify when it adopts a snapshot, so the
        // action bar picks the vote up from this rebuild.
        setState(() {
          hydrator.hydratePost(result.post);
          _postVoteHydration = _PostVoteHydration.current;
        });
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '⚠️ Could not refresh the post vote after an account change: '
          '${result.runtimeType}',
        );
      }
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Could not refresh the post vote after an account change: '
          '${error.runtimeType}',
        );
      }
      if (isSuperseded()) {
        return;
      }
    }
    _showPostVoteRefreshFailed();
  }

  /// Keep voting disabled and offer Retry, which fetches the post again.
  void _showPostVoteRefreshFailed() {
    setState(() => _postVoteHydration = _PostVoteHydration.failed);
    // Replaces a failure shown for an earlier account change, whose Retry
    // would no longer apply.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text("Couldn't load your vote on this post."),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Retry',
            textColor: AppColors.textPrimary,
            onPressed: _retryPostVoteRefresh,
          ),
        ),
      );
  }

  /// Retry the post's refetch, unless a sign-out or a later account change
  /// has superseded the one that failed, or the screen is gone. A snack bar
  /// outlives the screen that showed it.
  void _retryPostVoteRefresh() {
    if (!mounted ||
        _providerInvalidated ||
        _postVoteHydration != _PostVoteHydration.failed) {
      return;
    }
    unawaited(_refreshPostVote());
  }

  /// Initialize provider synchronously from cache
  ///
  /// Called from didChangeDependencies to ensure cached data is available
  /// for the first build. Creates ScrollController with initialScrollOffset
  /// set to cached position unless an explicit comment focus takes precedence.
  void _initializeProviderSync() {
    // Get or create provider from cache
    final cache = context.read<CommentsProviderCache>();
    _commentsCache = cache;
    _commentsProvider = cache.acquireProvider(
      postUri: _post.post.uri,
      postCid: _post.post.cid,
    );

    // Focus scans downward from the top, so cached scroll restoration must
    // not start below the requested comment.
    final hasCommentFocus = widget.focusCommentUri != null;
    final initialScrollOffset = hasCommentFocus
        ? 0.0
        : _commentsProvider.scrollPosition;
    _scrollController = ScrollController(
      initialScrollOffset: initialScrollOffset,
    );
    _scrollController.addListener(_onScroll);
    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: _onLoadMore,
    )..attach();

    if (kDebugMode && initialScrollOffset > 0) {
      debugPrint(
        '📍 Created ScrollController with initial offset: '
        '$initialScrollOffset',
      );
    }

    // Rebuilds come from the Consumer in _buildContent; this listener only
    // retries a pending comment focus once a load settles.
    _commentsProvider.addListener(_onProviderChanged);

    // Setup auth listener
    _setupAuthListener();

    // Mark as initialized before triggering any loads
    // This ensures the first build shows content (not loading) when cached
    _isInitialized = true;

    // Skip loading for optimistic posts (just created, not yet indexed)
    if (widget.isOptimistic) {
      if (kDebugMode) {
        debugPrint('✨ Optimistic post - skipping initial comment load');
      }
      // Don't load comments - there won't be any yet
    } else if (_commentsProvider.comments.isNotEmpty) {
      // Already have cached data - it will render immediately
      if (kDebugMode) {
        debugPrint(
          '📦 Using cached comments (${_commentsProvider.comments.length})',
        );
      }

      // Background refresh if data is stale (won't cause flicker). A focused
      // comment deep link always refreshes so replies posted since the thread
      // was cached are not missed.
      if (_commentsProvider.isStale || widget.focusCommentUri != null) {
        if (kDebugMode) {
          debugPrint('🔄 Refreshing cached thread in background');
        }
        _commentsProvider.loadComments(refresh: true);
      }
    } else {
      // No cached data - load fresh
      _commentsProvider.loadComments(refresh: true);
    }

    if (widget.focusCommentUri != null) {
      _focusPending = true;
      // Cached data renders on the first frame with no provider change
      // event, so kick the focus attempt from here as well.
      if (_commentsProvider.comments.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocusComment());
      }
    }
  }

  @override
  void didUpdateWidget(PostDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FeedViewPost has no value equality and parents (the cold-load loader,
    // router page rebuilds) rebuild it from a stale snapshot; adopting it
    // for the same post would revert a published replacement.
    if (widget.post.post.uri != _post.post.uri) {
      _post = widget.post;
    }
  }

  void _onPostChanged(PostChange change) {
    switch (change) {
      case PostReplaced(:final post) when post.uri == _post.post.uri:
        setState(() => _post = _post.copyWith(post: post));
      case PostRemoved(:final uri) when uri == _post.post.uri:
        if (!_leavingAfterDelete) {
          widget.onPostRemoved?.call();
        }
      case PostReplaced() || PostRemoved():
        break;
    }
  }

  @override
  void dispose() {
    _postChangeBroadcast.removePostChangeListener(_onPostChanged);
    // Remove auth listener via the stored reference — context.read here is
    // unsafe once the ancestor is deactivated (tree finalization) and throws
    // a FlutterError that `on Exception` cannot catch.
    _authProvider?.removeListener(_onAuthChanged);
    _authProvider = null;

    // Release provider pin in cache (prevents LRU eviction disposing an active
    // provider while this screen is in the navigation stack). After a
    // sign-out the cache has already cleared every pin, so this screen holds
    // none and a release would consume another owner's.
    if (_isInitialized && !_providerInvalidated) {
      try {
        _commentsCache?.releaseProvider(_post.post.uri);
      } on Exception catch (e) {
        // Cache may already be disposed - expected behavior
        if (kDebugMode) {
          debugPrint('dispose: cache release failed: $e');
        }
      }
    }

    // Remove provider listener if not already invalidated
    if (_isInitialized && !_providerInvalidated) {
      try {
        _commentsProvider.removeListener(_onProviderChanged);
      } on Exception catch (e) {
        // Provider may already be disposed - expected behavior
        if (kDebugMode) {
          debugPrint('dispose: provider listener removal failed: $e');
        }
      }
    }
    _paginationListener.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Retry a pending comment focus after the provider settles.
  ///
  /// No setState: the Consumer in [_buildContent] already rebuilds the
  /// comment list, and a screen-level rebuild would double the work.
  void _onProviderChanged() {
    if (mounted && _focusPending && !_commentsProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocusComment());
    }
  }

  /// Scroll to and highlight [PostDetailScreen.focusCommentUri].
  ///
  /// Runs once after the first successful thread load. The comment list is
  /// a lazy sliver, so the target's key has no context until its top-level
  /// ancestor has been laid out: we page the viewport down until it appears,
  /// then `ensureVisible` it. If the comment cannot be displayed in the loaded
  /// tree, its subtree is fetched by rkey and opened as a focused thread.
  Future<void> _tryFocusComment() async {
    final targetUri = widget.focusCommentUri;
    if (targetUri == null ||
        !_focusPending ||
        _focusInProgress ||
        !mounted ||
        _providerInvalidated) {
      return;
    }
    final provider = _commentsProvider;
    if (provider.isLoading) {
      return;
    }
    if (provider.comments.isEmpty && provider.error != null) {
      // Thread failed to load; nothing to focus. Retry re-triggers via
      // _onProviderChanged, so leave _focusPending set.
      return;
    }
    _focusInProgress = true;
    _focusPending = false;
    // Captured before the awaits below so the failure toast never touches
    // BuildContext across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    // A sign-out or account switch during an await disposes [provider], so
    // the attempt stops rather than call into it or act on its results.
    bool isAbandoned() =>
        !mounted ||
        _providerInvalidated ||
        !identical(provider, _commentsProvider);

    try {
      final isDisplayable = _isCommentDisplayable(
        provider.comments,
        targetUri,
        provider.collapsedComments,
      );

      if (isDisplayable) {
        final displayed = await _scrollToFocusedComment();
        if (isAbandoned() || displayed) {
          return;
        }
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        if (isAbandoned()) {
          return;
        }
      }

      // Missing or not displayable (e.g. collapsed / past the depth cutoff):
      // fetch its subtree and present it focused, with this thread underneath.
      final generationBeforeFetch = provider.treeGeneration;
      final subtree = await provider.loadMoreReplies(targetUri);
      if (isAbandoned()) {
        return;
      }
      if (subtree == null && provider.treeGeneration != generationBeforeFetch) {
        // A whole-tree refresh landed mid-flight and the subtree was
        // discarded as stale, not missing. The refresh's notification fired
        // while this attempt held _focusInProgress, so re-arm and retry
        // against the refreshed tree once the finally below releases it.
        _focusPending = true;
        WidgetsBinding.instance
          ..addPostFrameCallback((_) => _tryFocusComment())
          // A post-frame callback does not schedule a frame by itself.
          ..ensureVisualUpdate();
        return;
      }
      if (subtree == null) {
        _showFocusFailed(messenger);
        return;
      }
      _onContinueThread(subtree, const []);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Could not focus comment: $e');
      }
      if (!isAbandoned()) {
        _showFocusFailed(messenger);
      }
    } finally {
      _focusInProgress = false;
    }
  }

  Future<bool> _scrollToFocusedComment() async {
    // Lazy sliver: page down until the keyed card is built, then align it.
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!mounted || _providerInvalidated) {
        return false;
      }
      final targetContext = _focusedCommentKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        // The context is re-read from the key on every iteration after the
        // frame await above, so it is never stale here.
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.15,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return mounted && !_providerInvalidated;
      }
      if (!_scrollController.hasClients) {
        return false;
      }
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) {
        // Reached the end without finding it (it was collapsed or removed).
        return false;
      }
      _scrollController.jumpTo(
        (position.pixels + position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  void _showFocusFailed(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Couldn't find that comment. It may have been deleted."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Handle sort changes from dropdown
  Future<void> _onSortChanged(String newSort) async {
    final success = await _commentsProvider.setSortOption(newSort);

    // Show error snackbar if sort change failed. A post that is gone shows
    // its unavailable state instead: retrying the sort cannot help.
    if (!success && mounted && !_isPostUnavailable(_commentsProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to change sort order. Please try again.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Retry',
            textColor: AppColors.textPrimary,
            onPressed: () {
              _onSortChanged(newSort);
            },
          ),
        ),
      );
    }
  }

  /// Save scroll position to provider on every scroll event
  void _onScroll() {
    // Don't interact with disposed provider
    if (_providerInvalidated) {
      return;
    }

    if (_scrollController.hasClients) {
      _commentsProvider.scrollPosition = _scrollController.position.pixels;
    }
  }

  /// Load more comments when near bottom (fired by [_paginationListener])
  void _onLoadMore() {
    // Don't interact with disposed provider
    if (_providerInvalidated) {
      return;
    }

    _commentsProvider.loadMoreComments();
  }

  /// Whether the server reported the post gone (getComments RootNotFound).
  ///
  /// RootNotFound also covers a post the AppView has not indexed yet, so a
  /// post this client just created ([PostDetailScreen.isOptimistic]) treats
  /// it as an ordinary load error instead.
  bool _isPostUnavailable(CommentsProvider provider) =>
      !widget.isOptimistic &&
      provider.errorCode == CommentsProvider.rootNotFoundErrorCode;

  /// Handle pull-to-refresh
  Future<void> _onRefresh() async {
    // Don't interact with disposed provider
    if (_providerInvalidated) {
      return;
    }

    await _commentsProvider.refreshComments();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading until provider is initialized
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: FullScreenLoading(),
      );
    }

    // If provider was invalidated (sign-out), show loading while navigating
    // away
    if (_providerInvalidated) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: FullScreenLoading(),
      );
    }

    // Provide the cached CommentsProvider to descendant widgets
    return ChangeNotifierProvider.value(
      value: _commentsProvider,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _buildContent(),
        // Commenting on or voting for a post that is gone can never succeed.
        bottomNavigationBar: Selector<CommentsProvider, bool>(
          selector: (_, provider) => _isPostUnavailable(provider),
          builder: (context, postUnavailable, actionBar) =>
              postUnavailable ? const SizedBox.shrink() : actionBar!,
          child: _buildActionBar(),
        ),
      ),
    );
  }

  /// Build community title with avatar, name on top and instance below.
  ///
  /// Tapping the title navigates to the community's feed.
  Widget _buildCommunityTitle() {
    final community = _post.post.community;

    final displayHandle = CommunityHandleUtils.resolveDisplayHandle(
      name: community.name,
      origin: community.origin,
      handle: community.handle,
    );

    return TappableCommunity(
      communityDid: community.did,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // The avatar is only 28pt tall, so without a floor the tap target
      // lands short of the 48pt minimum. 48 still clears kToolbarHeight
      // (56), so the app bar is unaffected.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Community avatar
            CommunityAvatar(
              name: community.name,
              avatarUrl: community.avatar,
              size: 28,
            ),
            const SizedBox(width: 10),
            // Text column
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Community name with ! prefix - bigger, teal
                  Text(
                    '!${community.name}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.communityName,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Instance below - smaller (omitted when unresolvable)
                  if (displayHandle != null)
                    Text(
                      displayHandle.instance,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The post's link on the web client, shared from here. Null
  /// when the post's at-URI yields no canonical URL.
  String? get _postWebUrl => _post.post.webUrl(WebLinkBuilder.current());

  Future<void> _handleVote(
    VoteProvider voteProvider, {
    required String direction,
  }) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to vote on posts'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // The action bar's old tap handler stays installed until the frame
    // after an account change, so check hydration here too.
    if (!mounted ||
        _providerInvalidated ||
        _postVoteHydration != _PostVoteHydration.current) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    // Do not delay VoteProvider's per-subject lock on non-essential haptics.
    HapticFeedback.lightImpact().ignore();

    try {
      await voteProvider.toggleVote(
        postUri: _post.post.uri,
        postCid: _post.post.cid,
        direction: direction,
      );
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.vote(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Build bottom action bar with voting and comment actions
  Widget _buildActionBar() {
    return Consumer<VoteProvider>(
      builder: (context, voteProvider, child) {
        final isVoted = voteProvider.isLiked(_post.post.uri);
        final isVotePending = voteProvider.isPending(_post.post.uri);
        final adjustedScore = voteProvider.getAdjustedScore(
          _post.post.uri,
          _post.post.stats.score,
        );

        // Create a modified post with adjusted score for display
        final displayPost = _post.copyWith(
          post: _post.post.copyWith(
            stats: _post.post.stats.copyWith(score: adjustedScore),
          ),
        );

        return PostActionBar(
          post: displayPost,
          isVoted: isVoted,
          isVotePending: isVotePending,
          votingEnabled: _postVoteHydration == _PostVoteHydration.current,
          onCommentInputTap: _openCommentComposer,
          onCommentCountTap: _scrollToComments,
          onVoteTap: () => _handleVote(voteProvider, direction: 'up'),
          onSaveTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Save feature coming soon!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  /// Scroll to the comments section
  void _scrollToComments() {
    final context = _commentsHeaderKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Open the reply screen for composing a comment
  void _openCommentComposer() {
    // Check authentication
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to comment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to reply screen with full post context
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReplyScreen(
          post: _post,
          onSubmit: _handleCommentSubmit,
          commentsProvider: _commentsProvider,
        ),
      ),
    );
  }

  /// Handle comment submission (reply to post)
  Future<void> _handleCommentSubmit(
    String content,
    List<RichTextFacet> facets,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _commentsProvider.createComment(
        content: content,
        contentFacets: facets,
      );

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Comment posted'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.comment(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
      rethrow; // Let ReplyScreen know submission failed
    }
  }

  /// Handle reply to a comment (nested reply)
  Future<void> _handleCommentReply(
    String content,
    List<RichTextFacet> facets,
    ThreadViewComment parentComment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _commentsProvider.createComment(
        content: content,
        contentFacets: facets,
        parentComment: parentComment,
      );

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Reply posted'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.comment(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
      rethrow; // Let ReplyScreen know submission failed
    }
  }

  /// Leave the unavailable state: pop when there is a route to return to,
  /// otherwise (a deep link opened the post directly) go to the feed, as
  /// PostDetailLoader does.
  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/feed');
    }
  }

  /// Leaves detail once the viewer's delete of the shown post has been
  /// accepted by the server, as [_goBack] does, when detail is the current
  /// route. When the viewer opened another route over detail while the
  /// delete was pending, detail stays where it is, and the removal broadcast
  /// reloads it so the viewer finds it as "Post Not Found" on coming back.
  void _leaveAfterDelete() {
    if (!mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }
    _leavingAfterDelete = true;
    _goBack();
  }

  /// Open reply screen for replying to a comment
  void _openReplyToComment(ThreadViewComment comment) {
    // Check authentication
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to reply'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to reply screen with comment context
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReplyScreen(
          comment: comment,
          onSubmit: (content, facets) =>
              _handleCommentReply(content, facets, comment),
          commentsProvider: _commentsProvider,
        ),
      ),
    );
  }

  /// Navigate to focused thread screen for deep threads
  void _onContinueThread(
    ThreadViewComment thread,
    List<ThreadViewComment> ancestors,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FocusedThreadScreen(
          thread: thread,
          ancestors: ancestors,
          commentsProvider: _commentsProvider,
          parentPost: _post.post,
        ),
      ),
    );
  }

  /// Load hidden replies for a comment (per-parent cap / depth cutoff)
  Future<void> _onLoadMoreReplies(ThreadViewComment thread) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _commentsProvider.loadMoreReplies(thread.comment.uri);
    } on Exception {
      _showLoadRepliesFailed(messenger);
    }
  }

  void _showLoadRepliesFailed(ScaffoldMessengerState messenger) {
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Failed to load replies. Please try again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Build main content area
  Widget _buildContent() {
    // Use Consumer to rebuild when comments provider changes
    return Consumer<CommentsProvider>(
      builder: (context, commentsProvider, child) {
        final isLoading = commentsProvider.isLoading;
        final error = commentsProvider.error;
        final comments = commentsProvider.comments;
        final isLoadingMore = commentsProvider.isLoadingMore;
        final loadMoreError = commentsProvider.loadMoreError;

        // The post is gone: replace the post and any loaded thread, whose
        // content the server no longer serves. Stays up while Check again
        // is in flight, and clears once a refresh succeeds.
        if (_isPostUnavailable(commentsProvider)) {
          // The action bar is hidden and there is no app bar here, so the
          // state carries its own way back.
          return SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: BackButton(
                    color: AppColors.textPrimary,
                    onPressed: _goBack,
                  ),
                ),
                Expanded(
                  // RootNotFound also means not indexed yet or not visible
                  // to this viewer, so the state can be checked again.
                  child: FullScreenError(
                    title: _postUnavailableCopy,
                    message: 'It may have been deleted or removed.',
                    onRetry: null,
                    secondaryActionLabel: 'Check again',
                    onSecondaryAction: _onRefresh,
                  ),
                ),
              ],
            ),
          );
        }

        // Loading state (only show full-screen loader for initial load)
        if (isLoading && comments.isEmpty) {
          return const FullScreenLoading();
        }

        // Error state (only show full-screen error when no comments loaded yet)
        if (error != null && comments.isEmpty) {
          return FullScreenError(
            title: 'Failed to load comments',
            message: error,
            onRetry: commentsProvider.retry,
          );
        }

        // Content with RefreshIndicator and floating SliverAppBar
        // Wrapped in Stack to add solid status bar background overlay
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.primary,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Pinned app bar that stays visible when scrolling
                  SliverAppBar(
                    backgroundColor: AppColors.background,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: AppColors.textPrimary,
                    title: _buildCommunityTitle(),
                    centerTitle: false,
                    elevation: 0,
                    pinned: true,
                    actions: [
                      ShareButton(
                        url: _postWebUrl,
                        useIconButton: true,
                        color: AppColors.textPrimary,
                      ),
                      PostOptionsMenu(
                        post: _post,
                        sessionStamp: widget.sessionStamp,
                        onDeleted: _leaveAfterDelete,
                        anchorBuilder: (context, controller) => IconButton(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'More options',
                          onPressed: () {
                            if (controller.isOpen) {
                              controller.close();
                            } else {
                              controller.open();
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  // Post + comments + loading indicator
                  SliverSafeArea(
                    top: false,
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Post card (index 0)
                          if (index == 0) {
                            return ResponsiveUtils.wrapForTablet(
                              context,
                              Column(
                                children: [
                                  // Reuse PostCard (hide comment button in
                                  // detail view)
                                  // Use ValueListenableBuilder to only rebuild
                                  // when time changes
                                  _PostHeader(
                                    post: _post,
                                    currentTimeNotifier:
                                        commentsProvider.currentTimeNotifier,
                                  ),

                                  // Visual divider before comments section
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    height: 1,
                                    color: AppColors.border,
                                  ),

                                  // Comments header with sort dropdown.
                                  // The server-side commentCount includes
                                  // comments the viewer never sees (deleted,
                                  // blocked, filtered). When the thread
                                  // loaded successfully but nothing is
                                  // renderable, show the empty state instead
                                  // of a count over an empty list.
                                  CommentsHeader(
                                    key: _commentsHeaderKey,
                                    commentCount:
                                        PostDetailScreen.displayedCommentCount(
                                          serverCount: widget
                                              .post
                                              .post
                                              .stats
                                              .commentCount,
                                          isLoading: isLoading,
                                          hasError: error != null,
                                          hasComments: comments.isNotEmpty,
                                          hasMore: commentsProvider.hasMore,
                                        ),
                                    currentSort: commentsProvider.sort,
                                    onSortChanged: _onSortChanged,
                                  ),
                                ],
                              ),
                            );
                          }

                          // Loading indicator or error at the end
                          if (index == comments.length + 1) {
                            if (isLoadingMore) {
                              return ResponsiveUtils.wrapForTablet(
                                context,
                                const InlineLoading(),
                              );
                            }
                            // A load-more error wins over a refresh error,
                            // as in PaginatedSliverList. A refresh error only
                            // reaches here with comments on screen.
                            if (loadMoreError != null) {
                              return ResponsiveUtils.wrapForTablet(
                                context,
                                InlineError(
                                  message: loadMoreError,
                                  onRetry: commentsProvider.retryLoadMore,
                                ),
                              );
                            }
                            if (error != null) {
                              return ResponsiveUtils.wrapForTablet(
                                context,
                                InlineError(
                                  message: error,
                                  onRetry: commentsProvider.refreshComments,
                                ),
                              );
                            }
                          }

                          // Comment item - use existing CommentThread widget
                          final comment = comments[index - 1];
                          return ResponsiveUtils.wrapForTablet(
                            context,
                            _CommentItem(
                              comment: comment,
                              currentTimeNotifier:
                                  commentsProvider.currentTimeNotifier,
                              onCommentTap: _openReplyToComment,
                              collapsedComments:
                                  commentsProvider.collapsedComments,
                              onCollapseToggle:
                                  commentsProvider.toggleCollapsed,
                              onContinueThread: _onContinueThread,
                              onLoadMoreReplies: _onLoadMoreReplies,
                              loadingMoreReplies:
                                  commentsProvider.loadingMoreReplies,
                              onDelete: (uri) => commentsProvider.deleteComment(
                                commentUri: uri,
                              ),
                              focusedCommentUri: widget.focusCommentUri,
                              focusedCommentKey: _focusedCommentKey,
                              parentPost: _post.post,
                              sessionStamp: commentsProvider.sessionStamp,
                              reloadAfterModeration: () async {
                                await commentsProvider.loadComments(
                                  refresh: true,
                                  quiet: true,
                                );
                                return commentsProvider.error == null;
                              },
                            ),
                          );
                        },
                        childCount:
                            1 +
                            comments.length +
                            (isLoadingMore ||
                                    loadMoreError != null ||
                                    error != null
                                ? 1
                                : 0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Prevents content showing through transparent status bar
            const StatusBarOverlay(),
          ],
        );
      },
    );
  }
}

/// Post header widget that only rebuilds when time changes
///
/// Extracted to prevent unnecessary rebuilds when comment list changes.
/// Uses ValueListenableBuilder to listen only to time updates.
class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post, required this.currentTimeNotifier});

  final FeedViewPost post;
  final ValueNotifier<DateTime?> currentTimeNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: currentTimeNotifier,
      builder: (context, currentTime, child) {
        return DetailedPostView(post: post, currentTime: currentTime);
      },
    );
  }
}

/// Comment item wrapper that only rebuilds when time changes
///
/// Uses ValueListenableBuilder to prevent rebuilds when unrelated
/// provider state changes (like loading state or error state).
class _CommentItem extends StatelessWidget {
  const _CommentItem({
    required this.comment,
    required this.currentTimeNotifier,
    required this.sessionStamp,
    this.onCommentTap,
    this.collapsedComments = const {},
    this.onCollapseToggle,
    this.onContinueThread,
    this.onLoadMoreReplies,
    this.loadingMoreReplies = const {},
    this.onDelete,
    this.focusedCommentUri,
    this.focusedCommentKey,
    this.parentPost,
    this.reloadAfterModeration,
  });

  final ThreadViewComment comment;

  /// The session key the thread was loaded under.
  final Object? sessionStamp;

  /// Reloads the thread quietly after a moderation action finds a comment
  /// changed or gone, completing with whether the reload landed.
  final Future<bool> Function()? reloadAfterModeration;

  /// The post these comments belong to. Supplies what a comment permalink
  /// needs.
  final PostView? parentPost;
  final ValueNotifier<DateTime?> currentTimeNotifier;
  final void Function(ThreadViewComment)? onCommentTap;
  final Set<String> collapsedComments;
  final void Function(String uri)? onCollapseToggle;
  final void Function(ThreadViewComment, List<ThreadViewComment>)?
  onContinueThread;
  final void Function(ThreadViewComment)? onLoadMoreReplies;
  final Set<String> loadingMoreReplies;
  final Future<void> Function(String commentUri)? onDelete;
  final String? focusedCommentUri;
  final Key? focusedCommentKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: currentTimeNotifier,
      builder: (context, currentTime, child) {
        return CommentThread(
          thread: comment,
          currentTime: currentTime,
          maxDepth: _commentThreadMaxDepth,
          onCommentTap: onCommentTap,
          collapsedComments: collapsedComments,
          onCollapseToggle: onCollapseToggle,
          onContinueThread: onContinueThread,
          onLoadMoreReplies: onLoadMoreReplies,
          loadingMoreReplies: loadingMoreReplies,
          onDelete: onDelete,
          focusedCommentUri: focusedCommentUri,
          focusedCommentKey: focusedCommentKey,
          parentPost: parentPost,
          sessionStamp: sessionStamp,
          reloadAfterModeration: reloadAfterModeration,
        );
      },
    );
  }
}
