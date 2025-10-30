/// Helper for configuring Flutter routers to work with OAuth callbacks.
///
/// When using declarative routing packages (go_router, auto_route, etc.),
/// OAuth callback deep links may be intercepted before flutter_web_auth_2
/// can handle them. This helper provides utilities to configure your router
/// to ignore OAuth callback URIs.
///
/// ## go_router Example
///
/// ```dart
/// final router = GoRouter(
///   routes: [...],
///   redirect: FlutterOAuthRouterHelper.createGoRouterRedirect(
///     customSchemes: ['com.example.myapp'],
///   ),
/// );
/// ```
///
/// ## Manual Configuration
///
/// ```dart
/// final router = GoRouter(
///   routes: [...],
///   redirect: (context, state) {
///     if (FlutterOAuthRouterHelper.isOAuthCallback(
///       state.uri,
///       customSchemes: ['com.example.myapp'],
///     )) {
///       return null; // Let flutter_web_auth_2 handle it
///     }
///     return null; // Normal routing
///   },
/// );
/// ```
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Helper class for configuring routers to work with OAuth callbacks.
class FlutterOAuthRouterHelper {
  /// Checks if a URI is an OAuth callback that should be ignored by the router.
  ///
  /// Returns `true` if the URI uses a custom scheme from [customSchemes],
  /// indicating it's an OAuth callback deep link that flutter_web_auth_2
  /// should handle.
  ///
  /// Example:
  /// ```dart
  /// if (FlutterOAuthRouterHelper.isOAuthCallback(
  ///   uri,
  ///   customSchemes: ['com.example.myapp'],
  /// )) {
  ///   // This is an OAuth callback - don't route it
  ///   return null;
  /// }
  /// ```
  static bool isOAuthCallback(Uri uri, {required List<String> customSchemes}) {
    return customSchemes.contains(uri.scheme);
  }

  /// Creates a redirect function for go_router that ignores OAuth callbacks.
  ///
  /// This is a convenience method that returns a redirect function you can
  /// pass directly to GoRouter's `redirect` parameter.
  ///
  /// Parameters:
  /// - [customSchemes]: List of custom URL schemes used for OAuth callbacks
  ///   (e.g., `['com.example.myapp']`)
  /// - [fallbackRedirect]: Optional custom redirect logic for non-OAuth URIs
  ///
  /// Example:
  /// ```dart
  /// final router = GoRouter(
  ///   routes: [...],
  ///   redirect: FlutterOAuthRouterHelper.createGoRouterRedirect(
  ///     customSchemes: ['com.example.myapp'],
  ///   ),
  /// );
  /// ```
  ///
  /// With custom redirect logic:
  /// ```dart
  /// final router = GoRouter(
  ///   routes: [...],
  ///   redirect: FlutterOAuthRouterHelper.createGoRouterRedirect(
  ///     customSchemes: ['com.example.myapp'],
  ///     fallbackRedirect: (context, state) {
  ///       // Your custom auth redirect logic
  ///       if (!isAuthenticated) return '/login';
  ///       return null;
  ///     },
  ///   ),
  /// );
  /// ```
  static FutureOr<String?> Function(BuildContext, dynamic)
  createGoRouterRedirect({
    required List<String> customSchemes,
    FutureOr<String?> Function(BuildContext, dynamic)? fallbackRedirect,
  }) {
    return (BuildContext context, dynamic state) {
      // Extract URI from the state object (works with any router's state object that has a 'uri' property)
      final uri = (state as dynamic).uri as Uri;

      // Check if this is an OAuth callback
      if (isOAuthCallback(uri, customSchemes: customSchemes)) {
        // Let flutter_web_auth_2 handle OAuth callbacks
        if (kDebugMode) {
          print('🔀 RouterHelper: Detected OAuth callback - allowing through');
          print('   URI: $uri');
        }
        return null;
      }

      // Apply custom redirect logic if provided
      if (fallbackRedirect != null) {
        return fallbackRedirect(context, state);
      }

      // No redirect needed
      return null;
    };
  }

  /// Extracts the scheme from a redirect URI.
  ///
  /// This is useful for getting the custom scheme from your OAuth configuration.
  ///
  /// Example:
  /// ```dart
  /// final scheme = FlutterOAuthRouterHelper.extractScheme(
  ///   'com.example.myapp:/oauth/callback'
  /// );
  /// // Returns: 'com.example.myapp'
  /// ```
  static String extractScheme(String redirectUri) {
    final uri = Uri.parse(redirectUri);
    return uri.scheme;
  }
}
