import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_subscription_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/display_utils.dart';
import '../../utils/error_messages.dart';
import '../../widgets/community_header.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_card.dart';

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
  CovesApiService? _apiService;
  final ScrollController _scrollController = ScrollController();

  // Tab state
  int _selectedTabIndex = 0;

  // Feed sort state
  String _feedSort = 'hot';

  // Community state
  CommunityView? _community;
  bool _isLoadingCommunity = false;
  String? _communityError;

  // Feed state
  List<FeedViewPost> _posts = [];
  bool _isLoadingFeed = false;
  bool _isLoadingMore = false;
  String? _feedError;
  String? _loadMoreError;
  String? _cursor;
  bool _hasMore = true;

  // Time for relative timestamps
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _community = widget.community;
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeAndLoad();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _apiService?.dispose();
    super.dispose();
  }

  CovesApiService _getApiService() {
    if (_apiService == null) {
      final authProvider = context.read<AuthProvider>();
      _apiService = CovesApiService(
        tokenGetter: authProvider.getAccessToken,
        tokenRefresher: authProvider.refreshToken,
        signOutHandler: authProvider.signOut,
      );
    }
    return _apiService!;
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
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
    _loadFeed(refresh: true);
  }

  Future<void> _initializeAndLoad() async {
    if (_community == null) {
      await _loadCommunity();
    }
    await _loadFeed(refresh: true);
  }

  Future<void> _loadCommunity() async {
    if (_isLoadingCommunity) return;

    setState(() {
      _isLoadingCommunity = true;
      _communityError = null;
    });

    try {
      final apiService = _getApiService();
      final community = await apiService.getCommunity(
        community: widget.identifier,
      );

      if (mounted) {
        setState(() {
          _community = community;
          _isLoadingCommunity = false;
        });

        // Initialize subscription state from community viewer data
        final authProvider = context.read<AuthProvider>();
        if (authProvider.isAuthenticated &&
            community.viewer?.subscribed != null) {
          final subscriptionProvider =
              context.read<CommunitySubscriptionProvider>();
          subscriptionProvider.setInitialSubscriptionState(
            communityDid: community.did,
            isSubscribed: community.viewer!.subscribed!,
          );
        }
      }
    } on NetworkException catch (e) {
      if (kDebugMode) {
        debugPrint('Network error loading community: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = 'Please check your internet connection';
          _isLoadingCommunity = false;
        });
      }
    } on NotFoundException catch (e) {
      if (kDebugMode) {
        debugPrint('Community not found: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = 'Community not found';
          _isLoadingCommunity = false;
        });
      }
    } on ServerException catch (e) {
      if (kDebugMode) {
        debugPrint('Server error loading community: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = 'Server error. Please try again later';
          _isLoadingCommunity = false;
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error loading community: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = e.message;
          _isLoadingCommunity = false;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading community: $e');
      }
      if (mounted) {
        setState(() {
          _communityError = ErrorMessages.getUserFriendly(e.toString());
          _isLoadingCommunity = false;
        });
      }
    }
  }

  Future<void> _loadFeed({bool refresh = false}) async {
    if (_isLoadingFeed) return;

    setState(() {
      _isLoadingFeed = true;
      if (refresh) {
        _feedError = null;
        _cursor = null;
        _hasMore = true;
      }
    });

    try {
      final apiService = _getApiService();
      final response = await apiService.getCommunityFeed(
        community: widget.identifier,
        sort: _feedSort,
        cursor: refresh ? null : _cursor,
      );

      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
          if (refresh) {
            _posts = response.feed;
          } else {
            _posts = [..._posts, ...response.feed];
          }
          _cursor = response.cursor;
          _hasMore = response.cursor != null;
          _isLoadingFeed = false;
        });

        _syncViewerStates(response.feed);
      }
    } on NetworkException catch (e) {
      if (kDebugMode) {
        debugPrint('Network error loading feed: $e');
      }
      if (mounted) {
        setState(() {
          _feedError = 'Please check your internet connection';
          _isLoadingFeed = false;
        });
      }
    } on ServerException catch (e) {
      if (kDebugMode) {
        debugPrint('Server error loading feed: $e');
      }
      if (mounted) {
        setState(() {
          _feedError = 'Server error. Please try again later';
          _isLoadingFeed = false;
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error loading feed: $e');
      }
      if (mounted) {
        setState(() {
          _feedError = e.message;
          _isLoadingFeed = false;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading community feed: $e');
      }
      if (mounted) {
        setState(() {
          _feedError = ErrorMessages.getUserFriendly(e.toString());
          _isLoadingFeed = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoadingFeed) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final apiService = _getApiService();
      final response = await apiService.getCommunityFeed(
        community: widget.identifier,
        sort: _feedSort,
        cursor: _cursor,
      );

      if (mounted) {
        setState(() {
          _posts = [..._posts, ...response.feed];
          _cursor = response.cursor;
          _hasMore = response.cursor != null;
          _isLoadingMore = false;
        });

        _syncViewerStates(response.feed);
      }
    } on NetworkException catch (e) {
      if (kDebugMode) {
        debugPrint('Network error loading more posts: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = 'Please check your internet connection';
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error loading more posts: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = e.message;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading more posts: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = ErrorMessages.getUserFriendly(e.toString());
        });
      }
    }
  }

  void _clearLoadMoreError() {
    setState(() {
      _loadMoreError = null;
    });
  }

  void _syncViewerStates(List<FeedViewPost> posts) {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) return;

    final voteProvider = context.read<VoteProvider>();
    final subscriptionProvider = context.read<CommunitySubscriptionProvider>();

    for (final post in posts) {
      final viewer = post.post.viewer;
      voteProvider.setInitialVoteState(
        postUri: post.post.uri,
        voteDirection: viewer?.vote,
        voteUri: viewer?.voteUri,
      );

      final communityViewer = post.post.community.viewer;
      if (communityViewer?.subscribed != null) {
        subscriptionProvider.setInitialSubscriptionState(
          communityDid: post.post.community.did,
          isSubscribed: communityViewer!.subscribed!,
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadCommunity();
    await _loadFeed(refresh: true);
  }

  Future<void> _handleShare() async {
    if (_community == null) return;

    final handle = _community!.handle;
    final communityUrl = 'https://coves.social/community/$handle';
    final subject =
        'Check out ${_community!.displayName ?? _community!.name} on Coves';

    try {
      await Share.share(communityUrl, subject: subject);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error sharing community: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share. Please try again.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
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
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                _buildSubscribeButton(),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _handleShare,
                  tooltip: 'Share Community',
                ),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  const expandedHeight = 220.0;
                  final collapsedHeight =
                      kToolbarHeight + MediaQuery.of(context).padding.top;
                  final currentHeight = constraints.maxHeight;
                  final collapseProgress = 1 -
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
                                color: AppColors.background
                                    .withValues(alpha: 0.7 * collapseProgress),
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
                              opacity:
                                  ((collapseProgress - 0.5) * 2).clamp(0.0, 1.0),
                              child: Padding(
                                // Left padding: back button (48) + small gap (8)
                                // Right padding: action buttons space
                                padding:
                                    const EdgeInsets.only(left: 56, right: 100),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_community?.avatar != null &&
                                          _community!.avatar!.isNotEmpty)
                                        ClipOval(
                                          child: CachedNetworkImage(
                                            imageUrl: _community!.avatar!,
                                            width: 28,
                                            height: 28,
                                            fit: BoxFit.cover,
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            errorWidget: (context, url, error) {
                                              if (kDebugMode) {
                                                debugPrint(
                                                  'Error loading collapsed avatar: $error',
                                                );
                                              }
                                              return _buildCollapsedFallbackAvatar();
                                            },
                                          ),
                                        )
                                      else
                                        _buildCollapsedFallbackAvatar(),
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
                                            Text(
                                              _getInstanceFromHandle(),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      border: Border(bottom: BorderSide(color: AppColors.border)),
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
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
    );
  }

  String _getInstanceFromHandle() {
    final handle = _community?.handle;
    if (handle == null || !handle.contains('.')) {
      return 'coves.social';
    }
    final parts = handle.split('.');
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('.');
    }
    return 'coves.social';
  }

  Widget _buildCollapsedFallbackAvatar() {
    final name = _community?.name ?? '';
    final bgColor = DisplayUtils.getFallbackColor(name);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'C',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
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
          child: isPending
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
                        final wasSubscribed = isSubscribed;
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
                            final action = wasSubscribed ? 'leave' : 'join';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to $action community. Please try again.',
                                ),
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
                            color: isSubscribed
                                ? AppColors.teal
                                : AppColors.textSecondary.withValues(alpha: 0.5),
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
                              color: isSubscribed
                                  ? AppColors.teal
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isSubscribed ? 'Joined' : 'Join',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSubscribed
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
    // Loading state
    if (_isLoadingFeed && _posts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Error state
    if (_feedError != null && _posts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: InlineError(
            message: _feedError!,
            onRetry: () => _loadFeed(refresh: true),
          ),
        ),
      );
    }

    // Empty state
    if (_posts.isEmpty && !_isLoadingFeed) {
      return SliverFillRemaining(
        child: _buildEmptyPostsState(),
      );
    }

    // Posts list with loading indicator
    final showLoadingSlot = _isLoadingMore || _loadMoreError != null;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == _posts.length) {
            if (_isLoadingMore) {
              return const InlineLoading();
            }
            if (_loadMoreError != null) {
              return InlineError(
                message: _loadMoreError!,
                onRetry: () {
                  _clearLoadMoreError();
                  _loadMore();
                },
              );
            }
            if (!_hasMore && _posts.isNotEmpty) {
              return _buildEndOfFeed();
            }
            return const SizedBox(height: 80);
          }

          final post = _posts[index];
          return RepaintBoundary(
            key: ValueKey(post.post.uri),
            child: PostCard(
              post: post,
              currentTime: _currentTime,
              showHeader: true,
            ),
          );
        },
        childCount: _posts.length + (showLoadingSlot || !_hasMore ? 1 : 0),
      ),
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
                    icon: _community!.visibility == 'public'
                        ? Icons.public
                        : Icons.lock_outline,
                    label: 'Visibility',
                    value: _community!.visibility == 'public'
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
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
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
        Icon(
          icon,
          size: 18,
          color: AppColors.teal,
        ),
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
          color: isSelected
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

