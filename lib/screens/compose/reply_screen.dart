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
import '../../services/comments_provider_cache.dart';
import '../../services/coves_api_service.dart';
import '../../services/mention_resolver.dart';
import '../../utils/rich_text_composer.dart';
import '../../widgets/comment_thread.dart';
import '../../widgets/composer/composer_draft.dart';
import '../../widgets/composer/facet_editing_controller.dart';
import '../../widgets/composer/facet_serialization.dart';
import '../../widgets/composer/facet_text_field.dart';
import '../../widgets/composer/formatting_toolbar.dart';
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
///
/// With [ReplyScreen.editing] it edits that comment instead: the field opens
/// on the stored text and formatting, the button says "Save", and no reply
/// draft is read, saved or cleared.
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({
    this.post,
    this.comment,
    this.editing,
    required this.onSubmit,
    this.commentsProvider,
    super.key,
  }) : assert(
         editing != null
             ? post == null && comment == null
             : (post != null) != (comment != null) && commentsProvider != null,
         'Must provide exactly one: post, comment or editing; '
         'replying also requires commentsProvider',
       );

  /// Post being replied to (mutually exclusive with comment)
  final FeedViewPost? post;

  /// Comment being replied to (mutually exclusive with post)
  final ThreadViewComment? comment;

  /// The signed-in author's comment being edited (mutually exclusive with
  /// post and comment)
  final CommentView? editing;

  /// Callback when user submits reply. ReplyScreen does not report its
  /// failures: implementers must show their own error (on a messenger that
  /// can outlive their screen) and rethrow, so the composer restores the
  /// draft
  final Future<void> Function(String content, List<RichTextFacet> facets)
  onSubmit;

  /// CommentsProvider for draft save/restore and time updates; optional
  /// when [editing]
  final CommentsProvider? commentsProvider;

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> with WidgetsBindingObserver {
  late final FacetEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _hasText = false;
  bool _isKeyboardOpening = false;
  bool _isSubmitting = false;
  bool _authInvalidated = false;
  double _lastKeyboardHeight = 0;
  Timer? _bannerDismissTimer;
  FlutterView? _cachedView;
  CommentsProviderCache? _commentsCache;
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController = _restoredController();
    _hasText = _textController.text.trim().isNotEmpty;
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    // Pin the provider in the cache (acquire/release contract from
    // CommentsProviderCache): without a pin, LRU eviction could dispose
    // widget.commentsProvider while _ContextPreview's Consumer is still
    // listening — e.g. if the owning detail route is removed under this
    // reply route.
    _acquireProviderPin();

    // Autofocus after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setupAuthListener();

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

  void _acquireProviderPin() {
    final commentsProvider = widget.commentsProvider;
    if (commentsProvider == null) {
      return;
    }
    try {
      _commentsCache = context.read<CommentsProviderCache>()
        ..acquireProvider(
          postUri: commentsProvider.postUri,
          postCid: commentsProvider.postCid,
        );
    } on ProviderNotFoundException {
      // Expected in tests - the cache may not be available
    }
  }

  void _setupAuthListener() {
    try {
      // Keep a reference so dispose() can remove the listener without an
      // ancestor lookup (context.read is unsafe on a deactivated element)
      _authProvider = context.read<AuthProvider>()..addListener(_onAuthChanged);
    } on ProviderNotFoundException {
      // Expected in tests - AuthProvider may not be available
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('ERROR: Failed to setup auth listener: $e');
      }
    }
  }

  void _onAuthChanged() {
    if (!mounted || _authInvalidated) {
      return;
    }

    try {
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        _authInvalidated = true;
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } on ProviderNotFoundException {
      // Expected in tests - AuthProvider may not be available
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('ERROR: Failed to check auth state: $e');
      }
    }
  }

  /// Where reply drafts are kept: `widget.commentsProvider` directly — this
  /// screen is pushed on the root navigator, so
  /// `context.read<CommentsProvider>()` would look above the route and find
  /// nothing (the provider lives in the detail screen). Null when editing:
  /// an edit never touches the reply drafts.
  CommentsProvider? get _draftStore =>
      widget.editing == null ? widget.commentsProvider : null;

  /// A controller holding the edited comment's stored text and formatting,
  /// or this reply context's draft as it was saved (untrimmed), or an empty
  /// one when there is none
  FacetEditingController _restoredController() {
    final editing = widget.editing;
    if (editing != null) {
      return FacetEditingController.fromRecord(
        editing.content,
        editing.contentFacets ?? const [],
      );
    }
    final draft = _draftStore?.getDraft(parentUri: widget.comment?.comment.uri);
    if (draft == null) {
      return FacetEditingController();
    }
    return FacetEditingController.withRanges(
      draft.text,
      inlineRanges: draft.inlineRanges,
      blockRanges: draft.blockRanges,
      featureRanges: draft.featureRanges,
    );
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
    if (!mounted || _cachedView == null) {
      return;
    }

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
    _authProvider?.removeListener(_onAuthChanged);
    // Release the cache pin so the provider becomes evictable again.
    final pinned = widget.commentsProvider;
    if (pinned != null) {
      _commentsCache?.releaseProvider(pinned.postUri);
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
    if (_isSubmitting || _authInvalidated) {
      return;
    }

    // What is sent, and restored if the send fails: later edits and
    // formatting changes made while the send is in flight do not reach it
    final snapshot = _currentDraft();
    final SerializedFormatting serialized;
    try {
      serialized = serializeFormatting(
        snapshot.text,
        inlineRanges: snapshot.inlineRanges,
        blockRanges: snapshot.blockRanges,
        featureRanges: snapshot.featureRanges,
      );
    } on FacetLimitExceededException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Too much formatting to send. Remove some and try again.',
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final composed = composeFormattedRichText(
      serialized.content,
      formattingFacets: serialized.facets,
      excludedRanges: serialized.codeRanges,
    );
    if (composed.content.isEmpty) {
      return;
    }
    final parentUri = widget.comment?.comment.uri;
    // Shared app-wide API client (owned by main.dart), read before any await
    // and only when there is a handle to look up
    final mentionResolver = composed.mentions.isEmpty
        ? null
        : ApiMentionResolver(context.read<CovesApiService>());
    // The account that started the send; null when there is no AuthProvider
    final authProvider = _authProvider;
    final submittingDid = authProvider?.did;
    // Captured before any await so a failed mention lookup is still reported,
    // on the screen below, after system back has closed this one
    final messenger = ScaffoldMessenger.of(context);

    // Claimed and shown in one synchronous step, so a second tap is ignored
    // and no await separates the claim from the draft handling below
    setState(() => _isSubmitting = true);
    unawaited(HapticFeedback.lightImpact());

    // The text leaves the draft slot for the duration of the send, so a
    // composer reopened mid-send starts empty instead of inviting a duplicate
    // post; a failed send puts it back
    _draftStore?.clearDraft(parentUri: parentUri);

    var succeeded = false;
    try {
      final ComposedRichText resolved;
      try {
        resolved = mentionResolver == null
            ? composed
            : await resolveMentions(composed, mentionResolver);
      } on Exception catch (e) {
        // The parent screens report onSubmit failures themselves, but not
        // lookup failures, so this is shown even when the screen is gone
        if (messenger.mounted) {
          messenger.showSnackBar(_submitFailureSnackBar(e));
        }
        return;
      }
      // The session would now write as another account; the draft is kept
      if (_authInvalidated || authProvider?.did != submittingDid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your account changed while sending, so nothing was sent',
              ),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await widget.onSubmit(resolved.content, resolved.facets ?? const []);
      succeeded = true;
      // After a user back the route is animating out and no longer current;
      // pop() would then remove the screen below
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    } on Exception {
      // The parent screens report onSubmit failures and rethrow them; the
      // draft is restored below
    } finally {
      if (!succeeded) {
        // A newer draft saved while this send was in flight wins. If a
        // composer reopened during the send is still open when this send
        // fails and is closed afterwards, its text overwrites this one.
        final draftStore = _draftStore;
        if (draftStore != null &&
            draftStore.getDraft(parentUri: parentUri) == null) {
          draftStore.saveDraft(snapshot, parentUri: parentUri);
        }
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  SnackBar _submitFailureSnackBar(Exception error) => SnackBar(
    content: Text('Failed to submit: $error'),
    backgroundColor: AppColors.primary,
    behavior: SnackBarBehavior.floating,
  );

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
    // Save draft before closing (if text is not empty), except while a send
    // is in flight: _handleSubmit owns the draft slot then
    if (!_isSubmitting) {
      _saveDraft();
    }
    Navigator.of(context).pop();
  }

  /// Save current text and formatting as draft (none when editing)
  void _saveDraft() {
    _draftStore?.saveDraft(
      _currentDraft(),
      parentUri: widget.comment?.comment.uri,
    );
  }

  /// The field's text, untrimmed, with all of its ranges
  ComposerDraft _currentDraft() => ComposerDraft(
    text: _textController.text,
    inlineRanges: _textController.inlineRanges,
    blockRanges: _textController.blockRanges,
    featureRanges: _textController.featureRanges,
  );

  @override
  Widget build(BuildContext context) {
    // Provide CommentsProvider to descendant widgets (Consumer in
    // _ContextPreview)
    final commentsProvider = widget.commentsProvider;
    final screen =
        // System back / predictive back saves the draft just like the app-bar
        // Cancel button. Not while a send is in flight: _handleSubmit owns the
        // draft slot then and restores the text itself on failure. Never save
        // in dispose() instead: after a successful submit the controller still
        // holds the sent text.
        PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop && !_isSubmitting) {
              _saveDraft();
            }
          },
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
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
                leadingWidth: 80,
                title: widget.editing == null
                    ? null
                    : const Text('Edit comment'),
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
                          // Post or comment preview (none when editing)
                          if (widget.editing == null) ...[
                            _buildContext(),

                            const SizedBox(height: 8),

                            // Divider between post and text input
                            Container(height: 1, color: AppColors.border),
                          ],

                          // Text input - no background box, types directly into
                          // main area
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: FacetTextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              minLines: 8,
                              autocorrect: false,
                              textCapitalization: TextCapitalization.sentences,
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
                    controller: _textController,
                    focusNode: _focusNode,
                    hasText: _hasText,
                    isSubmitting: _isSubmitting,
                    isEditing: widget.editing != null,
                    onImageTap: _handleImageTap,
                    onMentionTap: _handleMentionTap,
                    onSubmit: _handleSubmit,
                  ),
                ],
              ),
            ),
          ),
        );
    return commentsProvider == null
        ? screen
        : ChangeNotifierProvider.value(value: commentsProvider, child: screen);
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
            // The parent post is shown for context only: no admin tools.
            sessionStamp: null,
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
            // The comment is shown for context only: no admin tools.
            sessionStamp: null,
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
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.isSubmitting,
    required this.isEditing,
    required this.onMentionTap,
    required this.onImageTap,
    required this.onSubmit,
  });

  /// The body field's controller, which the formatting toolbar edits
  final FacetEditingController controller;

  /// The body field's focus node: the formatting toolbar shows only while
  /// the field has focus
  final FocusNode focusNode;
  final bool hasText;
  final bool isSubmitting;

  /// Labels the button "Save" for an edit instead of "Send"
  final bool isEditing;
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
    final safeAreaBottom = math
        .max(0, viewPaddingBottom - keyboardInset)
        .toDouble();

    // Smooth tracking: Follow keyboard height in real-time (Bluesky/Thunder approach)
    _keyboardMarginNotifier.value = keyboardInset;
    _safeAreaBottomNotifier.value = safeAreaBottom;
  }

  @override
  Widget build(BuildContext context) {
    final leading = <Widget>[
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
    ];
    final send = Semantics(
      button: true,
      // The label alone: the pill's visible text would merge into it
      excludeSemantics: true,
      label: widget.isEditing ? 'Save comment' : 'Send comment',
      // excludeSemantics drops the GestureDetector's tap, so restate it
      enabled: widget.hasText && !widget.isSubmitting,
      onTap: (widget.hasText && !widget.isSubmitting) ? widget.onSubmit : null,
      child: GestureDetector(
        onTap: (widget.hasText && !widget.isSubmitting)
            ? widget.onSubmit
            : null,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (widget.hasText && !widget.isSubmitting)
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
                Text(
                  widget.isEditing ? 'Save' : 'Send',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
          child: ListenableBuilder(
            listenable: widget.focusNode,
            builder: (context, _) => widget.focusNode.hasFocus
                ? FormattingToolbar(
                    controller: widget.controller,
                    leading: leading,
                    trailing: [send],
                  )
                : Row(children: [...leading, const Spacer(), send]),
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
