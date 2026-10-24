import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/moderation_constants.dart';
import '../../models/community.dart';
import '../../models/moderation_action.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../services/admin_moderation_flow.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../services/moderation_errors.dart';
import '../../services/profile_cache.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/cursor_pagination_controller.dart';
import '../../utils/error_messages.dart';
import '../../utils/moderation_copy.dart';
import '../../utils/pagination_scroll_listener.dart';
import '../../widgets/icons/lucide_icon_painter.dart';
import '../../widgets/icons/lucide_paths.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/moderation/moderation_action_sheet.dart';
import '../../widgets/moderation/moderation_failure_decision.dart';
import '../../widgets/moderation/modlog_entry_tile.dart';
import '../../widgets/paginated_sliver_list.dart';
import '../compose/community_picker_screen.dart';

class ModlogScreen extends StatefulWidget {
  const ModlogScreen({super.key, this.subject, this.clock});

  final String? subject;

  /// Source of the current time for day headers and relative times;
  /// [DateTime.now] when null.
  final DateTime Function()? clock;

  @override
  State<ModlogScreen> createState() => _ModlogScreenState();
}

class _ModlogScreenState extends State<ModlogScreen> {
  final ScrollController _scrollController = ScrollController();
  late final CovesApiService _apiService;
  late final ProfileCache _profileCache;
  late final ViewerAuthorityProvider _viewerAuthority;

  /// Rows of the current run. A public-log run wraps each row in an envelope
  /// without private fields, so one controller serves both logs.
  late final CursorPaginationController<AdminModerationActionView> _controller;
  late final PaginationScrollListener _paginationListener;
  final Map<String, String?> _actorHandles = {};

  /// Display handle ("!name@origin") per community DID, null while the
  /// lookup is in flight or after it failed. A DID is looked up until one
  /// lookup succeeds; a failed lookup is asked again on pull-to-refresh.
  final Map<String, String?> _communityHandles = {};

  /// Community DIDs whose last lookup failed, asked again on pull-to-refresh.
  final Set<String> _failedCommunityLookups = {};
  bool _viewportFillCheckScheduled = false;
  String? _action;
  CommunityView? _community;
  String? _subject;

  /// Bumped whenever the list starts a new run: a filter change, a switch of
  /// log, a pull-to-refresh, or an invalid-cursor restart. An answer for an
  /// older run is stale and changes nothing.
  int _runGeneration = 0;

  /// Whether the current run reads the admin log. Chosen from the server's
  /// answer about the viewer: only an instance admin gets the admin log.
  bool _adminLog = false;

  /// The route's subject was not a post AT-URI with a DID authority, so it
  /// was dropped rather than sent; the backend would reject it on every load.
  bool _invalidSubjectLink = false;

  /// Set once an invalid cursor has triggered an automatic restart. Cleared
  /// by a page that loads from a cursor or by a user Retry, so a server that
  /// rejects every cursor gets one restart per chain instead of a loop.
  bool _invalidCursorRecoveryUsed = false;

  /// The removal whose restore is in flight; its row's Restore is disabled.
  ModerationActionRef? _restoringRemoval;

  String _idOf(AdminModerationActionView entry) =>
      '${entry.action.ref.serviceDid} ${entry.action.ref.actionId}';

  static String? _actorDidOf(AdminModerationActionView entry) =>
      entry.actorDid ?? entry.action.actorDid;

  /// The row's community: its public subject's, else its private subject's,
  /// else its scope's.
  static String? _communityDidOf(AdminModerationActionView entry) =>
      entry.action.subject?.communityDid ??
      entry.privateSubject?.communityDid ??
      entry.action.scope.communityDid;

