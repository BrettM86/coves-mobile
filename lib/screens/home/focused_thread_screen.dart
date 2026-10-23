import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../services/comments_provider_cache.dart';
import '../../utils/error_messages.dart';
import '../../widgets/comment_card.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/status_bar_overlay.dart';
import '../compose/reply_screen.dart';

/// Focused thread screen for viewing deep comment threads
///
/// Displays a specific comment as the "anchor" with its full reply tree.
/// Used when user taps "Read X more replies" on a deeply nested thread.
///
/// Shows:
/// - Ancestor comments shown flat at the top (walking up the chain)
/// - The anchor comment (highlighted as the focus)
/// - All replies threaded below with fresh depth starting at 0
///
/// ## Collapsed State
/// This screen maintains its own collapsed comment state, intentionally
/// providing a "fresh slate" experience. When the user navigates back,
/// any collapsed state is reset. This is by design - it allows users to
/// explore deep threads without their collapse choices persisting across
/// navigation, keeping the focused view clean and predictable.
///
/// ## Comments provider
/// Pins the post's CommentsProvider in [CommentsProviderCache] while open
/// and uses it for the thread, reply drafts and replies posted here. It
/// depends on no screen underneath: the router can replace the post
/// screen's State while this pageless route stays open. The cache disposes
/// every provider when the signed-in DID changes, so a sign-in, account
/// switch or sign-out moves the screen to the cache's provider for the new
/// session.
class FocusedThreadScreen extends StatefulWidget {
  const FocusedThreadScreen({
    required this.thread,
    required this.ancestors,
    required this.commentsProvider,
    this.parentPost,
    super.key,
  });

  /// The comment thread to focus on (becomes the new root)
  final ThreadViewComment thread;

  /// The post this thread belongs to, when the caller has it loaded.
  /// Supplies what a comment permalink needs.
  final PostView? parentPost;

  /// Ancestor comments leading to this thread (for context display)
  final List<ThreadViewComment> ancestors;

  /// The comments provider of the screen that opened this one. It only
  /// identifies the post: this screen pins the post's provider itself.
  final CommentsProvider commentsProvider;

  @override
  State<FocusedThreadScreen> createState() => _FocusedThreadScreenState();
}

class _FocusedThreadScreenState extends State<FocusedThreadScreen> {
  late CommentsProvider _commentsProvider;
  late final CommentsProviderCache _commentsCache;
  late final AuthProvider _authProvider;
  String? _signedInDid;

  /// The post whose provider this screen pins, and later releases.
  late final String _pinnedPostUri;

  @override
  void initState() {
    super.initState();
    // Pinned here rather than relying on the post screen underneath: the
    // router can replace that screen's State while this pageless route
    // stays open.
    _commentsCache = context.read<CommentsProviderCache>();
    _pinnedPostUri = widget.commentsProvider.postUri;
    _acquireProvider();
    _authProvider = context.read<AuthProvider>()..addListener(_onAuthChanged);
    _signedInDid = _authProvider.did;
  }

  void _acquireProvider() {
    _commentsProvider = _commentsCache.acquireProvider(
      postUri: _pinnedPostUri,
      postCid: widget.commentsProvider.postCid,
    );
  }

  /// Move to the cache's provider for the new session, signed in or out.
  /// The cache dropped every pin with the old provider, so the pin acquired
  /// here is the only one this screen holds. On sign-out a post screen
  /// underneath still pops back to the first route.
  void _onAuthChanged() {
    final previousDid = _signedInDid;
    _signedInDid = _authProvider.did;
    if (_signedInDid != previousDid) {
      setState(_acquireProvider);
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _commentsCache.releaseProvider(_pinnedPostUri);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Expose the post's CommentsProvider for ReplyScreen draft access
    return ChangeNotifierProvider.value(
      value: _commentsProvider,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _FocusedThreadBody(
          thread: widget.thread,
          ancestors: widget.ancestors,
          parentPost: widget.parentPost,
          commentsProvider: _commentsProvider,
        ),
      ),
    );
  }
}

class _FocusedThreadBody extends StatefulWidget {
  const _FocusedThreadBody({
    required this.thread,
    required this.ancestors,
    required this.commentsProvider,
    this.parentPost,
  });

