import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/embed_types.dart';
import '../../models/community.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../utils/facet_detector.dart';
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
/// - Optional title, URL, and body fields
/// - Language dropdown and NSFW toggle
/// - Form validation (at least one of title/body/URL required)
/// - Loading states and error handling
/// - Keyboard handling with scroll support
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({this.onNavigateToFeed, super.key});

  /// Callback to navigate to feed tab (used when in tab navigation)
  final VoidCallback? onNavigateToFeed;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with WidgetsBindingObserver {
  // Text controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

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

  // Computed state
  bool get _isFormValid {
    return _selectedCommunity != null &&
        (_titleController.text.trim().isNotEmpty ||
            _bodyController.text.trim().isNotEmpty ||
            _urlController.text.trim().isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen to text changes to update button state
    _titleController.addListener(_onTextChanged);
    _urlController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _scrollController.dispose();
    _titleFocusNode.dispose();
    _urlFocusNode.dispose();
    _bodyFocusNode.dispose();
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
        if (!mounted) return;
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
  }

  Future<void> _selectCommunity() async {
    final result = await Navigator.push<CommunityView>(
      context,
      MaterialPageRoute(
        builder: (context) => const CommunityPickerScreen(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedCommunity = result;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (!_isFormValid || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();

      // Create API service with auth
      final apiService = CovesApiService(
        tokenGetter: authProvider.getAccessToken,
        tokenRefresher: authProvider.refreshToken,
        signOutHandler: authProvider.signOut,
      );

      // Build embed if URL is provided
      ExternalEmbedInput? embed;
      final url = _urlController.text.trim();
      if (url.isNotEmpty) {
        // Validate URL
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !uri.hasScheme ||
            (!uri.scheme.startsWith('http'))) {
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

        embed = ExternalEmbedInput(
          uri: url,
          title: _titleController.text.trim().isNotEmpty
              ? _titleController.text.trim()
              : null,
        );
      }

      // Build labels if NSFW is enabled
      SelfLabels? labels;
      if (_isNsfw) {
        labels = const SelfLabels(values: [SelfLabel(val: 'nsfw')]);
      }

      // Detect link facets in the body content
      final bodyContent = _bodyController.text.trim();
      final facets = bodyContent.isNotEmpty
          ? FacetDetector.detectLinks(bodyContent)
          : null;

      // Create post
      final response = await apiService.createPost(
        community: _selectedCommunity!.did,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
        content: bodyContent.isNotEmpty ? bodyContent : null,
        facets: facets,
        embed: embed,
        langs: [_language],
        labels: labels,
      );

      if (mounted) {
        // Build optimistic post for immediate display
        final optimisticPost = _buildOptimisticPost(
          response: response,
          authProvider: authProvider,
        );

        // Reset form first
        _resetForm();

        // Navigate to post detail with optimistic data
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: optimisticPost,
              isOptimistic: true,
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create post: ${e.message}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create post: ${e.toString()}'),
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

  void _resetForm() {
    setState(() {
      _titleController.clear();
      _urlController.clear();
      _bodyController.clear();
      _selectedCommunity = null;
      _language = 'en';
      _isNsfw = false;
    });
  }

  /// Build optimistic post for immediate display after creation
  FeedViewPost _buildOptimisticPost({
    required CreatePostResponse response,
    required AuthProvider authProvider,
  }) {
    // Extract rkey from AT-URI (at://did/collection/rkey)
    final uriParts = response.uri.split('/');
    final rkey = uriParts.isNotEmpty ? uriParts.last : '';

    // Build embed if URL was provided
    PostEmbed? embed;
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      embed = PostEmbed(
        type: EmbedTypes.external,
        external: ExternalEmbed(
          uri: url,
          title: _titleController.text.trim().isNotEmpty
              ? _titleController.text.trim()
              : null,
        ),
        data: {
          r'$type': EmbedTypes.external,
          'external': {
            'uri': url,
            if (_titleController.text.trim().isNotEmpty)
              'title': _titleController.text.trim(),
          },
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
          displayName: null,
          avatar: null,
        ),
        community: CommunityRef(
          did: _selectedCommunity!.did,
          name: _selectedCommunity!.name,
          handle: _selectedCommunity!.handle,
          avatar: _selectedCommunity!.avatar,
        ),
        createdAt: now,
        indexedAt: now,
        record: PostRecord(
          content: _bodyController.text.trim(),
          title: _titleController.text.trim().isNotEmpty
              ? _titleController.text.trim()
              : null,
        ),
        stats: PostStats(
          upvotes: 0,
          downvotes: 0,
          score: 0,
          commentCount: 0,
        ),
        embed: embed,
        viewer: ViewerState(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userHandle = authProvider.handle ?? 'Unknown';

    return PopScope(
      canPop: widget.onNavigateToFeed == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.onNavigateToFeed != null) {
          widget.onNavigateToFeed!();
        }
      },
      child: Scaffold(
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
              onPressed: _isFormValid && !_isSubmitting ? _handleSubmit : null,
              style: TextButton.styleFrom(
                backgroundColor: _isFormValid && !_isSubmitting
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
              child:
                  _isSubmitting
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
              ),

              const SizedBox(height: 16),

              // Body field (multiline)
              _buildTextField(
                controller: _bodyController,
                focusNode: _bodyFocusNode,
                hintText: 'What are your thoughts?',
                minLines: 8,
                maxLines: null,
                maxLength: kContentMaxLength,
              ),

              const SizedBox(height: 24),

              // Language dropdown and NSFW toggle
              Row(
                children: [
                  // Language dropdown
                  Expanded(
                    child: _buildLanguageDropdown(),
                  ),

                  const SizedBox(width: 16),

                  // NSFW toggle
                  Expanded(
                    child: _buildNsfwToggle(),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      ),
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
                  style:
                      TextStyle(
                        color:
                            _selectedCommunity != null
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

  Widget _buildUserInfo(String handle) {
    return Row(
      children: [
        const Icon(
          Icons.person,
          color: AppColors.textSecondary,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          '@$handle',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
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
  }) {
    // For multiline fields, use newline action and multiline keyboard
    final isMultiline = minLines != null && minLines > 1;
    final effectiveKeyboardType =
        keyboardType ?? (isMultiline ? TextInputType.multiline : TextInputType.text);
    final effectiveTextInputAction =
        textInputAction ?? (isMultiline ? TextInputAction.newline : TextInputAction.next);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: effectiveKeyboardType,
      textInputAction: effectiveTextInputAction,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF5A6B7F)),
        filled: true,
        fillColor: const Color(0xFF1A2028),
        counterStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3441)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3441)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
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
          dropdownColor: AppColors.backgroundSecondary,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary,
          ),
          items:
              languages.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
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
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
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