  @override
  void initState() {
    super.initState();
    final subject = widget.subject;
    if (subject != null) {
      if (moderationSubjectUriKind(subject) == ModerationSubjectKind.post) {
        _subject = subject;
      } else {
        _invalidSubjectLink = true;
      }
    }
    _apiService = context.read<CovesApiService>();
    _profileCache = context.read<ProfileCache>();
    _viewerAuthority = context.read<ViewerAuthorityProvider>();
    _adminLog = _viewerAuthority.isInstanceAdmin;
    _viewerAuthority.addListener(_onAuthorityChanged);
    _controller = CursorPaginationController<AdminModerationActionView>(
      fetchPage: _fetchPage,
      idOf: _idOf,
      errorMapper: (error) => getErrorMessage(
        error,
        fallback: 'Failed to load moderation actions. Please try again.',
      ),
      sessionKeyOf: () => _viewerAuthority.sessionKey,
    )..addListener(_onPageChanged);
    _paginationListener = PaginationScrollListener(
      controller: _scrollController,
      onLoadMore: _controller.loadMore,
    )..attach();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _controller.refresh();
      unawaited(_askAuthorityAgainIfUnavailable());
    });
  }

  /// Switches between the admin and the public log when the viewer's
  /// authority changes. The rows of the other log are dropped in the same
  /// frame, so private fields never outlive the authority that revealed them.
  void _onAuthorityChanged() {
    final adminLog = _viewerAuthority.isInstanceAdmin;
    if (!mounted || adminLog == _adminLog) {
      return;
    }
    _adminLog = adminLog;
    _restartFilteredList();
  }

  /// Asks the server again when the last authority check failed; an answer
  /// of instance admin switches to the admin log through
  /// [_onAuthorityChanged].
  Future<void> _askAuthorityAgainIfUnavailable() async {
    if (_viewerAuthority.status == ViewerAuthorityStatus.unavailable) {
      await _viewerAuthority.refresh();
    }
  }

  Future<void> _pullToRefresh() async {
    // Forgetting a failed lookup makes the next page change ask again.
    _communityHandles.removeWhere(
      (communityDid, _) => _failedCommunityLookups.contains(communityDid),
    );
    _failedCommunityLookups.clear();
    final adminLog = _adminLog;
    await _askAuthorityAgainIfUnavailable();
    // A switch of log already restarted the list from the first page.
    if (!mounted || adminLog != _adminLog) {
      return;
    }
    _runGeneration++;
    _invalidCursorRecoveryUsed = false;
    await _controller.refresh();
  }

  Future<CursorPage<AdminModerationActionView>> _fetchPage(
    String? cursor,
  ) async {
    final runGeneration = _runGeneration;
    final adminLog = _adminLog;
    final sessionKey = _viewerAuthority.sessionKey;
    try {
      final page = adminLog
          ? await _fetchAdminPage(cursor)
          : await _fetchPublicPage(cursor);
      if (cursor != null && runGeneration == _runGeneration) {
        _invalidCursorRecoveryUsed = false;
      }
      return page;
    } on ApiException catch (error) {
      if (adminLog &&
          runGeneration == _runGeneration &&
          sessionKey == _viewerAuthority.sessionKey &&
          error.statusCode == 403 &&
          error.errorCode == 'Forbidden') {
        // The server no longer treats the current viewer as an instance
        // admin. The status change restarts the list as the public log, which
        // orphans this request, so the rethrow below is discarded as stale.
        // A Forbidden for an older run or another account revokes nothing.
        _viewerAuthority.markRevoked();
      }
      if (cursor != null &&
          runGeneration == _runGeneration &&
          !_invalidCursorRecoveryUsed &&
          error.statusCode == 400 &&
          error.errorCode == 'InvalidCursor') {
        _invalidCursorRecoveryUsed = true;
        _runGeneration++;
        // reset() drops the old rows and the rejected cursor and orphans this
        // append, so the rethrow below is discarded as stale. If the fresh
        // first page then fails, the screen shows the full-screen error
        // rather than following the rejected cursor again.
        _controller.reset();
        unawaited(_controller.refresh());
      }
      rethrow;
    }
  }

  Future<CursorPage<AdminModerationActionView>> _fetchAdminPage(
    String? cursor,
  ) async {
    final page = await _apiService.listAdminModerationActions(
      cursor: cursor,
      action: _action,
      community: _community?.did,
      subject: _subject,
    );
    return CursorPage(items: page.actions, cursor: page.cursor);
  }

  Future<CursorPage<AdminModerationActionView>> _fetchPublicPage(
    String? cursor,
  ) async {
    final page = await _apiService.listModerationActions(
      cursor: cursor,
      action: _action,
      community: _community?.did,
      subject: _subject,
    );
    return CursorPage(
      items: [
        for (final action in page.actions)
          AdminModerationActionView(action: action),
      ],
      cursor: page.cursor,
    );
  }

  void _onPageChanged() {
    if (!mounted) {
      return;
    }
    for (final entry in _controller.items) {
      final actorDid = _actorDidOf(entry);
      if (actorDid == null || _actorHandles.containsKey(actorDid)) {
        continue;
      }
      final cachedProfile = _profileCache.get(actorDid);
      _actorHandles[actorDid] = cachedProfile?.handle;
      if (cachedProfile == null) {
        unawaited(_resolveActor(actorDid));
      }
    }
    for (final entry in _controller.items) {
      final communityDid = _communityDidOf(entry);
      if (communityDid == null || _communityHandles.containsKey(communityDid)) {
        continue;
      }
      _communityHandles[communityDid] = null;
      unawaited(_resolveCommunity(communityDid));
    }
    setState(() {});
    if (_viewportFillCheckScheduled ||
        _controller.isLoading ||
        _controller.isLoadingMore ||
        _controller.loadMoreError != null ||
        !_controller.hasMore) {
      return;
    }
    _viewportFillCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportFillCheckScheduled = false;
      if (mounted) {
        _paginationListener.checkNow();
      }
    });
  }

  Future<void> _resolveActor(String actorDid) async {
    final String? handle;
    try {
      handle = (await _apiService.getProfile(actor: actorDid)).handle;
    } on ApiException {
      // The row names "A moderator" when a lookup fails; it never shows the
      // DID. An ApiException covers network, HTTP and parse failures alike.
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _actorHandles[actorDid] = handle;
    });
  }

  Future<void> _resolveCommunity(String communityDid) async {
    final CommunityView community;
    try {
      community = await _apiService.getCommunity(community: communityDid);
    } on ApiException {
      // The row names no community when a lookup fails; it never shows the
      // DID. Pull-to-refresh asks again. An ApiException covers network,
      // HTTP and parse failures alike.
      _failedCommunityLookups.add(communityDid);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _communityHandles[communityDid] =
          CommunityHandleUtils.resolveDisplayHandle(
            name: community.name,
            origin: community.origin,
            handle: community.handle,
          )?.toString();
    });
  }

  Future<bool> _retry() {
    _invalidCursorRecoveryUsed = false;
    return _controller.retry();
  }

  Future<void> _retryLoadMore() {
    _invalidCursorRecoveryUsed = false;
    return _controller.retryLoadMore();
  }

  /// Reloads the current log from its first page, keeping the rows on
  /// screen until the new page replaces them.
  void _reloadFromFirstPage() {
    _runGeneration++;
    _invalidCursorRecoveryUsed = false;
    unawaited(_controller.refresh());
  }

  /// Whether [entry] offers Restore: a local removal with a subject, in the
  /// admin log of the instance admin whose session loaded the rows. Log rows
  /// carry no per-viewer moderation state, so the server decides the rest
  /// when the restore runs.
  bool _offersRestore(AdminModerationActionView entry) =>
      _adminLog &&
      _viewerAuthority.status == ViewerAuthorityStatus.instanceAdmin &&
      _controller.sessionStamp == _viewerAuthority.sessionKey &&
      entry.action.action == ModerationActionKind.remove &&
      entry.action.origin == 'local' &&
      (entry.action.subject ?? entry.privateSubject) != null;

  /// Opens the restore sheet for [entry]'s removal. The restore runs only
  /// while that removal is still the subject's local removal; every answer
  /// that may have changed the log reloads it from the first page.
  Future<void> _restore(AdminModerationActionView entry) async {
    final subject = entry.action.subject ?? entry.privateSubject;
    if (subject == null) {
      return;
    }
    final authority = _viewerAuthority;
    final sessionKey = authority.sessionKey;
    final messenger = ScaffoldMessenger.of(context);
    final removal = entry.action.ref;
    final isComment =
        moderationSubjectUriKind(subject.uri) == ModerationSubjectKind.comment;
    final subjectNoun = isComment ? 'comment' : 'post';
    final flow = AdminModerationFlow(_apiService, authority: authority);
    // Anything that lands after the session changed or the screen closed
    // belongs to a log no longer shown and is neither shown nor applied.
    bool answerStillWanted() => mounted && authority.sessionKey == sessionKey;
    void showMessage(String message) {
      if (messenger.mounted && answerStillWanted()) {
        messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }

    void reloadLog() {
      if (answerStillWanted()) {
        _reloadFromFirstPage();
      }
    }

    try {
      await ModerationActionSheet.show<ModerationFlowResult>(
        context,
        title: isComment ? 'Restore comment' : 'Restore post',
        confirmLabel: 'Restore',
        reasons: restoreReasons,
        failureMessage: "Couldn't restore this $subjectNoun. Try again.",
        authority: authority,
        onSubmit: (reason, privateNote) async {
          if (mounted) {
            setState(() => _restoringRemoval = removal);
          }
          if (flow.retainedSubmission != null) {
            return (await flow.retry())!;
          }
          return flow.submitRestore(
            subjectUri: subject.uri,
            reason: reason,
            privateNote: privateNote,
            expectedRemoval: removal,
          );
        },
        onResult: (outcome) async {
          if (outcome is ModerationFlowRemovalNoLongerActive) {
            reloadLog();
            showMessage('This removal is no longer active.');
            return const ModerationSheetDecision();
          }
          final restoreOutcome = restoreOutcomeOf(outcome);
          if (restoreOutcome != null) {
            reloadLog();
            showMessage(switch (restoreOutcome) {
              RestoreOutcome.restored =>
                isComment ? 'Comment restored' : 'Post restored',
              RestoreOutcome.restoredButDeleted =>
                'Restored, but the author deleted it, so it stays hidden.',
              RestoreOutcome.restoredButUnavailable =>
                "Restored, but it can't be shown right now.",
              RestoreOutcome.notRemoved => 'This is no longer removed.',
            });
            return const ModerationSheetDecision();
          }
          return moderationFailureDecision(
            outcome,
            authority: authority,
            showMessage: showMessage,
            // A conflicting decision changed the removal: show the log as it
            // is now rather than asking to confirm a restore of a stale row.
            resolveStateConflict: (_) {
              reloadLog();
              showMessage('This item changed. Showing the latest version.');
              return true;
            },
            reloadSubject: (error) async {
              reloadLog();
              showMessage(
                error.code == ModerationErrorCode.contentChanged
                    ? 'The author edited this $subjectNoun. '
                          'Try restoring again.'
                    : error.message,
              );
            },
          );
        },
      );
    } finally {
      if (mounted && _restoringRemoval == removal) {
        setState(() => _restoringRemoval = null);
      }
    }
  }

  void _restartFilteredList() {
    _runGeneration++;
    _invalidCursorRecoveryUsed = false;
    _controller.reset();
    unawaited(_controller.refresh());
  }

  void _selectAction(String? action) {
    if (_action == action) {
      return;
    }
    _action = action;
    _restartFilteredList();
  }

  Future<void> _pickCommunity() async {
    final community = await Navigator.of(context).push<CommunityView>(
      MaterialPageRoute(
        builder: (_) =>
            const CommunityPickerScreen(title: 'Filter by community'),
      ),
    );
    if (!mounted || community == null || _community?.did == community.did) {
      return;
    }
    _community = community;
    _restartFilteredList();
  }

  void _clearCommunity() {
    _community = null;
    _restartFilteredList();
  }

  void _clearSubject() {
    _subject = null;
    _restartFilteredList();
  }

  /// The action filter's choices: label and the `action` sent to the log.
  static const List<(String, String?)> _actionChoices = [
    ('All actions', null),
    ('Removals', 'remove'),
    ('Restores', 'restore'),
  ];

  Widget _buildFilters() {
    final textTheme = Theme.of(context).textTheme;
    final noticeStyle = textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.navDivider)),
          ),
          child: Padding(
            // Each control draws its outline 2px inside its 48px-tall hit
            // area, so the outlines sit 4px from the top and 12px from the
            // divider.
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            // Above 1.3x text the two controls no longer share a narrow line.
            child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    // With each control's 2px inset, outlines sit 8px apart.
                    spacing: 4,
                    children: [_buildActionFilter(), _buildCommunityFilter()],
                  )
                : Row(
                    spacing: 8,
                    children: [
                      _buildActionFilter(),
                      Flexible(child: _buildCommunityFilter()),
                    ],
                  ),
          ),
        ),
        if (_invalidSubjectLink)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "This link isn't valid. Showing all actions.",
              style: noticeStyle,
            ),
          ),
        if (_subject != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing actions for one post',
                    style: noticeStyle,
                  ),
                ),
                TextButton(
                  onPressed: _clearSubject,
                  child: const Text('Show all'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static const _filterLabelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// The outline of a filter control: teal-tinted while it narrows the log.
  static ShapeDecoration _filterDecoration({required bool active}) =>
      ShapeDecoration(
        color: active ? AppColors.teal.withValues(alpha: 0.10) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: active
                ? AppColors.teal.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
      );

  /// A filter button with a 48px-tall hit area whose outline is drawn 2px
  /// inside it: [label] and a chevron that says it opens a choice. The label
  /// ellipsizes to fit a bounded width.
  Widget _filterButton({
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    final color = active ? AppColors.teal : AppColors.textPrimary;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Ink(
                decoration: _filterDecoration(active: active),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _filterLabelStyle.copyWith(color: color),
                        ),
                      ),
                      ExcludeSemantics(
                        child: LucideGlyph(
                          LucidePaths.chevronDown,
                          size: 14,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionFilter() {
    final selected = _actionChoices.firstWhere(
      (choice) => choice.$2 == _action,
      orElse: () => _actionChoices.first,
    );
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.backgroundSecondary),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
      menuChildren: [
        for (final (label, action) in _actionChoices)
          MenuItemButton(
            onPressed: () => _selectAction(action),
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(180, 48),
              foregroundColor: AppColors.textPrimary,
              textStyle: _filterLabelStyle,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            trailingIcon: action == _action
                ? const LucideGlyph(
                    LucidePaths.check,
                    size: 18,
                    color: AppColors.coral,
                  )
                : const SizedBox(width: 18),
            child: Semantics(selected: action == _action, child: Text(label)),
          ),
      ],
      builder: (context, controller, _) => _filterButton(
        label: selected.$1,
        active: _action != null,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget _buildCommunityFilter() {
    final community = _community;
    if (community == null) {
      return _filterButton(
        label: 'Community',
        active: false,
        onPressed: _pickCommunity,
      );
    }
    final label =
        CommunityHandleUtils.resolveDisplayHandle(
          name: community.name,
          origin: community.origin,
          handle: community.handle,
        )?.toString() ??
        community.name;
    // The outline is drawn 2px inside the 48px-tall slot, like the other
    // filter buttons, while the label's and the clear button's hit areas
    // fill the slot.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Ink(decoration: _filterDecoration(active: true)),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Semantics(
                  button: true,
                  label: 'Community filter',
                  child: InkWell(
                    onTap: _pickCommunity,
                    customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(12),
                      ),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _filterLabelStyle.copyWith(
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Clear community filter',
                onPressed: _clearCommunity,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const LucideGlyph(
                  LucidePaths.x,
                  size: 16,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _viewerAuthority.removeListener(_onAuthorityChanged);
    _paginationListener.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _controller.items;
    final actionsByRef = {
      for (final entry in items) entry.action.ref: entry.action,
    };
    final error = _controller.error;
    final now = (widget.clock ?? DateTime.now)();
    final Widget body;
    if (items.isEmpty && _controller.isLoading) {
      body = const FullScreenLoading();
    } else if (items.isEmpty && error != null) {
      body = FullScreenError(message: error, onRetry: _retry);
    } else {
      body = RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            PaginatedSliverList<AdminModerationActionView>(
              items: items,
              isLoadingMore: _controller.isLoadingMore,
              hasMore: _controller.hasMore,
              loadMoreError: _controller.loadMoreError,
              refreshError: items.isEmpty ? null : error,
              onRetryRefresh: _retry,
              onRetryLoadMore: _retryLoadMore,
              idOf: _idOf,
              emptyWidget: Center(
                child: Text(
                  _action != null || _community != null || _subject != null
                      ? 'No moderation actions match these filters.'
                      : 'No moderation actions yet.',
                ),
              ),
              itemBuilder: (context, entry, index) {
                final row = DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.navDivider),
                    ),
                  ),
                  child: ModlogEntryTile(
                    action: entry.action,
                    actorHandle: _actorHandles[_actorDidOf(entry)],
                    reversedAction: actionsByRef[entry.action.reverses],
                    privateActorDid: entry.actorDid,
                    privateNote: entry.privateNote,
                    privateSubject: entry.privateSubject,
                    privateContentSnapshot: entry.contentSnapshot,
                    communityHandle: _communityHandles[_communityDidOf(entry)],
                    now: now,
                    onRestore: _offersRestore(entry)
                        ? () => unawaited(_restore(entry))
                        : null,
                    restoring: _restoringRemoval == entry.action.ref,
                  ),
                );
                if (index > 0 &&
                    isSameLocalDay(
                      items[index - 1].action.createdAt,
                      entry.action.createdAt,
                    )) {
                  return row;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DayHeader(
                      label: moderationDayLabel(
                        entry.action.createdAt,
                        now: now,
                      ),
                    ),
                    row,
                  ],
                );
              },
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Stays the colour of the filter bar below it while rows scroll.
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const Flexible(
              child: Text(
                'Moderation log',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_adminLog) const _AdminViewPill(),
          ],
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The label above the first row of each local calendar day.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: AppColors.textMeta,
          ),
        ),
      ),
    );
  }
}

/// Marks the admin log, whose rows carry fields the public log withholds.
class _AdminViewPill extends StatelessWidget {
  const _AdminViewPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            ExcludeSemantics(
              child: LucideGlyph(
                LucidePaths.lock,
                size: 12,
                color: AppColors.coralLight,
              ),
            ),
            Text(
              'Admin view',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.coralLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