  final ThreadViewComment thread;
  final List<ThreadViewComment> ancestors;

  /// The provider exposed above this body. A new instance means the
  /// signed-in account changed.
  final CommentsProvider commentsProvider;

  /// The post these comments belong to, when the caller has it loaded.
  final PostView? parentPost;

  @override
  State<_FocusedThreadBody> createState() => _FocusedThreadBodyState();
}

class _FocusedThreadBodyState extends State<_FocusedThreadBody> {
  final Set<String> _collapsedComments = {};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _anchorKey = GlobalKey();

  /// Local fallback subtree rooted at the anchor comment.
  ///
  /// Starts as the snapshot passed from the parent thread (which may be
  /// truncated by the original fetch depth) and is refreshed from the
  /// server so deep replies and newly posted replies show up. The build
  /// method prefers the provider's live copy of the anchor node when it is
  /// still present in the loaded tree; this is the fallback for anchors
  /// outside it.
  late ThreadViewComment _thread;

  /// The [CommentsProvider.removalSequence] [_thread] reflects: 0 for the
  /// snapshot handed in at entry, else the sequence when its fetch was
  /// requested. Only removals after it are applied over it.
  int _threadRemovalsSeen = 0;

  /// Monotonic sequence for subtree fetches so an older in-flight response
  /// can never overwrite the result of a newer one.
  int _refreshSeq = 0;

  /// The ancestor rows shown above the anchor, each with the
  /// [CommentsProvider.removalSequence] it reflects (see
  /// [_threadRemovalsSeen]) and the session stamp it was loaded under.
  /// Seeded from the widget and replaced row by row by [refreshSnapshots].
  /// A row keeps its stamp across a session change, so admin tools stay
  /// denied on it until a fetch for the current session replaces it.
  late List<({ThreadViewComment row, int removalsSeen, Object? sessionStamp})>
  _ancestors;

  /// Monotonic sequence for ancestor refreshes so an older in-flight
  /// response can never overwrite the result of a newer one.
  int _ancestorRefreshSeq = 0;

  /// Whether the most recent anchor-subtree hydration failed.
  ///
  /// Only surfaced in the UI when the snapshot has no replies to fall back
  /// on (otherwise the stale-but-usable subtree stays visible silently), or
  /// while [_awaitingNewSessionSubtree] is set.
  bool _hydrationFailed = false;

  /// Whether [_thread] still belongs to the previous session: the signed-in
  /// account changed and no subtree fetched for the new session has landed.
  /// The vote provider holds no vote state for it, so the anchor and its
  /// replies are not shown with live vote and reply controls until one
  /// lands.
  bool _awaitingNewSessionSubtree = false;

  /// Whether the signed-in account changed since this screen opened.
  /// Ancestors come from the snapshot taken at that time or from
  /// [refreshSnapshots], which applies no vote state, so after a change
  /// only an ancestor present in the current provider's loaded tree has
  /// vote state for the new session.
  bool _ancestorsFromPreviousSession = false;

