import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../models/picked_image.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/image_picker_utils.dart';
import '../../widgets/image_source_picker.dart';

/// Admin handles that can create communities
const Set<String> kAdminHandles = {
  'coves.social',
  'alex.local.coves.dev', // Local development account
  'mari.local.coves.dev', // Local development account
};

/// Regex for DNS-valid community names (lowercase alphanumeric and hyphens)
final RegExp _dnsNameRegex = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

/// Admin panel pages
enum AdminPage {
  menu,
  createCommunity,
  changeProfilePic,
}

/// Admin Panel for Communities
///
/// Provides admin-only functionality:
/// - Community creation form
/// - Profile picture management
class CommunitiesAdminPanel extends StatefulWidget {
  const CommunitiesAdminPanel({super.key});

  @override
  State<CommunitiesAdminPanel> createState() => _CommunitiesAdminPanelState();
}

class _CommunitiesAdminPanelState extends State<CommunitiesAdminPanel> {
  // Current admin page
  AdminPage _currentPage = AdminPage.menu;

  // Form controllers for create community
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Form controllers for change profile pic
  final TextEditingController _communityHandleController =
      TextEditingController();

  // API service (cached to avoid repeated instantiation)
  CovesApiService? _apiService;

  // Form state
  bool _isSubmitting = false;
  String? _nameError;
  List<CreateCommunityResponse> _createdCommunities = [];

  // Profile pic state
  bool _isLoadingCommunities = false;
  List<CommunityView> _communities = [];
  CommunityView? _selectedCommunity;
  PickedImage? _selectedImage;

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
    _communityHandleController.dispose();
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

  String _getAdminTitle() {
    switch (_currentPage) {
      case AdminPage.menu:
        return 'Admin: Communities';
      case AdminPage.createCommunity:
        return 'Create Community';
      case AdminPage.changeProfilePic:
        return 'Change Profile Pic';
    }
  }

  void _navigateToPage(AdminPage page) {
    setState(() {
      _currentPage = page;
    });
    // Load communities when navigating to profile pic page
    if (page == AdminPage.changeProfilePic) {
      _loadCommunities();
    }
  }

