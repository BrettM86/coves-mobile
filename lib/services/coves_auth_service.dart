import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/environment_config.dart';
import '../config/oauth_config.dart';
import '../models/coves_session.dart';
import 'retry_interceptor.dart';

/// Coves Authentication Service
///
/// Simplified OAuth service that uses the Coves backend's mobile OAuth flow.
/// The backend handles all the complexity:
/// - PKCE generation
/// - DPoP key management
/// - Token exchange with PDS
/// - Token sealing (AES-256-GCM encryption)
/// - CSRF protection
///
/// This client just needs to:
/// 1. Open browser to backend's /oauth/mobile/login
/// 2. Receive sealed token via Universal Link / custom scheme
/// 3. Store and use the sealed token
/// 4. Call /oauth/refresh when needed
/// 5. Call /oauth/logout to sign out
class CovesAuthService {
  factory CovesAuthService({Dio? dio, FlutterSecureStorage? storage}) {
    _instance ??= CovesAuthService._internal(dio: dio, storage: storage);
    return _instance!;
  }

  CovesAuthService._internal({Dio? dio, FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          ),
      _injectedDio = dio;

  static CovesAuthService? _instance;

  /// Reset the singleton instance (for testing only)
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  /// Create a new instance for testing with injected dependencies
  @visibleForTesting
  static CovesAuthService createTestInstance({
    required Dio dio,
    required FlutterSecureStorage storage,
  }) {
    return CovesAuthService._internal(dio: dio, storage: storage);
  }

  // Secure storage for session data
  final FlutterSecureStorage _storage;

  // Storage key is namespaced per environment to prevent token reuse across dev/prod
  // This ensures switching between builds doesn't send prod tokens to dev servers
  String get _storageKey =>
      'coves_session_${EnvironmentConfig.current.environment.name}';

  // HTTP client for API calls - injected for testing or created in initialize()
  final Dio? _injectedDio;
  Dio? _dio;

  // Current session (cached in memory)
  CovesSession? _session;

  // Completer to track in-flight token refresh operations
  // Ensures only one refresh happens at a time, even with concurrent calls
  Completer<CovesSession>? _refreshCompleter;

  /// Get the current session (if any)
  CovesSession? get session => _session;

  /// Check if user is authenticated
  bool get isAuthenticated => _session != null;

  /// Initialize the auth service
  Future<void> initialize() async {
    // Use injected Dio (for testing) or create a new one
    if (_dio == null) {
      if (_injectedDio != null) {
        _dio = _injectedDio;
      } else {
        final dio = Dio(
          BaseOptions(
            baseUrl: EnvironmentConfig.current.apiUrl,
            // Shorter timeout with retries for mobile network resilience
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        // Add retry interceptor for transient network errors
        // Critical for token refresh - don't sign out user on transient failure
        dio.interceptors.add(
          RetryInterceptor(
            dio: dio,
            maxRetries: 2,
            serviceName: 'CovesAuthService',
          ),
        );
        _dio = dio;
      }
    }

    if (kDebugMode) {
      print('CovesAuthService initialized');
      print('  API URL: ${EnvironmentConfig.current.apiUrl}');
      print('  Redirect URI: ${OAuthConfig.redirectUri}');
    }
  }

  /// Sign in with an atProto handle
  ///
  /// Opens the system browser to the backend's mobile OAuth endpoint.
  /// The backend handles the complete OAuth flow with the user's PDS.
  /// On success, redirects back to the app with sealed token parameters.
  ///
  /// Returns the new session on success.
  /// Throws on error or user cancellation.
  Future<CovesSession> signIn(String handle) async {
    try {
      final normalizedHandle = validateAndNormalizeHandle(handle);

      if (kDebugMode) {
        print('Starting sign-in for: $normalizedHandle');
      }

      // Build the OAuth login URL
      final loginUrl = _buildLoginUrl(normalizedHandle);

      if (kDebugMode) {
        print('Opening browser: $loginUrl');
        print('Callback scheme: ${OAuthConfig.callbackScheme}');
      }

      // Open browser for OAuth flow
      // Backend redirects to custom scheme: social.coves:/callback
      final resultUrl = await FlutterWebAuth2.authenticate(
        url: loginUrl,
        callbackUrlScheme: OAuthConfig.callbackScheme,
        options: const FlutterWebAuth2Options(
          preferEphemeral: true, // Don't persist browser session
          timeout: 300, // 5 minutes
        ),
      );

      if (kDebugMode) {
        final redactedUrl = _redactSensitiveParams(resultUrl);
        print('Received callback URL: $redactedUrl');
      }

      // Parse the callback URL to extract session data
      final callbackUri = Uri.parse(resultUrl);
      final session = CovesSession.fromCallbackUri(callbackUri);

      if (kDebugMode) {
        print('Session created: $session');
      }

      // Store the session securely
      await _saveSession(session);

      // Cache in memory
      _session = session;

      if (kDebugMode) {
        print('Sign-in successful!');
        print('  DID: ${session.did}');
        print('  Handle: ${session.handle}');
      }

      return session;
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Sign-in failed: $e');
      }

      // Check for user cancellation
      if (e.toString().contains('CANCELED') ||
          e.toString().contains('cancelled')) {
        throw Exception('Sign in cancelled by user');
      }

      throw Exception('Sign in failed: $e');
    }
  }

  /// Restore a previous session from secure storage
  ///
  /// Returns the session if found and valid, null otherwise.
  Future<CovesSession?> restoreSession() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);

      if (jsonString == null) {
        if (kDebugMode) {
          print('No stored session found');
        }
        return null;
      }

      final session = CovesSession.fromJsonString(jsonString);

      if (kDebugMode) {
        print('Session restored: $session');
      }

      // Cache in memory
      _session = session;

      return session;
    } catch (e) {
      // Catch all errors including:
      // - FormatException/TypeError from malformed JSON (data corruption)
      // - PlatformException from secure storage access failures
      // - Any other unexpected errors
      //
      // We treat all errors the same (clear and return null) because:
      // 1. Data corruption: The stored data is unusable, clearing is correct
      // 2. Storage access errors: Retrying won't help, user needs to re-auth
      // 3. Both cases require the user to sign in again anyway
      //
      // The specific error type is logged in debug mode for troubleshooting.
      if (kDebugMode) {
        print('Failed to restore session (${e.runtimeType}): $e');
      }

      // Clear potentially corrupted data
      await _storage.delete(key: _storageKey);
      return null;
    }
  }

  /// Refresh the current session token
  ///
  /// Calls the backend's /oauth/refresh endpoint to get a new sealed token.
  /// The backend handles the actual token refresh with the PDS.
  ///
  /// Uses a mutex pattern to ensure only one refresh operation is in-flight
  /// at a time. If multiple callers request a refresh simultaneously, they
  /// will all wait for and receive the same refreshed session.
  ///
  /// Returns the updated session on success.
  /// Throws on error (caller should handle by signing out).
  Future<CovesSession> refreshToken() async {
    if (_session == null) {
      throw StateError('No session to refresh');
    }

    // If a refresh is already in progress, wait for it and return its result
    if (_refreshCompleter != null) {
      if (kDebugMode) {
        print('Token refresh already in progress, waiting...');
      }
      return _refreshCompleter!.future;
    }

    // Start a new refresh operation
    _refreshCompleter = Completer<CovesSession>();

    try {
      if (kDebugMode) {
        print('Refreshing token...');
      }

      // Build request body per backend API contract
      // Backend expects: {"did": "...", "session_id": "...", "sealed_token": "..."}
      final requestBody = {
        'did': _session!.did,
        'session_id': _session!.sessionId,
        'sealed_token': _session!.token,
      };

      final response = await _dio!.post<Map<String, dynamic>>(
        '/oauth/refresh',
        data: requestBody,
      );

      // Backend returns: {"sealed_token": "...", "access_token": "..."}
      // We use the new sealed_token (which already contains everything we need)
      final newToken = response.data?['sealed_token'] as String?;

      if (newToken == null || newToken.isEmpty) {
        throw Exception('Invalid refresh response: missing sealed_token');
      }

      // Create updated session with new token
      final updatedSession = _session!.copyWithToken(newToken);

      // Save and cache
      await _saveSession(updatedSession);
      _session = updatedSession;

      if (kDebugMode) {
        print('Token refreshed successfully');
      }

      // Complete the future with the updated session
      _refreshCompleter!.complete(updatedSession);
      return updatedSession;
    } on DioException catch (e) {
      if (kDebugMode) {
        print('Token refresh failed: ${e.message}');
        print('Status code: ${e.response?.statusCode}');
      }

      // 401 means session is invalid/expired - caller should sign out
      if (e.response?.statusCode == 401) {
        final error = Exception('Session expired');
        _refreshCompleter!.completeError(error);
        // Return the future to rethrow the error (don't throw directly)
        return _refreshCompleter!.future;
      }

      final error = Exception('Token refresh failed: ${e.message}');
      _refreshCompleter!.completeError(error);
      // Return the future to rethrow the error (don't throw directly)
      return _refreshCompleter!.future;
    } catch (e) {
      // Catch any other errors and propagate them to all waiters
      _refreshCompleter!.completeError(e);
      // Return the future to rethrow the error (don't rethrow directly)
      return _refreshCompleter!.future;
    } finally {
      // Clear the completer so future calls can start a new refresh
      _refreshCompleter = null;
    }
  }

  /// Sign out and revoke the session
  ///
  /// Calls the backend's /oauth/logout endpoint to revoke the session.
  /// The backend handles token revocation with the PDS.
  /// Always clears local storage even if server call fails.
  Future<void> signOut() async {
    try {
      if (_session != null) {
        if (kDebugMode) {
          print('Signing out...');
        }

        // Best-effort server-side revocation
        try {
          await _dio!.post<void>(
            '/oauth/logout',
            options: Options(
              headers: {'Authorization': 'Bearer ${_session!.token}'},
            ),
          );

          if (kDebugMode) {
            print('Server-side logout successful');
          }
        } on DioException catch (e) {
          // Log but don't fail - we still want to clear local state
          if (kDebugMode) {
            print('Server-side logout failed: ${e.message}');
          }
        }
      }
    } finally {
      // Always clear local state
      await _clearSession();
      _session = null;

      if (kDebugMode) {
        print('Local session cleared');
      }
    }
  }

  /// Get the current access token
  ///
  /// Returns the sealed token for use in API requests.
  /// Returns null if not authenticated.
  String? getToken() {
    return _session?.token;
  }

  /// Validate and normalize an atProto handle or DID
  ///
  /// Accepts:
  /// - Handles: alice.bsky.social, @alice.bsky.social
  /// - DIDs: did:plc:abc123, did:web:example.com
  /// - URLs: https://bsky.app/profile/alice.bsky.social (extracts handle)
  ///
  /// Returns the normalized handle/DID.
  /// Throws ArgumentError if invalid.
  @visibleForTesting
  String validateAndNormalizeHandle(String handle) {
    // Trim whitespace
    var normalized = handle.trim();

    // Check for empty input
    if (normalized.isEmpty) {
      throw ArgumentError('Handle cannot be empty');
    }

    // Extract handle from Bluesky profile URLs
    // e.g., https://bsky.app/profile/alice.bsky.social -> alice.bsky.social
    final urlPattern = RegExp(
      r'^https?://(?:www\.)?bsky\.app/profile/([^/?#]+)',
      caseSensitive: false,
    );
    final urlMatch = urlPattern.firstMatch(normalized);
    if (urlMatch != null) {
      normalized = urlMatch.group(1)!;
    }

    // Strip leading @ if present (common user input)
    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    // Check maximum length (atProto spec: 253 characters for handles)
    if (normalized.length > 253) {
      throw ArgumentError(
        'Handle too long (max 253 characters, got ${normalized.length})',
      );
    }

    // Validate DID format
    if (normalized.startsWith('did:')) {
      return _validateDid(normalized);
    }

    // Validate handle format
    return _validateHandle(normalized);
  }

  /// Validate a DID (Decentralized Identifier)
  ///
  /// Supports:
  /// - did:plc:abc123
  /// - did:web:example.com
  ///
  /// Throws ArgumentError if invalid.
  String _validateDid(String did) {
    // DID format: did:method:identifier
    // method: lowercase alphanumeric
    // identifier: method-specific, but generally alphanumeric with some special chars
    final didPattern = RegExp(r'^did:[a-z0-9]+:[a-zA-Z0-9._:%-]+$');

    if (!didPattern.hasMatch(did)) {
      throw ArgumentError(
        'Invalid DID format. Expected format: did:method:identifier',
      );
    }

    return did;
  }

  /// Validate a handle (domain name format)
  ///
  /// Handles must:
  /// - Contain only alphanumeric characters, hyphens, and periods
  /// - Not start or end with a hyphen or period
  /// - Have at least one period (domain format)
  /// - Each segment between periods must be valid (1-63 chars)
  /// - TLD (final segment) cannot start with a digit (per atProto spec)
  /// - Numeric segments are allowed in all positions except the TLD
  ///
  /// Throws ArgumentError if invalid.
  String _validateHandle(String handle) {
    // Handle must contain at least one period (domain format)
    if (!handle.contains('.')) {
      throw ArgumentError(
        'Invalid handle format. Handles must be in domain format (e.g., alice.bsky.social)',
      );
    }

    // Handle format: alphanumeric, hyphens, and periods only
    // No leading/trailing hyphens or periods
    final handlePattern = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$',
    );

    if (!handlePattern.hasMatch(handle)) {
      throw ArgumentError(
        'Invalid handle format. Handles can only contain letters, numbers, hyphens, '
        'and periods. Each segment must start and end with a letter or number.',
      );
    }

    // Validate each segment (part between periods)
    final segments = handle.split('.');
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.isEmpty) {
        throw ArgumentError('Handle cannot have empty segments');
      }

      // Each segment must not exceed 63 characters (DNS label limit)
      if (segment.length > 63) {
        throw ArgumentError(
          'Handle segment "$segment" too long (max 63 characters)',
        );
      }

      // TLD (last segment) cannot start with a digit (to avoid confusion with IP addresses)
      // Per atProto spec: numeric segments are allowed in all positions except the TLD
      if (i == segments.length - 1 && RegExp(r'^\d').hasMatch(segment)) {
        throw ArgumentError(
          'Handle TLD (final segment) cannot start with a digit (got: "$segment")',
        );
      }
    }

    return handle.toLowerCase();
  }

  /// Build the OAuth login URL
  String _buildLoginUrl(String handle) {
    final baseUrl = EnvironmentConfig.current.apiUrl;
    final redirectUri = OAuthConfig.redirectUri;

    return '$baseUrl/oauth/mobile/login'
        '?handle=${Uri.encodeComponent(handle)}'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}';
  }

  /// Save session to secure storage
  Future<void> _saveSession(CovesSession session) async {
    await _storage.write(key: _storageKey, value: session.toJsonString());
  }

  /// Clear session from secure storage
  Future<void> _clearSession() async {
    await _storage.delete(key: _storageKey);
  }

  /// Redact sensitive parameters from URLs for safe logging
  ///
  /// Replaces token values with [REDACTED] to prevent leaking
  /// sealed tokens in debug logs.
  ///
  /// Non-sensitive params like DID, handle, and session_id are preserved
  /// as they're useful for debugging without being security-sensitive.
  String _redactSensitiveParams(String url) {
    // Replace token=xxx with token=[REDACTED]
    // Matches token= followed by any non-whitespace, non-ampersand characters
    return url.replaceAllMapped(
      RegExp(r'token=([^&\s]+)'),
      (match) => 'token=[REDACTED]',
    );
  }
}
