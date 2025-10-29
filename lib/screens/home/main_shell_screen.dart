import 'package:flutter/material.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'create_post_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

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
          border: Border(
            top: BorderSide(
              color: Color(0xFF0B0F14),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home, 'Home'),
                _buildNavItem(1, Icons.search, 'Search'),
                _buildNavItem(2, Icons.add_box_outlined, 'Create'),
                _buildNavItem(3, Icons.notifications_outlined, 'Notifications'),
                _buildNavItem(4, Icons.person_outline, 'Me'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? const Color(0xFFFF6B35)
        : const Color(0xFFB6C2D2).withValues(alpha: 0.6);

    return Expanded(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Icon(
          icon,
          size: 28,
          color: color,
        ),
      ),
    );
  }
}
