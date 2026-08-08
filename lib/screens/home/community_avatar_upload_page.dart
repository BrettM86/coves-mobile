import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../models/picked_image.dart';
import '../../utils/image_crop_utils.dart';
import '../../utils/image_picker_utils.dart';
import '../../widgets/community_avatar.dart';
import '../../widgets/image_source_picker.dart';

/// Picks and crops an image for real. The default for
/// [CommunityAvatarUploadPage.pickImage], hoisted to a top-level function so
/// it can be a const default value.
Future<PickedImage?> _pickAndCropImage(ImageSource source) =>
    ImageCropUtils.pickAndCropImage(source: source);

/// The admin panel's "Change Profile Pic" page body.
///
/// Owns the selection: which community, and which freshly picked image. It
/// deliberately does NOT own the community list, the upload request or the
/// in-flight flag — the panel shell owns all three, because this widget is
/// destroyed whenever the user returns to the menu and a request must be
/// able to land after that.
///
/// Destroying this widget is also what clears the selected community and the
/// selected image on back-navigation - there is no explicit reset anywhere.
class CommunityAvatarUploadPage extends StatefulWidget {
  const CommunityAvatarUploadPage({
    required this.communities,
    required this.isLoadingCommunities,
    required this.isUploading,
    required this.onUploadAvatar,
    this.pickImage = _pickAndCropImage,
    super.key,
  });

  /// Communities the shell has loaded. Empty renders the empty state.
  final List<CommunityView> communities;

  /// Whether the shell's fetch is in flight; renders the spinner.
  final bool isLoadingCommunities;

  /// Whether the shell has an avatar upload in flight.
  final bool isUploading;

  /// Asks the shell to upload [PickedImage] as the community's avatar.
  /// Resolves true when it succeeded.
  ///
  /// The shell owns the request so its result survives this page being
  /// popped mid-flight; all this widget does with the answer is drop its
  /// local preview.
  final Future<bool> Function({
    required CommunityView community,
    required PickedImage image,
  }) onUploadAvatar;

  /// Seam for the platform image pick + crop, which is otherwise reachable
  /// only through statics with no injection point. Defaults to the real
  /// thing, so production behaviour is unchanged and only tests pass
  /// anything else.
  final Future<PickedImage?> Function(ImageSource source) pickImage;

  @override
  State<CommunityAvatarUploadPage> createState() =>
      _CommunityAvatarUploadPageState();
}

class _CommunityAvatarUploadPageState extends State<CommunityAvatarUploadPage> {
  CommunityView? _selectedCommunity;
  PickedImage? _selectedImage;

  void _selectCommunity(CommunityView community) {
    setState(() {
      _selectedCommunity = community;
    });
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _pickAndUploadImage() async {
    // Show bottom sheet to choose between gallery and camera
    final source = await ImageSourcePicker.show(context);
    if (source == null) {
      return;
    }

    try {
      // Pick image and open native cropper
      final picked = await widget.pickImage(source);
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
        name: 'CommunityAvatarUploadPage',
        error: e,
        stackTrace: stackTrace,
        level: 1000, // Error level
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: ${e.toString()}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Hands the upload to the shell and drops the local preview if it
  /// worked.
  ///
  /// Everything that must survive this page - the in-flight flag, the
  /// confirmation, the list refresh - happens on the shell's side. Clearing
  /// [_selectedImage] is the only part left here, and it is purely cosmetic:
  /// if this State is gone by the time the answer arrives there is no
  /// preview left to clear.
  Future<void> _uploadImage() async {
    final community = _selectedCommunity;
    final image = _selectedImage;
    if (image == null || community == null) {
      return;
    }

    final succeeded = await widget.onUploadAvatar(
      community: community,
      image: image,
    );
    if (succeeded && mounted) {
      setState(() {
        _selectedImage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCommunity;
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

          if (widget.isLoadingCommunities)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            )
          else if (widget.communities.isEmpty)
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
            ...widget.communities.map(
              (community) => _CommunitySelectTile(
                community: community,
                isSelected: selected?.did == community.did,
                onTap: () => _selectCommunity(community),
              ),
            ),

          if (selected != null) ...[
            const SizedBox(height: 24),
            if (_selectedImage != null)
              ..._buildImageComparison(selected, _selectedImage!)
            else
              ..._buildCurrentPicture(selected),
          ],
        ],
      ),
    );
  }

  /// Current-vs-new preview plus the clear/upload/reselect actions, shown
  /// once an image has been picked.
  List<Widget> _buildImageComparison(
    CommunityView community,
    PickedImage image,
  ) {
    return [
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
                child: CommunityAvatar(
                  name: community.name,
                  avatarUrl: community.avatar,
                  size: 100,
                  fallbackColor: AppColors.backgroundSecondary,
                  fallbackIcon: const Icon(
                    Icons.workspaces_outlined,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Current',
                style: TextStyle(color: Color(0xFFB6C2D2), fontSize: 12),
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
                  child: Image.file(image.file, fit: BoxFit.cover),
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
          community.displayName ?? community.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Center(
        child: Text(
          '@${community.handle ?? community.name}',
          style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 14),
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
              onPressed: widget.isUploading ? null : _uploadImage,
              icon: const Icon(Icons.upload),
              label: Text(widget.isUploading ? 'Uploading...' : 'Upload'),
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
    ];
  }

  /// The community's existing avatar plus the "pick one" call to action,
  /// shown while no new image has been selected.
  List<Widget> _buildCurrentPicture(CommunityView community) {
    return [
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
              child: CommunityAvatar(
                name: community.name,
                avatarUrl: community.avatar,
                size: 120,
                fallbackColor: AppColors.backgroundSecondary,
                fallbackIcon: const Icon(
                  Icons.workspaces_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              community.displayName ?? community.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '@${community.handle ?? community.name}',
              style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 14),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      // Select image button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.isUploading ? null : _pickAndUploadImage,
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
    ];
  }
}

/// One selectable community row in the picker list.
class _CommunitySelectTile extends StatelessWidget {
  const _CommunitySelectTile({
    required this.community,
    required this.isSelected,
    required this.onTap,
  });

  final CommunityView community;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            CommunityAvatar(
              name: community.name,
              avatarUrl: community.avatar,
              size: 40,
              fallbackColor: AppColors.background,
              fallbackIcon: const Icon(
                Icons.workspaces_outlined,
                size: 20,
                color: AppColors.primary,
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
}
