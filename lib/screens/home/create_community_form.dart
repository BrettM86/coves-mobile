import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../utils/community_name_validator.dart';
import '../../widgets/admin_text_field.dart';

/// The admin panel's "Create Community" page body.
///
/// This widget is built only while the panel is on the create page, so its
/// State is destroyed on every trip back to the menu. It therefore owns
/// exactly one thing — the name error, which is meaningless once the fields
/// it annotates are gone.
///
/// Everything that must survive that trip is passed in by the panel shell:
/// the draft (three controllers), the receipt list, the in-flight flag, and
/// the submit action itself. A create request outlives this page, so the
/// page must not be the one awaiting it.
class CreateCommunityForm extends StatefulWidget {
  const CreateCommunityForm({
    required this.nameController,
    required this.displayNameController,
    required this.descriptionController,
    required this.createdCommunities,
    required this.isSubmitting,
    required this.onSubmit,
    super.key,
  });

  /// Community name (the DNS slug). Owned and disposed by the shell.
  final TextEditingController nameController;

  /// Human-readable name. Owned and disposed by the shell.
  final TextEditingController displayNameController;

  /// Community description. Owned and disposed by the shell.
  final TextEditingController descriptionController;

  /// Communities created so far, newest last. Owned by the shell so the
  /// receipts survive a trip to the menu.
  final List<CreateCommunityResponse> createdCommunities;

  /// Whether the shell has a create request in flight. Owned there so the
  /// button stays disabled even if the admin leaves and comes back.
  final bool isSubmitting;

  /// Asks the shell to create a community from the current draft. Called
  /// only after [CommunityNameValidator] has accepted the name.
  final VoidCallback onSubmit;

  @override
  State<CreateCommunityForm> createState() => _CreateCommunityFormState();
}

class _CreateCommunityFormState extends State<CreateCommunityForm> {
  String? _nameError;

  TextEditingController get _nameController => widget.nameController;
  TextEditingController get _displayNameController =>
      widget.displayNameController;
  TextEditingController get _descriptionController =>
      widget.descriptionController;

  /// The controllers this State currently has [_onTextChanged] attached to,
  /// in the order the add/remove helpers walk them.
  List<TextEditingController> get _controllers => [
        _nameController,
        _displayNameController,
        _descriptionController,
      ];

  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty;
  }

  /// Preview of the handle the backend will mint from the name field.
  ///
  /// Lowercased through the same normalizer the validator and the create
  /// request use, so the preview can never promise a handle that differs
  /// from what is actually sent.
  String get _handlePreview {
    final name = CommunityNameValidator.normalize(_nameController.text);
    if (name.isEmpty) {
      return '@c-{name}.coves.social';
    }
    return '@c-$name.coves.social';
  }

  // LISTENING IS NOT OWNING.
  //
  // The three controllers belong to the panel shell, which created them and
  // will dispose them. This State attaches to them for exactly as long as it
  // is alive and detaches on the way out - so it never disposes one, but it
  // does add and remove the listener on every mount/unmount cycle. The
  // asymmetry is the point: the shell outlives many of these States, and a
  // listener left behind by a torn-down form would call setState on a dead
  // State the next time the admin typed.

  @override
  void initState() {
    super.initState();
    _attachListener(_controllers);
  }

  @override
  void didUpdateWidget(CreateCommunityForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell holds these controllers in final fields, so in practice they
    // never change identity. Handled anyway: a swapped-in controller with a
    // stale listener on the old one is the classic controller-prop bug.
    final previous = [
      oldWidget.nameController,
      oldWidget.displayNameController,
      oldWidget.descriptionController,
    ];
    final current = _controllers;
    for (var i = 0; i < current.length; i++) {
      if (!identical(previous[i], current[i])) {
        previous[i].removeListener(_onTextChanged);
        current[i].addListener(_onTextChanged);
      }
    }
  }

  @override
  void dispose() {
    // Detach only. Disposal is the shell's job - see the note above.
    for (final controller in _controllers) {
      controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  /// Attaches ONE shared [_onTextChanged] across every field - see that
  /// method for why a per-field listener would be wrong.
  void _attachListener(List<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.addListener(_onTextChanged);
    }
  }

  /// Rebuilds on every keystroke in ANY of the three fields, so the submit
  /// button's enabled state and the handle preview stay live.
  ///
  /// Clearing the name error here is deliberately not scoped to the name
  /// field: typing anywhere in the form dismisses it. Test-pinned - one
  /// shared listener is the mechanism, so do not split this per field.
  void _onTextChanged() {
    if (_nameError != null) {
      setState(() {
        _nameError = null;
      });
    } else {
      setState(() {});
    }
  }

  /// Runs the pure validator and projects its answer onto [_nameError].
  bool _validateName() {
    final error = CommunityNameValidator.validate(_nameController.text);
    setState(() => _nameError = error);
    return error == null;
  }

  /// Validates, then hands the request to the shell.
  ///
  /// Deliberately does NOT run the request itself. This State is destroyed
  /// the moment the admin taps Back, and a POST that lands afterwards still
  /// has to record its receipt, clear the draft and report itself. The shell
  /// outlives the page, so it owns the request and its outcome; the only
  /// thing left here is the part that is meaningless once the form is gone —
  /// the field-level error.
  void _submit() {
    if (!_isFormValid || widget.isSubmitting) {
      return;
    }

    if (!_validateName()) {
      return;
    }

    widget.onSubmit();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Name field (DNS-valid slug)
          AdminTextField(
            controller: _nameController,
            label: 'Name (unique identifier)',
            hint: 'worldnews',
            helperText: 'DNS-valid, lowercase, no spaces',
            errorText: _nameError,
          ),
          const SizedBox(height: 16),

          _HandlePreview(handle: _handlePreview),
          const SizedBox(height: 16),

          // Display Name field
          AdminTextField(
            controller: _displayNameController,
            label: 'Display Name',
            hint: 'World News',
            helperText: 'Human-readable name shown in the UI',
          ),
          const SizedBox(height: 16),

          // Description field
          AdminTextField(
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
                  _isFormValid && !widget.isSubmitting ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                disabledBackgroundColor: AppColors.backgroundSecondary,
              ),
              child: widget.isSubmitting
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
          if (widget.createdCommunities.isNotEmpty) ...[
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
            ...widget.createdCommunities.map(
              (community) => _CreatedCommunityTile(community: community),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only preview of the handle the name field will produce.
class _HandlePreview extends StatelessWidget {
  const _HandlePreview({required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              handle,
              style: const TextStyle(
                color: AppColors.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the "Created Communities" receipt list.
class _CreatedCommunityTile extends StatelessWidget {
  const _CreatedCommunityTile({required this.community});

  final CreateCommunityResponse community;

  @override
  Widget build(BuildContext context) {
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
                    color: AppColors.textSecondary,
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
