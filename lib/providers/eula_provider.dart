import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has accepted the current EULA version.
///
/// Uses shared_preferences to persist acceptance state.
/// Increment [currentEulaVersion] when the EULA changes to re-prompt users.
class EulaProvider with ChangeNotifier {
  static const String _eulaAcceptedKey = 'eula_accepted_version';
  static const int currentEulaVersion = 1;

  bool _hasAccepted = false;
  bool _isLoading = true;
  String? _error;

  bool get hasAccepted => _hasAccepted;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acceptedVersion = prefs.getInt(_eulaAcceptedKey) ?? 0;
      _hasAccepted = acceptedVersion >= currentEulaVersion;
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        print('Failed to check EULA acceptance: $e\n$stackTrace');
      }
      // Fail closed - require acceptance if we can't read state
      _hasAccepted = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> acceptEula() async {
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_eulaAcceptedKey, currentEulaVersion);
      _hasAccepted = true;
    } on Exception catch (e, stackTrace) {
      if (kDebugMode) {
        print('Failed to accept EULA: $e\n$stackTrace');
      }
      _error = 'Failed to save EULA acceptance. Please try again.';
    } finally {
      notifyListeners();
    }
  }
}
