import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coves_session.dart';
import '../services/coves_auth_service.dart';

/// Authentication Provider
///
/// Manages authentication state using the Coves backend OAuth flow.
/// Uses ChangeNotifier for reactive state updates across the app.
///
/// Key features:
/// - Uses CovesAuthService for backend-managed OAuth
/// - Tokens are sealed (AES-256-GCM encrypted) and opaque to the client
/// - Backend handles DPoP, PKCE, and token refresh internally
/// - Session stored securely (iOS Keychain / Android EncryptedSharedPreferences)
class AuthProvider with ChangeNotifier {
  /// Constructor with optional auth service for dependency injection
  AuthProvider({CovesAuthService? authService})
    : _authService = authService ?? CovesAuthService();
  final CovesAuthService _authService;

  // Session state
  CovesSession? _session;
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _error;

  // Getters
  CovesSession? get session => _session;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get did => _session?.did;
  String? get handle => _session?.handle;

  /// Get the current access token (sealed token)
  ///
  /// Returns the sealed token for API authentication.
  /// The token is opaque to the client - backend handles everything.
  ///
  /// If token refresh fails, attempts to refresh automatically.
  /// If refresh fails, signs out the user.
  Future<String?> getAccessToken() async {
    if (_session == null) {
      return null;
    }

    // Return the sealed token directly
    // Token refresh is handled by the backend when the token is used
    return _session!.token;
  }

  /// Initialize the provider and restore any existing session
  ///
  /// This is called on app startup to:
  /// 1. Initialize the auth service
  /// 2. Restore session from secure storage if available
  Future<void> initialize() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Initialize auth service
      await _authService.initialize();

      // Try to restore a previous session from secure storage
      final restoredSession = await _authService.restoreSession();

