import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// Comment Composer Widget
///
/// Reusable widget for composing comments across the app.
/// Used in post detail screens and potentially nested comment replies.
///
/// Features:
/// - Multi-line text input with auto-expanding height
/// - @ mention button (coming soon)
/// - Image upload button (coming soon)
/// - Send button with validation
/// - Proper keyboard handling
///
/// Note: This widget is currently unused but has been created for future use
/// in other parts of the app where inline comment composition is needed.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    required this.onSubmit,
    this.placeholder = 'Say something...',
    this.autofocus = false,
    super.key,
  });

  /// Callback when user submits a comment
  final Future<void> Function(String content) onSubmit;

  /// Placeholder text for the input field
  final String placeholder;

  /// Whether to autofocus the input field
  final bool autofocus;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _isSubmitting = false;
  Timer? _bannerDismissTimer;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    if (widget.autofocus) {
      // Focus after frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _bannerDismissTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  Future<void> _handleSubmit() async {
    final content = _textController.text.trim();
    if (content.isEmpty) {
      return;
    }

    // Add haptic feedback before submission
    await HapticFeedback.lightImpact();

    // Set loading state
    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onSubmit(content);
      _textController.clear();
      // Keep focus for rapid commenting
    } on Exception catch (e) {
      // Show error if submission fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showComingSoonBanner(String feature) {
    // Cancel any existing timer to prevent multiple banners
    _bannerDismissTimer?.cancel();

    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text('$feature coming soon!'),
        backgroundColor: AppColors.primary,
        leading: const Icon(Icons.info_outline, color: AppColors.textPrimary),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text(
              'Dismiss',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );

    // Auto-hide after 2 seconds with cancelable timer
    _bannerDismissTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        messenger.hideCurrentMaterialBanner();
      }
    });
  }

  void _handleMentionTap() {
    _showComingSoonBanner('Mention feature');
  }

  void _handleImageTap() {
    _showComingSoonBanner('Image upload');
  }

  @override
  Widget build(BuildContext context) {
    // Calculate max height for text input: 50% of screen
    final maxTextHeight = MediaQuery.of(context).size.height * 0.5;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 6,
          bottom: 6 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text input (scrollable if too long)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxTextHeight),
              child: Theme(
                data: Theme.of(context).copyWith(
                  scrollbarTheme: ScrollbarThemeData(
                    thumbColor: WidgetStateProperty.all(
                      AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Scrollbar(
                  thumbVisibility: false,
                  thickness: 3,
                  radius: const Radius.circular(2),
                  child: SingleChildScrollView(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.placeholder,
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Action buttons row with send button (always visible)
            Row(
              children: [
                // Mention button
                Semantics(
                  button: true,
                  label: 'Mention user',
                  child: GestureDetector(
                    onTap: _handleMentionTap,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.alternate_email_rounded,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Image button
                Semantics(
                  button: true,
                  label: 'Add image',
                  child: GestureDetector(
                    onTap: _handleImageTap,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.image_outlined,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Send button (pill-shaped)
                Semantics(
                  button: true,
                  label: 'Send comment',
                  child: GestureDetector(
                    onTap: (_hasText && !_isSubmitting) ? _handleSubmit : null,
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color:
                            (_hasText && !_isSubmitting)
                                ? AppColors.primary
                                : AppColors.textSecondary.withValues(
                                  alpha: 0.3,
                                ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSubmitting)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.textPrimary,
                                ),
                              ),
                            )
                          else
                            const Text(
                              'Send',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
