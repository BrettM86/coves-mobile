import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/environment_config.dart';
import '../config/oauth_config.dart';
import '../models/coves_session.dart';
import 'coves_http.dart';
import 'retry_interceptor.dart';

/// Thrown when the user backs out of the OAuth flow without completing it:
/// closing the browser tab, cancelling on the PDS sign-in page, or denying
/// the authorization request. Not an error — no tokens were ever issued.
class SignInCancelledException implements Exception {
  const SignInCancelledException();

  @override
  String toString() => 'Sign in cancelled by user';
}

/// Thrown when the backend definitively rejects the session during a token
/// refresh (HTTP 401): the session is dead and re-authentication is required.
/// Distinct from transient refresh failures (network, 5xx), which are plain
/// [Exception]s — callers that must not destroy a session on a transient
/// failure (e.g. the startup validation probe) catch this type specifically.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'Session expired';
}

/// Thrown when a token refresh completed but its result was discarded
/// because the session changed while the request was in flight (sign-out or
/// re-login raced the refresh). Storage was rewritten to match the session
/// that overtook it, so there is nothing to recover — callers should simply
/// drop the operation.
class SessionRefreshDiscardedException implements Exception {
  const SessionRefreshDiscardedException();

  @override
  String toString() => 'Session changed during refresh; result discarded';
}

/// Thrown by [CovesAuthService.replaceSession] when the account it was
/// replacing was signed out, expired, or swapped for another account before
/// the new session was committed. The new session was not kept, in memory or
/// in storage.
class SessionReplacementDiscardedException implements Exception {
  const SessionReplacementDiscardedException();

  @override
  String toString() => 'Session changed during replacement; result discarded';
}

