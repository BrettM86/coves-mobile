import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/liked_item.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/block_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../services/comment_change_broadcast.dart';
import '../../services/comment_service.dart';
import '../../services/coves_api_service.dart';
import '../../services/post_change_broadcast.dart';
import '../../services/profile_cache.dart';
import '../../services/viewer_state_hydrator.dart';
import '../../utils/error_messages.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../utils/responsive_utils.dart';
import '../../utils/web_link_builder.dart';
import '../../widgets/comment_card.dart';
import '../../widgets/icons/back_icon.dart';
import '../../widgets/icons/lucide_icon_painter.dart';
import '../../widgets/icons/lucide_paths.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/paginated_sliver_list.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/profile_header.dart';
import '../../widgets/share_button.dart';
import '../compose/reply_screen.dart';
import 'edit_profile_screen.dart';

/// Profile screen displaying user profile with header and posts
///
/// Supports viewing both own profile (via bottom nav) and other users
/// (via /profile/:actor route with DID or handle parameter).
///
/// Each screen owns its own [UserProfileProvider], created here and
/// disposed with the screen, so the own-profile tab and any pushed
/// profile pages never show each other's state. Only the [ProfileCache]
/// is shared between them. The scope is keyed by [actor], so a different
/// actor gets a fresh provider and view state instead of reusing the old.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({this.actor, super.key});

  /// User DID or handle to display. If null, shows current user's profile.
  final String? actor;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UserProfileProvider>(
      key: ValueKey<String?>(actor),
      create: (context) {
        final authority = context.read<ViewerAuthorityProvider>();
        return UserProfileProvider(
          context.read<AuthProvider>(),
          apiService: context.read<CovesApiService>(),
          commentService: context.read<CommentService>(),
          profileCache: context.read<ProfileCache>(),
          postChangeBroadcast: context.read<PostChangeBroadcast>(),
          // Fully wired, subscriptions included: profile posts seed both
          // votes and community subscriptions through hydrateFeed.
          hydrator: context.read<ViewerStateHydrator>(),
          sessionKeyOf: () => authority.sessionKey,
          commentChangeBroadcast: context.read<CommentChangeBroadcast?>(),
        );
      },
      child: _ProfileView(actor: actor),
    );
  }
}

