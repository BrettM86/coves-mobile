import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../providers/eula_provider.dart';

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
    try {
      final eulaProvider = context.read<EulaProvider>();
      await eulaProvider.acceptEula();
      // Router redirect handles navigation automatically
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept agreement: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.viewOnly
          ? AppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'End User License Agreement',
                style: GoogleFonts.nunito(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              leading: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.viewOnly) _buildHeader(),
            Expanded(
              child: _buildAgreementBody(),
            ),
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
              color: AppColors.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.gavel_rounded,
              color: AppColors.coral,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'License Agreement',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Please read the agreement before continuing',
                  style: GoogleFonts.nunito(
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid link: $href'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
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
                  color: AppColors.coral,
                  strokeWidth: 2,
                ),
              );
            }

            if (snapshot.hasError) {
              debugPrint(
                  'Error loading EULA: ${snapshot.error}');
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Error loading agreement',
                      style: GoogleFonts.nunito(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _retryLoadEula,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        'Retry',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600,
                        ),
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
                  data: snapshot.data ?? '',
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.keyboard_double_arrow_down_rounded,
            color: AppColors.textMuted,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            'Scroll to read full agreement',
            style: GoogleFonts.nunito(
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
    final bool canAccept =
        _hasScrolledToBottom && _hasAgreed && !_isAccepting;

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
                onTap: _hasScrolledToBottom
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
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: _hasScrolledToBottom
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
                    color: canAccept
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
                        child: _isAccepting
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
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: canAccept
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
        color: _hasAgreed
            ? AppColors.coral
            : Colors.transparent,
        border: Border.all(
          color: _hasAgreed
              ? AppColors.coral
              : enabled
                  ? AppColors.textSecondary
                  : AppColors.textMuted.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: _hasAgreed
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
      h1: GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      h2: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.coral,
        height: 1.3,
      ),
      h3: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.4,
      ),
      p: GoogleFonts.nunito(
        fontSize: 13,
        color: AppColors.textSecondary,
        height: 1.6,
      ),
      a: GoogleFonts.nunito(
        fontSize: 13,
        color: AppColors.teal,
        decoration: TextDecoration.underline,
      ),
      listBullet: GoogleFonts.nunito(
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
      strong: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      blockSpacing: 10.0,
      listIndent: 16.0,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),
    );
  }
}
