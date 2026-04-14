import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'communities_admin_panel.dart';
import 'communities_discovery_screen.dart';

/// Communities Screen
///
/// Shows different UI based on user role:
/// - Admin (kAdminHandles): Full admin panel for community management
/// - Regular users: Sectioned discovery layout with search
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
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(
              Icons.workspaces_rounded,
              size: 22,
              color: AppColors.coral,
            ),
            SizedBox(width: 10),
            Text(
              'Communities',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      body: const CommunitiesDiscoveryScreen(),
    );
  }
}
