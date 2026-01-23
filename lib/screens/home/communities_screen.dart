import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'communities_admin_panel.dart';

/// Communities Screen
///
/// Shows different UI based on user role:
/// - Admin (kAdminHandles): Full admin panel for community management
/// - Regular users: Placeholder with coming soon message
class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final handle = authProvider.handle;
    final isAdmin = kAdminHandles.contains(handle);

    if (kDebugMode) {
      debugPrint('CommunitiesScreen: handle=$handle, isAdmin=$isAdmin');
    }

    if (isAdmin) {
      return const CommunitiesAdminPanel();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: const Text('Communities'),
        automaticallyImplyLeading: false,
      ),
      body: const _CommunitiesPlaceholder(),
    );
  }
}

/// Placeholder UI for non-admin users
class _CommunitiesPlaceholder extends StatelessWidget {
  const _CommunitiesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspaces_outlined, size: 64, color: AppColors.primary),
            SizedBox(height: 24),
            Text(
              'Communities',
              style: TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Discover and join communities',
              style: TextStyle(fontSize: 16, color: Color(0xFFB6C2D2)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
