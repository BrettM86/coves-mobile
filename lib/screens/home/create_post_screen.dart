import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/embed_types.dart';
import '../../models/community.dart';
import '../../models/image_attachment.dart';
import '../../models/picked_image.dart';
import '../../models/post.dart';
import '../../models/post_embed_input.dart';
import '../../providers/auth_provider.dart';
import '../../providers/image_attachments_controller.dart';
import '../../services/coves_api_service.dart';
import '../../services/mention_resolver.dart';
import '../../utils/error_messages.dart';
import '../../utils/image_format.dart';
import '../../utils/image_picker_utils.dart';
import '../../utils/image_preparation.dart';
import '../../utils/rich_text_composer.dart';
import '../../utils/url_policy.dart';
import '../../widgets/composer/facet_editing_controller.dart';
import '../../widgets/composer/facet_serialization.dart';
import '../../widgets/composer/facet_text_field.dart';
import '../../widgets/composer/formatting_toolbar.dart';
import '../../widgets/composer/image_attachment_strip.dart';
import '../../widgets/composer/preparing_images_tile.dart';
import '../../widgets/icons/lucide_icon_painter.dart';
import '../../widgets/icons/lucide_paths.dart';
import '../../widgets/image_source_picker.dart';
import '../../widgets/sign_in_again_dialog.dart';
import '../compose/community_picker_screen.dart';
import 'post_detail_screen.dart';

/// Language options for posts
const Map<String, String> languages = {
  'en': 'English',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'de': 'German',
  'fr': 'French',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
};

/// Content limits from backend lexicon (social.coves.community.post)
/// Using grapheme limits as they are the user-facing character counts
const int kTitleMaxLength = 300;
const int kContentMaxLength = 10000;

