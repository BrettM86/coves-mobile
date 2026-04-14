import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/community_search_utils.dart';
import '../../widgets/community_list_tile.dart';

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

  List<CommunityView> _communities = [];
  List<CommunityView> _filteredCommunities = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  Timer? _searchDebounce;
  CovesApiService? _apiService;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApiService();
      _loadCommunities();
    });
  }

  void _initApiService() {
    final authProvider = context.read<AuthProvider>();
    _apiService = CovesApiService(
      tokenGetter: authProvider.getAccessToken,
      tokenRefresher: authProvider.refreshToken,
      signOutHandler: authProvider.signOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _apiService?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      _filterCommunities,
    );
  }

  void _filterCommunities() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredCommunities = CommunitySearchUtils.filterByQuery(
        _communities,
        query,
      );
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _loadMoreCommunities();
      }
    }
  }

  Future<void> _loadCommunities() async {
    if (_isLoading) return;
    if (_apiService == null) {
      setState(() {
        _error = 'Unable to connect. Please try again.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiService!.listCommunities(
        limit: 50,
        sort: widget.sort,
        subscribed: widget.subscribed,
      );

      if (mounted) {
        setState(() {
          _communities = response.communities;
          _filteredCommunities = response.communities;
          _cursor = response.cursor;
          _hasMore = response.cursor != null && response.cursor!.isNotEmpty;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to load communities: $e');
      }
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      if (mounted) {
        setState(() {
          _error = 'Failed to load communities. Pull down to retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreCommunities() async {
    if (_isLoadingMore || !_hasMore || _cursor == null) return;
    if (_apiService == null) {
      setState(() {
        _error = 'Unable to connect. Please try again.';
        _isLoadingMore = false;
      });
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await _apiService!.listCommunities(
        limit: 50,
        cursor: _cursor,
        sort: widget.sort,
        subscribed: widget.subscribed,
      );

      if (mounted) {
        setState(() {
          _communities.addAll(response.communities);
          _cursor = response.cursor;
          _hasMore = response.cursor != null && response.cursor!.isNotEmpty;
          _isLoadingMore = false;
        });
        _filterCommunities();
      }
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to load more communities: $e');
      }
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to load more communities. Try scrolling again.',
            ),
          ),
        );
      }
    }
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
    setState(() {
      _cursor = null;
      _hasMore = true;
      _communities = [];
      _filteredCommunities = [];
    });
    await _loadCommunities();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
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
                        _error!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadCommunities,
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

    if (_filteredCommunities.isEmpty) {
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
                        Icons.search_off,
                        size: 48,
                        color: AppColors.textMuted,
                      ),
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
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCommunities,
      color: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredCommunities.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _filteredCommunities.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          final community = _filteredCommunities[index];
          return CommunityListTile(
            community: community,
            onTap: () => context.push('/community/${community.did}'),
          );
        },
      ),
    );
  }
}