/// Outcome of probing the backend with the stored session token.
///
/// [indeterminate] means the probe couldn't reach a verdict (network error,
/// timeout, server error) — callers must NOT treat it as invalid, or offline
/// cold starts would sign the user out.
enum SessionValidationResult { valid, invalid, indeterminate }

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

  CovesAuthService._internal({this._dio, FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// Create a new instance for testing with injected dependencies
  @visibleForTesting
  factory CovesAuthService.createTestInstance({
    required Dio dio,
    required FlutterSecureStorage storage,
  }) {
    return CovesAuthService._internal(dio: dio, storage: storage);
  }

  static CovesAuthService? _instance;

  /// Reset the singleton instance (for testing only)
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  // Secure storage for session data
  final FlutterSecureStorage _storage;

  // Storage key is namespaced per environment to prevent token reuse across dev/prod
  // This ensures switching between builds doesn't send prod tokens to dev
  // servers
  String get _storageKey =>
      'coves_session_${EnvironmentConfig.current.environment.name}';

  // HTTP client for API calls - injected for testing or created in initialize()
  Dio? _dio;

  // Current session (cached in memory)
  CovesSession? _session;

  // Completer to track in-flight token refresh operations
  // Ensures only one refresh happens at a time, even with concurrent calls
  Completer<CovesSession>? _refreshCompleter;

  // Share logout attempts and keep new refreshes behind their outcome.
  Completer<void>? _signOutCompleter;

  // The in-flight [replaceSession], which sign-out waits for before deleting
  // credentials so the replacement cannot land after the delete.
  Future<void>? _pendingReplacement;

  /// Get the current session (if any)
  CovesSession? get session => _session;

  /// Check if user is authenticated
  bool get isAuthenticated => _session != null;

  /// Initialize the auth service
  Future<void> initialize() async {
    // Use injected Dio (set in the constructor, for testing) or create one
    if (_dio == null) {
      final dio = createCovesDio();
      // Add retry interceptor for transient network errors
      // Critical for token refresh - don't sign out user on transient failure
      dio.interceptors.add(
        RetryInterceptor(dio: dio, serviceName: 'CovesAuthService'),
      );
      _dio = dio;
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
  /// Returns the new session on success, after [authenticate] then storing
  /// it as the current session.
  /// Throws on error or user cancellation.
  Future<CovesSession> signIn(String handle) async {
    try {
      final session = await authenticate(handle);
      await _saveSession(session);
      _session = session;

      if (kDebugMode) {
        print('Sign-in successful!');
        print('  DID: ${session.did}');
        print('  Handle: ${session.handle}');
      }

      return session;
    } on SignInCancelledException {
      // User backed out of the flow — propagate untouched so callers can
      // treat it as a non-error (no scary message, no crash reporting).
      rethrow;
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Sign-in failed: $e');
      }

      throw Exception('Sign in failed: $e');
    }
  }

  /// Runs the OAuth flow for [handle] and returns the session it produced,
  /// without storing it or making it current.
  ///
  /// Throws [SignInCancelledException] when the user backs out, and any
  /// other exception from the flow or the callback unwrapped.
  Future<CovesSession> authenticate(String handle) async {
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
    final String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: loginUrl,
        callbackUrlScheme: OAuthConfig.callbackScheme,
        options: const FlutterWebAuth2Options(
          preferEphemeral: true, // Don't persist browser session
          timeout: 300, // 5 minutes
        ),
      );
    } on PlatformException catch (e) {
      // flutter_web_auth_2 signals user cancellation (browser dismissed,
      // system auth sheet cancelled) as PlatformException(code: 'CANCELED')
      // on every platform. Detect it via that typed signal, scoped to the
      // authenticate call ONLY, so exceptions from parseCallbackUrl —
      // which can embed server-controlled text like "cancelled" — are
      // never reclassified as a quiet user cancel.
      if (e.code == 'CANCELED') {
        throw const SignInCancelledException();
      }
      rethrow;
    }

    if (kDebugMode) {
      final redactedUrl = redactSensitiveParams(resultUrl);
      print('Received callback URL: $redactedUrl');
    }

    // Parse the callback URL to extract session data
    final session = parseCallbackUrl(resultUrl);

    if (kDebugMode) {
      print('Session created: $session');
    }

    return session;
  }

  /// Saves [session] to secure storage and makes it the current session, only
  /// while the current session is still for the same account ([session]'s
  /// DID).
  ///
  /// A token refresh of that account committed during the write is replaced
  /// too, with storage rewritten so [session] is what stays stored. If the
  /// account is signed out, expires, or changes first, storage is rewritten
  /// to match the current session (emptied when there is none) and this
  /// throws [SessionReplacementDiscardedException]. [signOut] waits for a
  /// pending replacement before deleting credentials.
  ///
  /// A failed write throws and leaves the current session unchanged.
  Future<void> replaceSession(CovesSession session) {
    final replacement = _replaceSession(session);
    _pendingReplacement = replacement;
    return replacement.whenComplete(() {
      if (identical(_pendingReplacement, replacement)) {
        _pendingReplacement = null;
      }
    });
  }

  Future<void> _replaceSession(CovesSession session) async {
    if (_signOutCompleter != null || _session?.did != session.did) {
      throw const SessionReplacementDiscardedException();
    }

    // Anything that changes the session commits after its own storage write
    // or delete, so a change seen after this write means that write may have
    // landed last; write again until no change raced it.
    CovesSession? before;
    do {
      before = _session;
      await _saveSession(session);
    } while (!identical(before, _session) && _session?.did == session.did);

    if (_session?.did != session.did) {
      await _restoreStoredSessionAfterDiscard();
      throw const SessionReplacementDiscardedException();
    }
    _session = session;
  }

  /// Parse an OAuth callback URL into a session.
  ///
  /// The authorization server may redirect back with an error instead of
  /// token parameters — e.g. `error=access_denied` when the user cancels
  /// on the PDS sign-in page or denies the consent screen. That case is
  /// surfaced as [SignInCancelledException]; other server-reported errors
  /// and missing/malformed parameters throw a descriptive [Exception] /
  /// [FormatException].
  @visibleForTesting
  static CovesSession parseCallbackUrl(String resultUrl) {
    final Uri callbackUri;
    final Map<String, String> queryParameters;
    try {
      callbackUri = Uri.parse(resultUrl);
      // Accessing queryParameters forces percent/UTF-8 decoding, which can
      // throw ArgumentError (an Error, not Exception — it would escape every
      // `on Exception` chain and crash) or a FormatException whose message
      // echoes the raw URL (including the token). Convert both to a
      // FormatException with a safe, fixed message.
      queryParameters = callbackUri.queryParameters;
    } on FormatException {
      throw const FormatException('Malformed callback URL');
      // Intentional Error->Exception conversion at the untrusted-input
      // boundary so malformed callbacks can't crash the app:
      // ignore: avoid_catching_errors
    } on ArgumentError {
      throw const FormatException(
        'Malformed callback URL: invalid percent-encoding',
      );
    }

    // The error/error_description params are attacker-influenceable (any app
    // can fire the social.coves custom scheme), so sanitize before embedding
    // them in exception messages that flow to Sentry/logs.
    final oauthError = _sanitizeCallbackText(queryParameters['error']);
    if (oauthError != null) {
      if (kDebugMode) {
        // Sanitized error codes contain no secrets — safe to log.
        print('OAuth callback returned error: $oauthError');
      }
      if (oauthError == 'access_denied') {
        throw const SignInCancelledException();
      }
      final description = _sanitizeCallbackText(
        queryParameters['error_description'],
      );
      final detail = description == null ? '' : ' ($description)';
      throw Exception('Authorization server error: $oauthError$detail');
    }

    try {
      return CovesSession.fromCallbackUri(callbackUri);
      // ignore: avoid_catching_errors
    } on ArgumentError {
      // Uri.decodeComponent inside fromCallbackUri throws ArgumentError on
      // malformed percent-encoding (e.g. token=%ZZ) — convert it to a
      // catchable FormatException so it can't crash the app.
      throw const FormatException(
        'Malformed callback URL: invalid percent-encoding',
      );
    }
  }

  /// Sanitize attacker-influenceable callback text before it is embedded in
  /// exception messages: strip control characters (including newlines) and
  /// cap the length so hostile callbacks can't inject into Sentry/logs.
  ///
  /// Returns null for null, empty, or control-character-only input.
  static String? _sanitizeCallbackText(String? value) {
    if (value == null) {
      return null;
    }
    var sanitized = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    if (sanitized.length > 200) {
      sanitized = '${sanitized.substring(0, 200)}...';
    }
    return sanitized.isEmpty ? null : sanitized;
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
    } on Object catch (e) {
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
  /// Transient failures retain credentials. [SessionExpiredException] means
  /// the rejected session has been invalidated locally.
  Future<CovesSession> refreshToken() async {
    final pendingSignOut = _signOutCompleter;
    if (pendingSignOut != null) {
      await pendingSignOut.future;
      throw const SessionRefreshDiscardedException();
    }

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

    // Capture the session this refresh is FOR. If sign-out or re-login
    // replaces it while the request is in flight, the result must be
    // discarded — committing it would resurrect a session the user just
    // terminated (live token written back to secure storage after logout).
    final sessionAtStart = _session!;

    try {
      if (kDebugMode) {
        print('Refreshing token...');
      }

      // Build request body per backend API contract
      // Backend expects: {"did": "...", "session_id": "...",
      // "sealed_token": "..."}
      final requestBody = {
        'did': sessionAtStart.did,
        'session_id': sessionAtStart.sessionId,
        'sealed_token': sessionAtStart.token,
      };

      final response = await _dio!.post<Map<String, dynamic>>(
        '/oauth/refresh',
        data: requestBody,
      );

      if (!identical(_session, sessionAtStart)) {
        throw const SessionRefreshDiscardedException();
      }

      // Backend returns: {"sealed_token": "...", "access_token": "..."}
      // We use the new sealed_token (which already contains everything we need)
      final newToken = response.data?['sealed_token'] as String?;

      if (newToken == null || newToken.isEmpty) {
        throw Exception('Invalid refresh response: missing sealed_token');
      }

      // Create updated session with new token
      final updatedSession = sessionAtStart.copyWithToken(newToken);

      // signOut() awaits any in-flight refresh before its storage delete, so
      // the delete always lands after this save. A re-login through
      // [replaceSession] does not wait, so it can replace the session while
      // this write is pending; then this write must not stay in storage.
      await _saveSession(updatedSession);
      if (!identical(_session, sessionAtStart)) {
        await _restoreStoredSessionAfterDiscard();
        throw const SessionRefreshDiscardedException();
      }
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

      // The race-discard rule applies to failures too: if sign-out or
      // re-login replaced the session mid-flight, this outcome belongs to
      // a session that no longer exists. Without this check a stale 401
      // would be classified as SessionExpiredException below, and the
      // caller would sign out the race winner's freshly created session.
      if (!identical(_session, sessionAtStart)) {
        const error = SessionRefreshDiscardedException();
        _refreshCompleter!.completeError(error);
        return _refreshCompleter!.future;
      }

      // A definitive rejection needs local cleanup, not another network
      // logout request. Transient failures below preserve the session.
      if (e.response?.statusCode == 401) {
        _session = null;
        try {
          await _clearSession();
          // Plugin errors must not strand callers awaiting the shared refresh.
        } on Object {
          if (kDebugMode) {
            print('Failed to remove expired session from secure storage');
          }
        }
        const error = SessionExpiredException();
        _refreshCompleter!.completeError(error);
        // Return the future to rethrow the error (don't throw directly)
        return _refreshCompleter!.future;
      }

      final error = Exception('Token refresh failed: ${e.message}');
      _refreshCompleter!.completeError(error);
      // Return the future to rethrow the error (don't throw directly)
      return _refreshCompleter!.future;
    } on Object catch (e) {
      // Catch any other errors and propagate them to all waiters
      _refreshCompleter!.completeError(e);
      // Return the future to rethrow the error (don't rethrow directly)
      return _refreshCompleter!.future;
    } finally {
      // Clear the completer so future calls can start a new refresh
      _refreshCompleter = null;
    }
  }

  /// Validate the current session against the backend
  ///
  /// Probes GET /api/me (RequireAuth) with the sealed token. The backend's
  /// read endpoints all use OptionalAuth, which silently degrades a dead
  /// session to anonymous — so without this probe, a user who only browses
  /// never discovers their session is dead (no viewer state, no likes,
  /// no error). See AuthProvider for the startup validation flow.
  ///
  /// Returns:
  /// - [SessionValidationResult.valid]: token unsealed and session live
  /// - [SessionValidationResult.invalid]: backend rejected the token (401) —
  ///   caller should refresh or force re-auth
  /// - [SessionValidationResult.indeterminate]: couldn't tell (no session
  ///   loaded, network error, timeout, 5xx) — caller should keep the session
  Future<SessionValidationResult> validateSession() async {
    if (_session == null || _dio == null) {
      return SessionValidationResult.indeterminate;
    }

    try {
      await _dio!.get<Map<String, dynamic>>(
        '/api/me',
        options: Options(
          headers: {'Authorization': 'Bearer ${_session!.token}'},
        ),
      );
      return SessionValidationResult.valid;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        if (kDebugMode) {
          print('Session validation failed: backend rejected token (401)');
        }
        return SessionValidationResult.invalid;
      }
      // Network errors, timeouts, and server errors are not a verdict on
      // the session - the RetryInterceptor already retried transient ones.
      if (kDebugMode) {
        print(
          'Session validation indeterminate: '
          '${e.response?.statusCode ?? e.type}',
        );
      }
      return SessionValidationResult.indeterminate;
    }
  }

  /// Revoke the server session before clearing local credentials.
  /// Failures preserve the session so the user can retry.
  Future<void> signOut() async {
    if (_signOutCompleter != null) {
      return _signOutCompleter!.future;
    }
    final completer = Completer<void>();
    _signOutCompleter = completer;
    try {
      // A replacement already in flight must commit or discard itself before
      // credentials are deleted, or its write could land after the delete.
      final pendingReplacement = _pendingReplacement;
      if (pendingReplacement != null) {
        try {
          await pendingReplacement;
        } on Object {
          // Its outcome is irrelevant; the session it left is signed out.
        }
      }

      // A refresh already in flight must finish before credentials are deleted.
      if (_refreshCompleter != null) {
        try {
          await _refreshCompleter!.future;
        } on SessionExpiredException {
          // Expiry cleanup already ran; no further request is needed.
          completer.complete();
          return await completer.future;
        } on Exception {
          // A transient refresh failure allows logout with the old token.
        }
      }

      if (_session != null) {
        final response = await _dio!.post<void>(
          '/oauth/logout',
          options: Options(
            headers: {'Authorization': 'Bearer ${_session!.token}'},
          ),
        );
        if (response.statusCode != 200) {
          throw Exception('Server did not confirm sign-out');
        }
      }

      await _clearSession();
      _session = null;
      completer.complete();
      // All waiters must finish even if a plugin throws an Error.
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _signOutCompleter = null;
    }
    return completer.future;
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
    // identifier: method-specific, but generally alphanumeric with some
    // special chars
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
        'Invalid handle format. Handles must be in domain '
        'format (e.g., alice.bsky.social)',
      );
    }

    // Handle format: alphanumeric, hyphens, and periods only
    // No leading/trailing hyphens or periods
    final handlePattern = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$',
    );

    if (!handlePattern.hasMatch(handle)) {
      throw ArgumentError(
        'Invalid handle format. Handles can only contain '
        'letters, numbers, hyphens, '
        'and periods. Each segment must start and end with a letter or number.',
      );
    }

    // Validate each segment (part between periods)
    final segments = handle.split('.');
    for (var i = 0; i < segments.length; i++) {
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

      // TLD (last segment) cannot start with a digit (to avoid confusion
      // with IP addresses)
      // Per atProto spec: numeric segments are allowed in all positions
      // except the TLD
      if (i == segments.length - 1 && RegExp(r'^\d').hasMatch(segment)) {
        throw ArgumentError(
          'Handle TLD (final segment) cannot start with a digit '
          '(got: "$segment")',
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

  /// [_restoreStoredSession] for a discarded write, whose caller always
  /// throws its discard exception: a storage failure here is logged (without
  /// the token) rather than replacing that exception.
  Future<void> _restoreStoredSessionAfterDiscard() async {
    try {
      await _restoreStoredSession();
    } on Object catch (e) {
      if (kDebugMode) {
        print(
          'Failed to rewrite storage after a discarded write '
          '(${e.runtimeType})',
        );
      }
    }
  }

  /// Rewrites storage to match the current session after a discarded write
  /// stored its own. Repeats if the session changes during the write, so the
  /// session that overtook the discarded one is the one left in storage.
  Future<void> _restoreStoredSession() async {
    CovesSession? written;
    do {
      written = _session;
      if (written == null) {
        await _clearSession();
      } else {
        await _saveSession(written);
      }
    } while (!identical(written, _session));
  }

  /// Clear session from secure storage
  Future<void> _clearSession() async {
    await _storage.delete(key: _storageKey);
  }

  /// Redact sensitive parameters from URLs for safe logging
  ///
  /// Replaces token values with `[REDACTED]` to prevent leaking
  /// sealed tokens in debug logs.
  ///
  /// Non-sensitive params like DID, handle, and session_id are preserved
  /// as they're useful for debugging without being security-sensitive.
  @visibleForTesting
  static String redactSensitiveParams(String url) {
    // Replace token=xxx with token=[REDACTED]
    // Matches token= followed by any non-whitespace, non-ampersand characters
    return url.replaceAllMapped(
      RegExp(r'token=([^&\s]+)'),
      (match) => 'token=[REDACTED]',
    );
  }
}
