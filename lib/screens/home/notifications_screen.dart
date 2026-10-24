import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/notification.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_preferences_change_signal.dart';
import '../../providers/notifications_list_provider.dart';
import '../../providers/unread_notification_count_provider.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../utils/app_route_observer.dart';
import '../../utils/notification_navigation.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../widgets/icons/app_icons.dart';
import '../../widgets/icons/lucide_icon_painter.dart';
import '../../widgets/icons/lucide_paths.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/notifications/notification_reply_card.dart';
import '../../widgets/notifications/notification_upvote_row.dart';
import '../../widgets/paginated_sliver_list.dart';
import '../../widgets/primary_button.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.isSelected});

  final bool isSelected;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with RouteAware {
  final ScrollController _scrollController = ScrollController();
  late final PaginationScrollListener _paginationListener;
  bool _viewportFillCheckScheduled = false;
  bool _seenCheckScheduled = false;
  bool _isTopRoute = true;
  ModalRoute<void>? _subscribedRoute;
  late final UnreadNotificationCountProvider _unreadCount;
  late final NotificationPreferencesChangeSignal _preferencesChangeSignal;
  late final AuthProvider _authProvider;
  late final ViewerAuthorityProvider _viewerAuthority;
  Object? _sessionKey;
  late int _lastObservedCount;
  late int _lastConsumedPreferencesVersion;
  bool _reloadPending = false;
  bool _reloadScheduled = false;

  /// Rows whose sensitive content the user revealed, keyed by
  /// [NotificationView.identity] so a different notification arriving in the
  /// same position starts concealed.
  final Set<String> _revealedIdentities = {};

  bool get _isVisible => widget.isSelected && _isTopRoute;

  @override
  void initState() {
    super.initState();
    _unreadCount = context.read<UnreadNotificationCountProvider>();
    _lastObservedCount = _unreadCount.count;
    _unreadCount.addListener(_onUnreadCountChanged);
    _preferencesChangeSignal = context
        .read<NotificationPreferencesChangeSignal>();
    _lastConsumedPreferencesVersion = _preferencesChangeSignal.version;
    _preferencesChangeSignal.addListener(_onPreferencesChanged);
    _viewerAuthority = context.read<ViewerAuthorityProvider>();
    _sessionKey = _viewerAuthority.sessionKey;
    _authProvider = context.read<AuthProvider>()..addListener(_onAuthChanged);
    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: () {
        if (mounted) {
          context.read<NotificationsListProvider>().loadMore();
        }
      },
    )..attach();
  }

  @override
  void didUpdateWidget(NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected && !widget.isSelected) {
      _reloadPending = false;
    }
    if (!oldWidget.isSelected &&
        widget.isSelected &&
        (_unreadCount.count > 0 || _hasPendingPreferencesChange)) {
      _reloadPending = true;
      _scheduleReload();
    }
  }

  bool get _hasPendingPreferencesChange =>
      _preferencesChangeSignal.version != _lastConsumedPreferencesVersion;

  void _onUnreadCountChanged() {
    final count = _unreadCount.count;
    final rose = count > _lastObservedCount;
    _lastObservedCount = count;
    if (rose && widget.isSelected) {
      _reloadPending = true;
      if (_isVisible) {
        _scheduleReload();
      }
    }
  }

  /// A new session starts with nothing revealed, and a preference change
  /// made under the previous session never reloads the new session's list:
  /// its own first-page load covers it.
  void _onAuthChanged() {
    final sessionKey = _viewerAuthority.sessionKey;
    if (sessionKey == _sessionKey) {
      return;
    }
    _sessionKey = sessionKey;
    _lastConsumedPreferencesVersion = _preferencesChangeSignal.version;
    setState(_revealedIdentities.clear);
  }

  void _onPreferencesChanged() {
    if (_isVisible && _hasPendingPreferencesChange) {
      _scheduleReload();
    }
  }

  void _scheduleReload() {
    if (_reloadScheduled) {
      return;
    }
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadScheduled = false;
      if (!mounted) {
        return;
      }
      if (!context.read<AuthProvider>().isAuthenticated) {
        _reloadPending = false;
        return;
      }
      if (!_isVisible || (!_reloadPending && !_hasPendingPreferencesChange)) {
        return;
      }
      _reloadPending = false;
      _lastConsumedPreferencesVersion = _preferencesChangeSignal.version;
      unawaited(context.read<NotificationsListProvider>().refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_subscribedRoute == route) {
      return;
    }
    appRouteObserver.unsubscribe(this);
    _subscribedRoute = route;
    _isTopRoute = route?.isCurrent ?? true;
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    setState(() => _isTopRoute = false);
  }

  @override
  void didPopNext() {
    setState(() => _isTopRoute = true);
    if (widget.isSelected && (_reloadPending || _hasPendingPreferencesChange)) {
      _scheduleReload();
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _unreadCount.removeListener(_onUnreadCountChanged);
    _preferencesChangeSignal.removeListener(_onPreferencesChanged);
    _authProvider.removeListener(_onAuthChanged);
    _paginationListener.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSeenCheck() {
    if (_seenCheckScheduled || !_isVisible) {
      return;
    }
    _seenCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seenCheckScheduled = false;
      if (!mounted ||
          !_isVisible ||
          !context.read<AuthProvider>().isAuthenticated) {
        return;
      }
      unawaited(context.read<NotificationsListProvider>().markPageOneSeen());
    });
  }

  void _scheduleViewportFillCheck(NotificationsListProvider provider) {
    final controller = provider.controller;
    if (_viewportFillCheckScheduled ||
        controller.isLoading ||
        controller.isLoadingMore ||
        controller.loadMoreError != null ||
        !controller.hasMore) {
      return;
    }

    _viewportFillCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportFillCheckScheduled = false;
      if (!mounted ||
          !_scrollController.hasClients ||
          !context.read<AuthProvider>().isAuthenticated) {
        return;
      }
      final currentProvider = context.read<NotificationsListProvider>();
      final current = currentProvider.controller;
      if (current.hasMore &&
          !current.isLoading &&
          !current.isLoadingMore &&
          current.loadMoreError == null &&
          isNearScrollEnd(_scrollController.position)) {
        currentProvider.loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AuthProvider>().isAuthenticated;
    if (isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<AuthProvider>().isAuthenticated) {
          context.read<NotificationsListProvider>().requestFirstPage();
        }
      });
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            AppIcon.bellOutline(size: 22, color: AppColors.coral),
            const SizedBox(width: 10),
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          if (isAuthenticated)
            IconButton(
              tooltip: 'Settings',
              icon: AppIcon.settings(color: AppColors.textPrimary),
              onPressed: () => context.push('/settings'),
            ),
        ],
      ),
      body: isAuthenticated ? _buildSignedInBody() : _buildSignedOutPrompt(),
    );
  }

  Widget _buildSignedInBody() {
    final provider = context.watch<NotificationsListProvider>();
    final controller = provider.controller;
    final notifications = controller.items;
    if ((controller.isLoading || provider.isAwaitingFirstPage) &&
        notifications.isEmpty) {
      return const FullScreenLoading();
    }
    final error = controller.error;
    if (error != null && notifications.isEmpty) {
      return FullScreenError(message: error, onRetry: provider.refresh);
    }
    if (notifications.isNotEmpty) {
      _scheduleSeenCheck();
    }
    _scheduleViewportFillCheck(provider);
    final loadMoreError = controller.loadMoreError;
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          PaginatedSliverList<NotificationView>(
            items: notifications,
            isLoadingMore: controller.isLoadingMore,
            hasMore: controller.hasMore,
            loadMoreError: loadMoreError,
            refreshError: notifications.isNotEmpty ? error : null,
            onRetryLoadMore: provider.retryLoadMore,
            onRetryRefresh: provider.refresh,
            idOf: (notification) => notification.identity,
            emptyWidget: loadMoreError != null
                ? InlineError(
                    message: loadMoreError,
                    onRetry: provider.retryLoadMore,
                  )
                : controller.hasMore
                ? const Center(child: CircularProgressIndicator())
                : const Center(
                    child: Text(
                      'No notifications yet',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ),
            itemBuilder: (context, notification, index) =>
                notification.reason == NotificationReason.upvote
                ? NotificationUpvoteRow(
                    notification: notification,
                    onTap: () => context.push(notificationRoute(notification)),
                    sensitiveContentRevealed: _revealedIdentities.contains(
                      notification.identity,
                    ),
                    onSensitiveContentToggle: () =>
                        _toggleSensitiveContent(notification.identity),
                  )
                : NotificationReplyCard(
                    notification: notification,
                    onTap: () => context.push(notificationRoute(notification)),
                    sensitiveContentRevealed: _revealedIdentities.contains(
                      notification.identity,
                    ),
                    onSensitiveContentToggle: () =>
                        _toggleSensitiveContent(notification.identity),
                  ),
          ),
        ],
      ),
    );
  }

  void _toggleSensitiveContent(String identity) {
    setState(() {
      if (!_revealedIdentities.remove(identity)) {
        _revealedIdentities.add(identity);
      }
    });
  }

  Widget _buildSignedOutPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LucideGlyph(
              LucidePaths.bell,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in to view your notifications',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            PrimaryButton(
              title: 'Sign in',
              onPressed: () => context.push('/login'),
            ),
          ],
        ),
      ),
    );
  }
}
