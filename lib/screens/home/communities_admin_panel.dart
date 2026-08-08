import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../models/picked_image.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/community_name_validator.dart';
import 'community_avatar_upload_page.dart';
import 'create_community_form.dart';

/// Admin handles that can create communities
const Set<String> kAdminHandles = {
  'coves.social',
  'alex.local.coves.dev', // Local development account
  'mari.local.coves.dev', // Local development account
};

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
///
/// A shell, not a screen: it owns which [AdminPage] is showing, the AppBar
/// that titles it, and every piece of state that has to OUTLIVE a page —
/// the community list, the create-form draft and the created-community
/// receipts. Page-local, genuinely transient state stays in the pages.
class CommunitiesAdminPanel extends StatefulWidget {
  const CommunitiesAdminPanel({super.key});

  @override
  State<CommunitiesAdminPanel> createState() => _CommunitiesAdminPanelState();
}

class _CommunitiesAdminPanelState extends State<CommunitiesAdminPanel> {
  AdminPage _currentPage = AdminPage.menu;

  // Shared app-wide API client (owned by main.dart) — do not dispose here
  late final CovesApiService _apiService;

  // Community list for the profile-pic page, and the guard for its fetch.
  //
  // Held HERE rather than in CommunityAvatarUploadPage because that widget
  // is destroyed every time the user returns to the menu, and both of these
  // have to outlive it:
  //
  //   * _isLoadingCommunities so that leaving and re-entering DURING a fetch
  //     does not fire a second one (test-pinned). Note the narrowness of
  //     that guarantee: once the fetch settles the flag is false again, and
  //     _navigateToPage calls _loadCommunities() unconditionally, so every
  //     later visit does refetch. Only the in-flight window is protected.
  //   * _communities so the already-fetched list is still on screen when the
  //     admin comes back, instead of the page starting empty each time.
  bool _isLoadingCommunities = false;
  List<CommunityView> _communities = [];

  // The create form's draft and its receipt list.
  //
  // Held HERE for the same reason as the community list: CreateCommunityForm
  // is only built while _currentPage is createCommunity, so anything it
  // owned would be thrown away the moment the admin glanced at the menu.
  // Both a half-typed draft and the receipts have to survive that trip.
  // Test-pinned.
  //
  // The receipts carry the most weight: _createCommunity below runs on this
  // State, so a create started here still finishes and still appends while
  // the admin is off looking at the menu. That receipt is then the only
  // record they have of the new community's handle and DID - nothing else
  // in this panel shows it.
  //
  // This State owns them and therefore disposes them; the form only borrows
  // them (see the listener note in CreateCommunityForm).
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  List<CreateCommunityResponse> _createdCommunities = [];

