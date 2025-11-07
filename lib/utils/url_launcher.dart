import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utility class for safely launching external URLs
///
/// Provides security validation and error handling for opening URLs
/// in external browsers or applications.
class UrlLauncher {
  UrlLauncher._(); // Private constructor to prevent instantiation

  /// Allowed URL schemes for security
  static const _allowedSchemes = ['http', 'https'];

  /// Launches an external URL with security validation
  ///
  /// Returns true if the URL was successfully launched, false otherwise.
  ///
  /// Security:
  /// - Only allows http and https schemes
  /// - Blocks potentially malicious schemes (javascript:, file:, etc.)
  /// - Opens in external browser for user control
  ///
  /// If [context] is provided and mounted, shows a user-friendly error message
  /// when the URL cannot be opened.
  static Future<bool> launchExternalUrl(
    String url, {
    BuildContext? context,
  }) async {
    try {
      final uri = Uri.parse(url);

      // Validate URL scheme for security
      if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) {
        if (kDebugMode) {
          debugPrint('Blocked non-http(s) URL scheme: ${uri.scheme}');
        }
        _showErrorIfPossible(context, 'Invalid link format');
        return false;
      }

      // Check if URL can be launched
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (kDebugMode) {
        debugPrint('Could not launch URL: $url');
      }
      // ignore: use_build_context_synchronously
      _showErrorIfPossible(context, 'Could not open link');
      return false;
    } on FormatException catch (e) {
      if (kDebugMode) {
        debugPrint('Invalid URL format: $url - $e');
      }
      // ignore: use_build_context_synchronously
      _showErrorIfPossible(context, 'Invalid link format');
      return false;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error launching URL: $url - $e');
      }
      // ignore: use_build_context_synchronously
      _showErrorIfPossible(context, 'Could not open link');
      return false;
    }
  }

  /// Shows an error snackbar if context is available and mounted
  static void _showErrorIfPossible(BuildContext? context, String message) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
