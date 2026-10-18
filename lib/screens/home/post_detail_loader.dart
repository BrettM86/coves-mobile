import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/moderation_constants.dart';
import '../../models/moderation.dart';
import '../../models/post.dart';
import '../../models/post_get_result.dart';
import '../../providers/auth_provider.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/admin_moderation_flow.dart';
import '../../services/admin_tools_gate.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../services/moderation_errors.dart';
import '../../services/viewer_state_hydrator.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/error_messages.dart';
import '../../utils/post_detail_route.dart';
import '../../utils/removal_copy.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/moderation/moderation_action_sheet.dart';
import '../../widgets/moderation/moderation_failure_decision.dart';
import 'post_detail_screen.dart';

/// Function that fetches a post by AT-URI.
///
/// Injectable for testing; defaults to [CovesApiService.getPost].
typedef PostFetcher = Future<PostGetResult> Function(String uri);

/// Post Detail Loader
///
/// Cold-loads a post by AT-URI and renders [PostDetailScreen] once fetched.
/// Used when the `/post/:postUri` route is entered without a [FeedViewPost]
/// in route extras (e.g., OS state restoration or deep links). With
/// [loadedPost] (in-app navigation) that post is shown without a fetch.
///
/// When the shown post is removed, the loader fetches it again and shows
/// whatever the server now returns, such as the tombstone.
///
/// States:
/// - Loading: full-screen spinner with a back button
/// - Success: renders [PostDetailScreen]
/// - Not found / blocked: user-friendly error with navigation back
/// - Removed by moderation: a tombstone that offers an admin "Restore post"
///   when the server grants it to the session that requested the post
/// - Fetch failure: error state with retry
class PostDetailLoader extends StatefulWidget {
  const PostDetailLoader({
    required this.postUri,
    this.fetchPost,
    this.focusCommentUri,
    this.loadedPost,
    super.key,
  });

  /// The post the opening surface already loaded, with the session it was
  /// loaded under; shown without a fetch.
  final PostDetailRouteExtra? loadedPost;

  /// Decoded AT-URI of the post to load (must start with `at://`)
  final String postUri;

  /// Optional AT-URI of a comment to scroll to and highlight once loaded.
  final String? focusCommentUri;

  /// Optional fetcher override for testing.
  ///
  /// When null, a [CovesApiService] wired to [AuthProvider] is used.
  /// Anonymous access is fine - the endpoint is public.
  final PostFetcher? fetchPost;

  @override
  State<PostDetailLoader> createState() => _PostDetailLoaderState();
}

class _PostDetailLoaderState extends State<PostDetailLoader> {
  /// Result of the fetch, null while loading or on error
  PostGetResult? _result;

  /// Error from the last fetch attempt, null while loading or on success
  Object? _error;

  /// [PostDetailLoader.loadedPost]'s post while it is shown in place of a
  /// fetched [_result].
  FeedViewPost? _handedOverPost;

  /// Session key when the request behind [_result] started; admin tools on
  /// the result are offered only while this session stays signed in.
  Object? _loadedUnderSessionKey;