/// The profile view itself; its context sits below the screen's own
/// [UserProfileProvider].
class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.actor});

  final String? actor;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  int _selectedTabIndex = 0;
  bool _commentsLoadedOnce = false;
  bool _likesLoadedOnce = false;

  final ScrollController _scrollController = ScrollController();
  late final PaginationScrollListener _paginationListener;

  // One pending post-frame "does the content fill the viewport?" check.
  bool _viewportFillCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    // Pagination is driven by the scroll position, not by the item builder:
    // triggering a load from build() re-enters the provider mid-frame.
    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: _loadMoreForActiveTab,
    )..attach();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  @override
  void dispose() {
    _paginationListener.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The tab to render and act on. The Likes tab exists only on the own
  /// profile; while it is hidden (a session change, or a profile that is
  /// not the viewer's) a stored Likes selection falls back to Posts.
  int _effectiveTab(UserProfileProvider profileProvider) {
    if (_selectedTabIndex == 2 && !profileProvider.isOwnProfile) {
      return 0;
    }
    return _selectedTabIndex;
  }

  void _loadMoreForActiveTab() {
    if (!mounted) {
      return;
    }
    final profileProvider = context.read<UserProfileProvider>();
    final tab = _effectiveTab(profileProvider);
    if (tab == 0) {
      profileProvider.loadMorePosts();
    } else if (tab == 1) {
      profileProvider.loadMoreComments();
    } else if (tab == 2) {
      profileProvider.loadMoreLikes();
    }
  }

  /// Keep loading while the active tab's content does not fill the
  /// viewport.
  ///
  /// [PaginationScrollListener] only fires on scroll events. The build-phase
  /// trigger this screen used to have covered the short-first-page case by
  /// accident; this covers it on purpose, after layout instead of during
  /// it. Scheduled from build, at most one callback outstanding.
  void _scheduleViewportFillCheck({
    required bool isLoading,
    required bool isLoadingMore,
    required bool hasMore,
    required String? loadMoreError,
  }) {
    if (_viewportFillCheckScheduled ||
        isLoading ||
        isLoadingMore ||
        loadMoreError != null ||
        !hasMore) {
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
    // A Likes selection that fell back to Posts no longer has loaded likes
    // behind it: the next switch to Likes loads them again.
    if (_effectiveTab(context.read<UserProfileProvider>()) !=
        _selectedTabIndex) {
      _likesLoadedOnce = false;
    }
    setState(() {
      _selectedTabIndex = index;
    });

    // Lazy load comments when first switching to Comments tab
    if (index == 1 && !_commentsLoadedOnce) {
      _commentsLoadedOnce = true;
      context.read<UserProfileProvider>().loadComments(refresh: true);
    }

    // Lazy load likes when first switching to the Likes tab
    if (index == 2 && !_likesLoadedOnce) {
      _likesLoadedOnce = true;
      context.read<UserProfileProvider>().loadLikes(refresh: true);
    }
  }

  /// Loads the profile, then seeds block state and loads posts (and
  /// comments or likes, if their tab is selected). Retry reruns this whole
  /// load with [forceRefresh].
  Future<void> _loadProfile({bool forceRefresh = false}) async {
    final authProvider = context.read<AuthProvider>();
    final profileProvider = context.read<UserProfileProvider>();

    // Determine which profile to load
    final actor = widget.actor ?? authProvider.did;

    if (actor == null) {
      // No actor available - set error state instead of silently failing
      profileProvider.setError('Unable to determine profile to load');
      return;
    }

    await profileProvider.loadProfile(actor, forceRefresh: forceRefresh);

    // Check mounted after async gap (CLAUDE.md requirement)
    if (!mounted) {
      return;
    }

    // Only seed block state / load posts if the profile loaded successfully
    // (a profile and no error) — a failed load can leave a stale cached
    // profile whose viewer state must not be seeded, and a load dropped by
    // a session change leaves no profile at all.
    final profile = profileProvider.profile;
    if (profile != null && profileProvider.profileError == null) {
      // Seed block state from the profile's viewer data so block/unblock
      // menus reflect the server-side block after an app restart (the
      // seed never clobbers fresher in-session optimistic state). Only
      // seed when a viewer object is present: an unauthenticated response
      // omits it entirely, and that absence must not be read as "false".
      final viewer = profile.viewer;
      if (viewer != null && profile.did != authProvider.did) {
        context.read<BlockProvider>().setInitialUserBlockState(
          userDid: profile.did,
          isBlocked: viewer.blocked,
        );
      }

      // A full load (including Retry after a session reset cleared both
      // feeds) starts comments and likes over: load them now if their tab
      // is showing, otherwise lazily on the next switch to it.
      final tab = _effectiveTab(profileProvider);
      _commentsLoadedOnce = tab == 1;
      if (_commentsLoadedOnce) {
        unawaited(profileProvider.loadComments(refresh: true));
      }
      _likesLoadedOnce = tab == 2;
      if (_likesLoadedOnce) {
        unawaited(profileProvider.loadLikes(refresh: true));
      }

      await profileProvider.loadPosts(refresh: true);
    }
  }

  void _showMenuSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const LucideGlyph(
                  LucidePaths.settings,
                  color: AppColors.textSecondary,
                ),
                title: const Text(
                  'Settings',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/settings');
                },
              ),
              const Divider(color: AppColors.border, height: 1),
              // View EULA
              ListTile(
                leading: const LucideGlyph(
                  LucidePaths.fileText,
                  color: AppColors.textSecondary,
                ),
                title: const Text(
                  'End User License Agreement',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/eula?viewOnly=true');
                },
              ),
              const Divider(color: AppColors.border, height: 1),
              // View Community Guidelines
              ListTile(
                leading: const LucideGlyph(
                  LucidePaths.users,
                  color: AppColors.textSecondary,
                ),
                title: const Text(
                  'Community Guidelines',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/community-guidelines?viewOnly=true');
                },
              ),
              const Divider(color: AppColors.border, height: 1),
              // Sign out option
              ListTile(
                leading: LucideGlyph(
                  LucidePaths.logOut,
                  color: Colors.red.shade400,
                ),
                title: Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 16),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _handleSignOut();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSignOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();

    // Check mounted after async gap
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (authProvider.isAuthenticated) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text("Couldn't sign out. Please try again."),
          action: SnackBarAction(label: 'Retry', onPressed: _handleSignOut),
        ),
      );
      return;
    }

    context.go('/login');
  }

  void _navigateToEditProfile(BuildContext context, UserProfile profile) {
    // The pushed route sits outside this screen's subtree, so hand it the
    // owning provider explicitly: saving refreshes this screen's header.
    final profileProvider = context.read<UserProfileProvider>();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ChangeNotifierProvider<UserProfileProvider>.value(
          value: profileProvider,
          child: EditProfileScreen(profile: profile),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final profileProvider = context.watch<UserProfileProvider>();
    final activeTab = _effectiveTab(profileProvider);

    // If no actor specified and not authenticated, show sign-in prompt
    if (widget.actor == null && !authProvider.isAuthenticated) {
      return _buildSignInPrompt(context);
    }

    // Show loading state
    if (profileProvider.isLoadingProfile && profileProvider.profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context, null),
        body: const FullScreenLoading(),
      );
    }

    // Show error state
    if (profileProvider.profileError != null &&
        profileProvider.profile == null) {
      // Only show sign out option for own profile (no actor param)
      // This prevents users from being trapped with a misconfigured profile
      final isOwnProfile = widget.actor == null;

      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context, null),
        body: FullScreenError(
          title: 'Failed to load profile',
          message: profileProvider.profileError!,
          onRetry: () => _loadProfile(forceRefresh: true),
          secondaryActionLabel: isOwnProfile ? 'Sign Out' : null,
          onSecondaryAction: isOwnProfile ? _handleSignOut : null,
          secondaryActionDestructive: true,
        ),
      );
    }

    // Header height derived from the toolbar, banner overhang, and text
    // scale so the banner/avatar/DID land identically on all screens.
    // SliverAppBar adds the status-bar inset to this itself.
    final expandedHeight = ProfileHeader.expandedHeightFor(context);

    final profile = profileProvider.profile;

    final tabBar = Container(
      color: AppColors.background,
      child: _ProfileTabBar(
        selectedIndex: activeTab,
        showLikes: profileProvider.isOwnProfile,
        onTabChanged: _onTabChanged,
        likesFilter: profileProvider.likesFilter,
        onLikesFilterChanged: profileProvider.setLikesFilter,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.backgroundSecondary,
        onRefresh: () async {
          final actor = widget.actor ?? authProvider.did;
          if (actor != null) {
            await profileProvider.loadProfile(actor, forceRefresh: true);
            if (!mounted) {
              return;
            }
            // Refresh the active tab content, as of after the profile load.
            final tab = _effectiveTab(profileProvider);
            if (tab == 0) {
              await profileProvider.loadPosts(refresh: true);
            } else if (tab == 1) {
              await profileProvider.loadComments(refresh: true);
            } else if (tab == 2) {
              await profileProvider.loadLikes(refresh: true);
            }
          }
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Collapsing app bar with profile header and frosted glass effect
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.textPrimary,
              expandedHeight: expandedHeight,
              // Not pinned: the top bar scrolls away and the tab bar pins
              // under the status bar instead.
              stretch: true,
              leading: widget.actor != null
                  ? IconButton(
                      icon: const BackIcon(),
                      onPressed: () => context.pop(),
                    )
                  : null,
              automaticallyImplyLeading: widget.actor != null,
              actions: [
                if (profileProvider.isOwnProfile && profile != null)
                  IconButton(
                    icon: const LucideGlyph(LucidePaths.pencil, size: 18),
                    onPressed: () => _navigateToEditProfile(context, profile),
                    tooltip: 'Edit Profile',
                  ),
                // Anyone who can see a profile can share it; editing and the
                // menu act on the viewer's own account.
                if (profile != null)
                  ShareButton(
                    url: WebLinkBuilder.current().profile(
                      did: profile.did,
                      handle: profile.handle,
                    ),
                    useIconButton: true,
                    color: AppColors.textPrimary,
                    tooltip: 'Share Profile',
                  ),
                if (profileProvider.isOwnProfile)
                  IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => _showMenuSheet(context),
                    tooltip: 'Menu',
                  ),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate collapse progress (0 = expanded, 1 = collapsed).
                  // The upper bound is the sliver's real max extent, which
                  // includes the status-bar inset SliverAppBar adds on top
                  // of expandedHeight.
                  final collapsedHeight = ProfileHeader.collapsedExtentFor(
                    context,
                  );
                  final maxExtent = ProfileHeader.maxExtentFor(context);
                  final currentHeight = constraints.maxHeight;
                  final collapseProgress =
                      1 -
                      ((currentHeight - collapsedHeight) /
                              (maxExtent - collapsedHeight))
                          .clamp(0.0, 1.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Profile header background (parallax effect)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProfileHeader(profile: profileProvider.profile),
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
                    ],
                  );
                },
              ),
            ),
            // Bio, stats, and join date as normal scroll content so they
            // are never clipped by the collapsing header
            SliverToBoxAdapter(
              child: ProfileDetails(profile: profileProvider.profile),
            ),
            // Tab bar header, pinned under the status bar. Over the last
            // status-bar-inset pixels before it reaches the top, it grows
            // background-colored space above the strip, so the strip stops
            // at the inset line and its labels never sit under the status
            // bar, without adding a gap at rest.
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final statusBarInset = MediaQuery.paddingOf(context).top;
                final distanceToTop = constraints.scrollOffset > 0
                    ? 0.0
                    : constraints.viewportMainAxisExtent -
                          constraints.remainingPaintExtent;
                return SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabBarDelegate(
                    topSpace: (statusBarInset - distanceToTop).clamp(
                      0.0,
                      statusBarInset,
                    ),
                    child: tabBar,
                  ),
                );
              },
            ),
            // Content based on selected tab
            if (activeTab == 0)
              _buildPostsList(profileProvider)
            else if (activeTab == 1)
              _buildCommentsList(profileProvider)
            else
              _buildLikesList(profileProvider),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, String? title) {
    return AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      title: Text(title ?? 'Profile'),
      leading: widget.actor != null
          ? IconButton(icon: const BackIcon(), onPressed: () => context.pop())
          : null,
      automaticallyImplyLeading: widget.actor != null,
    );
  }

  Widget _buildSignInPrompt(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person, size: 64, color: AppColors.primary),
              const SizedBox(height: 24),
              const Text(
                'Profile',
                style: TextStyle(
                  fontSize: 28,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign in to view your profile',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              PrimaryButton(
                title: 'Sign in',
                onPressed: () => context.go('/login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsList(UserProfileProvider profileProvider) {
    final postsState = profileProvider.postsState;

    // Loading state for posts
    if (postsState.isLoading && postsState.posts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Error state for posts — only while there is nothing to read. With
    // posts on screen the same failure (a pull-to-refresh that failed)
    // goes to the footer below instead of blanking the tab.
    if (postsState.error != null && postsState.posts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: InlineError(
            message: postsState.error!,
            onRetry: () => profileProvider.retryPosts(),
          ),
        ),
      );
    }

    _scheduleViewportFillCheck(
      isLoading: postsState.isLoading,
      isLoadingMore: postsState.isLoadingMore,
      hasMore: postsState.hasMore,
      loadMoreError: postsState.loadMoreError,
    );

    // Posts list. Pagination failures show in the footer via
    // loadMoreError; a failed refresh shows there too, via refreshError.
    return PaginatedSliverList<FeedViewPost>(
      items: postsState.posts,
      isLoadingMore: postsState.isLoadingMore,
      hasMore: postsState.hasMore,
      loadMoreError: postsState.loadMoreError,
      refreshError: postsState.posts.isEmpty ? null : postsState.error,
      onRetryRefresh: () => profileProvider.retryPosts(),
      onRetryLoadMore: profileProvider.retryLoadMorePosts,
      idOf: (feedViewPost) => feedViewPost.post.uri,
      footerKey: const ValueKey<String>('profile_posts_footer'),
      emptyWidget: const Center(
        child: Text(
          'No posts yet',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ),
      itemBuilder: (context, feedViewPost, index) {
        final postCard = PostCard(
          post: feedViewPost,
          sessionStamp: profileProvider.postsSessionStamp,
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

  Widget _buildCommentsList(UserProfileProvider profileProvider) {
    final commentsState = profileProvider.commentsState;

    // Loading state for comments
    if (commentsState.isLoading && commentsState.comments.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Error state for comments
    if (commentsState.error != null && commentsState.comments.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: InlineError(
            message: commentsState.error!,
            onRetry: () => profileProvider.retryComments(),
          ),
        ),
      );
    }

    _scheduleViewportFillCheck(
      isLoading: commentsState.isLoading,
      isLoadingMore: commentsState.isLoadingMore,
      hasMore: commentsState.hasMore,
      loadMoreError: commentsState.loadMoreError,
    );

    // Comments list — same footer/error split as the posts tab.
    return PaginatedSliverList<CommentView>(
      items: commentsState.comments,
      isLoadingMore: commentsState.isLoadingMore,
      hasMore: commentsState.hasMore,
      loadMoreError: commentsState.loadMoreError,
      refreshError: commentsState.comments.isEmpty ? null : commentsState.error,
      onRetryRefresh: () => profileProvider.retryComments(),
      onRetryLoadMore: profileProvider.retryLoadMoreComments,
      idOf: (comment) => comment.uri,
      footerKey: const ValueKey<String>('profile_comments_footer'),
      emptyWidget: const Center(
        child: Text(
          'No comments yet',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ),
      itemBuilder: (context, comment, index) {
        final commentCard = _ProfileCommentCard(comment: comment);

        // Constrain width on tablets for better readability
        if (ResponsiveUtils.isTablet(context)) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ResponsiveUtils.maxContentWidth,
              ),
              child: commentCard,
            ),
          );
        }
        return commentCard;
      },
    );
  }

  static String _likesEmptyText(LikesFilter filter) => switch (filter) {
    LikesFilter.all => 'No likes yet',
    LikesFilter.posts => 'No liked posts yet',
    LikesFilter.comments => 'No liked comments yet',
  };

  Widget _buildLikesList(UserProfileProvider profileProvider) {
    final likesState = profileProvider.likesState;

    if (likesState.isLoading && likesState.items.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (likesState.error != null && likesState.items.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: InlineError(
            message: likesState.error!,
            onRetry: () => profileProvider.retryLikes(),
          ),
        ),
      );
    }

    _scheduleViewportFillCheck(
      isLoading: likesState.isLoading,
      isLoadingMore: likesState.isLoadingMore,
      hasMore: likesState.hasMore,
      loadMoreError: likesState.loadMoreError,
    );

    // With nothing on screen yet (empty pages whose cursor leads on), the
    // next page's failure or progress replaces the empty text: the list
    // footer only shows below loaded rows.
    if (likesState.items.isEmpty) {
      final loadMoreError = likesState.loadMoreError;
      if (loadMoreError != null) {
        return SliverFillRemaining(
          child: Center(
            child: InlineError(
              message: loadMoreError,
              onRetry: profileProvider.retryLoadMoreLikes,
            ),
          ),
        );
      }
      if (likesState.isLoadingMore || likesState.hasMore) {
        return const SliverFillRemaining(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      }
    }

    // Same footer/error split as the posts tab.
    return PaginatedSliverList<LikedItem>(
      items: likesState.items,
      isLoadingMore: likesState.isLoadingMore,
      hasMore: likesState.hasMore,
      loadMoreError: likesState.loadMoreError,
      refreshError: likesState.items.isEmpty ? null : likesState.error,
      onRetryRefresh: () => profileProvider.retryLikes(),
      onRetryLoadMore: profileProvider.retryLoadMoreLikes,
      idOf: (item) => item.uri,
      footerKey: const ValueKey<String>('profile_likes_footer'),
      emptyWidget: Center(
        child: Text(
          _likesEmptyText(profileProvider.likesFilter),
          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ),
      itemBuilder: (context, item, index) {
        final card = switch (item) {
          LikedPost(:final feedViewPost) => PostCard(
            post: feedViewPost,
            sessionStamp: profileProvider.likesSessionStamp,
          ),
          LikedComment(:final comment, :final post) => _ProfileCommentCard(
            comment: comment,
            parentPost: post,
          ),
        };

        // Constrain width on tablets for better readability
        if (ResponsiveUtils.isTablet(context)) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ResponsiveUtils.maxContentWidth,
              ),
              child: card,
            ),
          );
        }
        return card;
      },
    );
  }
}

