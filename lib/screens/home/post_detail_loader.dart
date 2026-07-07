import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/post.dart';
import '../../models/post_get_result.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/error_messages.dart';
import '../../widgets/loading_error_states.dart';
import 'post_detail_screen.dart';

/// Function that fetches a post by AT-URI.
///
/// Injectable for testing; defaults to [CovesApiService.getPost].
typedef PostFetcher = Future<PostGetResult> Function(String uri);

/// Post Detail Loader
///
/// Cold-loads a post by AT-URI and renders [PostDetailScreen] once fetched.
/// Used when the `/post/:postUri` route is entered without a [FeedViewPost]
/// in route extras (e.g., OS state restoration or deep links).
///
/// States:
/// - Loading: full-screen spinner with a back button
/// - Success: renders [PostDetailScreen]
/// - Not found / blocked: user-friendly error with navigation back
/// - Fetch failure: error state with retry
class PostDetailLoader extends StatefulWidget {
  const PostDetailLoader({required this.postUri, this.fetchPost, super.key});

  /// Decoded AT-URI of the post to load (must start with `at://`)
  final String postUri;

  /// Optional fetcher override for testing.
  ///
  /// When null, a [CovesApiService] wired to [AuthProvider] is used.
  /// Anonymous access is fine - the endpoint is public.
  final PostFetcher? fetchPost;

  @override
  State<PostDetailLoader> createState() => _PostDetailLoaderState();
}

class _PostDetailLoaderState extends State<PostDetailLoader> {
  /// API service created for the default fetcher (null when injected)
  CovesApiService? _apiService;

  /// Result of the fetch, null while loading or on error
  PostGetResult? _result;

  /// Error from the last fetch attempt, null while loading or on success
  Object? _error;

  /// Monotonic id so a stale in-flight fetch can't overwrite a newer one
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(PostDetailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The router can reuse this State for a different /post/:postUri -
    // re-validate and refetch. Direct field mutation is safe here: the
    // framework always rebuilds this State after didUpdateWidget returns.
    if (oldWidget.postUri != widget.postUri) {
      _startLoad();
    }
  }

  @override
  void dispose() {
    _apiService?.dispose();
    super.dispose();
  }

  /// Resets state, invalidates in-flight fetches, and starts a new load.
  ///
  /// Callers must ensure a rebuild is already scheduled (initState,
  /// didUpdateWidget) or wrap the call in setState (retry).
  void _startLoad() {
    _requestId++;
    _result = null;
    _error = null;

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

  /// Resolves the fetcher: injected override or a lazily created API service
  PostFetcher _resolveFetcher() {
    final injected = widget.fetchPost;
    if (injected != null) {
      return injected;
    }

    // context.read doesn't subscribe, so it's safe outside of build
    final authProvider = context.read<AuthProvider>();
    _apiService ??= CovesApiService(
      tokenGetter: () async => authProvider.session?.token,
      tokenRefresher: authProvider.refreshToken,
      signOutHandler: authProvider.signOut,
    );
    return _apiService!.getPost;
  }

  Future<void> _fetch() async {
    // Capture the request id and URI: if the widget moves to a new URI
    // while this fetch is in flight, its result must be discarded
    final requestId = _requestId;
    final postUri = widget.postUri;

    try {
      final result = await _resolveFetcher()(postUri);
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() => _result = result);
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
        return PostDetailScreen(post: FeedViewPost(post: post));
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
