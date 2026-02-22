import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has accepted the current community guidelines version.
///
/// Uses shared_preferences to persist acceptance state.
/// Increment [currentVersion] when the guidelines change to re-prompt users.
class CommunityGuidelinesProvider with ChangeNotifier {
  static const String _acceptedKey = 'community_guidelines_accepted_version';
  static const int currentVersion = 1;

  bool _hasAccepted = false;
  bool _isLoading = true;
  String? _error;

  bool get hasAccepted => _hasAccepted;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acceptedVersion = prefs.getInt(_acceptedKey) ?? 0;
      _hasAccepted = acceptedVersion >= currentVersion;
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        print('Failed to check community guidelines acceptance: $e\n$stackTrace');
      }
      await Sentry.captureException(e, stackTrace: stackTrace, withScope: (scope) {
        scope.setTag('phase', 'community_guidelines_initialization');
      });
      // Fail closed - require acceptance if we can't read state
      _hasAccepted = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> accept() async {
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_acceptedKey, currentVersion);
      _hasAccepted = true;
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        print('Failed to accept community guidelines: $e\n$stackTrace');
      }
      await Sentry.captureException(e, stackTrace: stackTrace, withScope: (scope) {
        scope.setTag('phase', 'community_guidelines_acceptance');
      });
      _error = 'Failed to save acceptance. Please try again.';
    } finally {
      notifyListeners();
    }
  }
}
