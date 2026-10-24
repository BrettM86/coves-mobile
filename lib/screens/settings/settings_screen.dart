import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/notification_preferences_provider.dart';
import '../../services/api_exceptions.dart';
import '../../utils/error_messages.dart';
import '../../widgets/icons/lucide_icon_painter.dart';
import '../../widgets/icons/lucide_paths.dart';
import '../../widgets/loading_error_states.dart';
import '../../widgets/primary_button.dart';

const _sectionInset = 16.0;
const _sectionRadius = 16.0;
const _rowPadding = 16.0;
const _rowMinHeight = 60.0;

// On: a white thumb on a solid coral track. Off: a white thumb on a muted
// gray track, which stays visible on the section's background. Neither has
// an outline.
final _switchThumbColor = WidgetStateProperty.all<Color>(AppColors.textPrimary);
final _switchTrackColor = WidgetStateProperty.resolveWith<Color>(
  (states) => states.contains(WidgetState.selected)
      ? AppColors.coral
      : AppColors.textMuted,
);
final _switchTrackOutlineColor = WidgetStateProperty.all<Color>(
  Colors.transparent,
);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Values changed elsewhere since the last open, or a failed load, are
    // fetched again; a queued toggle keeps what is shown.
    context.read<NotificationPreferencesProvider>().reloadOnOpen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs on open and whenever the provider notifies, so a new session
    // loads once while Settings is shown.
    context.read<NotificationPreferencesProvider>().loadIfNeeded();
  }

  void _toggle(
    NotificationPreferencesProvider preferences,
    NotificationPreferenceKey key,
  ) {
    // Captured now so a failure still shows after Settings is closed.
    final messenger = ScaffoldMessenger.of(context);
    preferences.toggle(
      key,
      onFailure: (error) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException && error.errorCode == 'AccountNotIndexed'
                ? 'Your account is still being set up. Try again in a minute.'
                : ErrorMessage.notificationPreferences(error),
          ),
        ),
      ),
    );
  }

  Widget _switch(
    NotificationPreferencesProvider preferences,
    String label,
    NotificationPreferenceKey key,
  ) => SwitchListTile(
    title: Text(
      label,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
    ),
    value: preferences.valueFor(key),
    onChanged: (_) => _toggle(preferences, key),
    contentPadding: const EdgeInsets.symmetric(horizontal: _rowPadding),
    minTileHeight: _rowMinHeight,
    thumbColor: _switchThumbColor,
    trackColor: _switchTrackColor,
    trackOutlineColor: _switchTrackOutlineColor,
  );

  /// A rounded group of rows split by hairlines inset from the leading edge.
  Widget _section(List<Widget> rows) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _sectionInset),
    child: Material(
      color: AppColors.backgroundSecondary,
      borderRadius: BorderRadius.circular(_sectionRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 0.5,
                thickness: 0.5,
                indent: _rowPadding,
                color: AppColors.border,
              ),
            rows[index],
          ],
        ],
      ),
    ),
  );

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
            const SizedBox(height: 16),
            const Text(
              'Sign in to manage your notification settings',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              title: 'Sign in',
              onPressed: () => context.push('/login'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<NotificationPreferencesProvider>();
    final Widget body;
    if (!preferences.isSignedIn) {
      body = _buildSignedOutPrompt();
    } else if (!preferences.isLoaded) {
      final loadError = preferences.loadError;
      body = loadError != null
          ? FullScreenError(
              message: ErrorMessage.notificationPreferences(
                loadError,
                isLoad: true,
              ),
              onRetry: preferences.retry,
            )
          : const FullScreenLoading();
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              _sectionInset + _rowPadding,
              24,
              _sectionInset,
              10,
            ),
            child: Text(
              'Notifications',
              style: TextStyle(color: AppColors.textMeta, fontSize: 14),
            ),
          ),
          _section([
            _switch(
              preferences,
              'Replies to your posts',
              NotificationPreferenceKey.postReply,
            ),
            _switch(
              preferences,
              'Replies to your comments',
              NotificationPreferenceKey.commentReply,
            ),
            _switch(preferences, 'Mentions', NotificationPreferenceKey.mention),
            _switch(preferences, 'Likes', NotificationPreferenceKey.upvote),
          ]),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: body,
    );
  }
}