  /// The provider's [CommentsProvider.lastRefreshTime] when this screen last
  /// started an anchor subtree fetch.
  DateTime? _threadRefreshTimeAtSubtreeFetch;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    // Snapshots handed in may predate any removal made in this session.
    // They were loaded with the provider's displayed thread, so they carry
    // its stamp.
    final sessionStamp = widget.commentsProvider.sessionStamp;
    _ancestors = [
      for (final ancestor in widget.ancestors)
        (row: ancestor, removalsSeen: 0, sessionStamp: sessionStamp),
    ];
    _threadRefreshTimeAtSubtreeFetch = widget.commentsProvider.lastRefreshTime;
    widget.commentsProvider.addListener(_onCommentsChanged);
    // Scroll to anchor comment after build, then hydrate the full subtree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAnchor();
      _refreshSubtree();
    });
  }

  @override
  void didUpdateWidget(_FocusedThreadBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.commentsProvider, oldWidget.commentsProvider)) {
      oldWidget.commentsProvider.removeListener(_onCommentsChanged);
      _threadRefreshTimeAtSubtreeFetch =
          widget.commentsProvider.lastRefreshTime;
      widget.commentsProvider.addListener(_onCommentsChanged);
      // A fetch still in flight on the old provider must not land on the
      // new session.
      _refreshSeq++;
      _ancestorRefreshSeq++;
      // Removal sequences are per provider, and the new one recorded none
      // before these snapshots were taken.
      _threadRemovalsSeen = 0;
      _ancestors = [
        for (final ancestor in _ancestors)
          (
            row: ancestor.row,
            removalsSeen: 0,
            sessionStamp: ancestor.sessionStamp,
          ),
      ];
      _hydrationFailed = false;
      _awaitingNewSessionSubtree = true;
      _ancestorsFromPreviousSession = true;
      // Fetch the anchor's subtree again so its replies carry the new
      // session's votes.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSubtree());
    }
  }

  /// Fetch the anchor's subtree again once a whole-thread refresh lands
  /// after the last fetch started. The provider discards a subtree fetch
  /// the refresh overlapped, and the refresh replaces the provider's copy
  /// of the anchor with one cut off at the thread's depth limit.
  ///
  /// While a fetch of the anchor is in flight the provider would hand that
  /// fetch back, so this waits for the notification its completion sends.
  /// Only a landed refresh changes the refresh time, so this fetches at
  /// most once per refresh.
  void _onCommentsChanged() {
    if (widget.commentsProvider.lastRefreshTime !=
            _threadRefreshTimeAtSubtreeFetch &&
        !_isAnchorFetchInFlight) {
      _refreshSubtree();
    }
  }

  bool get _isAnchorFetchInFlight => widget.commentsProvider.loadingMoreReplies
      .contains(widget.thread.comment.uri);

  /// Re-fetch the anchor's subtree from the server and update the view.
  ///
  /// Also merges the subtree into the provider's tree (when the anchor is
  /// present there), keeping the full thread in sync. Failures are
  /// non-fatal when a snapshot with replies is already visible; with an
  /// empty snapshot a retryable error state is shown. While
  /// [_awaitingNewSessionSubtree] is set, a failure or a null subtree shows
  /// the retryable error whatever the snapshot holds.
  ///
  /// Completes with whether this fetch landed a subtree: false when it
  /// failed, the response did not carry the anchor (nothing is applied),
  /// the screen unmounted, or a newer fetch superseded it.
  Future<bool> _refreshSubtree() async {
    if (!mounted) {
      return false;
    }
    final provider = widget.commentsProvider;
    final seq = ++_refreshSeq;
    final removalsSeen = provider.removalSequence;
    // Joining a fetch already in flight keeps the recorded time, so a
    // refresh that overlapped that fetch still triggers another one.
    if (!_isAnchorFetchInFlight) {
      _threadRefreshTimeAtSubtreeFetch = provider.lastRefreshTime;
    }
    try {
      final subtree = await provider.loadMoreReplies(widget.thread.comment.uri);
      if (!mounted || seq != _refreshSeq) {
        return false;
      }
      setState(() {
        // A null subtree leaves the snapshot as it is, which must not show
        // in a new session.
        _hydrationFailed = subtree == null && _awaitingNewSessionSubtree;
        if (subtree != null) {
          _thread = subtree;
          _threadRemovalsSeen = removalsSeen;
          _awaitingNewSessionSubtree = false;
        }
      });
      return subtree != null;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to refresh focused subtree: $e');
      }
      if (!mounted || seq != _refreshSeq) {
        return false;
      }
      setState(() => _hydrationFailed = true);
      return false;
    }
  }

  /// Re-fetches what this screen holds as its own snapshots: the anchor's
  /// subtree (through [_refreshSubtree]) and each ancestor row. An ancestor
  /// fetch that failed or did not carry the row keeps that row's snapshot.
  /// Each row that landed is stamped with the removal sequence of its own
  /// request, never with the sequence when the whole batch completed: a
  /// removal confirmed while another row was still in flight must keep
  /// showing on a row that had already landed.
  ///
  /// Completes with whether every row was refreshed: false when any
  /// ancestor fetch or the subtree refresh failed or came back without its
  /// row, or when this refresh was not applied because the screen unmounted
  /// or a newer one superseded it.
  Future<bool> refreshSnapshots() async {
    if (!mounted) {
      return false;
    }
    final provider = widget.commentsProvider;
    final seq = ++_ancestorRefreshSeq;
    final ancestors = _ancestors;
    final subtreeRefresh = _refreshSubtree();
    final refreshed = await Future.wait([
      for (final ancestor in ancestors) _fetchAncestor(provider, ancestor.row),
    ]);
    final subtreeRefreshed = await subtreeRefresh;
    if (!mounted || seq != _ancestorRefreshSeq) {
      return false;
    }
    setState(() {
      _ancestors = [
        for (var index = 0; index < ancestors.length; index++)
          refreshed[index] ?? ancestors[index],
      ];
    });
    return subtreeRefreshed && refreshed.every((row) => row != null);
  }

  /// The server's current copy of [ancestor] with the removal sequence and
  /// the provider's session stamp read when its request started, or null
  /// when it did not land: the fetch failed or the response did not carry
  /// the row. Either way the row was not refreshed.
  Future<({ThreadViewComment row, int removalsSeen, Object? sessionStamp})?>
  _fetchAncestor(CommentsProvider provider, ThreadViewComment ancestor) async {
    // Read when the request starts, as the provider does: a removal
    // confirmed while it is out is already applied to the result, and
    // applying it again at build changes nothing.
    final removalsSeen = provider.removalSequence;
    final sessionStamp = provider.sessionStamp;
    try {
      final row = await provider.fetchCommentSnapshot(ancestor.comment.uri);
      return row == null
          ? null
          : (row: row, removalsSeen: removalsSeen, sessionStamp: sessionStamp);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to refresh an ancestor row: $e');
      }
      return null;
    }
  }

  /// The reload a comment card runs when a moderation action finds a
  /// comment changed or gone: the whole thread quietly, then this screen's
  /// own snapshots. Sequential, so the subtree fetch starts against the
  /// refreshed tree instead of being discarded when the refresh lands.
  /// Completes with whether both landed.
  Future<bool> _reloadAfterModeration() async {
    final provider = widget.commentsProvider;
    await provider.loadComments(refresh: true, quiet: true);
    final threadReloaded = provider.error == null;
    final snapshotsRefreshed = await refreshSnapshots();
    return threadReloaded && snapshotsRefreshed;
  }

  /// Check again from the unavailable state: reload the thread. Once it
  /// lands, [_onCommentsChanged] fetches the anchor's subtree again, so the
  /// failure that showed the state must not show as a replies error.
  void _checkPostAgain() {
    setState(() => _hydrationFailed = false);
    widget.commentsProvider.refreshComments();
  }

  /// Retry from the error shown in place of the previous session's
  /// snapshot: back to the loader while the subtree is fetched again.
  void _retryNewSessionSubtree() {
    setState(() => _hydrationFailed = false);
    _refreshSubtree();
  }

  @override
  void dispose() {
    widget.commentsProvider.removeListener(_onCommentsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToAnchor() {
    final context = _anchorKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleCollapsed(String uri) {
    setState(() {
      if (_collapsedComments.contains(uri)) {
        _collapsedComments.remove(uri);
      } else {
        _collapsedComments.add(uri);
      }
    });
  }

  void _openReplyScreen(ThreadViewComment comment) {
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (navigatorContext) => ReplyScreen(
          comment: comment,
          onSubmit: (content, facets) => _submitReply(content, facets, comment),
          commentsProvider: context.read<CommentsProvider>(),
        ),
      ),
    );
  }

  /// Post a reply to [parent] through this screen's provider, then fetch
  /// the anchor's subtree again so the reply shows here. Rethrows a failure
  /// so the composer stays open.
  Future<void> _submitReply(
    String content,
    List<RichTextFacet> facets,
    ThreadViewComment parent,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.commentsProvider.createComment(
        content: content,
        contentFacets: facets,
        parentComment: parent,
      );
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
      rethrow;
    }
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Reply posted'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    await _refreshSubtree();
  }

  /// Load hidden replies for a nested comment inside the focused view
  Future<void> _onLoadMoreReplies(ThreadViewComment node) async {
    final provider = context.read<CommentsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // Skip the local merge when a newer anchor refresh starts while this
    // fetch is in flight (the refreshed subtree supersedes it).
    final seq = _refreshSeq;
    try {
      final subtree = await provider.loadMoreReplies(node.comment.uri);
      if (subtree != null && mounted && seq == _refreshSeq) {
        setState(() => _thread = _thread.replaceDescendant(subtree));
      }
    } on Exception {
      // A post that is gone shows its unavailable state instead.
      if (provider.errorCode != CommentsProvider.rootNotFoundErrorCode) {
        _showLoadRepliesFailed(messenger);
      }
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

  /// Delete a comment, then refresh both the full thread and this subtree
  Future<void> _onDelete(String uri) async {
    await context.read<CommentsProvider>().deleteComment(commentUri: uri);
    if (!mounted) {
      return;
    }
    await _refreshSubtree();
  }

  /// Navigate deeper into a nested thread
  void _onContinueThread(
    ThreadViewComment thread,
    List<ThreadViewComment> ancestors,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (navigatorContext) => FocusedThreadScreen(
          thread: thread,
          ancestors: ancestors,
          commentsProvider: context.read<CommentsProvider>(),
          parentPost: widget.parentPost,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on provider changes (e.g. per-node reply-loading spinners)
    final commentsProvider = context.watch<CommentsProvider>();

    // Prefer the provider's live copy of the anchor node when it is still
    // present in the loaded tree, so deletes, sort changes, and hydrations
    // performed elsewhere reach this screen. The local snapshot is the
    // fallback for anchors outside the provider's loaded tree.
    // The fallback snapshot and the ancestor rows are this screen's own
    // copies, so a removal confirmed anywhere after each was taken is
    // applied to it here. An earlier removal is already reflected in it,
    // and reapplying it would hide a comment restored since.
    final thread =
        _findInLoadedTree(commentsProvider, widget.thread.comment.uri) ??
        commentsProvider.applyRemovalOverlay(
          _thread,
          since: _threadRemovalsSeen,
        );

    // Calculate minimum bottom padding to allow anchor to scroll to top
    final screenHeight = MediaQuery.of(context).size.height;
    final minBottomPadding = screenHeight * 0.6;

    // The server reports the post gone: its thread is no longer served, so
    // nothing of it stays on screen. RootNotFound also means not indexed yet
    // or not visible to this viewer, so the state can be checked again.
    final postGone =
        commentsProvider.errorCode == CommentsProvider.rootNotFoundErrorCode;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            // App bar
            const SliverAppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              foregroundColor: AppColors.textPrimary,
              title: Text(
                'Thread',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              centerTitle: false,
              elevation: 0,
              floating: true,
              snap: true,
            ),

            if (postGone)
              SliverFillRemaining(
                hasScrollBody: false,
                child: FullScreenError(
                  title: postUnavailableTitle,
                  message: postUnavailableMessage,
                  onRetry: null,
                  secondaryActionLabel: 'Check again',
                  onSecondaryAction: _checkPostAgain,
                ),
              )
            else
              // Content
              SliverSafeArea(
                top: false,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Ancestor comments (shown flat, not nested)
                    for (final ancestor in _ancestors)
                      _buildAncestorComment(
                        commentsProvider.applyRemovalOverlay(
                          ancestor.row,
                          since: ancestor.removalsSeen,
                        ),
                        ancestor.sessionStamp,
                        commentsProvider,
                      ),

                    // The previous session's snapshot has no vote state for
                    // this one: a loader, or a retryable error, stands in for
                    // the anchor and its replies until the new subtree lands.
                    if (_awaitingNewSessionSubtree)
                      if (_hydrationFailed)
                        InlineError(
                          message:
                              'Could not load this thread. Please try again.',
                          onRetry: _retryNewSessionSubtree,
                        )
                      else
                        const InlineLoading()
                    else ...[
                      // Anchor comment (the focused comment) - made prominent
                      KeyedSubtree(
                        key: _anchorKey,
                        child: _buildAnchorComment(
                          thread,
                          commentsProvider.sessionStamp,
                        ),
                      ),

                      // Replies (if any)
                      if (thread.replies != null && thread.replies!.isNotEmpty)
                        ...thread.replies!.map((reply) {
                          return CommentThread(
                            key: ValueKey(reply.comment.uri),
                            thread: reply,
                            depth: 1,
                            maxDepth: 6,
                            onCommentTap: _openReplyScreen,
                            collapsedComments: _collapsedComments,
                            onCollapseToggle: _toggleCollapsed,
                            onContinueThread: _onContinueThread,
                            onLoadMoreReplies: _onLoadMoreReplies,
                            loadingMoreReplies:
                                commentsProvider.loadingMoreReplies,
                            ancestors: [thread],
                            onDelete: _onDelete,
                            parentPost: widget.parentPost,
                            sessionStamp: commentsProvider.sessionStamp,
                            reloadAfterModeration: _reloadAfterModeration,
                          );
                        }),

                      // More direct replies to the anchor beyond this page
                      if (thread.hasMore &&
                          !_collapsedComments.contains(thread.comment.uri))
                        LoadMoreRepliesButton(
                          depth: 0,
                          isLoading: commentsProvider.loadingMoreReplies
                              .contains(thread.comment.uri),
                          onTap: () => _onLoadMoreReplies(thread),
                        ),

                      // Empty state (or retryable error) if no replies loaded
                      if (thread.replies == null ||
                          thread.replies!.isEmpty) ...[
                        if (_hydrationFailed)
                          InlineError(
                            message:
                                'Could not load replies. Please try again.',
                            onRetry: _refreshSubtree,
                          )
                        else if (!thread.hasMore)
                          _buildNoReplies(),
                      ],
                    ],

                    // Bottom padding to allow anchor to scroll to top
                    SizedBox(height: minBottomPadding),
                  ]),
                ),
              ),
          ],
        ),

        // Prevents content showing through transparent status bar
        const StatusBarOverlay(),
      ],
    );
  }

  /// The node for [commentUri] in [provider]'s loaded tree, if present.
  ThreadViewComment? _findInLoadedTree(
    CommentsProvider provider,
    String commentUri,
  ) {
    for (final root in provider.comments) {
      final node = root.findByUri(commentUri);
      if (node != null) {
        return node;
      }
    }
    return null;
  }

  /// Build an ancestor comment (shown flat as context above anchor)
  /// Styled more subtly than the anchor to show it's contextual
  ///
  /// After a session change its vote and reply controls act only when
  /// [commentsProvider]'s loaded tree has it: that provider was created for
  /// the new session, so its tree came from responses whose votes it
  /// applied.
  ///
  /// [sessionStamp] is the stamp the row's snapshot was loaded under, so a
  /// row retained from a previous session is denied admin tools.
  Widget _buildAncestorComment(
    ThreadViewComment ancestor,
    Object? sessionStamp,
    CommentsProvider commentsProvider,
  ) {
    final controlsEnabled =
        !_ancestorsFromPreviousSession ||
        _findInLoadedTree(commentsProvider, ancestor.comment.uri) != null;
    return Opacity(
      opacity: 0.6,
      child: CommentCard(
        comment: ancestor.comment,
        onTap: controlsEnabled ? () => _openReplyScreen(ancestor) : null,
        onDelete: _onDelete,
        parentPost: widget.parentPost,
        sessionStamp: sessionStamp,
        reloadAfterModeration: _reloadAfterModeration,
        votingEnabled: controlsEnabled,
      ),
    );
  }

  /// Build the anchor comment (the focused comment) with prominent styling
  Widget _buildAnchorComment(ThreadViewComment thread, Object? sessionStamp) {
    // Note: CommentCard has its own Consumer<VoteProvider> for vote state
    return Container(
      decoration: BoxDecoration(
        // Subtle highlight to distinguish anchor from ancestors
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      child: CommentCard(
        comment: thread.comment,
        onTap: () => _openReplyScreen(thread),
        onLongPress: () => _toggleCollapsed(thread.comment.uri),
        isCollapsed: _collapsedComments.contains(thread.comment.uri),
        collapsedCount: _collapsedComments.contains(thread.comment.uri)
            ? thread.comment.stats.replyCount
            : 0,
        onDelete: _onDelete,
        parentPost: widget.parentPost,
        sessionStamp: sessionStamp,
        reloadAfterModeration: _reloadAfterModeration,
      ),
    );
  }

  /// Build empty state when there are no replies
  Widget _buildNoReplies() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No replies yet',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to reply to this comment',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
