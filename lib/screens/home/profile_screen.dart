import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/block_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../utils/responsive_utils.dart';
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
import 'edit_profile_screen.dart';

/// Profile screen displaying user profile with header and posts
///
/// Supports viewing both own profile (via bottom nav) and other users
/// (via /profile/:actor route with DID or handle parameter).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.actor, super.key});

  /// User DID or handle to display. If null, shows current user's profile.
  final String? actor;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedTabIndex = 0;
  bool _commentsLoadedOnce = false;

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

  void _loadMoreForActiveTab() {
    if (!mounted) {
      return;
    }
    final profileProvider = context.read<UserProfileProvider>();
    if (_selectedTabIndex == 0) {
      profileProvider.loadMorePosts();
    } else if (_selectedTabIndex == 1) {
      profileProvider.loadMoreComments();
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

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actor != widget.actor) {
      // Reset comments loaded flag when viewing a different profile
      _commentsLoadedOnce = false;
      _loadProfile();
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
    });

    // Lazy load comments when first switching to Comments tab
    if (index == 1 && !_commentsLoadedOnce) {
      _commentsLoadedOnce = true;
      final profileProvider = context.read<UserProfileProvider>();
      profileProvider.loadComments(refresh: true);
    }
  }

  Future<void> _loadProfile() async {
    final authProvider = context.read<AuthProvider>();
    final profileProvider = context.read<UserProfileProvider>();

    // Determine which profile to load
    final actor = widget.actor ?? authProvider.did;

    if (actor == null) {
      // No actor available - set error state instead of silently failing
      profileProvider.setError('Unable to determine profile to load');
      return;
    }

    await profileProvider.loadProfile(actor);

    // Check mounted after async gap (CLAUDE.md requirement)
    if (!mounted) return;

    // Only seed block state / load posts if the profile loaded successfully
    // (no error) — a failed load can leave a stale cached profile whose
    // viewer state must not be seeded.
    if (profileProvider.profileError == null) {
      // Seed block state from the profile's viewer data so block/unblock
      // menus reflect the server-side block after an app restart (the
      // seed never clobbers fresher in-session optimistic state). Only
      // seed when a viewer object is present: an unauthenticated response
      // omits it entirely, and that absence must not be read as "false".
      final profile = profileProvider.profile;
      final viewer = profile?.viewer;
      if (profile != null &&
          viewer != null &&
          profile.did != authProvider.did) {
        context.read<BlockProvider>().setInitialUserBlockState(
          userDid: profile.did,
          isBlocked: viewer.blocked,
        );
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
              // View EULA
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
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
                leading: const Icon(
                  Icons.groups_outlined,
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
                leading: Icon(Icons.logout, color: Colors.red.shade400),
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
    if (!mounted) return;

    // Navigate to login screen
    context.go('/login');
  }

  void _navigateToEditProfile(BuildContext context, UserProfile profile) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => EditProfileScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final profileProvider = context.watch<UserProfileProvider>();

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
          onRetry: () => profileProvider.retryProfile(),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.backgroundSecondary,
        onRefresh: () async {
          final actor = widget.actor ?? authProvider.did;
          if (actor != null) {
            await profileProvider.loadProfile(actor, forceRefresh: true);
            // Refresh the active tab content
            if (_selectedTabIndex == 0) {
              await profileProvider.loadPosts(refresh: true);
            } else if (_selectedTabIndex == 1) {
              await profileProvider.loadComments(refresh: true);
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
              pinned: true,
              stretch: true,
              leading:
                  widget.actor != null
                      ? IconButton(
                        icon: const BackIcon(),
                        onPressed: () => context.pop(),
                      )
                      : null,
              automaticallyImplyLeading: widget.actor != null,
              actions:
                  profileProvider.isOwnProfile
                      ? [
                        if (profileProvider.profile != null)
                          IconButton(
                            icon: const LucideGlyph(LucidePaths.pencil),
                            onPressed:
                                () => _navigateToEditProfile(
                                  context,
                                  profileProvider.profile!,
                                ),
                            tooltip: 'Edit Profile',
                          ),
                        const ShareButton(
                          useIconButton: true,
                          color: AppColors.textPrimary,
                          tooltip: 'Share Profile',
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => _showMenuSheet(context),
                          tooltip: 'Menu',
                        ),
                      ]
                      : null,
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
            // Tab bar header
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProfileTabBarDelegate(
                child: Container(
                  color: AppColors.background,
                  child: _ProfileTabBar(
                    selectedIndex: _selectedTabIndex,
                    onTabChanged: _onTabChanged,
                  ),
                ),
              ),
            ),
            // Content based on selected tab
            if (_selectedTabIndex == 0)
              _buildPostsList(profileProvider)
            else if (_selectedTabIndex == 1)
              _buildCommentsList(profileProvider)
            else
              _buildComingSoonPlaceholder('Likes'),
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
      leading:
          widget.actor != null
              ? IconButton(
                icon: const BackIcon(),
                onPressed: () => context.pop(),
              )
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
        final postCard = PostCard(post: feedViewPost);

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

  Widget _buildComingSoonPlaceholder(String feature) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              feature == 'Comments'
                  ? Icons.chat_bubble_outline
                  : Icons.favorite_outline,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '$feature coming soon',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab bar for profile content with icons
class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({
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
          Expanded(
            child: _TabItem(
              label: 'Likes',
              icon: Icons.favorite_outline,
              isSelected: selectedIndex == 2,
              onTap: () => onTabChanged(2),
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
                color: isSelected ? AppColors.primary : Colors.transparent,
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
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  _ProfileTabBarDelegate({required this.child});

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
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// A simplified comment card for the profile comments list
///
/// Displays a flat comment without threading since these are shown in
/// a profile context without parent/child relationships visible.
class _ProfileCommentCard extends StatelessWidget {
  const _ProfileCommentCard({required this.comment});

  final CommentView comment;

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.read<UserProfileProvider>();

    return CommentCard(
      comment: comment,
      depth: 0,
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
    );
  }
}
