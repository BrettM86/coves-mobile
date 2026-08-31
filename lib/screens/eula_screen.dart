import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../providers/eula_provider.dart';
import '../widgets/icons/back_icon.dart';

class EulaScreen extends StatefulWidget {
  const EulaScreen({this.viewOnly = false, super.key});

  final bool viewOnly;

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _hasAgreed = false;
  bool _isAccepting = false;
  late Future<String> _eulaFuture;

  @override
  void initState() {
    super.initState();
    _eulaFuture = rootBundle.loadString('assets/legal/eula.md');
    if (!widget.viewOnly) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasScrolledToBottom) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Trigger when user is within 40px of the bottom
    if (currentScroll >= maxScroll - 40) {
      setState(() => _hasScrolledToBottom = true);
    }
  }

  Future<void> _handleAccept() async {
    setState(() => _isAccepting = true);
    final eulaProvider = context.read<EulaProvider>();
    await eulaProvider.acceptEula();
    if (!mounted) return;
    if (eulaProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(eulaProvider.error!),
          backgroundColor: AppColors.error,
        ),
      );
    }
    setState(() => _isAccepting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          widget.viewOnly
              ? AppBar(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                title: const Text(
                  'End User License Agreement',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                leading: IconButton(
                  icon: const BackIcon(color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              )
              : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.viewOnly) _buildHeader(),
            Expanded(child: _buildAgreementBody()),
            if (!widget.viewOnly) _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.gavel_rounded,
              color: AppColors.teal,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'License Agreement',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Please read the agreement before continuing',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _retryLoadEula() {
    setState(() {
      _eulaFuture = rootBundle.loadString('assets/legal/eula.md');
    });
  }

  Future<void> _handleLinkTap(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid link: $href'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $href'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } on Exception catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open link: $href'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildAgreementBody() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<String>(
          future: _eulaFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.teal,
                  strokeWidth: 2,
                ),
              );
            }

            if (snapshot.hasError) {
              debugPrint('Error loading EULA: ${snapshot.error}');
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Error loading agreement',
                      style: TextStyle(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _retryLoadEula,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'Retry',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }

            final content = snapshot.data ?? '';
            if (content.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Agreement content unavailable',
                      style: TextStyle(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _retryLoadEula,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'Retry',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Stack(
              children: [
                Markdown(
                  controller: _scrollController,
                  data: content,
                  styleSheet: _buildMarkdownStyle(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  onTapLink: (text, href, title) => _handleLinkTap(href),
                ),
                // Scroll hint at the bottom when user hasn't scrolled down yet
                if (!widget.viewOnly && !_hasScrolledToBottom)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildScrollHint(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollHint() {
    return Container(
      padding: const EdgeInsets.only(bottom: 10, top: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundSecondary.withValues(alpha: 0.0),
            AppColors.backgroundSecondary.withValues(alpha: 0.95),
            AppColors.backgroundSecondary,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.keyboard_double_arrow_down_rounded,
            color: AppColors.textMuted,
            size: 16,
          ),
          SizedBox(width: 6),
          Text(
            'Scroll to read full agreement',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool canAccept = _hasScrolledToBottom && _hasAgreed && !_isAccepting;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Checkbox row
              GestureDetector(
                onTap:
                    _hasScrolledToBottom
                        ? () => setState(() => _hasAgreed = !_hasAgreed)
                        : null,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      _buildCheckbox(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I have read and agree to the End User License Agreement',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                _hasScrolledToBottom
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Accept button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color:
                        canAccept
                            ? AppColors.coral
                            : AppColors.coral.withValues(alpha: 0.2),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canAccept ? _handleAccept : null,
                      borderRadius: BorderRadius.circular(10),
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      child: Center(
                        child:
                            _isAccepting
                                ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: AppColors.background,
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(
                                  'Accept & Continue',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        canAccept
                                            ? AppColors.background
                                            : AppColors.textMuted,
                                  ),
                                ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox() {
    final bool enabled = _hasScrolledToBottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: _hasAgreed ? AppColors.coral : Colors.transparent,
        border: Border.all(
          color:
              _hasAgreed
                  ? AppColors.coral
                  : enabled
                  ? AppColors.textSecondary
                  : AppColors.textMuted.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child:
          _hasAgreed
              ? const Icon(
                Icons.check_rounded,
                size: 16,
                color: AppColors.background,
              )
              : null,
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle() {
    return MarkdownStyleSheet(
      h1: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h2: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.coral,
        height: 1.3,
      ),
      h3: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.4,
      ),
      p: const TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
        height: 1.6,
      ),
      a: const TextStyle(
        fontSize: 13,
        color: AppColors.teal,
        decoration: TextDecoration.underline,
      ),
      listBullet: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      strong: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      blockSpacing: 10.0,
      listIndent: 16.0,
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
    );
  }
}