/// Create Post Screen
///
/// Full-screen interface for creating a new post in a community.
///
/// Features:
/// - Community selector (required)
/// - Optional title, URL, and body fields, and up to 8 images
/// - Language dropdown and NSFW toggle
/// - Form validation (at least one of title/body/URL/images required)
/// - Loading states and error handling
/// - Keyboard handling with scroll support
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    this.onNavigateToFeed,
    this.onDirtyChanged,
    this.imagePreparer,
    super.key,
  });

  /// Callback to navigate to feed tab (used when in tab navigation)
  final VoidCallback? onNavigateToFeed;

  /// Notifies the shell when the composer gains/loses unsaved input, so the
  /// shell can decide whether system back needs to protect a draft.
  final ValueChanged<bool>? onDirtyChanged;

  /// Prepares picked images; defaults to [ImagePreparer.platform].
  final ImagePreparer? imagePreparer;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with WidgetsBindingObserver {
  // Text controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final FacetEditingController _bodyController = FacetEditingController();

  // Scroll and focus
  final ScrollController _scrollController = ScrollController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _urlFocusNode = FocusNode();
  final FocusNode _bodyFocusNode = FocusNode();
  double _lastKeyboardHeight = 0;

  // Form state
  CommunityView? _selectedCommunity;
  String _language = 'en';
  bool _isNsfw = false;
  bool _isSubmitting = false;

  /// Picked images still being prepared; Add and Post wait for them.
  int _preparingImageCount = 0;

  /// The attached images; they upload when the post is submitted.
  late final ImageAttachmentsController _images;

  /// The signed-in account, watched so that uploads made under one account
  /// are never posted, or continued, under another.
  late final AuthProvider _authProvider;

  /// The account the attachments' uploads belong to.
  String? _uploadsDid;

  /// Shared app-wide API client (owned by main.dart). Looked up on first
  /// use, which is always while mounted (a submit or a tile's Retry), and
  /// kept so uploads queued behind an await never read an unmounted context.
  late final CovesApiService _apiService = context.read<CovesApiService>();

  /// Converts and re-encodes picked images before they are attached.
  late final ImagePreparer _imagePreparer =
      widget.imagePreparer ?? ImagePreparer.platform();

  // Computed state
  bool get _isFormValid {
    return _selectedCommunity != null && _hasUnsavedInput;
  }

  /// Whether Post can be tapped: not while submitting, and not while picked
  /// images are still being prepared, which a submit would leave behind.
  bool get _canSubmit =>
      _isFormValid && !_isSubmitting && _preparingImageCount == 0;

  /// True when any text field holds user input or an image is attached (a
  /// draft worth protecting).
  ///
  /// Deliberately considers trimmed text only: community, NSFW, and language
  /// selections are cheap to redo and alone are not worth blocking back for.
  bool get _hasUnsavedInput {
    return _titleController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty ||
        _urlController.text.trim().isNotEmpty ||
        _images.attachments.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _images = ImageAttachmentsController(
      upload: (bytes, contentType, {onSendProgress}) => _apiService.uploadImage(
        bytes,
        contentType,
        onSendProgress: onSendProgress,
      ),
    )..addListener(_onTextChanged);
    _authProvider = context.read<AuthProvider>()
      ..addListener(_onAccountChanged);
    _uploadsDid = _authProvider.did;
    // Listen to text changes to update button state
    _titleController.addListener(_onTextChanged);
    _urlController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider.removeListener(_onAccountChanged);
    _titleController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _scrollController.dispose();
    _titleFocusNode.dispose();
    _urlFocusNode.dispose();
    _bodyFocusNode.dispose();
    _images.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) {
      return;
    }

    final keyboardHeight = View.of(context).viewInsets.bottom;

    // Detect keyboard closing and unfocus all text fields
    // Use a debounce to avoid false positives during keyboard animations
    if (_lastKeyboardHeight > 0 && keyboardHeight == 0) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) {
          return;
        }
        final currentHeight = View.of(context).viewInsets.bottom;
        // Only unfocus if keyboard is still closed after delay
        if (currentHeight == 0) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      });
    }

    _lastKeyboardHeight = keyboardHeight;
  }

  void _onTextChanged() {
    // Force rebuild to update Post button state
    setState(() {});
    widget.onDirtyChanged?.call(_hasUnsavedInput);
  }

  /// Discards the uploads of the previous account when the account changes.
  void _onAccountChanged() {
    if (_authProvider.did == _uploadsDid) {
      return;
    }
    _uploadsDid = _authProvider.did;
    _images.forgetUploads();
  }

  void _showAccountChanged() {
    _showError('Your account changed while posting, so nothing was posted');
  }

  Future<void> _selectCommunity() async {
    final result = await Navigator.push<CommunityView>(
      context,
      MaterialPageRoute(builder: (context) => const CommunityPickerScreen()),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedCommunity = result;
      });
    }
  }

  /// Asks for a source, then attaches the images picked from it.
  ///
  /// Does nothing while a submit is running, and drops images picked once a
  /// submit has started, since the submit has already taken its uploads.
  /// Each image is prepared (converted or re-encoded) first, with a
  /// preparing indicator shown and Add and Post disabled meanwhile; a
  /// prepared file of a dropped pick is deleted.
  Future<void> _addImages() async {
    if (_isSubmitting || _preparingImageCount > 0) {
      return;
    }
    final source = await ImageSourcePicker.show(context);
    if (source == null || !mounted || _isSubmitting) {
      return;
    }

    final ({List<PickedImage> images, int unreadableCount}) picked;
    try {
      picked = await ImagePickerUtils.pickPostImages(
        source,
        remaining: _images.remaining,
      );
    } on PlatformException {
      _showError(
        source == ImageSource.camera
            ? "Couldn't open the camera"
            : "Couldn't open your photos",
      );
      return;
    }
    if (!mounted || _isSubmitting) {
      return;
    }

    final notices = <String>{
      if (picked.unreadableCount > 0) unreadablePostImageMessage,
    };
    setState(() => _preparingImageCount = picked.images.length);
    final List<PickedImage>? prepared;
    try {
      // A dropped pick, or one cut short by an unexpected error, has its
      // prepared files deleted.
      prepared = await _imagePreparer.prepareAll(
        picked.images,
        isDropped: () => !mounted || _isSubmitting,
        onRefused: notices.add,
      );
    } finally {
      if (mounted) {
        setState(() => _preparingImageCount = 0);
      }
    }
    if (prepared == null) {
      return;
    }
    final addNotice = _images.add(prepared);
    if (addNotice != null) {
      notices.add(addNotice);
    }
    if (notices.isNotEmpty) {
      _showError(notices.join(' '));
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) {
      return;
    }

    // The body as it was at submit, with its formatting: edits and
    // formatting changes made while the post is in flight do not reach it
    final SerializedFormatting serializedBody;
    try {
      serializedBody = serializeFormatting(
        _bodyController.text,
        inlineRanges: _bodyController.inlineRanges,
        blockRanges: _bodyController.blockRanges,
        featureRanges: _bodyController.featureRanges,
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
    final composedBody = composeFormattedRichText(
      serializedBody.content,
      formattingFacets: serializedBody.facets,
      excludedRanges: serializedBody.codeRanges,
    );

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final apiService = _apiService;
      // The post is built from the form as it was at submit; edits made while
      // mentions resolve, and a switch of account, must not leak into it
      final submittingDid = authProvider.did;
      final community = _selectedCommunity!;
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : null;
      final language = _language;
      final isNsfw = _isNsfw;

      // Build the link embed if a URL is provided
      ExternalEmbedInput? external;
      final url = _urlController.text.trim();
      if (url.isNotEmpty) {
        // Validate URL
        if (!isAllowedWebUrl(url)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Please enter a valid URL (http or https)'),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          setState(() {
            _isSubmitting = false;
          });
          return;
        }

        external = ExternalEmbedInput(uri: url, title: title);
      }

      // Upload the images that have no blob yet; a failed tile shows its
      // error and Retry, and no record is sent
      var uploadsFailed = false;
      try {
        await _images.uploadMissing();
      } on ImageUploadFailedException {
        uploadsFailed = true;
      }
      // The blobs belong to the account that uploaded them
      if (authProvider.did != submittingDid) {
        _images.forgetUploads();
        _showAccountChanged();
        return;
      }
      if (uploadsFailed) {
        // Not awaited: the submit ends now, so Post stays enabled behind it
        if (_images.needsSignInAgain && mounted) {
          unawaited(showSignInAgainDialog(context, authProvider: authProvider));
        }
        return;
      }
      // Taken together, so the optimistic images match the embed
      final attachments = _images.attachments;
      final embed = buildPostEmbed(
        images: _images.embedImages,
        external: external,
      );

      // Build labels if NSFW is enabled
      SelfLabels? labels;
      if (isNsfw) {
        labels = const SelfLabels(values: [SelfLabel(val: 'nsfw')]);
      }

      final body = await resolveMentions(
        composedBody,
        ApiMentionResolver(apiService),
      );

      // The session would now write as another account; keep the form, but
      // not the blobs uploaded under the old one
      if (authProvider.did != submittingDid) {
        _images.forgetUploads();
        _showAccountChanged();
        return;
      }

      // Create post
      final response = await apiService.createPost(
        community: community.did,
        title: title,
        content: body.content.isNotEmpty ? body.content : null,
        facets: body.facets,
        embed: embed,
        langs: [language],
        labels: labels,
      );

      if (mounted) {
        // Build optimistic post for immediate display
        final optimisticPost = _buildOptimisticPost(
          response: response,
          authProvider: authProvider,
          community: community,
          title: title,
          external: external,
          attachments: attachments,
          content: body.content,
          facets: body.facets,
          isNsfw: isNsfw,
        );

        // Reset form first; the optimistic post takes the image files
        final ownedImageFiles = _resetForm();

        // Navigate to post detail with optimistic data
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: optimisticPost,
              isOptimistic: true,
              ownedImageFiles: ownedImageFiles,
              sessionStamp: null,
            ),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.createPost(e)),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// Clears the form and hands the attachments off; returns the files the
  /// app owns among them, for the optimistic post to delete.
  List<File> _resetForm() {
    setState(() {
      _titleController.clear();
      _urlController.clear();
      _bodyController.clear();
      _selectedCommunity = null;
      _language = 'en';
      _isNsfw = false;
    });
    // The optimistic post still draws from these files, so they are only
    // detached here, never deleted
    return [
      for (final attachment in _images.handOff())
        if (attachment.ownsFile) attachment.file,
    ];
  }

  /// Build optimistic post for immediate display after creation, from the
  /// values that were sent
  FeedViewPost _buildOptimisticPost({
    required CreatePostResponse response,
    required AuthProvider authProvider,
    required CommunityView community,
    required String? title,
    required ExternalEmbedInput? external,
    required List<ImageAttachment> attachments,
    required String content,
    required List<RichTextFacet>? facets,
    required bool isNsfw,
  }) {
    // Extract rkey from AT-URI (at://did/collection/rkey)
    final uriParts = response.uri.split('/');
    final rkey = uriParts.isNotEmpty ? uriParts.last : '';

    final externalEmbed = external == null
        ? null
        : ExternalEmbed(uri: external.uri, title: external.title);
    final externalData = external == null
        ? null
        : {
            r'$type': EmbedTypes.external,
            'external': {'uri': external.uri, 'title': ?external.title},
          };
    // The blobs are not served until the record is indexed, so the images
    // are drawn from the local files the user picked
    final images = [
      for (final attachment in attachments)
        EmbedImage.local(
          attachment.file,
          alt: attachment.trimmedAlt,
          aspectRatio: attachment.aspectRatio,
          isGif: attachment.mimeType == ImageFormat.gif.mimeType,
        ),
    ];

    final PostEmbed? postEmbed;
    if (images.isEmpty) {
      postEmbed = externalEmbed == null
          ? null
          : ExternalPostEmbed(
              type: EmbedTypes.external,
              external: externalEmbed,
              data: externalData!,
            );
    } else if (externalEmbed == null) {
      postEmbed = ImagesPostEmbed(
        type: EmbedTypes.imagesView,
        images: images,
        data: const {r'$type': EmbedTypes.imagesView},
      );
    } else {
      postEmbed = ImagesWithAttachmentPostEmbed(
        type: EmbedTypes.imagesWithAttachmentView,
        images: images,
        attachment: ExternalAttachment(externalEmbed),
        data: {
          r'$type': EmbedTypes.imagesWithAttachmentView,
          'attachment': externalData,
        },
      );
    }

    final now = DateTime.now();

    return FeedViewPost(
      post: PostView(
        uri: response.uri,
        cid: response.cid,
        rkey: rkey,
        author: AuthorView(
          did: authProvider.did ?? '',
          handle: authProvider.handle ?? 'unknown',
        ),
        community: CommunityRef(
          did: community.did,
          name: community.name,
          origin: community.origin,
          handle: community.handle,
          avatar: community.avatar,
        ),
        createdAt: now,
        indexedAt: now,
        record: PostRecord(
          content: content,
          title: title,
          facets: facets,
          // Mirror the self-label sent to the API so the author's own post
          // arrives at the detail screen concealed, not exposed until refetch.
          labels: isNsfw ? const ['nsfw'] : const [],
        ),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        embed: postEmbed,
        viewer: ViewerState(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userHandle = authProvider.handle ?? 'Unknown';

    // NOTE: no PopScope here. When embedded in MainShellScreen's IndexedStack
    // this widget stays alive on every tab, so a local PopScope would hijack
    // system back shell-wide. The shell owns back handling and only intercepts
    // when this tab is active with unsaved input (see onDirtyChanged).
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Create Post'),
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () {
            // Use callback if available (tab navigation), otherwise pop
            if (widget.onNavigateToFeed != null) {
              widget.onNavigateToFeed!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _canSubmit ? _handleSubmit : null,
              style: TextButton.styleFrom(
                backgroundColor: _canSubmit
                    ? AppColors.primary
                    : AppColors.textSecondary.withValues(alpha: 0.3),
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.textPrimary,
                        ),
                      ),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Community selector
                    _buildCommunitySelector(),

                    const SizedBox(height: 16),

                    // User info row
                    _buildUserInfo(userHandle),

                    const SizedBox(height: 24),

                    // Title field
                    _buildTextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      hintText: 'Title',
                      maxLines: 1,
                      maxLength: kTitleMaxLength,
                    ),

                    const SizedBox(height: 16),

                    // URL field
                    _buildTextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      hintText: 'URL',
                      maxLines: 1,
                      keyboardType: TextInputType.url,
                      // URLs must never be auto-capitalized ("Https://..." breaks
                      // backend unfurling and external link handling)
                      textCapitalization: TextCapitalization.none,
                    ),

                    const SizedBox(height: 16),

                    // Body field (multiline, formatted from the toolbar)
                    _buildBodyField(),

                    const SizedBox(height: 16),

                    ImageAttachmentStrip(
                      controller: _images,
                      onAdd: _addImages,
                      enabled: !_isSubmitting,
                    ),

                    if (_preparingImageCount > 0)
                      PreparingImagesTile(count: _preparingImageCount),

                    _buildAddImageButton(),

                    const SizedBox(height: 24),

                    // Language dropdown and NSFW toggle
                    Row(
                      children: [
                        // Language dropdown
                        Expanded(child: _buildLanguageDropdown()),

                        const SizedBox(width: 16),

                        // NSFW toggle
                        Expanded(child: _buildNsfwToggle()),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Docked at the keyboard top while the body is focused
            ListenableBuilder(
              listenable: _bodyFocusNode,
              builder: (context, _) => _bodyFocusNode.hasFocus
                  ? ColoredBox(
                      color: AppColors.backgroundSecondary,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FormattingToolbar(controller: _bodyController),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyField() {
    return FacetTextField(
      controller: _bodyController,
      focusNode: _bodyFocusNode,
      minLines: 8,
      maxLength: kContentMaxLength,
      autocorrect: false,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: _inputDecoration('What are your thoughts?'),
    );
  }

  Widget _buildCommunitySelector() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _selectCommunity,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.workspaces_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedCommunity?.displayName ??
                      _selectedCommunity?.name ??
                      'Select a community',
                  style: TextStyle(
                    color: _selectedCommunity != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddImageButton() {
    final onTap =
        _images.remaining > 0 && !_isSubmitting && _preparingImageCount == 0
        ? _addImages
        : null;

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        key: const Key('create-post-add-image'),
        button: true,
        enabled: onTap != null,
        label: 'Add image…',
        excludeSemantics: true,
        onTap: onTap,
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          ),
          icon: LucideGlyph(
            LucidePaths.imagePlus,
            size: 20,
            color: onTap != null
                ? AppColors.textSecondary
                : AppColors.textMuted,
          ),
          label: const Text('Add image', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildUserInfo(String handle) {
    return Row(
      children: [
        const Icon(Icons.person, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '@$handle',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    FocusNode? focusNode,
    int? maxLines,
    int? minLines,
    int? maxLength,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    // For multiline fields, use newline action and multiline keyboard
    final isMultiline = minLines != null && minLines > 1;
    final effectiveKeyboardType =
        keyboardType ??
        (isMultiline ? TextInputType.multiline : TextInputType.text);
    final effectiveTextInputAction =
        textInputAction ??
        (isMultiline ? TextInputAction.newline : TextInputAction.next);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: effectiveKeyboardType,
      textInputAction: effectiveTextInputAction,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: _inputDecoration(hintText),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: AppColors.textPlaceholder),
      filled: true,
      fillColor: AppColors.backgroundTertiary,
      counterStyle: const TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(16),
    );
  }

  Widget _buildLanguageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _language,
          isExpanded: true,
          dropdownColor: AppColors.backgroundSecondary,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary,
          ),
          items: languages.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _language = value;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildNsfwToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'NSFW',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch.adaptive(
              value: _isNsfw,
              activeTrackColor: AppColors.primary,
              onChanged: (value) {
                setState(() {
                  _isNsfw = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
