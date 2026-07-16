import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/icons/bluesky_icons.dart';
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

    // Tablet layout: NavigationRail on the left
    if (isTablet) {
      return _wrapWithBackGuard(Scaffold(
        body: Row(
          children: [
            // Wrap NavigationRail in a colored container that extends to
            // status bar, preventing content from bleeding behind it
            Container(
              color: const Color(0xFF0B0F14),
              child: SafeArea(
                right: false,
                bottom: false,
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  backgroundColor: const Color(0xFF0B0F14),
                  indicatorColor: AppColors.primary.withValues(alpha: 0.2),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                NavigationRailDestination(
                  icon: BlueSkyIcon.homeSimple(
                    color: const Color(0xFFB6C2D2).withValues(alpha: 0.6),
                  ),
                  selectedIcon:
                      BlueSkyIcon.homeSimple(color: AppColors.primary),
                  label: const Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(
                    Icons.workspaces_outlined,
                    color: const Color(0xFFB6C2D2).withValues(alpha: 0.6),
                  ),
                  selectedIcon:
                      const Icon(Icons.workspaces, color: AppColors.primary),
                  label: const Text('Communities'),
                ),
                NavigationRailDestination(
                  icon: BlueSkyIcon.plus(
                    color: const Color(0xFFB6C2D2).withValues(alpha: 0.6),
                  ),
                  selectedIcon: BlueSkyIcon.plus(color: AppColors.primary),
                  label: const Text('Create'),
                ),
                NavigationRailDestination(
                  icon: BlueSkyIcon.bellOutline(
                    color: const Color(0xFFB6C2D2).withValues(alpha: 0.6),
                  ),
                  selectedIcon:
                      BlueSkyIcon.bellFilled(color: AppColors.primary),
                  label: const Text('Notifications'),
                ),
                NavigationRailDestination(
                  icon: BlueSkyIcon.personSimple(
                    color: const Color(0xFFB6C2D2).withValues(alpha: 0.6),
                  ),
                  selectedIcon:
                      BlueSkyIcon.personSimple(color: AppColors.primary),
                  label: const Text('Me'),
                ),
              ],
                ),
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFF1A2433),
            ),
            Expanded(child: body),
          ],
        ),
      ));
    }

    // Phone layout: Bottom navigation bar
    return _wrapWithBackGuard(Scaffold(
      body: body,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0F14),
          border: Border(top: BorderSide(color: Color(0xFF0B0F14), width: 0.5)),
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
    ));
  }

  /// Shell-level back handling.
  ///
  /// Only intercepts system back when the Create tab is active AND the
  /// composer has unsaved input — in that case back switches to the Home tab
  /// so the draft stays alive in the IndexedStack instead of the app being
  /// backgrounded mid-compose. Everywhere else back behaves normally
  /// (backgrounds the app / pops the route).
  Widget _wrapWithBackGuard(Widget child) {
    final protectDraft =
        _selectedIndex == _createTabIndex && _composeHasDraft;
    return PopScope(
      canPop: !protectDraft,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _onNavigateToFeed();
        }
      },
      child: child,
    );
  }

  Widget _buildNavItem(int index, String iconName, String label) {
    final isSelected = _selectedIndex == index;
    final color =
        isSelected
            ? AppColors.primary
            : const Color(0xFFB6C2D2).withValues(alpha: 0.6);

    // Use filled variant when selected, outline when not
    Widget icon;
    switch (iconName) {
      case 'home':
        icon = BlueSkyIcon.homeSimple(color: color);
        break;
      case 'communities':
        icon = Icon(
          isSelected ? Icons.workspaces : Icons.workspaces_outlined,
          color: color,
          size: 24,
        );
        break;
      case 'plus':
        icon = BlueSkyIcon.plus(color: color);
        break;
      case 'bell':
        icon =
            isSelected
                ? BlueSkyIcon.bellFilled(color: color)
                : BlueSkyIcon.bellOutline(color: color);
        break;
      case 'person':
        icon = BlueSkyIcon.personSimple(color: color);
        break;
      default:
        icon = BlueSkyIcon.homeOutline(color: color);
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
