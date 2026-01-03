import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/multi_feed_provider.dart';
import '../../widgets/feed_page.dart';
import '../../widgets/icons/bluesky_icons.dart';

/// Header layout constants
const double _kHeaderHeight = 44;
const double _kTabUnderlineWidth = 28;
const double _kTabUnderlineHeight = 3;

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.onSearchTap});

  /// Callback when search icon is tapped (to switch to communities tab)
  final VoidCallback? onSearchTap;

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> {
  late PageController _pageController;
  final Map<FeedType, ScrollController> _scrollControllers = {};
  late AuthProvider _authProvider;
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();

    // Initialize PageController
    // Start on page 0 (Discover) or 1 (For You) based on current feed
    final provider = context.read<MultiFeedProvider>();
    final initialPage = provider.currentFeedType == FeedType.forYou ? 1 : 0;
    _pageController = PageController(initialPage: initialPage);

    // Save reference to AuthProvider for listener management
    _authProvider = context.read<AuthProvider>();
    _wasAuthenticated = _authProvider.isAuthenticated;

    // Listen to auth changes to sync PageController with provider state
    _authProvider.addListener(_onAuthChanged);

    // Load initial feed after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialFeed();
      }
    });
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Handle auth state changes to sync PageController with provider
  ///
  /// When user signs out while on For You tab, the provider switches to
  /// Discover but PageController stays on page 1. This listener ensures
  /// they stay in sync.
  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;

    // On sign-out: jump to Discover (page 0) to match provider state
    if (_wasAuthenticated && !isAuthenticated) {
      if (_pageController.hasClients && _pageController.page != 0) {
        _pageController.jumpToPage(0);
      }
    }

    _wasAuthenticated = isAuthenticated;
  }

  /// Load initial feed based on authentication
  void _loadInitialFeed() {
    final provider = context.read<MultiFeedProvider>();
    final isAuthenticated = context.read<AuthProvider>().isAuthenticated;

    // Load the current feed
    provider.loadFeed(provider.currentFeedType, refresh: true);

    // Preload the other feed if authenticated
    if (isAuthenticated) {
      final otherFeed =
          provider.currentFeedType == FeedType.discover
              ? FeedType.forYou
              : FeedType.discover;
      provider.loadFeed(otherFeed, refresh: true);
    }
  }

  /// Get or create scroll controller for a feed type
  ScrollController _getOrCreateScrollController(FeedType type) {
    if (!_scrollControllers.containsKey(type)) {
      final provider = context.read<MultiFeedProvider>();
      final state = provider.getState(type);
      _scrollControllers[type] = ScrollController(
        initialScrollOffset: state.scrollPosition,
      );
      _scrollControllers[type]!.addListener(() => _onScroll(type));
    }
    return _scrollControllers[type]!;
  }

  /// Handle scroll events for pagination and scroll position saving
  void _onScroll(FeedType type) {
    final controller = _scrollControllers[type];
    if (controller != null && controller.hasClients) {
      // Save scroll position passively (no rebuild needed)
      context.read<MultiFeedProvider>().saveScrollPosition(
        type,
        controller.position.pixels,
      );

      // Trigger pagination when near bottom
      if (controller.position.pixels >=
          controller.position.maxScrollExtent - 200) {
        context.read<MultiFeedProvider>().loadMore(type);
      }
    }
  }

  /// Scroll the current feed to the top with animation
  void scrollToTop() {
    final currentFeed = context.read<MultiFeedProvider>().currentFeedType;
    final controller = _scrollControllers[currentFeed];
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild when specific fields change
    final isAuthenticated = context.select<AuthProvider, bool>(
      (p) => p.isAuthenticated,
    );
    final currentFeed = context.select<MultiFeedProvider, FeedType>(
      (p) => p.currentFeedType,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Feed content with PageView for swipe navigation
            _buildBody(isAuthenticated: isAuthenticated),
            // Transparent header overlay
            _buildHeader(
              feedType: currentFeed,
              isAuthenticated: isAuthenticated,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required FeedType feedType,
    required bool isAuthenticated,
  }) {
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        // Gradient fade from solid to transparent
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withValues(alpha: 0.8),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Feed type tabs in the center
          Expanded(
            child: _buildFeedTypeTabs(
              feedType: feedType,
              isAuthenticated: isAuthenticated,
            ),
          ),
          // Search/Communities icon on the right
          if (widget.onSearchTap != null)
            Semantics(
              label: 'Navigate to Communities',
              button: true,
              child: InkWell(
                onTap: widget.onSearchTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: AppColors.primary.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: BlueSkyIcon.search(color: AppColors.textPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedTypeTabs({
    required FeedType feedType,
    required bool isAuthenticated,
  }) {
    // If not authenticated, only show Discover
    if (!isAuthenticated) {
      return Center(
        child: _buildFeedTypeTab(
          label: 'Discover',
          isActive: true,
          onTap: null,
        ),
      );
    }

    // Authenticated: show both tabs side by side (TikTok style)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildFeedTypeTab(
          label: 'Discover',
          isActive: feedType == FeedType.discover,
          onTap: () => _switchToFeedType(FeedType.discover, 0),
        ),
        const SizedBox(width: 24),
        _buildFeedTypeTab(
          label: 'For You',
          isActive: feedType == FeedType.forYou,
          onTap: () => _switchToFeedType(FeedType.forYou, 1),
        ),
      ],
    );
  }

  Widget _buildFeedTypeTab({
    required String label,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      label: '$label feed${isActive ? ', selected' : ''}',
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary.withValues(alpha: 0.6),
                fontSize: 16,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            // Underline indicator (TikTok style)
            Container(
              width: _kTabUnderlineWidth,
              height: _kTabUnderlineHeight,
              decoration: BoxDecoration(
                color: isActive ? AppColors.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Switch to a feed type and animate PageView
  void _switchToFeedType(FeedType type, int pageIndex) {
    context.read<MultiFeedProvider>().setCurrentFeed(type);

    // Animate to the corresponding page
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // Load the feed if it hasn't been loaded yet
    _ensureFeedLoaded(type);

    // Restore scroll position after page animation completes
    _restoreScrollPosition(type);
  }

  /// Ensure a feed is loaded (trigger initial load if needed)
  ///
  /// Called when switching to a feed that may not have been loaded yet,
  /// e.g., when user signs in after app start and taps "For You" tab.
  void _ensureFeedLoaded(FeedType type) {
    final provider = context.read<MultiFeedProvider>();
    final state = provider.getState(type);

    // If the feed has no posts and isn't currently loading, trigger a load
    if (state.posts.isEmpty && !state.isLoading) {
      provider.loadFeed(type, refresh: true);
    }
  }

  /// Restore scroll position for a feed type
  void _restoreScrollPosition(FeedType type) {
    // Wait for the next frame to ensure the controller has clients
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final controller = _scrollControllers[type];
      if (controller != null && controller.hasClients) {
        final provider = context.read<MultiFeedProvider>();
        final savedPosition = provider.getState(type).scrollPosition;

        // Only jump if the saved position differs from current
        if ((controller.offset - savedPosition).abs() > 1) {
          controller.jumpTo(savedPosition);
        }
      }
    });
  }

  Widget _buildBody({required bool isAuthenticated}) {
    // For unauthenticated users, show only Discover feed (no PageView)
    if (!isAuthenticated) {
      return _buildFeedPage(FeedType.discover, isAuthenticated);
    }

    // For authenticated users, use PageView for swipe navigation
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        final type = index == 0 ? FeedType.discover : FeedType.forYou;
        context.read<MultiFeedProvider>().setCurrentFeed(type);
        // Load the feed if it hasn't been loaded yet
        _ensureFeedLoaded(type);
        // Restore scroll position when swiping between feeds
        _restoreScrollPosition(type);
      },
      children: [
        _buildFeedPage(FeedType.discover, isAuthenticated),
        _buildFeedPage(FeedType.forYou, isAuthenticated),
      ],
    );
  }

  /// Build a FeedPage widget with all required state from provider
  Widget _buildFeedPage(FeedType feedType, bool isAuthenticated) {
    return Consumer<MultiFeedProvider>(
      builder: (context, provider, _) {
        final state = provider.getState(feedType);

        // Handle error: treat null and empty string as no error
        final error = state.error;
        final hasError = error != null && error.isNotEmpty;

        return FeedPage(
          feedType: feedType,
          posts: state.posts,
          isLoading: state.isLoading,
          isLoadingMore: state.isLoadingMore,
          hasMore: state.hasMore,
          error: hasError ? error : null,
          scrollController: _getOrCreateScrollController(feedType),
          onRefresh: () => provider.loadFeed(feedType, refresh: true),
          onRetry: () => provider.retry(feedType),
          onClearErrorAndLoadMore:
              () =>
                  provider
                    ..clearError(feedType)
                    ..loadMore(feedType),
          isAuthenticated: isAuthenticated,
          currentTime: provider.currentTime,
        );
      },
    );
  }
}