  /// Monotonic id so a stale in-flight fetch can't overwrite a newer one
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _showLoadedPostOrLoad();
  }

  @override
  void didUpdateWidget(PostDetailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The router can reuse this State for a different /post/:postUri -
    // re-validate and refetch. Direct field mutation is safe here: the
    // framework always rebuilds this State after didUpdateWidget returns.
    if (oldWidget.postUri != widget.postUri) {
      _showLoadedPostOrLoad();
    }
  }

  /// Shows [PostDetailLoader.loadedPost] when it is this URI's post, else
  /// starts a load. Same rebuild contract as [_startLoad].
  void _showLoadedPostOrLoad() {
    final loadedPost = widget.loadedPost;
    if (loadedPost == null || loadedPost.post.post.uri != widget.postUri) {
      _startLoad();
      return;
    }
    _requestId++;
    _result = null;
    _error = null;
    _handedOverPost = loadedPost.post;
    _loadedUnderSessionKey = loadedPost.sessionStamp;
  }

  /// The shown post was removed: fetch it again so the server's answer,
  /// such as the tombstone, replaces it.
  void _reloadAfterRemoval() {
    if (mounted) {
      setState(_startLoad);
    }
  }

  /// Resets state, invalidates in-flight fetches, and starts a new load.
  ///
  /// Callers must ensure a rebuild is already scheduled (initState,
  /// didUpdateWidget) or wrap the call in setState (retry).
  void _startLoad() {
    _requestId++;
    _result = null;
    _error = null;
    _handedOverPost = null;

    // Invalid AT-URIs can never resolve - skip the network call entirely
    if (!widget.postUri.startsWith('at://')) {
      _result = PostGetNotFound(widget.postUri);
      return;
    }

    _fetch();
  }

  /// Retry handler: clears the previous error and refetches
  void _retry() {
    setState(_startLoad);
  }

  /// Resolves the fetcher: injected override or the shared API service
  PostFetcher _resolveFetcher() {
    final injected = widget.fetchPost;
    if (injected != null) {
      return injected;
    }

    // context.read doesn't subscribe, so it's safe outside of build
    return context.read<CovesApiService>().getPost;
  }

  Future<void> _fetch() async {
    // Capture the request id and URI: if the widget moves to a new URI
    // while this fetch is in flight, its result must be discarded
    final requestId = _requestId;
    final postUri = widget.postUri;

    try {
      // Stamped when the request starts: an answer landing after the session
      // changed belongs to the previous session.
      final sessionKey = context.read<ViewerAuthorityProvider>().sessionKey;
      final result = await _resolveFetcher()(postUri);
      if (!mounted || requestId != _requestId) {
        return;
      }
      _applyViewerVoteState(result);
      setState(() {
        _result = result;
        _loadedUnderSessionKey = sessionKey;
      });
    } on ApiException catch (e) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      // A 400 means the URI itself is invalid (backend InvalidRequest) -
      // retrying can never succeed, so treat it as not found
      if (e.statusCode == 400) {
        setState(() => _result = PostGetNotFound(postUri));
      } else {
        setState(() => _error = e);
      }
      // Deliberately broad: _fetch is fire-and-forget, so a thrown Error
      // (TypeError, ArgumentError, ...) would otherwise vanish into the
      // async zone and leave the spinner up forever. Every exit must set
      // exactly one of _result/_error.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() => _error = e);
    }
  }

  /// Seeds VoteProvider from a cold-loaded post's viewer state so a
  /// deep-linked post the user already voted on renders a lit heart.
  ///
  /// The response is fresh from getPost, so applying it honors
  /// [VoteProvider.applyServerVoteState]'s fresh-snapshots-only contract.
  ///
  /// Skipped when signed out, and the [VoteProvider] lookup stays behind
  /// that guard so provider-less widget trees (tests, and any screen that
  /// only ever renders anonymously) never look it up. The hydrator gates on
  /// auth too; this outer gate is about the lookup, not the work, so both
  /// stay.
  void _applyViewerVoteState(PostGetResult result) {
    if (result is! PostGetSuccess) {
      return;
    }
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      return;
    }

    ViewerStateHydrator(
      authProvider: authProvider,
      voteProvider: context.read<VoteProvider>(),
    ).hydratePost(result.post);
  }

  /// Navigate away: pop if possible, otherwise fall back to the feed
  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/feed');
    }
  }

  /// Wraps loading/error bodies in a Scaffold so the user can always leave
  Widget _buildScaffold(Widget body) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: BackButton(onPressed: _goBack),
      ),
      body: body,
    );
  }

  /// Content-free tombstone for a removed post: who removed it and, when
  /// known, its community. Never shows the author.
  Widget _buildRemoved(
    String removalCopy,
    CommunityRef? community, {
    bool showModerationLog = false,
    bool showRestore = false,
  }) {
    String? communityLabel;
    if (community != null) {
      communityLabel =
          CommunityHandleUtils.resolveDisplayHandle(
            name: community.name,
            origin: community.origin,
            handle: community.handle,
          )?.toString() ??
          community.name;
    }
    return NotFoundError(
      title: 'Post Removed',
      message: communityLabel == null
          ? removalCopy
          : '$removalCopy\nin $communityLabel',
      onBackPressed: _goBack,
      extraActions: [
        if (showModerationLog)
          (
            label: 'View moderation log',
            onPressed: () => context.push(
              Uri(
                path: '/modlog',
                queryParameters: {'subject': widget.postUri},
              ).toString(),
            ),
          ),
        if (showRestore) (label: 'Restore post', onPressed: _restorePost),
      ],
    );
  }

  /// Opens the restore sheet for the removed post. Any answer the server
  /// gives reloads the post, which then shows whatever the server returns.
  Future<void> _restorePost() async {
    final apiService = context.read<CovesApiService>();
    final authority = context.read<ViewerAuthorityProvider>();
    final sessionKey = authority.sessionKey;
    final messenger = ScaffoldMessenger.of(context);
    final subjectUri = widget.postUri;
    final flow = AdminModerationFlow(apiService, authority: authority);
    // Anything that lands after the session changed belongs to the
    // previous account and is neither shown nor applied.
    bool sessionChanged() => authority.sessionKey != sessionKey;
    void showMessage(String message) {
      if (messenger.mounted && !sessionChanged()) {
        messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }

    void reload() {
      if (mounted && widget.postUri == subjectUri && !sessionChanged()) {
        setState(_startLoad);
      }
    }

    await ModerationActionSheet.show<ModerationFlowResult>(
      context,
      title: 'Restore post',
      confirmLabel: 'Restore',
      reasons: restoreReasons,
      failureMessage: "Couldn't restore this post. Try again.",
      authority: authority,
      onSubmit: (reason, privateNote) async {
        if (flow.retainedSubmission != null) {
          return (await flow.retry())!;
        }
        return flow.submitRestore(
          subjectUri: subjectUri,
          reason: reason,
          privateNote: privateNote,
        );
      },
      onResult: (outcome) async {
        final restoreOutcome = restoreOutcomeOf(outcome);
        if (restoreOutcome != null) {
          reload();
          showMessage(switch (restoreOutcome) {
            RestoreOutcome.restored => 'Post restored',
            RestoreOutcome.restoredButDeleted =>
              'Restored, but the author deleted it, so it stays hidden.',
            RestoreOutcome.restoredButUnavailable =>
              "Restored, but it can't be shown right now.",
            RestoreOutcome.notRemoved => 'This is no longer removed.',
          });
          return const ModerationSheetDecision();
        }
        return moderationFailureDecision(
          outcome,
          authority: authority,
          showMessage: showMessage,
          // A conflicting decision changed the removal: show the post as it
          // is now rather than asking to confirm a restore of a stale view.
          resolveStateConflict: (_) {
            reload();
            showMessage('This item changed. Showing the latest version.');
            return true;
          },
          reloadSubject: (error) async {
            reload();
            showMessage(
              error.code == ModerationErrorCode.contentChanged
                  ? 'The author edited this post. Try restoring again.'
                  : error.message,
            );
          },
        );
      },
    );
  }

  /// User-facing message for a blocked post based on who blocked it
  String _blockedMessage(BlockedBy blockedBy) {
    switch (blockedBy) {
      case BlockedBy.author:
        return 'This post is from an account you\'ve blocked.';
      case BlockedBy.community:
        return 'This post is from a community you\'ve blocked.';
      case BlockedBy.moderator:
        return 'This post was removed by moderators.';
      case BlockedBy.unknown:
        return 'This post is unavailable because it\'s from a blocked '
            'source.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final error = _error;
    final handedOverPost = _handedOverPost;

    if (handedOverPost != null) {
      return PostDetailScreen(
        post: handedOverPost,
        sessionStamp: _loadedUnderSessionKey,
        focusCommentUri: widget.focusCommentUri,
        onPostRemoved: _reloadAfterRemoval,
      );
    }

    if (error != null) {
      return _buildScaffold(
        FullScreenError(
          title: 'Failed to load post',
          message: getErrorMessage(error),
          onRetry: _retry,
        ),
      );
    }

    if (result == null) {
      return _buildScaffold(const FullScreenLoading());
    }

    switch (result) {
      case PostGetSuccess(:final post):
        return PostDetailScreen(
          post: FeedViewPost(post: post),
          sessionStamp: _loadedUnderSessionKey,
          focusCommentUri: widget.focusCommentUri,
          onPostRemoved: _reloadAfterRemoval,
        );
      case PostGetModerated(
        :final moderation,
        :final community,
        :final viewerModeration,
      ):
        return _buildRemoved(
          RemovalCopy.forModeration(moderation),
          community,
          showModerationLog: true,
          showRestore: adminToolAllowed(
            capability: ModerationCapability.restore,
            capabilities: viewerModeration,
            loadedUnderSessionKey: _loadedUnderSessionKey,
            authority: context.watch<ViewerAuthorityProvider>(),
          ),
        );
      case PostGetCommunityRemoved():
        return _buildRemoved(RemovalCopy.removedByCommunityModerator, null);
      case PostGetNotFound():
        return NotFoundError(
          title: 'Post Not Found',
          message:
              'This post could not be loaded. It may have been '
              'deleted or the link is invalid.',
          onBackPressed: _goBack,
        );
      case PostGetBlocked(:final blockedBy):
        return NotFoundError(
          title: 'Post Unavailable',
          message: _blockedMessage(blockedBy),
          onBackPressed: _goBack,
        );
    }
  }
}
