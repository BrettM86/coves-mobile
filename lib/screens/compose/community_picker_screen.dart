import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/community.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';

/// Community Picker Screen
///
/// Full-screen interface for selecting a community when creating a post.
///
/// Features:
/// - Search bar with 300ms debounce for client-side filtering
/// - Scroll pagination - loads more communities when near bottom
/// - Loading, error, and empty states
/// - Returns selected community on tap via Navigator.pop
///
/// Design:
/// - Header: "Post to" with X close button
/// - Search bar: "Search for a community" with search icon
/// - List of communities showing:
///   - Avatar (CircleAvatar with first letter fallback)
///   - Community name (bold)
///   - Member count + optional description
class CommunityPickerScreen extends StatefulWidget {
  const CommunityPickerScreen({super.key});

  @override
  State<CommunityPickerScreen> createState() => _CommunityPickerScreenState();
}

class _CommunityPickerScreenState extends State<CommunityPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CommunityView> _communities = [];
  List<CommunityView> _filteredCommunities = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  Timer? _searchDebounce;
  CovesApiService? _apiService;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    // Defer API initialization to first frame to access context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApiService();
      _loadCommunities();
    });
  }

  void _initApiService() {
    final authProvider = context.read<AuthProvider>();
    _apiService = CovesApiService(
      tokenGetter: authProvider.getAccessToken,
      tokenRefresher: authProvider.refreshToken,
      signOutHandler: authProvider.signOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _apiService?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Cancel previous debounce timer
    _searchDebounce?.cancel();

    // Start new debounce timer (300ms)
    _searchDebounce = Timer(const Duration(milliseconds: 300), _filterCommunities);
  }

  void _filterCommunities() {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredCommunities = _communities;
      });
      return;
    }

    setState(() {
      _filteredCommunities = _communities.where((community) {
        final name = community.name.toLowerCase();
        final displayName = community.displayName?.toLowerCase() ?? '';
        final description = community.description?.toLowerCase() ?? '';

        return name.contains(query) ||
            displayName.contains(query) ||
            description.contains(query);
      }).toList();
    });
  }

  void _onScroll() {
    // Load more when near bottom (80% scrolled)
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _loadMoreCommunities();
      }
    }
  }

  Future<void> _loadCommunities() async {
    if (_isLoading || _apiService == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiService!.listCommunities(
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _communities = response.communities;
          _filteredCommunities = response.communities;
          _cursor = response.cursor;
          _hasMore = response.cursor != null && response.cursor!.isNotEmpty;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load communities: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreCommunities() async {
    if (_isLoadingMore || !_hasMore || _cursor == null || _apiService == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await _apiService!.listCommunities(
        limit: 50,
        cursor: _cursor,
      );

      if (mounted) {
        setState(() {
          _communities.addAll(response.communities);
          _cursor = response.cursor;
          _hasMore = response.cursor != null && response.cursor!.isNotEmpty;
          _isLoadingMore = false;

          // Re-apply search filter if active
          _filterCommunities();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoadingMore = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onCommunityTap(CommunityView community) {
    Navigator.pop(context, community);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: const Text('Post to'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search for a community',
                  hintStyle: const TextStyle(color: Color(0xFF5A6B7F)),
                  filled: true,
                  fillColor: const Color(0xFF1A2028),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF5A6B7F),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),

            // Community list
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Loading state (initial load)
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    // Error state
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Color(0xFF5A6B7F),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB6C2D2),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadCommunities,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (_filteredCommunities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.search_off,
                size: 48,
                color: Color(0xFF5A6B7F),
              ),
              const SizedBox(height: 16),
              Text(
                _searchController.text.trim().isEmpty
                    ? 'No communities found'
                    : 'No communities match your search',
                style: const TextStyle(
                  color: Color(0xFFB6C2D2),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Community list
    return ListView.builder(
      controller: _scrollController,
      itemCount: _filteredCommunities.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at bottom
        if (index == _filteredCommunities.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          );
        }

        final community = _filteredCommunities[index];
        return _buildCommunityTile(community);
      },
    );
  }

  Widget _buildCommunityAvatar(CommunityView community) {
    final fallbackChild = CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.backgroundSecondary,
      foregroundColor: Colors.white,
      child: Text(
        community.name.isNotEmpty ? community.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (community.avatar == null) {
      return fallbackChild;
    }

    return CachedNetworkImage(
      imageUrl: community.avatar!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.backgroundSecondary,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.backgroundSecondary,
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
      errorWidget: (context, url, error) => fallbackChild,
    );
  }

  Widget _buildCommunityTile(CommunityView community) {
    // Format member count
    String formatCount(int? count) {
      if (count == null) {
        return '0';
      }
      if (count >= 1000000) {
        return '${(count / 1000000).toStringAsFixed(1)}M';
      } else if (count >= 1000) {
        return '${(count / 1000).toStringAsFixed(1)}K';
      }
      return count.toString();
    }

    final memberCount = formatCount(community.memberCount);
    final subscriberCount = formatCount(community.subscriberCount);

    // Build description line
    var descriptionLine = '';
    if (community.memberCount != null && community.memberCount! > 0) {
      descriptionLine = '$memberCount members';
      if (community.subscriberCount != null &&
          community.subscriberCount! > 0) {
        descriptionLine += ' · $subscriberCount subscribers';
      }
    } else if (community.subscriberCount != null &&
        community.subscriberCount! > 0) {
      descriptionLine = '$subscriberCount subscribers';
    }

    if (community.description != null && community.description!.isNotEmpty) {
      if (descriptionLine.isNotEmpty) {
        descriptionLine += ' · ';
      }
      descriptionLine += community.description!;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onCommunityTap(community),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF2A3441),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              _buildCommunityAvatar(community),
              const SizedBox(width: 12),

              // Community info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Community name
                    Text(
                      community.displayName ?? community.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Description line
                    if (descriptionLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        descriptionLine,
                        style: const TextStyle(
                          color: Color(0xFFB6C2D2),
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
