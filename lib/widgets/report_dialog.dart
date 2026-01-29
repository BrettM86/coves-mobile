import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';

/// Report reason categories matching backend enum.
///
/// Uses enhanced enum to enforce a closed set of valid reasons at compile time.
enum ReportReason {
  spam(label: 'Spam', description: 'Unsolicited advertising or repetitive content'),
  harassment(label: 'Harassment', description: 'Bullying, threats, or targeted attacks'),
  doxing(label: 'Doxing', description: 'Sharing private information without consent'),
  illegal(label: 'Illegal Content', description: 'Content that violates laws or regulations'),
  csam(label: 'Child Safety', description: 'Content exploiting or endangering minors'),
  other(label: 'Other', description: 'Other policy violations');

  const ReportReason({required this.label, required this.description});

  final String label;
  final String description;

  /// The API value for this reason (matches enum name)
  String get value => name;
}

/// Dialog for reporting posts or comments
///
/// Shows a list of report reasons and an optional explanation field.
/// Returns true if the report was submitted successfully.
class ReportDialog extends StatefulWidget {
  const ReportDialog({
    required this.targetUri,
    required this.contentType,
    super.key,
  });

  /// AT-URI of the content being reported
  final String targetUri;

  /// Type of content ('post' or 'comment') for display purposes
  final String contentType;

  /// Show the report dialog
  ///
  /// Returns true if report was submitted, false if cancelled, null if dismissed
  static Future<bool?> show(
    BuildContext context, {
    required String targetUri,
    required String contentType,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ReportDialog(
        targetUri: targetUri,
        contentType: contentType,
      ),
    );
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  ReportReason? _selectedReason;
  final _explanationController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  static const int _maxExplanationLength = 1000;

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      setState(() => _error = 'Please select a reason');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics not supported
    }

    final authProvider = context.read<AuthProvider>();
    final apiService = CovesApiService(
      tokenGetter: authProvider.getAccessToken,
      tokenRefresher: authProvider.refreshToken,
      signOutHandler: authProvider.signOut,
    );

    try {
      await apiService.submitReport(
        targetUri: widget.targetUri,
        reason: _selectedReason!.value,
        explanation: _explanationController.text.trim().isEmpty
            ? null
            : _explanationController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AuthenticationException catch (e) {
      if (kDebugMode) {
        debugPrint('Auth error submitting report: $e');
      }
      if (mounted) {
        setState(() {
          _error = 'You must be signed in to report content';
          _isSubmitting = false;
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('API error submitting report: $e');
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _isSubmitting = false;
        });
      }
    } finally {
      apiService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(
        'Report ${widget.contentType}',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
          maxWidth: double.maxFinite,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why are you reporting this?',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              // Reason selection list
              ...ReportReason.values.map((reason) => _buildReasonTile(reason)),
              const SizedBox(height: 16),
              // Explanation field
              TextField(
                controller: _explanationController,
                maxLines: 3,
                maxLength: _maxExplanationLength,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: AppColors.backgroundSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  counterStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              // Error message
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: _isSubmitting
                  ? AppColors.textSecondary.withValues(alpha: 0.5)
                  : AppColors.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedReason == null ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.textPrimary,
            disabledBackgroundColor: AppColors.error.withValues(alpha: 0.3),
            disabledForegroundColor: AppColors.textPrimary.withValues(alpha: 0.5),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }

  Widget _buildReasonTile(ReportReason reason) {
    final isSelected = _selectedReason == reason;

    return GestureDetector(
      onTap: _isSubmitting
          ? null
          : () {
              setState(() {
                _selectedReason = reason;
                _error = null;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.error.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.error : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.error : AppColors.textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.error,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Label and description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason.label,
                    style: TextStyle(
                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reason.description,
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 12,
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
}
