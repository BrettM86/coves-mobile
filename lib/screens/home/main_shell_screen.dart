import 'package:flutter/material.dart';

import '../../widgets/icons/bluesky_icons.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    FeedScreen(),
    SearchScreen(),
    CreatePostScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
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
                _buildNavItem(1, 'search', 'Search'),
                _buildNavItem(2, 'plus', 'Create'),
                _buildNavItem(3, 'bell', 'Notifications'),
                _buildNavItem(4, 'person', 'Me'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String iconName, String label) {
    final isSelected = _selectedIndex == index;
    final color =
        isSelected
            ? const Color(0xFFFF6B35)
            : const Color(0xFFB6C2D2).withValues(alpha: 0.6);

    // Use filled variant when selected, outline when not
    Widget icon;
    switch (iconName) {
      case 'home':
        icon = BlueSkyIcon.homeSimple(color: color);
        break;
      case 'search':
        icon = BlueSkyIcon.search(color: color);
        break;
      case 'plus':
        icon = BlueSkyIcon.plus(color: color);
        break;
      case 'bell':
        icon = isSelected
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
      child: InkWell(
        onTap: () => _onItemTapped(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: icon,
      ),
    );
  }
}
