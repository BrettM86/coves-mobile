import 'package:flutter/foundation.dart';
import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/oauth_service.dart';

/// Authentication Provider
///
/// Manages authentication state using the new atproto_oauth_flutter package.
/// Uses ChangeNotifier for reactive state updates across the app.
///
/// Key improvements:
/// ✅ Uses OAuthSession from the new package (with built-in token management)
/// ✅ Stores only the DID in SharedPreferences (public info, not sensitive)
/// ✅ Tokens are stored securely by the package (iOS Keychain / Android EncryptedSharedPreferences)
/// ✅ Automatic token refresh handled by the package
class AuthProvider with ChangeNotifier {
  final OAuthService _oauthService = OAuthService();

  // SharedPreferences key for storing the current user's DID
  // The DID is public information (like a username), so SharedPreferences is fine
  // The actual tokens are stored securely by the atproto_oauth_flutter package
  static const String _prefKeyDid = 'current_user_did';

  // Session state
  OAuthSession? _session;
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _error;

  // User info
  String? _did;
  String? _handle;

  // Getters
  OAuthSession? get session => _session;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get did => _did;
  String? get handle => _handle;

  /// Initialize the provider and restore any existing session
  ///
  /// This is called on app startup to:
  /// 1. Initialize the OAuth service
  /// 2. Check if there's a stored DID (from previous session)
  /// 3. Restore the session if found (with automatic token refresh)
  Future<void> initialize() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Initialize OAuth service
      await _oauthService.initialize();

      // Check if we have a stored DID from a previous session
      final prefs = await SharedPreferences.getInstance();
      final storedDid = prefs.getString(_prefKeyDid);

      if (storedDid != null) {
        if (kDebugMode) {
          print('Found stored DID: $storedDid');
        }

        // Try to restore the session
        // The package will automatically refresh tokens if needed
        final restoredSession = await _oauthService.restoreSession(storedDid);

        if (restoredSession != null) {
          _session = restoredSession;
          _isAuthenticated = true;
          _did = restoredSession.sub;

          // Extract handle from session metadata if available
          // The handle might be in the session metadata or we can store it separately
          _handle = storedDid; // TODO: Store handle separately if needed

          if (kDebugMode) {
            print('✅ Successfully restored session');
            print('   DID: ${restoredSession.sub}');
          }
        } else {
          // Failed to restore - clear the stored DID
          await prefs.remove(_prefKeyDid);
          if (kDebugMode) {
            print('⚠️ Could not restore session - cleared stored DID');
          }
        }
      } else {
        if (kDebugMode) {
          print('No stored DID found - user not logged in');
        }
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        print('❌ Failed to initialize auth: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with an atProto handle
  ///
  /// This works with ANY handle on ANY PDS:
  /// - alice.bsky.social → Bluesky PDS
  /// - bob.custom-pds.com → Custom PDS
  /// - did:plc:abc123 → Direct DID
  ///
  /// The package handles:
  /// - Handle → DID resolution
  /// - PDS discovery
  /// - OAuth authorization
  /// - Token storage
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

      // Perform OAuth sign in with the new package
      final session = await _oauthService.signIn(trimmedHandle);

      // Update state
      _session = session;
      _isAuthenticated = true;
      _did = session.sub;
      _handle = trimmedHandle;

      // Store the DID in SharedPreferences so we can restore on next launch
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyDid, session.sub);

      if (kDebugMode) {
        print('✅ Successfully signed in');
        print('   Handle: $trimmedHandle');
        print('   DID: ${session.sub}');
      }
    } catch (e) {
      _error = e.toString();
      _isAuthenticated = false;
      _session = null;
      _did = null;
      _handle = null;

      if (kDebugMode) {
        print('❌ Sign in failed: $e');
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
  /// 1. Calls the server's token revocation endpoint (best-effort)
  /// 2. Deletes session from secure storage
  /// 3. Clears the stored DID from SharedPreferences
  /// 4. Resets the provider state
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Get the current DID before clearing state
      final currentDid = _did;

      if (currentDid != null) {
        // Call the new package's revoke method
        // This handles server-side revocation + local storage cleanup
        await _oauthService.signOut(currentDid);
      }

      // Clear the stored DID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyDid);

      // Clear state
      _session = null;
      _isAuthenticated = false;
      _did = null;
      _handle = null;
      _error = null;

      if (kDebugMode) {
        print('✅ Successfully signed out');
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        print('⚠️ Sign out failed: $e');
      }

      // Even if revocation fails, clear local state
      _session = null;
      _isAuthenticated = false;
      _did = null;
      _handle = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    _oauthService.dispose();
    super.dispose();
  }
}
