import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/notification_preferences.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'notification_preferences_change_signal.dart';
import 'unread_notification_count_provider.dart';

enum NotificationPreferenceKey { postReply, commentReply, mention, upvote }

typedef _PendingChange = ({
  NotificationPreferenceKey key,
  bool value,
  void Function(Object error) onFailure,
});

/// The signed-in session's notification preferences: the loaded values, the
/// toggles not yet confirmed, the serial update queue and the load error.
///
/// App-wide, so the queue outlives the Settings screen: a reopened screen
/// shows and extends the same queue, and reloads the values when nothing is
/// queued ([reloadOnOpen]). Everything belongs to one session
/// (`sessionKeyOf`): a session change drops it all at once, a request that
/// completes under an older session is ignored, and nothing is sent while
/// signed out.
class NotificationPreferencesProvider extends ChangeNotifier {
  NotificationPreferencesProvider({
    required this._apiService,
    required this._authProvider,
    required this._sessionKeyOf,
    required this._unreadNotificationCountProvider,
    required this._changeSignal,
  }) {
    _sessionKey = _sessionKeyOf();
    _authProvider.addListener(_onAuthChanged);
  }

  final CovesApiService _apiService;
  final AuthProvider _authProvider;
  final Object? Function() _sessionKeyOf;
  final UnreadNotificationCountProvider _unreadNotificationCountProvider;
  final NotificationPreferencesChangeSignal _changeSignal;

  Object? _sessionKey;
  NotificationPreferences? _server;
  Object? _loadError;
  bool _isLoading = false;
  final Queue<_PendingChange> _pending = Queue();
  bool _isSending = false;
  bool _isDisposed = false;

  /// Toggles queued so far, so a load can tell one was queued after it began.
  int _toggleCount = 0;

  bool get isSignedIn => _sessionKey != null;

  bool get isLoaded => _server != null;

  /// The last load failure of this session, until a [retry] or
  /// [reloadOnOpen].
  Object? get loadError => _loadError;

  /// The value to show for [key]: the server's, overlaid with every toggle
  /// not yet confirmed. Only valid while [isLoaded].
  bool valueFor(NotificationPreferenceKey key) {
    final server = _server!;
    var value = switch (key) {
      NotificationPreferenceKey.postReply => server.postReply,
      NotificationPreferenceKey.commentReply => server.commentReply,
      NotificationPreferenceKey.mention => server.mention,
      NotificationPreferenceKey.upvote => server.upvote,
    };
    for (final change in _pending) {
      if (change.key == key) {
        value = change.value;
      }
    }
    return value;
  }

  /// Loads this session's preferences unless they are loaded, loading or
  /// failed (a failure waits for [retry] or [reloadOnOpen]). Changes nothing
  /// visible until the response arrives, so a screen may call it while
  /// building.
  void loadIfNeeded() {
    if (_server != null || _isLoading || _loadError != null) {
      return;
    }
    _startLoad();
  }

  /// Loads this session's preferences again when a screen opens, so changes
  /// made elsewhere show and an earlier load failure is retried. Skipped
  /// while a load is running or a toggle is queued or sending; the loaded
  /// values stay shown until the response arrives. Does not notify, so a
  /// screen may call it from `initState`.
  void reloadOnOpen() {
    if (_liveSessionKey == null ||
        _isLoading ||
        _isSending ||
        _pending.isNotEmpty) {
      return;
    }
    _loadError = null;
    _startLoad();
  }

  void retry() {
    if (_liveSessionKey == null || _server != null || _isLoading) {
      return;
    }
    _loadError = null;
    notifyListeners();
    _startLoad();
  }

  /// Flips [key] at once and queues its update behind any update in flight.
  /// [onFailure] runs if the update fails while this session is current.
  void toggle(
    NotificationPreferenceKey key, {
    required void Function(Object error) onFailure,
  }) {
    final sessionKey = _liveSessionKey;
    if (sessionKey == null || _server == null) {
      return;
    }
    _pending.add((key: key, value: !valueFor(key), onFailure: onFailure));
    _toggleCount++;
    notifyListeners();
    if (!_isSending) {
      unawaited(_sendPending(sessionKey));
    }
  }

  /// The session key when it is signed in and matches the session this
  /// provider holds, else null.
  Object? get _liveSessionKey {
    final sessionKey = _sessionKeyOf();
    return sessionKey != null && sessionKey == _sessionKey ? sessionKey : null;
  }

  bool _isStale(Object sessionKey) => _isDisposed || sessionKey != _sessionKey;

  void _startLoad() {
    final sessionKey = _liveSessionKey;
    if (sessionKey == null) {
      return;
    }
    _isLoading = true;
    unawaited(_load(sessionKey));
  }

  /// Drops a response that was requested before a toggle was queued: it may
  /// predate that toggle's update, so it would overwrite a newer value.
  Future<void> _load(Object sessionKey) async {
    final toggleCountAtStart = _toggleCount;
    try {
      final preferences = await _apiService.getNotificationPreferences();
      if (_isStale(sessionKey)) {
        return;
      }
      if (_toggleCount == toggleCountAtStart) {
        _server = preferences;
      }
    } on Object catch (error) {
      if (_isStale(sessionKey)) {
        return;
      }
      _loadError = error;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<NotificationPreferences> _send(_PendingChange change) =>
      switch (change.key) {
        NotificationPreferenceKey.postReply =>
          _apiService.putNotificationPreferences(postReply: change.value),
        NotificationPreferenceKey.commentReply =>
          _apiService.putNotificationPreferences(commentReply: change.value),
        NotificationPreferenceKey.mention =>
          _apiService.putNotificationPreferences(mention: change.value),
        NotificationPreferenceKey.upvote =>
          _apiService.putNotificationPreferences(upvote: change.value),
      };

  /// Sends [sessionKey]'s queue in tap order. Stops without touching any
  /// state once the session changes; the next session has its own queue.
  Future<void> _sendPending(Object sessionKey) async {
    _isSending = true;
    while (_pending.isNotEmpty) {
      if (_liveSessionKey != sessionKey) {
        break;
      }
      final change = _pending.first;
      final NotificationPreferences response;
      try {
        response = await _send(change);
      } on Object catch (error) {
        if (_isStale(sessionKey)) {
          return;
        }
        _pending.removeFirst();
        notifyListeners();
        change.onFailure(error);
        continue;
      }
      if (_isStale(sessionKey)) {
        return;
      }
      _server = response;
      _pending.removeFirst();
      notifyListeners();
      _changeSignal.bump();
      unawaited(_unreadNotificationCountProvider.refresh());
    }
    _isSending = false;
  }

  void _onAuthChanged() {
    final sessionKey = _sessionKeyOf();
    if (sessionKey == _sessionKey) {
      return;
    }
    _sessionKey = sessionKey;
    _server = null;
    _loadError = null;
    _isLoading = false;
    _pending.clear();
    _isSending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}