  void _navigateBack() {
    setState(() {
      _currentPage = AdminPage.menu;
      _selectedCommunity = null;
      _selectedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: Text(_getAdminTitle()),
        automaticallyImplyLeading: false,
        leading: _currentPage != AdminPage.menu
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateBack,
              )
            : null,
      ),
      body: _buildAdminUI(),
    );
  }

  Future<void> _loadCommunities() async {
    if (_isLoadingCommunities) return;

    setState(() {
      _isLoadingCommunities = true;
    });

    try {
      final apiService = _getApiService();
      final response = await apiService.listCommunities();

      if (mounted) {
        if (kDebugMode) {
          for (final c in response.communities) {
            debugPrint('Community: ${c.name}, avatar: ${c.avatar}');
          }
        }
        setState(() {
          _communities = response.communities;
          _isLoadingCommunities = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading communities: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingCommunities = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load communities'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildAdminUI() {
    switch (_currentPage) {
      case AdminPage.menu:
        return _buildAdminMenu();
      case AdminPage.createCommunity:
        return _buildCreateCommunityUI();
      case AdminPage.changeProfilePic:
        return _buildChangeProfilePicUI();
    }
  }

  Widget _buildAdminMenu() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Tools',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage communities and settings',
            style: TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
          ),
          const SizedBox(height: 24),
          _buildAdminMenuItem(
            icon: Icons.add_circle_outline,
            title: 'Create Community',
            subtitle: 'Create a new community for Coves users',
            onTap: () => _navigateToPage(AdminPage.createCommunity),
          ),
          const SizedBox(height: 12),
          _buildAdminMenuItem(
            icon: Icons.image_outlined,
            title: 'Change Profile Pic',
            subtitle: 'Update a community\'s profile picture',
            onTap: () => _navigateToPage(AdminPage.changeProfilePic),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFB6C2D2),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFB6C2D2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateCommunityUI() {
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
              onPressed:
                  _isFormValid && !_isSubmitting ? _createCommunity : null,
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
            ..._createdCommunities
                .map((community) => _buildCommunityTile(community)),
          ],
        ],
      ),
    );
  }

  Widget _buildChangeProfilePicUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Change Profile Picture',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a community and upload a new profile picture',
            style: TextStyle(fontSize: 14, color: Color(0xFFB6C2D2)),
          ),
          const SizedBox(height: 24),

          // Community selector
          const Text(
            'Select Community',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),

          if (_isLoadingCommunities)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            )
          else if (_communities.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'No communities found',
                  style: TextStyle(color: Color(0xFFB6C2D2)),
                ),
              ),
            )
          else
            ...(_communities.map((community) => _buildCommunitySelectTile(community))),

          if (_selectedCommunity != null) ...[
            const SizedBox(height: 24),

            // Show current vs new image comparison when image is selected
            if (_selectedImage != null) ...[
              const Text(
                'Preview Changes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Current image
                  Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: AppColors.border, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: _selectedCommunity!.avatar != null
                              ? CachedNetworkImage(
                                  imageUrl: '${_selectedCommunity!.avatar!}',
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  placeholder: (context, url) => Container(
                                    color: AppColors.backgroundSecondary,
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                    Icons.workspaces_outlined,
                                    size: 40,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(
                                  Icons.workspaces_outlined,
                                  size: 40,
                                  color: AppColors.primary,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Current',
                        style: TextStyle(
                          color: Color(0xFFB6C2D2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(
                      Icons.arrow_forward,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  // New image preview
                  Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: AppColors.primary, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: Image.file(
                            _selectedImage!.file,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'New',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _selectedCommunity!.displayName ?? _selectedCommunity!.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Center(
                child: Text(
                  '@${_selectedCommunity!.handle ?? _selectedCommunity!.name}',
                  style: const TextStyle(
                    color: Color(0xFFB6C2D2),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons when image is selected
              Row(
                children: [
                  // Clear button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clearSelectedImage,
                      icon: const Icon(Icons.close),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Upload button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _uploadImage,
                      icon: const Icon(Icons.upload),
                      label: Text(_isSubmitting ? 'Uploading...' : 'Upload'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor: AppColors.backgroundSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Select different image button
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _pickAndUploadImage,
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Select Different Image'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else ...[
              // Show current profile picture when no new image is selected
              const Text(
                'Current Profile Picture',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(60),
                        border: Border.all(color: AppColors.border, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(60),
                        child: _selectedCommunity!.avatar != null
                            ? CachedNetworkImage(
                                imageUrl: '${_selectedCommunity!.avatar!}',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => Container(
                                  color: AppColors.backgroundSecondary,
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                  Icons.workspaces_outlined,
                                  size: 48,
                                  color: AppColors.primary,
                                ),
                              )
                            : const Icon(
                                Icons.workspaces_outlined,
                                size: 48,
                                color: AppColors.primary,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedCommunity!.displayName ?? _selectedCommunity!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '@${_selectedCommunity!.handle ?? _selectedCommunity!.name}',
                      style: const TextStyle(
                        color: Color(0xFFB6C2D2),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Select image button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _pickAndUploadImage,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Select New Picture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: AppColors.backgroundSecondary,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCommunitySelectTile(CommunityView community) {
    final isSelected = _selectedCommunity?.did == community.did;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCommunity = community;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: community.avatar != null
                    ? CachedNetworkImage(
                        imageUrl: '${community.avatar!}',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => Container(
                          color: AppColors.backgroundSecondary,
                        ),
                        errorWidget: (context, url, error) =>
                            const Icon(
                          Icons.workspaces_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.workspaces_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.displayName ?? community.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '@${community.handle ?? community.name}',
                    style: const TextStyle(
                      color: Color(0xFFB6C2D2),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    // Show bottom sheet to choose between gallery and camera
    final source = await ImageSourcePicker.show(context);
    if (source == null) return;

    try {
      final picked = await ImagePickerUtils.pickImage(source);
      if (picked != null && mounted) {
        setState(() {
          _selectedImage = picked;
        });
      }
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Error picking image',
        name: 'CommunitiesAdminPanel',
        error: e,
        stackTrace: stackTrace,
        level: 1000, // Error level
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: ${e.toString()}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null || _selectedCommunity == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Use bytes and mimeType from PickedImage (already read during picking)
      final imageBytes = _selectedImage!.bytes;
      final mimeType = _selectedImage!.mimeType;

      if (kDebugMode) {
        debugPrint(
          'Uploading image: ${imageBytes.length} bytes, $mimeType',
        );
      }

      final apiService = _getApiService();

      await apiService.updateCommunity(
        communityDid: _selectedCommunity!.did,
        imageBytes: imageBytes,
        mimeType: mimeType,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _selectedImage = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Avatar updated for ${_selectedCommunity!.displayName ?? _selectedCommunity!.name}',
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Reload communities list to show updated avatar
        await _loadCommunities();
      }
    } on ApiException catch (e, stackTrace) {
      developer.log(
        'API error uploading avatar',
        name: 'CommunitiesAdminPanel',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload avatar: ${e.message}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        'Unexpected error uploading avatar',
        name: 'CommunitiesAdminPanel',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
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

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
    });
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
