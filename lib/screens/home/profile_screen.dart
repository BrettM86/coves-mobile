import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../widgets/comment_card.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/profile_header.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
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

    // Only load posts if profile loaded successfully (no error)
    if (profileProvider.profileError == null) {
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
              // Sign out option
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Colors.red.shade400,
                ),
                title: Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontSize: 16,
                  ),
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

  void _handleShare() {
    final profile = context.read<UserProfileProvider>().profile;
    if (profile == null) return;

    final handle = profile.handle;
    final profileUrl = 'https://coves.social/profile/$handle';
    final subject = 'Check out ${profile.displayNameOrHandle} on Coves';
    Share.share(profileUrl, subject: subject);
  }

  Future<void> _handleSignOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();

    // Check mounted after async gap
    if (!mounted) return;

    // Navigate to login screen
    context.go('/login');
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
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context, null),
        body: FullScreenError(
          title: 'Failed to load profile',
          message: profileProvider.profileError!,
          onRetry: () => profileProvider.retryProfile(),
        ),
      );
    }

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
          slivers: [
            // Collapsing app bar with profile header and frosted glass effect
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.textPrimary,
              expandedHeight: 220,
              pinned: true,
              stretch: true,
              leading:
                  widget.actor != null
                      ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => context.pop(),
                      )
                      : null,
              automaticallyImplyLeading: widget.actor != null,
              actions: profileProvider.isOwnProfile
                  ? [
                      IconButton(
                        icon: const Icon(Icons.share_outlined),
                        onPressed: _handleShare,
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
                  // Calculate collapse progress (0 = expanded, 1 = collapsed)
                  const expandedHeight = 220.0;
                  final collapsedHeight = kToolbarHeight +
                      MediaQuery.of(context).padding.top;
                  final currentHeight = constraints.maxHeight;
                  final collapseProgress = 1 -
                      ((currentHeight - collapsedHeight) /
                              (expandedHeight - collapsedHeight))
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
                        child: ProfileHeader(
                          profile: profileProvider.profile,
                          isOwnProfile: profileProvider.isOwnProfile,
                        ),
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
                    ],
                  );
                },
              ),
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
                icon: const Icon(Icons.arrow_back),
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

    // Error state for posts
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

    // Empty state
    if (postsState.posts.isEmpty && !postsState.isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            'No posts yet',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // Posts list
    // Only add extra slot for loading/error indicators, not just hasMore
    final showLoadingSlot =
        postsState.isLoadingMore || postsState.error != null;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        // Load more when reaching end
        if (index == postsState.posts.length - 3 && postsState.hasMore) {
          profileProvider.loadMorePosts();
        }

        // Show loading indicator or error at the end
        if (index == postsState.posts.length) {
          if (postsState.isLoadingMore) {
            return const InlineLoading();
          }
          if (postsState.error != null) {
            return InlineError(
              message: postsState.error!,
              onRetry: () => profileProvider.loadMorePosts(),
            );
          }
          // Shouldn't reach here due to showLoadingSlot check
          return const SizedBox.shrink();
        }

        final feedViewPost = postsState.posts[index];
        return PostCard(post: feedViewPost);
      }, childCount: postsState.posts.length + (showLoadingSlot ? 1 : 0)),
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

    // Empty state
    if (commentsState.comments.isEmpty && !commentsState.isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            'No comments yet',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // Comments list
    final showLoadingSlot =
        commentsState.isLoadingMore || commentsState.error != null;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        // Load more when reaching end
        if (index == commentsState.comments.length - 3 &&
            commentsState.hasMore) {
          profileProvider.loadMoreComments();
        }

        // Show loading indicator or error at the end
        if (index == commentsState.comments.length) {
          if (commentsState.isLoadingMore) {
            return const InlineLoading();
          }
          if (commentsState.error != null) {
            return InlineError(
              message: commentsState.error!,
              onRetry: () => profileProvider.loadMoreComments(),
            );
          }
          return const SizedBox.shrink();
        }

        final comment = commentsState.comments[index];
        return _ProfileCommentCard(comment: comment);
      }, childCount: commentsState.comments.length + (showLoadingSlot ? 1 : 0)),
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
                  color: isSelected
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
    return CommentCard(
      comment: comment,
      depth: 0,
    );
  }
}