  // In-flight flags for the two write requests.
  //
  // Here for the same reason again, and this one is the sharpest: a request
  // started on a page that is then left behind must still land somewhere.
  // Owned by a State that dies with the page, a succeeded create would
  // record no receipt, clear no draft and say nothing - and the re-entered
  // page, seeing a fresh `false`, would happily let the admin submit the
  // same community twice. Test-pinned.
  bool _isCreatingCommunity = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _apiService = context.read<CovesApiService>();
  }

  @override
  void dispose() {
    // Owner disposes. The form removes its own listener in its dispose,
    // which always runs first: the body is torn down before this State is.
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Creates a community from the draft the controllers hold.
  ///
  /// The form has already validated the name; this owns the request and
  /// everything that happens to its result. Note the shape of the error
  /// handling: only the API call sits inside `try`. The success path - the
  /// receipt, the draft clear, the confirmation - runs AFTER it, outside
  /// every catch, because the community exists on the server by then and an
  /// [Error] thrown while rendering a SnackBar must never be reported to the
  /// admin as "creating the community failed".
  Future<void> _createCommunity() async {
    if (_isCreatingCommunity) {
      return;
    }

    setState(() {
      _isCreatingCommunity = true;
    });

    final CreateCommunityResponse response;
    try {
      response = await _apiService.createCommunity(
        name: CommunityNameValidator.normalize(_nameController.text),
        displayName: _displayNameController.text.trim(),
        description: _descriptionController.text.trim(),
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error creating community: ${e.message}');
      }
      _finishCreate(
        message: 'Failed to create community: ${e.message}',
        background: Colors.red[700],
      );
      return;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Unexpected error in _createCommunity: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      _finishCreate(
        message: 'An unexpected error occurred. Please try again.',
        background: Colors.red,
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isCreatingCommunity = false;
      _createdCommunities = [..._createdCommunities, response];
    });

    // Clear the draft that produced it, so a returning admin is not looking
    // at a form that invites the same submission again.
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

  /// Clears the in-flight flag and reports a failed create.
  void _finishCreate({required String message, required Color? background}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isCreatingCommunity = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Uploads [image] as [community]'s avatar, returning whether it worked.
  ///
  /// Owned here rather than on the upload page for the same reason as
  /// [_createCommunity]: a success that lands after the admin navigated away
  /// still has to refresh the list, or the stale avatar survives on screen
  /// and invites a pointless re-upload. Same error-handling shape too — the
  /// API call alone is inside `try`.
  Future<bool> _uploadAvatar({
    required CommunityView community,
    required PickedImage image,
  }) async {
    if (_isUploadingAvatar) {
      return false;
    }

    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      if (kDebugMode) {
        debugPrint(
          'Uploading image: ${image.bytes.length} bytes, ${image.mimeType}',
        );
      }
      await _apiService.updateCommunity(
        communityDid: community.did,
        imageBytes: image.bytes,
        mimeType: image.mimeType,
      );
    } on ApiException catch (e, stackTrace) {
      developer.log(
        'API error uploading avatar',
        name: 'CommunitiesAdminPanel',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
      _finishUpload(
        message: 'Failed to upload avatar: ${e.message}',
        background: Colors.red[700],
      );
      return false;
    } catch (e, stackTrace) {
      developer.log(
        'Unexpected error uploading avatar',
        name: 'CommunitiesAdminPanel',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
      _finishUpload(
        message: 'An unexpected error occurred. Please try again.',
        background: Colors.red,
      );
      return false;
    }

    if (!mounted) {
      return false;
    }
    setState(() {
      _isUploadingAvatar = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Avatar updated for ${community.displayName ?? community.name}',
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Reload so the new avatar replaces the stale one in the picker.
    await _loadCommunities();
    return true;
  }

  /// Clears the in-flight flag and reports a failed upload.
  void _finishUpload({required String message, required Color? background}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isUploadingAvatar = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    // Load communities when navigating to profile pic page. Not awaited
    // because this method is void and the fetch is safe to leave running:
    // it catches its own errors and re-checks `mounted` before touching
    // state, so nothing is lost by not holding on to its Future.
    if (page == AdminPage.changeProfilePic) {
      _loadCommunities();
    }
  }

  /// Returns to the menu.
  ///
  /// Nothing is reset here: the selected community and the picked image live
  /// in [CommunityAvatarUploadPage], and swapping the body away destroys
  /// that State, so re-entering always starts clean. Test-pinned.
  void _navigateBack() {
    setState(() {
      _currentPage = AdminPage.menu;
    });
  }

  Future<void> _loadCommunities() async {
    if (_isLoadingCommunities) {
      return;
    }

    setState(() {
      _isLoadingCommunities = true;
    });

    try {
      final response = await _apiService.listCommunities();

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

  @override
  Widget build(BuildContext context) {
    // NOTE: system back is handled at the shell level (MainShellScreen) and
    // only intercepted when the Create tab has a draft; here it backgrounds
    // the app as usual — use the in-app Back arrow to return to the menu.
    // The pages below are deliberately NOT Navigator routes: real routes
    // would let system back pop them and change that.
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
                tooltip: 'Back',
                onPressed: _navigateBack,
              )
            : null,
      ),
      body: _buildAdminUI(),
    );
  }

  Widget _buildAdminUI() {
    switch (_currentPage) {
      case AdminPage.menu:
        return _AdminMenu(onSelectPage: _navigateToPage);
      case AdminPage.createCommunity:
        return CreateCommunityForm(
          nameController: _nameController,
          displayNameController: _displayNameController,
          descriptionController: _descriptionController,
          createdCommunities: _createdCommunities,
          isSubmitting: _isCreatingCommunity,
          onSubmit: _createCommunity,
        );
      case AdminPage.changeProfilePic:
        return CommunityAvatarUploadPage(
          communities: _communities,
          isLoadingCommunities: _isLoadingCommunities,
          isUploading: _isUploadingAvatar,
          onUploadAvatar: _uploadAvatar,
        );
    }
  }
}

/// The panel's landing page: one row per admin tool.
class _AdminMenu extends StatelessWidget {
  const _AdminMenu({required this.onSelectPage});

  final ValueChanged<AdminPage> onSelectPage;

  @override
  Widget build(BuildContext context) {
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
          _AdminMenuItem(
            icon: Icons.add_circle_outline,
            title: 'Create Community',
            subtitle: 'Create a new community for Coves users',
            onTap: () => onSelectPage(AdminPage.createCommunity),
          ),
          const SizedBox(height: 12),
          _AdminMenuItem(
            icon: Icons.image_outlined,
            title: 'Change Profile Pic',
            subtitle: 'Update a community\'s profile picture',
            onTap: () => onSelectPage(AdminPage.changeProfilePic),
          ),
        ],
      ),
    );
  }
}

/// One tappable tool row in [_AdminMenu].
class _AdminMenuItem extends StatelessWidget {
  const _AdminMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            const Icon(Icons.chevron_right, color: Color(0xFFB6C2D2)),
          ],
        ),
      ),
    );
  }
}
