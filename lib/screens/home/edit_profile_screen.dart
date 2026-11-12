import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/bluesky_profile_import.dart';
import '../../models/picked_image.dart';
import '../../models/user_profile.dart';
import '../../providers/user_profile_provider.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../services/own_profile_refresher.dart';
import '../../services/profile_cache.dart';
import '../../utils/error_messages.dart';
import '../../utils/image_crop_utils.dart';
import '../../utils/image_picker_utils.dart';
import '../../widgets/bluesky_profile_import_dialog.dart';
import '../../widgets/image_source_picker.dart';
import '../../widgets/user_avatar.dart';

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
  bool _isFetchingBlueskyImport = false;

  /// True from the import check fetch until its dialog closes; Save and
  /// the import workflow exclude each other.
  bool _isImportingFromBluesky = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current profile values
    _displayNameController = TextEditingController(
      text: widget.profile.displayName ?? '',
    );
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
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
    if (source == null) {
      return;
    }

    try {
      final picked = await ImageCropUtils.pickAndCropImage(source: source);
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
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pickBanner() async {
    final source = await ImageSourcePicker.show(context);
    if (source == null) {
      return;
    }

    try {
      final picked = await ImageCropUtils.pickAndCropImage(
        source: source,
        constraints: ImageConstraints.banner,
        cropConfig: CropConfig.banner,
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
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _isImportingFromBluesky || !_hasChanges) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final profileProvider = context.read<UserProfileProvider>();

      // Determine what to send (only changed fields)
      final displayName = _displayNameController.text.trim();
      final bio = _bioController.text.trim();

      // Only send text fields if they changed
      final sendDisplayName = displayName != (widget.profile.displayName ?? '');
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
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: AppColors.primary,
        ),
      );

      Navigator.pop(context);
    } on Object catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessage.updateProfile(e)),
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

  Future<void> _importFromBluesky() async {
    if (_isSaving || _isImportingFromBluesky) {
      return;
    }
    setState(() {
      _isImportingFromBluesky = true;
    });
    try {
      await _runBlueskyImport();
    } finally {
      if (mounted) {
        setState(() {
          _isImportingFromBluesky = false;
        });
      }
    }
  }

  /// The import check, dialog and import. Dropped when the signed-in
  /// session changes while it waits.
  Future<void> _runBlueskyImport() async {
    final apiService = context.read<CovesApiService>();
    final profileCache = context.read<ProfileCache>();
    final viewerAuthority = context.read<ViewerAuthorityProvider>();
    final sessionKey = viewerAuthority.sessionKey;
    bool isSameSession() => viewerAuthority.sessionKey == sessionKey;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final did = widget.profile.did;

    setState(() {
      _isFetchingBlueskyImport = true;
    });
    final BlueskyProfileImport profileImport;
    try {
      profileImport = await apiService.getBlueskyProfileImport();
    } on ApiException catch (e) {
      if (mounted && isSameSession()) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.blueskyImport(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingBlueskyImport = false;
        });
      }
    }
    // The editor may have been closed while the check was pending; its route
    // is then popping or covered, and no dialog or message should follow.
    if (!mounted ||
        !isSameSession() ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final choices = settingsImportChoices(profileImport);
    if (choices == null || choices.isEmpty) {
      final message =
          profileImport.status == BlueskyProfileImportStatus.noBlueskyProfile
          ? 'No Bluesky profile found'
          : blueskyImportResultMessage(const []);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final imported = await showBlueskyProfileImportDialog(
      context,
      choices: choices,
      handle: widget.profile.handle,
      onImport: (fields) async {
        if (!isSameSession()) {
          // Not a NothingToImport result: the dialog closes on the session
          // change, and the isSameSession() check after it returns before
          // any snackbar, so this empty list is never shown.
          return const [];
        }
        final imported = await apiService.importBlueskyProfile(fields);
        if (!isSameSession()) {
          return imported;
        }
        try {
          await refreshOwnProfile(
            apiService: apiService,
            cache: profileCache,
            did: did,
          );
        } on Exception {
          // The import landed; the profile screen catches up on its next
          // load.
        }
        return imported;
      },
    );
    if (imported == null || !mounted || !isSameSession()) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(blueskyImportResultMessage(imported))),
    );
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
            onPressed: (_hasChanges && !_isSaving && !_isImportingFromBluesky)
                ? _saveProfile
                : null,
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
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: (_isSaving || _isImportingFromBluesky)
                        ? null
                        : _importFromBluesky,
                    icon: _isFetchingBlueskyImport
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Import from Bluesky'),
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
                ? Image.file(_selectedBanner!.file, fit: BoxFit.cover)
                : (widget.profile.banner != null &&
                      widget.profile.banner!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: widget.profile.banner!,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (context, url, error) => _buildDefaultBanner(),
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
                    Icon(Icons.camera_alt, color: Colors.white, size: 32),
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
              child: Semantics(
                label: 'Change Avatar',
                button: true,
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
                                  : UserAvatar(
                                      name: widget.profile.handle ?? '',
                                      did: widget.profile.did,
                                      avatarUrl: widget.profile.avatar,
                                      size: avatarSize - 8,
                                    ),
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
            ),
          ],
        ),
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
