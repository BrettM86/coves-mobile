import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/icons/app_icons.dart';
import 'communities_screen.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;
  final _feedScreenKey = GlobalKey<FeedScreenState>();

  /// Tab index of the Create Post composer in the IndexedStack.
  static const int _createTabIndex = 2;

  /// Whether the composer currently holds unsaved input (reported by
  /// CreatePostScreen). Used to decide if system back must be intercepted.
  bool _composeHasDraft = false;

  void _onComposeDirtyChanged(bool dirty) {
    if (dirty == _composeHasDraft) {
      return;
    }
    setState(() {
      _composeHasDraft = dirty;
    });
  }

  void _onItemTapped(int index) {
    // If already on feed tab, scroll to top
    if (index == 0 && _selectedIndex == 0) {
      _feedScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onCommunitiesTap() {
    setState(() {
      _selectedIndex = 1; // Switch to communities tab
    });
  }

  void _onNavigateToFeed() {
    setState(() {
      _selectedIndex = 0; // Switch to feed tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        FeedScreen(key: _feedScreenKey, onSearchTap: _onCommunitiesTap),
        const CommunitiesScreen(),
        CreatePostScreen(
          onNavigateToFeed: _onNavigateToFeed,
          onDirtyChanged: _onComposeDirtyChanged,
        ),
        const NotificationsScreen(),
        const ProfileScreen(),
      ],
    );
    // Guard the magic constant: _createTabIndex couples this children list,
    // the back-guard in _wrapWithBackGuard, and the "plus" nav item indices.
    assert(
      body.children[_createTabIndex] is CreatePostScreen,
      '_createTabIndex must point at CreatePostScreen in the IndexedStack',
    );

    // Tablet layout: NavigationRail on the left
    if (isTablet) {
      return _wrapWithBackGuard(
        Scaffold(
          body: Row(
            children: [
              // Wrap NavigationRail in a colored container that extends to
              // status bar, preventing content from bleeding behind it
              Container(
                color: AppColors.background,
                child: SafeArea(
                  right: false,
                  bottom: false,
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _onItemTapped,
                    backgroundColor: AppColors.background,
                    indicatorColor: AppColors.primary.withValues(alpha: 0.2),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      NavigationRailDestination(
                        icon: AppIcon.homeSimple(
                          color: AppColors.textSecondary,
                        ),
                        selectedIcon: AppIcon.homeSimple(
                          color: AppColors.primary,
                        ),
                        label: const Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: AppIcon.communities(
                          color: AppColors.textSecondary,
                        ),
                        selectedIcon: AppIcon.communities(
                          color: AppColors.primary,
                        ),
                        label: const Text('Communities'),
                      ),
                      NavigationRailDestination(
                        icon: AppIcon.create(color: AppColors.textSecondary),
                        selectedIcon: AppIcon.create(color: AppColors.primary),
                        label: const Text('Create'),
                      ),
                      NavigationRailDestination(
                        icon: AppIcon.bellOutline(
                          color: AppColors.textSecondary,
                        ),
                        selectedIcon: AppIcon.bellOutline(
                          color: AppColors.primary,
                        ),
                        label: const Text('Notifications'),
                      ),
                      NavigationRailDestination(
                        icon: AppIcon.personSimple(
                          color: AppColors.textSecondary,
                        ),
                        selectedIcon: AppIcon.personSimple(
                          color: AppColors.primary,
                        ),
                        label: const Text('Me'),
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.navDivider,
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    // Phone layout: Bottom navigation bar
    return _wrapWithBackGuard(
      Scaffold(
        body: body,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(
              top: BorderSide(color: AppColors.background, width: 0.5),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, 'home', 'Home'),
                  _buildNavItem(1, 'communities', 'Communities'),
                  _buildNavItem(2, 'plus', 'Create'),
                  _buildNavItem(3, 'bell', 'Notifications'),
                  _buildNavItem(4, 'person', 'Me'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shell-level back handling.
  ///
  /// Only intercepts system back when the Create tab is active AND the
  /// composer has unsaved input — in that case back switches to the Home tab
  /// so the draft stays alive in the IndexedStack instead of the app being
  /// backgrounded mid-compose. Everywhere else back behaves normally
  /// (backgrounds the app / pops the route).
  Widget _wrapWithBackGuard(Widget child) {
    final protectDraft = _selectedIndex == _createTabIndex && _composeHasDraft;
    return PopScope(
      canPop: !protectDraft,
      onPopInvokedWithResult: (didPop, result) {
        // Re-check the draft-protection condition instead of inferring it
        // from !didPop alone: a pop blocked by any other PopScope in the
        // subtree must not yank the user to the Feed tab.
        if (!didPop && _selectedIndex == _createTabIndex && _composeHasDraft) {
          _onNavigateToFeed();
        }
      },
      child: child,
    );
  }

  Widget _buildNavItem(int index, String iconName, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;

    // Use filled variant when selected, outline when not
    Widget icon;
    switch (iconName) {
      case 'home':
        icon = AppIcon.homeSimple(color: color);
        break;
      case 'communities':
        icon = AppIcon.communities(color: color);
        break;
      case 'plus':
        icon = AppIcon.create(color: color);
        break;
      case 'bell':
        icon = AppIcon.bellOutline(color: color);
        break;
      case 'person':
        icon = AppIcon.personSimple(color: color);
        break;
      default:
        icon = AppIcon.homeOutline(color: color);
    }

    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: () => _onItemTapped(index),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: icon,
        ),
      ),
    );
  }
}
