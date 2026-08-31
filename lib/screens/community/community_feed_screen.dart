import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../constants/app_colors.dart';
import '../../utils/responsive_utils.dart';
import '../../models/community.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_subscription_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../services/viewer_state_hydrator.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/cursor_pagination_controller.dart';
import '../../utils/display_utils.dart';
import '../../utils/error_messages.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../widgets/community_avatar.dart';
import '../../widgets/community_header.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/paginated_sliver_list.dart';
import '../../widgets/post_card.dart';
import '../../widgets/share_button.dart';
import '../../widgets/icons/back_icon.dart';

/// Screen displaying a community's feed with header info
///
/// Features a collapsing header similar to profile screen with:
/// - Banner image with gradient overlay
/// - Community avatar, name, and description
/// - Tabbed content (Feed, About)
/// - Subscribe button in app bar
class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({
    required this.identifier,
    this.community,
    super.key,
  });

  /// Community DID or handle
  final String identifier;

  /// Pre-fetched community data (optional, for faster initial display)
  final CommunityView? community;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  // Shared app-wide API client (owned by main.dart) — do not dispose here
  late final CovesApiService _apiService;
  final ScrollController _scrollController = ScrollController();

  // Tab state
  int _selectedTabIndex = 0;

  // Feed sort state
  String _feedSort = 'hot';

  // Community state
  CommunityView? _community;
  bool _isLoadingCommunity = false;
  String? _communityError;
  bool _communityIsAuthError = false;

  // Feed state — items, cursor, loading flags and both error channels live
  // in the shared controller
  late final CursorPaginationController<FeedViewPost> _feedController;
  late final PaginationScrollListener _paginationListener;

  // Time for relative timestamps
  DateTime _currentTime = DateTime.now();

  // One pending post-frame "does the content fill the viewport?" check.
  bool _viewportFillCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _apiService = context.read<CovesApiService>();
    _community = widget.community;

    _feedController = CursorPaginationController<FeedViewPost>(
      fetchPage: _fetchFeedPage,
      onPageLoaded: _syncViewerStates,
      errorMapper: ErrorMessage.loadFeed,
      // Cursor drift hands back overlapping pages; the list keys its rows
      // by this URI and asserts on duplicates.
      idOf: (post) => post.post.uri,
      onUnexpectedError: _reportUnexpected,
    )..addListener(_onFeedChanged);

    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: _feedController.loadMore,
    )..attach();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeAndLoad();
      }
    });
  }

  @override
  void dispose() {
    _paginationListener.dispose();
    _feedController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The controller owns the feed state; rebuild when it changes.
  void _onFeedChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleViewportFillCheck();
  }

  /// Keep loading while the loaded posts do not fill the viewport.
  ///
  /// [PaginationScrollListener] only fires on scroll events, so a first
  /// page shorter than the screen leaves nothing to scroll and pagination
  /// stalls (the profile screen's old build-phase trigger did not have this
  /// hole). Asked once per landed page, after layout.
  void _scheduleViewportFillCheck() {
    if (_viewportFillCheckScheduled ||
        _feedController.isLoading ||
        _feedController.isLoadingMore ||
        _feedController.loadMoreError != null ||
        !_feedController.hasMore) {
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

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
  }

  void _onFeedSortChanged(String sort) {
    if (_feedSort == sort) return;
    setState(() {
      _feedSort = sort;
    });
    // Whatever is in flight for the previous sort — a first page or an
    // append — is superseded by this refresh and discarded when it lands,
    // so the new label can never sit above the old sort's posts.
    _loadFeed();
  }

  Future<void> _initializeAndLoad() async {
    if (_community == null) {
      await _loadCommunity();
    }
    await _loadFeed();
  }

  Future<void> _loadCommunity() async {
    if (_isLoadingCommunity) return;

    setState(() {
      _isLoadingCommunity = true;
      _communityError = null;
      _communityIsAuthError = false;
    });

    try {
      final community = await _apiService.getCommunity(
        community: widget.identifier,
      );

      if (mounted) {
        setState(() {
          _community = community;
          _isLoadingCommunity = false;
        });

        // Seed subscription state from this community's viewer data.
        //
        // The providers are looked up only once the snapshot is known to
        // say something, so a provider-less tree is never asked for them.
        // The hydrator repeats both checks; it skips a null `subscribed`
        // rather than coercing it to false, unlike the discovery LIST site.
        final authProvider = context.read<AuthProvider>();
        if (authProvider.isAuthenticated &&
            community.viewer?.subscribed != null) {
          ViewerStateHydrator(
            authProvider: authProvider,
            subscriptionProvider: context.read<CommunitySubscriptionProvider>(),
          ).hydrateCommunitySubscription(community);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading community: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = ErrorMessage.community(e);
          _communityIsAuthError = isAuthError(e);
          _isLoadingCommunity = false;
        });
      }
    }
  }

  /// Everything the feed controller swallows.
  ///
  /// Typed [ApiException]s are skipped: they are the expected,
  /// already-on-screen failures. What matters here is the rest — above all
  /// a viewer-state hydration failure, which silently leaves votes and
  /// subscriptions wrong in the UI.
  void _reportUnexpected(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      return;
    }
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }

  /// Reload the feed from the top (also the initial load).
  ///
  /// The controller clears both error channels and supersedes any in-flight
  /// request, so a stale load-more error or a page of the previous sort can
  /// never survive into the new feed.
  Future<void> _loadFeed() async {
    await _feedController.refresh();
    if (mounted) {
      setState(() {
        _currentTime = DateTime.now();
      });
    }
  }

  Future<CursorPage<FeedViewPost>> _fetchFeedPage(String? cursor) async {
    final response = await _apiService.getCommunityFeed(
      community: widget.identifier,
      sort: _feedSort,
      cursor: cursor,
    );

    return CursorPage<FeedViewPost>(
      items: response.feed,
      cursor: response.cursor,
    );
  }

  /// Seeds votes and subscription state for a landed page.
  ///
  /// [posts] is whatever the controller deduplicated down to - a
  /// cursor-drift duplicate never reaches here, unlike MultiFeedProvider,
  /// which hydrates straight off the raw response. The controller also
  /// notifies before calling this and catches whatever it throws, keeping
  /// the page on screen. Both belong to the controller, not the hydrator.
  ///
  /// The providers are read only after the auth gate so provider-less trees
  /// never look them up.
  Future<void> _syncViewerStates(List<FeedViewPost> posts) async {
    if (!mounted) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) return;

    ViewerStateHydrator(
      authProvider: authProvider,
      voteProvider: context.read<VoteProvider>(),
      subscriptionProvider: context.read<CommunitySubscriptionProvider>(),
    ).hydrateFeed(posts);
  }

  Future<void> _onRefresh() async {
    await _loadCommunity();
    await _loadFeed();
  }

  @override
  Widget build(BuildContext context) {
    // Loading community info
    if (_isLoadingCommunity && _community == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildSimpleAppBar(),
        body: const FullScreenLoading(),
      );
    }

    // Error loading community
    if (_communityError != null && _community == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildSimpleAppBar(),
        body: FullScreenError(
          title: 'Community not found',
          message: _communityError!,
          onRetry: _loadCommunity,
          secondaryActionLabel: _communityIsAuthError ? 'Sign In' : null,
          onSecondaryAction:
              _communityIsAuthError ? () => context.push('/login') : null,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.backgroundSecondary,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Collapsing app bar with community header
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.textPrimary,
              expandedHeight: 220,
              pinned: true,
              stretch: true,
              leading: IconButton(
                icon: const BackIcon(),
                onPressed: () => context.pop(),
              ),
              actions: [
                _buildSubscribeButton(),
                const ShareButton(
                  useIconButton: true,
                  color: AppColors.textPrimary,
                  tooltip: 'Share Community',
                ),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  const expandedHeight = 220.0;
                  final collapsedHeight =
                      kToolbarHeight + MediaQuery.of(context).padding.top;
                  final currentHeight = constraints.maxHeight;
                  final collapseProgress =
                      1 -
                      ((currentHeight - collapsedHeight) /
                              (expandedHeight - collapsedHeight))
                          .clamp(0.0, 1.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Community header background
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: CommunityHeader(community: _community),
                      ),
                      // Frosted glass overlay when collapsed
                      if (collapseProgress > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: collapsedHeight,
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: 10 * collapseProgress,
                                sigmaY: 10 * collapseProgress,
                              ),
                              child: Container(
                                color: AppColors.background.withValues(
                                  alpha: 0.7 * collapseProgress,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Community name in collapsed app bar
                      if (collapseProgress > 0.5)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: collapsedHeight,
                          child: SafeArea(
                            bottom: false,
                            child: Opacity(
                              opacity: ((collapseProgress - 0.5) * 2).clamp(
                                0.0,
                                1.0,
                              ),
                              child: Padding(
                                // Left padding: back button (48) + small gap (8)
                                // Right padding: action buttons space
                                padding: const EdgeInsets.only(
                                  left: 56,
                                  right: 100,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CommunityAvatar(
                                        name: _community?.name ?? '',
                                        avatarUrl: _community?.avatar,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '!${_community?.name ?? ''}',
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.communityName,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (_resolveInstance()
                                                case final instance?)
                                              Text(
                                                instance,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w400,
                                                  color: AppColors.textSecondary
                                                      .withValues(alpha: 0.8),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            // Tab bar header (scrolls away)
            SliverPersistentHeader(
              pinned: false,
              delegate: _CommunityTabBarDelegate(
                child: Container(
                  color: AppColors.background,
                  child: _CommunityTabBar(
                    selectedIndex: _selectedTabIndex,
                    onTabChanged: _onTabChanged,
                  ),
                ),
              ),
            ),
            // Feed sort selector - pinned (only shown on Feed tab)
            if (_selectedTabIndex == 0)
              SliverPersistentHeader(
                pinned: true,
                delegate: _FeedSortDelegate(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        _FeedSortChip(
                          label: 'Hot',
                          icon: Icons.local_fire_department,
                          isSelected: _feedSort == 'hot',
                          onTap: () => _onFeedSortChanged('hot'),
                        ),
                        const SizedBox(width: 8),
                        _FeedSortChip(
                          label: 'New',
                          icon: Icons.schedule,
                          isSelected: _feedSort == 'new',
                          onTap: () => _onFeedSortChanged('new'),
                        ),
                        const SizedBox(width: 8),
                        _FeedSortChip(
                          label: 'Top',
                          icon: Icons.trending_up,
                          isSelected: _feedSort == 'top',
                          onTap: () => _onFeedSortChanged('top'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Content based on selected tab
            if (_selectedTabIndex == 0)
              _buildPostsList()
            else
              _buildAboutSection(),
          ],
        ),
      ),
    );
  }

  AppBar _buildSimpleAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      title: const Text('Community'),
      leading: IconButton(
        icon: const BackIcon(),
        onPressed: () => context.pop(),
      ),
    );
  }

  String? _resolveInstance() {
    final community = _community;
    if (community == null) {
      return null;
    }
    return CommunityHandleUtils.resolveDisplayHandle(
      name: community.name,
      origin: community.origin,
      handle: community.handle,
    )?.instance;
  }

  Widget _buildSubscribeButton() {
    final isAuthenticated = context.watch<AuthProvider>().isAuthenticated;
    if (!isAuthenticated || _community == null) {
      return const SizedBox.shrink();
    }

    return Consumer<CommunitySubscriptionProvider>(
      builder: (context, provider, _) {
        final isSubscribed = provider.isSubscribed(_community!.did);
        final isPending = provider.isPending(_community!.did);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child:
              isPending
                  ? Container(
                    key: const ValueKey('loading'),
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  )
                  : Material(
                    key: ValueKey('button_$isSubscribed'),
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () async {
                        try {
                          await provider.toggleSubscription(
                            communityDid: _community!.did,
                          );
                          await _loadCommunity();
                        } on Exception catch (e) {
                          if (kDebugMode) {
                            debugPrint('Error toggling subscription: $e');
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ErrorMessage.subscription(e)),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                isSubscribed
                                    ? AppColors.teal
                                    : AppColors.textSecondary.withValues(
                                      alpha: 0.5,
                                    ),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSubscribed
                                  ? Icons.check
                                  : Icons.add_circle_outline,
                              size: 12,
                              color:
                                  isSubscribed
                                      ? AppColors.teal
                                      : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isSubscribed ? 'Joined' : 'Join',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSubscribed
                                        ? AppColors.teal
                                        : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
        );
      },
    );
  }

  Widget _buildPostsList() {
    final posts = _feedController.items;

    // Loading state
    if (_feedController.isLoading && posts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Full-screen error only while there is nothing to read. With posts on
    // screen the same failure (a pull-to-refresh that failed) goes to the
    // footer instead — blanking readable content would be worse, and
    // showing nothing at all was the old bug.
    final feedError = _feedController.error;
    if (feedError != null && posts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: InlineError(message: feedError, onRetry: _loadFeed),
        ),
      );
    }

    return PaginatedSliverList<FeedViewPost>(
      items: posts,
      isLoadingMore: _feedController.isLoadingMore,
      hasMore: _feedController.hasMore,
      loadMoreError: _feedController.loadMoreError,
      refreshError: posts.isEmpty ? null : feedError,
      onRetryRefresh: _loadFeed,
      onRetryLoadMore: _feedController.retryLoadMore,
      idOf: (post) => post.post.uri,
      footerKey: const ValueKey<String>('community_feed_footer'),
      endOfFeedWidget: _buildEndOfFeed(),
      emptyWidget: _buildEmptyPostsState(),
      itemBuilder: (context, post, index) {
        final postCard = PostCard(
          post: post,
          currentTime: _currentTime,
          showHeader: true,
        );

        // Constrain width on tablets for better readability
        if (ResponsiveUtils.isTablet(context)) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ResponsiveUtils.maxContentWidth,
              ),
              child: postCard,
            ),
          );
        }
        return postCard;
      },
    );
  }

  Widget _buildEmptyPostsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.article_outlined,
                size: 40,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 20,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something in ${_community?.displayName ?? _community?.name ?? 'this community'}!',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndOfFeed() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.teal,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "You're all caught up!",
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    if (_community == null) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description section
            if (_community!.description != null &&
                _community!.description!.isNotEmpty) ...[
              const _SectionHeader(title: 'About'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _community!.description!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            // Stats section
            const _SectionHeader(title: 'Community Stats'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  if (_community!.subscriberCount != null)
                    _AboutStatRow(
                      icon: Icons.notifications_active_outlined,
                      label: 'Subscribers',
                      value: _formatCount(_community!.subscriberCount!),
                    ),
                  if (_community!.memberCount != null) ...[
                    const SizedBox(height: 12),
                    _AboutStatRow(
                      icon: Icons.group_outlined,
                      label: 'Members',
                      value: _formatCount(_community!.memberCount!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Community info
            const _SectionHeader(title: 'Info'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _AboutStatRow(
                    icon:
                        _community!.visibility == 'public'
                            ? Icons.public
                            : Icons.lock_outline,
                    label: 'Visibility',
                    value:
                        _community!.visibility == 'public'
                            ? 'Public'
                            : 'Private',
                  ),
                  const SizedBox(height: 12),
                  _AboutStatRow(
                    icon: Icons.qr_code_2,
                    label: 'DID',
                    value: _community!.did,
                    isMonospace: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) => DisplayUtils.formatCount(count);
}

/// Tab bar for community content
class _CommunityTabBar extends StatelessWidget {
  const _CommunityTabBar({
    required this.selectedIndex,
    required this.onTabChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabItem(
              label: 'Feed',
              icon: Icons.grid_view,
              isSelected: selectedIndex == 0,
              onTap: () => onTabChanged(0),
            ),
          ),
          Expanded(
            child: _TabItem(
              label: 'About',
              icon: Icons.info_outline,
              isSelected: selectedIndex == 1,
              onTap: () => onTabChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color:
                      isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color:
                        isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 3,
              width: 50,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Delegate for pinned tab bar header
class _CommunityTabBarDelegate extends SliverPersistentHeaderDelegate {
  _CommunityTabBarDelegate({required this.child});

  final Widget child;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant _CommunityTabBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// Delegate for pinned feed sort header
class _FeedSortDelegate extends SliverPersistentHeaderDelegate {
  _FeedSortDelegate({required this.child});

  final Widget child;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 56;

  @override
  double get minExtent => 56;

  @override
  bool shouldRebuild(covariant _FeedSortDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// Section header for About tab
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Stat row for About tab
class _AboutStatRow extends StatelessWidget {
  const _AboutStatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isMonospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontFamily: isMonospace ? 'monospace' : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Chip button for feed sort selection
class _FeedSortChip extends StatelessWidget {
  const _FeedSortChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.teal.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.teal : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? AppColors.teal : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.teal : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