      if (restoredSession != null) {
        _session = restoredSession;
        _isAuthenticated = true;

        if (kDebugMode) {
          print('Restored session');
          print('   DID: ${restoredSession.did}');
          print('   Handle: ${restoredSession.handle}');
        }

        // Validate the restored session in the background (never block cold
        // start on the network). All read endpoints are OptionalAuth and
        // silently degrade a dead session to anonymous, so without this
        // probe a browsing-only user would stay half-authed forever.
        unawaited(_validateRestoredSession());
      } else {
        if (kDebugMode) {
          print('No stored session found - user not logged in');
        }
      }
    } catch (e) {
      // Catch all errors to prevent app crashes during initialization
      _error = e.toString();
      if (kDebugMode) {
        print('Failed to initialize auth: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Validate a just-restored session against the backend (GET /api/me)
  ///
  /// Runs in the background after [initialize] optimistically restores the
  /// session, so a dead session is detected and cleared instead of degrading
  /// silently to anonymous browsing:
  /// - valid: nothing to do
  /// - invalid (401): attempt a token refresh. A refresh 401
  ///   ([SessionExpiredException]) means the session is definitively dead:
  ///   sign out, which flips [isAuthenticated] and rebuilds listeners into
  ///   the signed-out state. (The router deliberately allows anonymous
  ///   browsing, so there is no forced navigation to sign-in — the user
  ///   simply sees signed-out UI.) Any other refresh failure is treated as
  ///   transient: keep the session and let the next cold start retry, so a
  ///   backend blip can never destroy a live session.
  /// - indeterminate (offline, timeout, 5xx): keep the session — being
  ///   offline is not evidence the session is dead
  Future<void> _validateRestoredSession() async {
    // Capture the token so a sign-out or re-login that races the probe
    // can't be clobbered by a stale verdict.
    final validatedToken = _session?.token;
    if (validatedToken == null) {
      return;
    }

    try {
      final result = await _authService.validateSession();

      if (_session?.token != validatedToken) {
        // Session changed while the probe was in flight - verdict is stale.
        return;
      }

      if (result != SessionValidationResult.invalid) {
        if (kDebugMode) {
          if (result == SessionValidationResult.valid) {
            print('Restored session validated against /api/me');
          }
        }
        return;
      }

      if (kDebugMode) {
        print('Restored session rejected by backend - attempting refresh');
      }

      // Call the service directly rather than [refreshToken]: that method
      // signs out on ANY failure (appropriate for its 401-interceptor
      // callers), while this proactive probe must only sign out when the
      // backend definitively rejects the session.
      try {
        final refreshedSession = await _authService.refreshToken();
        if (_session?.token != validatedToken) {
          // Signed out / re-logged-in mid-refresh; verdict is stale.
          return;
        }
        _session = refreshedSession;
        notifyListeners();
        if (kDebugMode) {
          print('Restored session refreshed after rejected probe');
        }
      } on SessionExpiredException {
        // Definitively dead - force the signed-out state.
        await signOut();
      } on SessionRefreshDiscardedException {
        // Sign-out or re-login raced the refresh; nothing to do.
      } on Exception catch (e) {
        // Transient refresh failure (network, 5xx): keep the session.
        if (kDebugMode) {
          print('Probe refresh failed transiently (session kept): $e');
        }
      }
      // This is the outermost guard of a fire-and-forget startup task: no
      // throwable may escape, or it becomes an unhandled async error (a
      // sign-out race can surface Error types like StateError here).
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (kDebugMode) {
        print('Session validation error (ignored): $e');
      }
    }
  }

  /// Sign in with an atProto handle
  ///
  /// Opens the system browser to the backend's OAuth endpoint.
  /// The backend handles:
  /// - Handle -> DID resolution
  /// - PDS discovery
  /// - OAuth authorization with PKCE/DPoP
  /// - Token sealing
  ///
  /// Works with ANY handle on ANY PDS:
  /// - alice.bsky.social -> Bluesky PDS
  /// - bob.custom-pds.com -> Custom PDS
  /// - did:plc:abc123 -> Direct DID
  Future<void> signIn(String handle) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Validate handle format
      final trimmedHandle = handle.trim();
      if (trimmedHandle.isEmpty) {
        throw Exception('Please enter a valid handle');
      }

      // Perform OAuth sign in via backend
      final session = await _authService.signIn(trimmedHandle);

      // Update state
      _session = session;
      _isAuthenticated = true;

      if (kDebugMode) {
        print('Successfully signed in');
        print('   Handle: ${session.handle ?? trimmedHandle}');
        print('   DID: ${session.did}');
      }
    } on SignInCancelledException {
      // Cancel is not an error: don't record _error or flip auth state.
      // The finally block still clears _isLoading.
      rethrow;
    } catch (e) {
      _error = e.toString();
      _isAuthenticated = false;
      _session = null;

      if (kDebugMode) {
        print('Sign in failed: $e');
      }

      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign out and clear session
  ///
  /// This:
  /// 1. Calls the backend's logout endpoint (revokes session server-side)
  /// 2. Clears session from secure storage
  /// 3. Resets the provider state
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Call auth service signOut (handles server + local cleanup)
      await _authService.signOut();

      // Clear state
      _session = null;
      _isAuthenticated = false;
      _error = null;

      if (kDebugMode) {
        print('Successfully signed out');
      }
    } on Exception catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        print('Sign out failed: $e');
      }

      // Even if server revocation fails, clear local state
      _session = null;
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh the current session token
  ///
  /// Calls the backend's /oauth/refresh endpoint.
  /// The backend handles the actual PDS token refresh internally.
  ///
  /// Returns true if refresh succeeded, false otherwise.
  Future<bool> refreshToken() async {
    if (_session == null) {
      return false;
    }

    try {
      final refreshedSession = await _authService.refreshToken();
      if (_session == null) {
        // Signed out while the refresh was in flight - don't resurrect.
        return false;
      }
      _session = refreshedSession;
      notifyListeners();

      if (kDebugMode) {
        print('Token refreshed successfully');
      }

      return true;
    } on SessionRefreshDiscardedException {
      // Sign-out or re-login raced the refresh; the result was discarded.
      // The session state is already whatever the race winner made it -
      // signing out here would destroy a freshly created session.
      return false;
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Token refresh failed: $e');
      }

      // If refresh fails, sign out the user
      await signOut();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
