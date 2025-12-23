import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';

/// Admin handles that can create communities
const Set<String> kAdminHandles = {
  'coves.social',
  'alex.local.coves.dev', // Local development account
};

/// Regex for DNS-valid community names (lowercase alphanumeric and hyphens)
final RegExp _dnsNameRegex = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

/// Communities Screen
///
/// Shows different UI based on user role:
/// - Admin (coves.social): Community creation form
/// - Regular users: Placeholder with coming soon message
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // API service (cached to avoid repeated instantiation)
  CovesApiService? _apiService;

  // Form state
  bool _isSubmitting = false;
  String? _nameError;
  List<CreateCommunityResponse> _createdCommunities = [];

  // Computed state
  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty;
  }

  // Generate handle preview from name
  String get _handlePreview {
    final name = _nameController.text.trim().toLowerCase();
    if (name.isEmpty) return '@c-{name}.coves.social';
    return '@c-$name.coves.social';
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onTextChanged);
    _displayNameController.addListener(_onTextChanged);
    _descriptionController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    // Remove listeners before disposing controllers
    _nameController.removeListener(_onTextChanged);
    _displayNameController.removeListener(_onTextChanged);
    _descriptionController.removeListener(_onTextChanged);
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _apiService?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Clear name error when user types
    if (_nameError != null) {
      setState(() {
        _nameError = null;
      });
    } else {
      setState(() {});
    }
  }

  /// Validates the community name is DNS-valid
  bool _validateName() {
    final name = _nameController.text.trim().toLowerCase();

    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return false;
    }

    if (name.length > 63) {
      setState(() => _nameError = 'Name must be 63 characters or less');
      return false;
    }

    if (!_dnsNameRegex.hasMatch(name)) {
      setState(() {
        _nameError =
            'Name must be lowercase letters, numbers, and hyphens only';
      });
      return false;
    }

    setState(() => _nameError = null);
    return true;
  }

  /// Gets or creates the cached API service
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

  Future<void> _createCommunity() async {
    if (!_isFormValid || _isSubmitting) return;

    // Validate DNS-valid name before API call
    if (!_validateName()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final apiService = _getApiService();

      final response = await apiService.createCommunity(
        name: _nameController.text.trim().toLowerCase(),
        displayName: _displayNameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _createdCommunities = [..._createdCommunities, response];
          _isSubmitting = false;
        });

        // Clear form
        _nameController.clear();
        _displayNameController.clear();
        _descriptionController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Community created: ${response.handle}'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error creating community: ${e.message}');
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create community: ${e.message}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Unexpected error in _createCommunity: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An unexpected error occurred. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final handle = authProvider.handle;
    final isAdmin = kAdminHandles.contains(handle);

    if (kDebugMode) {
      debugPrint('CommunitiesScreen: handle=$handle, isAdmin=$isAdmin');
      debugPrint('CommunitiesScreen: kAdminHandles=$kAdminHandles');
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: Text(isAdmin ? 'Admin: Communities' : 'Communities'),
        automaticallyImplyLeading: false,
      ),
      body: isAdmin ? _buildAdminUI() : _buildPlaceholderUI(),
    );
  }

  Widget _buildPlaceholderUI() {
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

  Widget _buildAdminUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Create Community',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a new community for Coves users',
            style: TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
          ),
          const SizedBox(height: 24),

          // Name field (DNS-valid slug)
          _buildTextField(
            controller: _nameController,
            label: 'Name (unique identifier)',
            hint: 'worldnews',
            helperText: 'DNS-valid, lowercase, no spaces',
            errorText: _nameError,
          ),
          const SizedBox(height: 16),

          // Handle preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _handlePreview,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Display Name field
          _buildTextField(
            controller: _displayNameController,
            label: 'Display Name',
            hint: 'World News',
            helperText: 'Human-readable name shown in the UI',
          ),
          const SizedBox(height: 16),

          // Description field
          _buildTextField(
            controller: _descriptionController,
            label: 'Description',
            hint: 'Global news and current events from around the world',
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Create button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isFormValid && !_isSubmitting ? _createCommunity : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                disabledBackgroundColor: AppColors.backgroundSecondary,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create Community',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          // Created communities list
          if (_createdCommunities.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Text(
              'Created Communities',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._createdCommunities.map((community) => _buildCommunityTile(community)),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    String? errorText,
    int maxLines = 1,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            helperText: hasError ? null : helperText,
            helperStyle: const TextStyle(color: Color(0xFFB6C2D2)),
            errorText: errorText,
            errorStyle: const TextStyle(color: Colors.red),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityTile(CreateCommunityResponse community) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  community.handle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  community.did,
                  style: const TextStyle(
                    color: Color(0xFFB6C2D2),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
