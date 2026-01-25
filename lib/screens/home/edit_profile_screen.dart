import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/picked_image.dart';
import '../../models/user_profile.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/api_exceptions.dart';
import '../../utils/image_picker_utils.dart';
import '../../widgets/image_source_picker.dart';

/// Content limits matching backend lexicon
const int kDisplayNameMaxLength = 64;
const int kBioMaxLength = 256;

/// Edit Profile Screen
///
/// Full-screen interface for editing user profile (avatar, banner, display
/// name, and bio).
///
/// Features:
/// - Tappable avatar and banner to change images
/// - Current vs. new image preview when changed
/// - Display name and bio text fields with character limits
/// - Form validation and error handling
/// - Loading states during save
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({required this.profile, super.key});

  /// Current user profile to edit
  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Text controllers
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;

  // Image state
  PickedImage? _selectedAvatar;
  PickedImage? _selectedBanner;

  // Form state
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current profile values
    _displayNameController = TextEditingController(
      text: widget.profile.displayName ?? '',
    );
    _bioController = TextEditingController(
      text: widget.profile.bio ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// Check if any changes have been made
  bool get _hasChanges {
    final displayNameChanged =
        _displayNameController.text != (widget.profile.displayName ?? '');
    final bioChanged = _bioController.text != (widget.profile.bio ?? '');
    return displayNameChanged ||
        bioChanged ||
        _selectedAvatar != null ||
        _selectedBanner != null;
  }

  Future<void> _pickAvatar() async {
    final source = await ImageSourcePicker.show(context);
    if (source == null) return;

    try {
      final picked = await ImagePickerUtils.pickImage(
        source,
        constraints: ImageConstraints.avatar,
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedAvatar = picked;
        });
      }
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pickBanner() async {
    final source = await ImageSourcePicker.show(context);
    if (source == null) return;

    try {
      final picked = await ImagePickerUtils.pickImage(
        source,
        constraints: ImageConstraints.banner,
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedBanner = picked;
        });
      }
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || !_hasChanges) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final profileProvider = context.read<UserProfileProvider>();

      // Determine what to send (only changed fields)
      final displayName = _displayNameController.text.trim();
      final bio = _bioController.text.trim();

      // Only send text fields if they changed
      final sendDisplayName =
          displayName != (widget.profile.displayName ?? '');
      final sendBio = bio != (widget.profile.bio ?? '');

      await profileProvider.updateProfile(
        displayName: sendDisplayName ? displayName : null,
        bio: sendBio ? bio : null,
        avatarBytes: _selectedAvatar?.bytes,
        avatarMimeType: _selectedAvatar?.mimeType,
        bannerBytes: _selectedBanner?.bytes,
        bannerMimeType: _selectedBanner?.mimeType,
      );

      // Check mounted after async gap
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: AppColors.primary,
        ),
      );

      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: (_hasChanges && !_isSaving) ? _saveProfile : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: _hasChanges
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner section
            _buildBannerSection(),
            // Avatar section
            _buildAvatarSection(),
            const SizedBox(height: 24),
            // Text fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTextField(
                    controller: _displayNameController,
                    label: 'Display Name',
                    hint: 'How your name appears',
                    maxLength: kDisplayNameMaxLength,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _bioController,
                    label: 'Bio',
                    hint: 'Tell people about yourself',
                    maxLength: kBioMaxLength,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerSection() {
    return GestureDetector(
      onTap: _pickBanner,
      child: Stack(
        children: [
          // Banner image
          SizedBox(
            height: 150,
            width: double.infinity,
            child: _selectedBanner != null
                ? Image.file(
                    _selectedBanner!.file,
                    fit: BoxFit.cover,
                  )
                : (widget.profile.banner != null &&
                        widget.profile.banner!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: widget.profile.banner!,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (context, url, error) =>
                            _buildDefaultBanner(),
                      )
                    : _buildDefaultBanner(),
          ),
          // Overlay with edit indicator
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 32,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Change Banner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // "New" indicator if banner changed
          if (_selectedBanner != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.6),
            AppColors.primary.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    const avatarSize = 100.0;

    return Transform.translate(
      offset: const Offset(0, -40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  // Avatar container
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.background,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        children: [
                          // Avatar image
                          SizedBox(
                            width: avatarSize - 8,
                            height: avatarSize - 8,
                            child: _selectedAvatar != null
                                ? Image.file(
                                    _selectedAvatar!.file,
                                    fit: BoxFit.cover,
                                  )
                                : (widget.profile.avatar != null)
                                    ? CachedNetworkImage(
                                        imageUrl: widget.profile.avatar!,
                                        fit: BoxFit.cover,
                                        fadeInDuration: Duration.zero,
                                        fadeOutDuration: Duration.zero,
                                        errorWidget: (context, url, error) =>
                                            _buildFallbackAvatar(
                                          avatarSize - 8,
                                        ),
                                      )
                                    : _buildFallbackAvatar(avatarSize - 8),
                          ),
                          // Edit overlay
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.4),
                              child: const Center(
                                child: Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // "New" indicator if avatar changed
                  if (_selectedAvatar != null)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.primary,
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: maxLength,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            counterStyle: const TextStyle(color: AppColors.textSecondary),
          ),
          onChanged: (_) => setState(() {}), // Trigger rebuild for hasChanges
        ),
      ],
    );
  }
}
