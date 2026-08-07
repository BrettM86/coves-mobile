import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/community_search_utils.dart';
import '../../utils/cursor_pagination_controller.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../widgets/community_list_tile.dart';
import '../../widgets/paginated_sliver_list.dart';

/// Full paginated list of communities for a given sort/filter.
///
/// Reached via "See all" from the discovery screen sections.
/// Supports pagination, search, and loading/error/empty states.
class CommunitiesSeeAllScreen extends StatefulWidget {
  const CommunitiesSeeAllScreen({
    required this.title,
    required this.sort,
    this.subscribed,
    super.key,
  });

  final String title;
  final String sort;
  final bool? subscribed;

  @override
  State<CommunitiesSeeAllScreen> createState() =>
      _CommunitiesSeeAllScreenState();
}

class _CommunitiesSeeAllScreenState extends State<CommunitiesSeeAllScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Loaded pages, cursor, loading flags and both error channels.
  late final CursorPaginationController<CommunityView> _controller;
  late final PaginationScrollListener _paginationListener;

  /// The loaded communities narrowed by the search box. Search is
  /// client-side over the pages loaded so far — it does not query the API.
  List<CommunityView> _filteredCommunities = [];
  Timer? _searchDebounce;

  // One pending post-frame "does the content fill the viewport?" check.
  bool _viewportFillCheckScheduled = false;
  // Shared app-wide API client (owned by main.dart) — do not dispose here
  late final CovesApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = context.read<CovesApiService>();

    _controller = CursorPaginationController<CommunityView>(
      fetchPage: _fetchCommunitiesPage,
      errorMapper: _errorMessage,
      // Cursor drift hands back overlapping pages; the list keys its rows
      // by this DID and asserts on duplicates.
      idOf: (community) => community.did,
      onUnexpectedError: _reportUnexpected,
    )..addListener(_onCommunitiesChanged);

    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: _controller.loadMore,
    )..attach();

    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paginationListener.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      _filterCommunities,
    );
  }

  void _onCommunitiesChanged() {
    if (!mounted) {
      return;
    }
    _filterCommunities();
    _scheduleViewportFillCheck();
  }

  /// Keep loading while the loaded communities do not fill the viewport.
  ///
  /// [PaginationScrollListener] only fires on scroll events, so a first
  /// page shorter than the screen leaves nothing to scroll and pagination
  /// stalls. Skipped while a search is active: an almost-empty list is then
  /// a filter artifact, not a short page, and chasing it would pull the
  /// whole directory down 50 rows at a time.
  void _scheduleViewportFillCheck() {
    if (_viewportFillCheckScheduled ||
        _controller.isLoading ||
        _controller.isLoadingMore ||
        _controller.loadMoreError != null ||
        !_controller.hasMore ||
        _searchController.text.trim().isNotEmpty) {
      return;
    }

    _viewportFillCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportFillCheckScheduled = false;
      if (mounted) {
        _paginationListener.checkNow();
      }
    });
  }

  void _filterCommunities() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredCommunities = CommunitySearchUtils.filterByQuery(
        _controller.items,
        query,
      );
    });
  }

  Future<CursorPage<CommunityView>> _fetchCommunitiesPage(
    String? cursor,
  ) async {
    final response = await _apiService.listCommunities(
      limit: 50,
      cursor: cursor,
      sort: widget.sort,
      subscribed: widget.subscribed,
    );

    return CursorPage<CommunityView>(
      items: response.communities,
      cursor: response.cursor,
    );
  }

  /// Everything the controller swallows.
  ///
  /// Typed [ApiException]s are skipped — already-typed, user-presentable
  /// failures, reported to the user by the error states below. This is the
  /// single reporting point now: the controller catches fetch failures on
  /// the caller's behalf, so the fetcher no longer captures its own.
  void _reportUnexpected(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      return;
    }
    if (kDebugMode) {
      debugPrint('Failed to load communities: $error');
    }
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }

  String _errorMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return 'Failed to load communities. Pull down to retry.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search communities',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.backgroundTertiary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCommunities() async {
    await _controller.refresh();
  }

  Widget _buildBody() {
    final communities = _controller.items;

    if (_controller.isLoading && communities.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // First-page failure — pagination failures show in the list footer.
    final error = _controller.error;
    if (error != null && communities.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCommunities,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        error,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _controller.refresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCommunities,
      color: AppColors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          PaginatedSliverList<CommunityView>(
            items: _filteredCommunities,
            isLoadingMore: _controller.isLoadingMore,
            hasMore: _controller.hasMore,
            loadMoreError: _controller.loadMoreError,
            // A pull-to-refresh that fails with rows on screen: the
            // full-screen error above is empty-list-only, so without this
            // the failure would be invisible.
            refreshError: communities.isEmpty ? null : error,
            onRetryRefresh: _refreshCommunities,
            onRetryLoadMore: _controller.retryLoadMore,
            idOf: (community) => community.did,
            footerKey: const ValueKey<String>('communities_see_all_footer'),
            emptyWidget: _buildEmptyState(),
            endOfFeedWidget: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Text(
                "That's every community",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
            itemBuilder: (context, community, index) => CommunityListTile(
              community: community,
              onTap: () => context.push('/community/${community.did}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              _searchController.text.trim().isEmpty
                  ? 'No communities found'
                  : 'No communities match your search',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
