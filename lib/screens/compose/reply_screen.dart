import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/comments_provider.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/post_card.dart';

/// Reply Screen
///
/// Full-screen reply interface inspired by Thunder's natural scrolling
/// approach:
/// - Scrollable content area (post/comment preview + text input)
/// - Fixed bottom action bar with keyboard-aware margin
/// - "Cancel" button in app bar (left)
/// - "Reply" button in app bar (right, pill-shaped, enabled when text
///   present)
///
/// Key Features:
/// - Natural scrolling without fixed split ratios
/// - Thunder-style keyboard handling with manual margin
/// - Post/comment context visible while composing
/// - Text selection and copy/paste enabled
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({
    this.post,
    this.comment,
    required this.onSubmit,
    required this.commentsProvider,
    super.key,
  }) : assert(
         (post != null) != (comment != null),
         'Must provide exactly one: post or comment',
       );

  /// Post being replied to (mutually exclusive with comment)
  final FeedViewPost? post;

  /// Comment being replied to (mutually exclusive with post)
  final ThreadViewComment? comment;

  /// Callback when user submits reply
  final Future<void> Function(String content) onSubmit;

  /// CommentsProvider for draft save/restore and time updates
  final CommentsProvider commentsProvider;

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _hasText = false;
  bool _isKeyboardOpening = false;
  bool _isSubmitting = false;
  bool _authInvalidated = false;
  double _lastKeyboardHeight = 0;
  Timer? _bannerDismissTimer;
  FlutterView? _cachedView;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    // Restore draft and autofocus after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setupAuthListener();
        _restoreDraft();

        // Autofocus with delay (Thunder approach - let screen render first)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _isKeyboardOpening = true;
            _focusNode.requestFocus();
          }
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the view reference so we can safely use it in didChangeMetrics
    // even when the widget is being deactivated
    _cachedView = View.of(context);
  }

  void _setupAuthListener() {
    try {
      context.read<AuthProvider>().addListener(_onAuthChanged);
    } on Exception {
      // AuthProvider may not be available (e.g., tests)
    }
  }

  void _onAuthChanged() {
    if (!mounted || _authInvalidated) return;

    try {
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        _authInvalidated = true;
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } on Exception {
      // AuthProvider may not be available
    }
  }

  /// Restore draft text if available for this reply context
  void _restoreDraft() {
    try {
      final commentsProvider = context.read<CommentsProvider>();
      final ourParentUri = widget.comment?.comment.uri;

      // Get draft for this specific parent URI
      final draft = commentsProvider.getDraft(parentUri: ourParentUri);

      if (draft.isNotEmpty) {
        _textController.text = draft;
        setState(() {
          _hasText = true;
        });
      }
    } on Exception catch (e) {
      // CommentsProvider might not be available (e.g., during testing)
      if (kDebugMode) {
        debugPrint('📝 Draft not restored: $e');
      }
    }
  }

  void _onFocusChanged() {
    // When text field gains focus, scroll to bottom as keyboard opens
    if (_focusNode.hasFocus) {
      _isKeyboardOpening = true;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Guard against being called after widget is deactivated
    // (can happen during keyboard animation while navigating away)
    if (!mounted || _cachedView == null) return;

    final keyboardHeight = _cachedView!.viewInsets.bottom;

    // Detect keyboard closing and unfocus text field
    if (_lastKeyboardHeight > 0 && keyboardHeight == 0) {
      // Keyboard just closed - unfocus the text field
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
      }
    }

    _lastKeyboardHeight = keyboardHeight;

    // Scroll to bottom as keyboard opens
    if (_isKeyboardOpening && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);

          // Stop auto-scrolling after keyboard animation completes
          if (keyboardHeight > 100) {
            // Keyboard is substantially open, stop tracking after a delay
            Future.delayed(const Duration(milliseconds: 500), () {
              _isKeyboardOpening = false;
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _bannerDismissTimer?.cancel();
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } on Exception {
      // AuthProvider may not be available
    }
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
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
    if (_authInvalidated) {
      return;
    }

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
      // Clear draft on success
      try {
        if (mounted) {
          final parentUri = widget.comment?.comment.uri;
          context.read<CommentsProvider>().clearDraft(parentUri: parentUri);
        }
      } on Exception catch (e) {
        // CommentsProvider might not be available
        if (kDebugMode) {
          debugPrint('📝 Draft not cleared: $e');
        }
      }
      // Pop screen after successful submission
      if (mounted) {
        Navigator.of(context).pop();
      }
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
        // Reset loading state on error
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

  void _handleCancel() {
    // Save draft before closing (if text is not empty)
    _saveDraft();
    Navigator.of(context).pop();
  }

  /// Save current text as draft
  void _saveDraft() {
    try {
      final commentsProvider = context.read<CommentsProvider>();
      commentsProvider.saveDraft(
        _textController.text,
        parentUri: widget.comment?.comment.uri,
      );
    } on Exception catch (e) {
      // CommentsProvider might not be available
      if (kDebugMode) {
        debugPrint('📝 Draft not saved: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Provide CommentsProvider to descendant widgets (Consumer in _ContextPreview)
    return ChangeNotifierProvider.value(
      value: widget.commentsProvider,
      child: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false, // Thunder approach
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: TextButton(
            onPressed: _handleCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
          ),
          leadingWidth: 80,
        ),
        body: Column(
          children: [
            // Scrollable content area (Thunder style)
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    // Post or comment preview
                    _buildContext(),

                    const SizedBox(height: 8),

                    // Divider between post and text input
                    Container(height: 1, color: AppColors.border),

                    // Text input - no background box, types directly into
                    // main area
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        minLines: 8,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          height: 1.4,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Divider - simple straight line like posts and comments
            Container(height: 1, color: AppColors.border),

            _ReplyToolbar(
              hasText: _hasText,
              isSubmitting: _isSubmitting,
              onImageTap: _handleImageTap,
              onMentionTap: _handleMentionTap,
              onSubmit: _handleSubmit,
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Build context area (post or comment chain)
  Widget _buildContext() {
    // Wrap in RepaintBoundary to isolate from keyboard animation rebuilds
    return RepaintBoundary(
      child: _ContextPreview(post: widget.post, comment: widget.comment),
    );
  }
}

/// Isolated context preview that doesn't rebuild on keyboard changes
class _ContextPreview extends StatelessWidget {
  const _ContextPreview({this.post, this.comment});

  final FeedViewPost? post;
  final ThreadViewComment? comment;

  @override
  Widget build(BuildContext context) {
    if (post != null) {
      // Show full post card - Consumer only rebuilds THIS widget, not parents
      return Consumer<CommentsProvider>(
        builder: (context, commentsProvider, child) {
          return PostCard(
            post: post!,
            currentTime: commentsProvider.currentTimeNotifier.value,
            showCommentButton: false,
            disableNavigation: true,
            showActions: false,
            showBorder: false,
            showFullText: true,
            showAuthorFooter: true,
            textFontSize: 16,
            textLineHeight: 1.6,
            embedHeight: 280,
            titleFontSize: 20,
            titleFontWeight: FontWeight.w600,
          );
        },
      );
    } else if (comment != null) {
      // Show comment thread/chain
      return Consumer<CommentsProvider>(
        builder: (context, commentsProvider, child) {
          return CommentThread(
            thread: comment!,
            currentTime: commentsProvider.currentTimeNotifier.value,
            maxDepth: 6,
          );
        },
      );
    }

    return const SizedBox.shrink();
  }
}

class _ReplyToolbar extends StatefulWidget {
  const _ReplyToolbar({
    required this.hasText,
    required this.isSubmitting,
    required this.onMentionTap,
    required this.onImageTap,
    required this.onSubmit,
  });

  final bool hasText;
  final bool isSubmitting;
  final VoidCallback onMentionTap;
  final VoidCallback onImageTap;
  final VoidCallback onSubmit;

  @override
  State<_ReplyToolbar> createState() => _ReplyToolbarState();
}

class _ReplyToolbarState extends State<_ReplyToolbar>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _keyboardMarginNotifier = ValueNotifier(0);
  final ValueNotifier<double> _safeAreaBottomNotifier = ValueNotifier(0);
  FlutterView? _cachedView;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache view reference for safe access in didChangeMetrics
    _cachedView = View.of(context);
    _updateMargins();
  }

  @override
  void dispose() {
    _keyboardMarginNotifier.dispose();
    _safeAreaBottomNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Schedule update after frame to ensure context is valid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMargins();
    });
  }

  void _updateMargins() {
    if (!mounted || _cachedView == null) {
      return;
    }
    final view = _cachedView!;
    final devicePixelRatio = view.devicePixelRatio;
    final keyboardInset = view.viewInsets.bottom / devicePixelRatio;
    final viewPaddingBottom = view.viewPadding.bottom / devicePixelRatio;
    final safeAreaBottom =
        math.max(0, viewPaddingBottom - keyboardInset).toDouble();

    // Smooth tracking: Follow keyboard height in real-time (Bluesky/Thunder approach)
    _keyboardMarginNotifier.value = keyboardInset;
    _safeAreaBottomNotifier.value = safeAreaBottom;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _keyboardMarginNotifier,
          builder: (context, margin, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              margin: EdgeInsets.only(bottom: margin),
              color: AppColors.backgroundSecondary,
              padding: const EdgeInsets.only(
                left: 8,
                right: 8,
                top: 4,
                bottom: 4,
              ),
              child: child,
            );
          },
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Mention user',
                child: GestureDetector(
                  onTap: widget.onMentionTap,
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
              Semantics(
                button: true,
                label: 'Add image',
                child: GestureDetector(
                  onTap: widget.onImageTap,
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
              Semantics(
                button: true,
                label: 'Send comment',
                child: GestureDetector(
                  onTap:
                      (widget.hasText && !widget.isSubmitting)
                          ? widget.onSubmit
                          : null,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color:
                          (widget.hasText && !widget.isSubmitting)
                              ? AppColors.primary
                              : AppColors.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isSubmitting)
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
        ),
        ValueListenableBuilder<double>(
          valueListenable: _safeAreaBottomNotifier,
          builder: (context, safeAreaBottom, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              height: safeAreaBottom,
              color: AppColors.backgroundSecondary,
            );
          },
        ),
      ],
    );
  }
}
