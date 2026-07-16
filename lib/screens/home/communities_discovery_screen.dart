import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_subscription_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/community_search_utils.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/community_chip.dart';
import '../../widgets/community_hero_card.dart';
import '../../widgets/community_list_tile.dart';
import 'communities_see_all_screen.dart';

/// Communities discovery screen with sectioned layout.
///
/// Shows three sections with differentiated visual treatments:
/// - "Your Communities" (authenticated only) — horizontal chip row for quick access
/// - "Popular" — horizontal scrolling hero cards
/// - "Recently Created" — list tiles with join buttons
///
/// Includes a search bar, pull-to-refresh, and "See all" navigation.
class CommunitiesDiscoveryScreen extends StatefulWidget {
  const CommunitiesDiscoveryScreen({super.key});

  @override
  State<CommunitiesDiscoveryScreen> createState() =>
      _CommunitiesDiscoveryScreenState();
}

class _CommunitiesDiscoveryScreenState
    extends State<CommunitiesDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // Section data
  List<CommunityView> _subscribedCommunities = [];
  List<CommunityView> _popularCommunities = [];
  List<CommunityView> _newCommunities = [];

  // Search state
  List<CommunityView> _allCommunities = [];
  List<CommunityView> _searchResults = [];
  String _searchQuery = '';
  bool _hasLoadedFullList = false;
  bool _isLoadingFullList = false;
  bool _isUsingPartialData = false;

  // Loading state per section
  bool _isLoadingSubscribed = false;
  bool _isLoadingPopular = false;
  bool _isLoadingNew = false;

  // Per-section error fields to avoid race conditions between parallel loads
  String? _subscribedError;
  String? _popularError;
  String? _newError;

  bool _hasLoaded = false;
  CovesApiService? _apiService;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApiService();
      _loadAllSections();
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
    _searchDebounce?.cancel();
    _apiService?.dispose();
    super.dispose();
  }

  // --- Data Loading ---

  /// Whether any section has an error.
  bool get _hasAnyError =>
      _subscribedError != null || _popularError != null || _newError != null;

  /// Returns the first non-null section error for display purposes.
  String? get _firstError => _subscribedError ?? _popularError ?? _newError;

  Future<void> _loadAllSections() async {
    if (_hasLoaded && !_hasAnyError) return;

    final authProvider = context.read<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;

    setState(() {
      _subscribedError = null;
      _popularError = null;
      _newError = null;
      _isLoadingPopular = true;
      _isLoadingNew = true;
      if (isAuthenticated) _isLoadingSubscribed = true;
    });

    // Guard against null API service (initialization may have failed)
    if (_apiService == null) {
      setState(() {
        _subscribedError = 'Service not initialized. Pull to retry.';
        _popularError = 'Service not initialized. Pull to retry.';
        _newError = 'Service not initialized. Pull to retry.';
        _isLoadingSubscribed = false;
        _isLoadingPopular = false;
        _isLoadingNew = false;
      });
      return;
    }

    // Fire all requests in parallel
    await Future.wait([
      if (isAuthenticated) _loadSubscribed(),
      _loadPopular(),
      _loadNew(),
    ]);

    _hasLoaded = true;
  }

  Future<void> _refresh() async {
    _hasLoaded = false;
    _hasLoadedFullList = false;
    _isUsingPartialData = false;
    _allCommunities = [];
    await _loadAllSections();
  }

  /// Generic section loader that handles the common pattern of:
  /// fetching communities, updating state on success, and setting error on failure.
  Future<void> _loadSection({
    required int limit,
    String sort = 'popular',
    bool? subscribed,
    required void Function(List<CommunityView> communities) onSuccess,
    required void Function(bool isLoading, String? error) onStateChange,
    required String fallbackError,
  }) async {
    try {
      final response = await _apiService!.listCommunities(
        limit: limit,
        sort: sort,
        subscribed: subscribed,
      );

      if (mounted) {
        onSuccess(response.communities);
        onStateChange(false, null);
      }
    } on ApiException catch (e) {
      if (mounted) {
        onStateChange(false, e.message);
      }
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Section load failed: $e');
      }
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        onStateChange(false, fallbackError);
      }
    }
  }

  Future<void> _loadSubscribed() async {
    // Capture provider before async gap to avoid context.read after await
    final subProvider = context.read<CommunitySubscriptionProvider>();
    await _loadSection(
      limit: 10,
      subscribed: true,
      onSuccess: (communities) {
        for (final c in communities) {
          if (c.viewer != null) {
            subProvider.setInitialSubscriptionState(
              communityDid: c.did,
              isSubscribed: c.viewer!.subscribed ?? false,
            );
          }
        }
        _subscribedCommunities = communities;
      },
      onStateChange: (isLoading, error) {
        setState(() {
          _isLoadingSubscribed = isLoading;
          _subscribedError = error;
        });
      },
      fallbackError: 'Failed to load your communities. Pull to retry.',
    );
  }

  Future<void> _loadPopular() async {
    await _loadSection(
      limit: 8,
      sort: 'popular',
      onSuccess: (communities) {
        _popularCommunities = communities;
      },
      onStateChange: (isLoading, error) {
        setState(() {
          _isLoadingPopular = isLoading;
          _popularError = error;
        });
      },
      fallbackError: 'Failed to load popular communities. Pull to retry.',
    );
  }

  Future<void> _loadNew() async {
    await _loadSection(
      limit: 5,
      sort: 'new',
      onSuccess: (communities) {
        _newCommunities = communities;
      },
      onStateChange: (isLoading, error) {
        setState(() {
          _isLoadingNew = isLoading;
          _newError = error;
        });
      },
      fallbackError: 'Failed to load new communities. Pull to retry.',
    );
  }

  // --- Search ---

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final query = _searchController.text.trim().toLowerCase();

      if (query.isEmpty) {
        setState(() {
          _searchQuery = '';
          _searchResults = [];
        });
        return;
      }

      // Load full list on first search if not already loaded
      if (!_hasLoadedFullList && !_isLoadingFullList) {
        _loadFullCommunityList(query);
        return;
      }

      _applySearchFilter(query);
    });
  }

  Future<void> _loadFullCommunityList(String query) async {
    if (_apiService == null) {
      // Fall back to partial data if API service isn't initialized
      if (kDebugMode) {
        debugPrint(
          'CommunitiesDiscoveryScreen: _apiService is null during search, '
          'falling back to partial data',
        );
      }
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: 'Search fell back to partial data: _apiService was null',
            category: 'communities.search',
            level: SentryLevel.warning,
          ),
        ),
      );
      _allCommunities = _deduplicateCommunities([
        ..._subscribedCommunities,
        ..._popularCommunities,
        ..._newCommunities,
      ]);
      setState(() {
        _isUsingPartialData = _allCommunities.isNotEmpty;
      });
      _applySearchFilter(query);
      return;
    }

    setState(() {
      _isLoadingFullList = true;
      _searchQuery = query;
    });

    try {
      final response = await _apiService!.listCommunities(limit: 100);

      if (mounted) {
        _allCommunities = response.communities;
        _hasLoadedFullList = true;
        _isUsingPartialData = false;
        setState(() {
          _isLoadingFullList = false;
        });
        _applySearchFilter(query);
      }
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to load full community list: $e');
      }
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        // Fall back to filtering from already-loaded section data.
        // Keep _hasLoadedFullList as false so the next search attempt
        // will retry the full fetch rather than being locked to partial data.
        _allCommunities = _deduplicateCommunities([
          ..._subscribedCommunities,
          ..._popularCommunities,
          ..._newCommunities,
        ]);
        setState(() {
          _isLoadingFullList = false;
          _isUsingPartialData = true;
        });
        _applySearchFilter(query);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load all communities. Search results may be incomplete.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _applySearchFilter(String query) {
    setState(() {
      _searchQuery = query;
      _searchResults = CommunitySearchUtils.filterByQuery(
        _allCommunities,
        query,
      );
    });
  }

  List<CommunityView> _deduplicateCommunities(List<CommunityView> list) {
    final seen = <String>{};
    return list.where((c) => seen.add(c.did)).toList();
  }

  // --- Navigation ---

  void _onCommunityTap(CommunityView community) {
    context.push('/community/${community.did}');
  }

  // TODO: migrate to go_router route — currently uses Navigator.push because
  // CommunitiesSeeAllScreen does not have a registered go_router route. This is
  // inconsistent with _onCommunityTap which uses context.push() via go_router,
  // and breaks deep linking and go_router's route state for this path.
  void _onSeeAll({
    required String title,
    required String sort,
    bool? subscribed,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => CommunitiesSeeAllScreen(
              title: title,
              sort: sort,
              subscribed: subscribed,
            ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final isAllLoading = _isLoadingPopular && _isLoadingNew;

    Widget body;
    if (isAllLoading && !_hasLoaded) {
      body = RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildSearchBar(),
            const SizedBox(height: 120),
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ],
        ),
      );
    } else if (_hasAnyError && !_hasLoaded) {
      body = RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [_buildSearchBar(), _buildErrorState()],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: _buildContent(),
      );
    }

    if (ResponsiveUtils.isTablet(context)) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ResponsiveUtils.maxContentWidth,
          ),
          child: body,
        ),
      );
    }

    return body;
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _firstError ?? 'An unexpected error occurred.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Semantics(
              label: 'Try again',
              button: true,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  onTap: _refresh,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildSearchBar(),
        if (_searchQuery.isNotEmpty)
          _buildSearchResults()
        else
          ..._buildSections(),
      ],
    );
  }

  // --- Search Bar ---

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Explore communities...',
          hintStyle: TextStyle(
            color: AppColors.textMuted.withValues(alpha: 0.8),
            fontSize: 15,
          ),
          filled: true,
          fillColor: AppColors.backgroundTertiary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.textMuted.withValues(alpha: 0.8),
            size: 22,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                    tooltip: 'Clear search',
                    icon: Icon(
                      Icons.clear_rounded,
                      color: AppColors.textMuted.withValues(alpha: 0.8),
                      size: 20,
                    ),
                    onPressed: _searchController.clear,
                  )
                  : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  // --- Search Results ---

  Widget _buildSearchResults() {
    if (_isLoadingFullList) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 28,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No communities match "$_searchQuery"',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isUsingPartialData) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _loadFullCommunityList(_searchQuery),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '· tap to load more',
                          style: TextStyle(
                            color: AppColors.teal.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final community = _searchResults[index];
            return CommunityListTile(
              community: community,
              onTap: () => _onCommunityTap(community),
              showJoinButton: true,
            );
          },
        ),
      ],
    );
  }

  // --- Sections ---

  List<Widget> _buildSections() {
    final authProvider = context.watch<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;

    return [
      // Your Communities — horizontal chip row
      if (isAuthenticated) _buildSubscribedSection(),

      // Popular Communities — horizontal hero cards
      _buildPopularSection(),

      // New Communities — list tiles with accents
      _buildNewSection(),

      Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 48),
        child: Center(
          child: Container(
            width: 40,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    ];
  }

  // --- Your Communities (Chip Row) ---

  Widget _buildSubscribedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Your Communities',
          icon: Icons.bookmark_rounded,
          iconColor: AppColors.coral,
          onSeeAll:
              _subscribedCommunities.isNotEmpty
                  ? () => _onSeeAll(
                    title: 'Your Communities',
                    sort: 'popular',
                    subscribed: true,
                  )
                  : null,
        ),
        if (_isLoadingSubscribed)
          _buildSectionLoading()
        else if (_subscribedError != null)
          _buildSectionError(_subscribedError!)
        else if (_subscribedCommunities.isEmpty)
          _buildEmptySubscribed()
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _subscribedCommunities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final community = _subscribedCommunities[index];
                return CommunityChip(
                  community: community,
                  onTap: () => _onCommunityTap(community),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEmptySubscribed() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.group_add_rounded,
                size: 20,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join your first community',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Browse below and tap Join to get started',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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

  // --- Popular Communities (Hero Cards) ---

  Widget _buildPopularSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Popular',
          icon: Icons.local_fire_department_rounded,
          iconColor: AppColors.teal,
          onSeeAll:
              _popularCommunities.isNotEmpty
                  ? () =>
                      _onSeeAll(title: 'Popular Communities', sort: 'popular')
                  : null,
        ),
        if (_isLoadingPopular)
          _buildSectionLoading(verticalPadding: 40)
        else if (_popularError != null)
          _buildSectionError(_popularError!)
        else if (_popularCommunities.isEmpty)
          _buildEmptyGeneric('No communities yet')
        else
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _popularCommunities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final community = _popularCommunities[index];
                return CommunityHeroCard(
                  community: community,
                  onTap: () => _onCommunityTap(community),
                  showJoinButton: true,
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // --- New Communities (List Tiles) ---

  Widget _buildNewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Recently Created',
          icon: Icons.auto_awesome_rounded,
          iconColor: AppColors.coralLight,
          onSeeAll:
              _newCommunities.isNotEmpty
                  ? () => _onSeeAll(title: 'New Communities', sort: 'new')
                  : null,
        ),
        if (_isLoadingNew)
          _buildSectionLoading()
        else if (_newError != null)
          _buildSectionError(_newError!)
        else if (_newCommunities.isEmpty)
          _buildEmptyGeneric('No communities yet')
        else
          for (final community in _newCommunities)
            CommunityListTile(
              community: community,
              onTap: () => _onCommunityTap(community),
              showJoinButton: true,
            ),
      ],
    );
  }

  // --- Shared Components ---

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            Semantics(
              label: 'See all $title',
              button: true,
              // Own semantics boundary so screen readers and UI tests see the
              // button separately from the section title row.
              container: true,
              child: Material(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  onTap: onSeeAll,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: TextStyle(
                            color: AppColors.teal.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.teal.withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLoading({double verticalPadding = 24}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: AppColors.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: 'Retry loading',
              button: true,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  onTap: _refresh,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGeneric(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      ),
    );
  }
}
