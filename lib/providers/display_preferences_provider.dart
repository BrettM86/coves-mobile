import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local display settings, saved with shared_preferences.
class DisplayPreferencesProvider with ChangeNotifier {
  static const String showSoftwareLogosKey = 'show_software_logos';

  bool _showSoftwareLogos = true;

  /// Whether Lemmy and PieFed logos show next to bridged communities.
  bool get showSoftwareLogos => _showSoftwareLogos;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    // A value of another type (never written by this app) keeps the default
    // instead of failing startup.
    final stored = prefs.get(showSoftwareLogosKey);
    _showSoftwareLogos = stored is! bool || stored;
    notifyListeners();
  }

  /// Applies [value] at once; a failed save keeps it for this run only.
  // Positional so it tears off as a Switch's onChanged.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setShowSoftwareLogos(bool value) async {
    if (value == _showSoftwareLogos) {
      return;
    }
    _showSoftwareLogos = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(showSoftwareLogosKey, value);
      if (!saved) {
        await Sentry.captureMessage(
          'show_software_logos save returned false',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('phase', 'display_preferences_save');
          },
        );
      }
    } on Exception catch (error, stackTrace) {
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('phase', 'display_preferences_save');
        },
      );
    }
  }
}