/// Tab bar for profile content with icons
class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({
    required this.selectedIndex,
    required this.showLikes,
    required this.onTabChanged,
    required this.likesFilter,
    required this.onLikesFilterChanged,
  });

  final int selectedIndex;

  /// Likes are private to their owner, so only the own profile has the tab.
  final bool showLikes;
  final ValueChanged<int> onTabChanged;
  final LikesFilter likesFilter;
  final ValueChanged<LikesFilter> onLikesFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('profile_tab_bar'),
      height: 49, // 48 of content plus the 1px bottom border
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabItem(
              label: 'Posts',
              icon: Icons.grid_view,
              isSelected: selectedIndex == 0,
              onTap: () => onTabChanged(0),
            ),
          ),
          Expanded(
            child: _TabItem(
              label: 'Comments',
              icon: Icons.chat_bubble_outline,
              isSelected: selectedIndex == 1,
              onTap: () => onTabChanged(1),
            ),
          ),
          if (showLikes)
            Expanded(
              child: _TabItem(
                label: 'Likes',
                lucidePaths: LucidePaths.heart,
                isSelected: selectedIndex == 2,
                onTap: () => onTabChanged(2),
                trailing: selectedIndex == 2
                    ? _LikesFilterMenu(
                        selected: likesFilter,
                        onSelected: onLikesFilterChanged,
                      )
                    : null,
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
    this.icon,
    this.lucidePaths,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData? icon;

  /// Lucide glyph drawn instead of [icon], to match the vote heart.
  final List<String>? lucidePaths;
  final bool isSelected;
  final VoidCallback onTap;

  /// Shown right of the label; it handles its own taps.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        // The underline spans the icon and label. A trailing control (the
        // Likes filter) sits beside them in its own full-height hit area.
        // The label shrinks and ellipsizes so large text never overflows
        // the cell, keeping the trailing control at full size.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (lucidePaths case final paths?)
                          LucideGlyph(
                            paths,
                            size: 16,
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          )
                        else
                          Icon(
                            icon,
                            size: 16,
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The Likes tab's All / Posts / Comments menu; the glyph turns the primary
/// color while a filter narrows the list.
///
/// A MenuAnchor rather than a PopupMenuButton: it has no modal barrier and
/// closes when the profile scrolls.
class _LikesFilterMenu extends StatelessWidget {
  const _LikesFilterMenu({required this.selected, required this.onSelected});

  final LikesFilter selected;
  final ValueChanged<LikesFilter> onSelected;

  /// The same icons the profile tabs use, so each filter reads at a glance.
  static Widget _icon(LikesFilter filter) => switch (filter) {
    LikesFilter.all => const LucideGlyph(
      LucidePaths.heart,
      size: 18,
      color: AppColors.textSecondary,
    ),
    LikesFilter.posts => const Icon(
      Icons.grid_view,
      size: 18,
      color: AppColors.textSecondary,
    ),
    LikesFilter.comments => const Icon(
      Icons.chat_bubble_outline,
      size: 18,
      color: AppColors.textSecondary,
    ),
  };

  static String _label(LikesFilter filter) => switch (filter) {
    LikesFilter.all => 'All',
    LikesFilter.posts => 'Posts',
    LikesFilter.comments => 'Comments',
  };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      // The menu's own panel is invisible and the visible card carries a
      // right margin: MenuAnchor otherwise lays the panel flush against the
      // screen edge.
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Material(
            color: AppColors.backgroundSecondary,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final filter in LikesFilter.values)
                    MenuItemButton(
                      onPressed: () => onSelected(filter),
                      leadingIcon: _icon(filter),
                      trailingIcon: filter == selected
                          ? const LucideGlyph(
                              LucidePaths.check,
                              size: 18,
                              color: AppColors.primary,
                            )
                          : null,
                      child: Semantics(
                        selected: filter == selected,
                        child: Text(
                          _label(filter),
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Filter likes',
        child: Semantics(
          button: true,
          // No ink splash: the ripple made the menu feel slow to open.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            // A 48x48 target (accessibility minimum) with the glyph drawn
            // near the label rather than centred in it.
            child: SizedBox(
              width: 48,
              height: 48,
              child: Align(
                alignment: const Alignment(-0.5, -0.2),
                child: LucideGlyph(
                  LucidePaths.listFilter,
                  size: 16,
                  color: selected == LikesFilter.all
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Delegate for the pinned tab bar header: the 49px strip (48 of content
/// plus its 1px bottom border) with [topSpace]
/// of background-colored space above it.
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  _ProfileTabBarDelegate({required this.topSpace, required this.child});

  final double topSpace;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.only(top: topSpace),
        child: child,
      ),
    );
  }

  @override
  double get maxExtent => 49 + topSpace;

  @override
  double get minExtent => 49 + topSpace;

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return topSpace != oldDelegate.topSpace || child != oldDelegate.child;
  }
}

/// A simplified comment card for the profile Comments and Likes lists
///
/// Displays a flat comment without threading since these are shown in
/// a profile context without parent/child relationships visible.
class _ProfileCommentCard extends StatelessWidget {
  const _ProfileCommentCard({required this.comment, this.parentPost});

  final CommentView comment;

  /// The comment's root post, when the list has its view (liked comments);
  /// it gives the card's Share its permalink context.
  final PostView? parentPost;

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.read<UserProfileProvider>();

    return CommentCard(
      comment: comment,
      parentPost: parentPost,
      // A profile list has no thread to trace.
      showThreadLine: false,
      // A profile's comment list offers no admin tools.
      sessionStamp: null,
      onTap: () {
        // Open the parent post's thread, scrolled to and highlighting this
        // comment. The post is cold-loaded by URI (no FeedViewPost here).
        final encodedPost = Uri.encodeComponent(comment.post.uri);
        final encodedComment = Uri.encodeQueryComponent(comment.uri);
        context.push('/post/$encodedPost?comment=$encodedComment');
      },
      onDelete: (commentUri) async {
        await profileProvider.deleteComment(commentUri: commentUri);
      },
      onEdit: (comment) => _openEditComment(context, profileProvider, comment),
    );
  }

  /// Open the edit screen for the viewer's own [comment]; the profile
  /// provider patches its list on save. A failed save shows an error and
  /// rethrows so the composer stays open.
  void _openEditComment(
    BuildContext context,
    UserProfileProvider profileProvider,
    CommentView comment,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplyScreen(
          editing: comment,
          onSubmit: (content, facets, _) async {
            try {
              await profileProvider.updateComment(
                comment: comment,
                content: content,
                facets: facets,
              );
            } on Exception catch (e) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ErrorMessage.updateComment(e)),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
              rethrow;
            }
          },
        ),
      ),
    );
  }
}
