import 'dart:async';
import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'package:flutter/foundation.dart';
import '../config/oauth_config.dart';

/// OAuth Service for atProto authentication using the new atproto_oauth_flutter package
///
/// Key improvements over the old implementation:
/// ✅ Proper decentralized OAuth discovery - works with ANY PDS (not just bsky.social)
/// ✅ Built-in session management - no manual token storage
/// ✅ Automatic token refresh with concurrency control
/// ✅ Session event streams for updates and deletions
/// ✅ Secure storage handled internally (iOS Keychain, Android EncryptedSharedPreferences)
///
/// The new package handles the complete OAuth flow:
/// 1. Handle/DID resolution
/// 2. PDS discovery from DID document
/// 3. Authorization server discovery
/// 4. PKCE + DPoP generation
/// 5. Browser-based authorization
/// 6. Token exchange and storage
/// 7. Automatic refresh and revocation
class OAuthService {
  static final OAuthService _instance = OAuthService._internal();
  factory OAuthService() => _instance;
  OAuthService._internal();

  FlutterOAuthClient? _client;

  // Session event stream subscriptions
  StreamSubscription<SessionUpdatedEvent>? _onUpdatedSubscription;
  StreamSubscription<SessionDeletedEvent>? _onDeletedSubscription;

  /// Initialize the OAuth client
  ///
  /// This creates a FlutterOAuthClient with:
  /// - Discoverable client metadata (HTTPS URL)
  /// - Custom URL scheme for deep linking
  /// - DPoP enabled for token security
  /// - Automatic session management
  Future<void> initialize() async {
    try {
      // Create client with metadata from config
      _client = FlutterOAuthClient(
        clientMetadata: OAuthConfig.createClientMetadata(),
        responseMode: OAuthResponseMode.query, // Mobile-friendly response mode
      );

      // Set up session event listeners
      _setupEventListeners();

      if (kDebugMode) {
        print('✅ FlutterOAuthClient initialized');
        print('   Client ID: ${OAuthConfig.clientId}');
        print('   Redirect URI: ${OAuthConfig.customSchemeCallback}');
        print('   Scope: ${OAuthConfig.scope}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize OAuth client: $e');
      }
      rethrow;
    }
  }

  /// Set up listeners for session events
  void _setupEventListeners() {
    if (_client == null) return;

    // Listen for session updates (token refresh, etc.)
    _onUpdatedSubscription = _client!.onUpdated.listen((event) {
      if (kDebugMode) {
        print('📝 Session updated for: ${event.sub}');
      }
    });

    // Listen for session deletions (revoke, expiry, errors)
    _onDeletedSubscription = _client!.onDeleted.listen((event) {
      if (kDebugMode) {
        print('🗑️ Session deleted for: ${event.sub}');
        print('   Cause: ${event.cause}');
      }
    });
  }

  /// Sign in with an atProto handle
  ///
  /// The new package handles the complete OAuth flow:
  /// 1. Resolves handle → DID (using any handle resolver)
  /// 2. Fetches DID document to find the user's PDS
  /// 3. Discovers authorization server from PDS metadata
  /// 4. Generates PKCE challenge and DPoP keys
  /// 5. Opens browser for user authorization
  /// 6. Handles callback and exchanges code for tokens
  /// 7. Stores session securely (iOS Keychain / Android EncryptedSharedPreferences)
  ///
  /// This works with ANY PDS - not just bsky.social! 🎉
  ///
  /// Examples:
  /// - `signIn('alice.bsky.social')` → Bluesky PDS
  /// - `signIn('bob.custom-pds.com')` → Custom PDS ✅
  /// - `signIn('did:plc:abc123')` → Direct DID (skips handle resolution)
  ///
  /// Returns the authenticated OAuthSession.
  Future<OAuthSession> signIn(String input) async {
    try {
      if (_client == null) {
        throw Exception(
          'OAuth client not initialized. Call initialize() first.',
        );
      }

      // Validate input
      final trimmedInput = input.trim();
      if (trimmedInput.isEmpty) {
        throw Exception('Please enter a valid handle or DID');
      }

      if (kDebugMode) {
        print('🔐 Starting sign-in for: $trimmedInput');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      // Call the new package's signIn method
      // This does EVERYTHING: handle resolution, PDS discovery, OAuth flow, token storage
      if (kDebugMode) {
        print('📞 Calling FlutterOAuthClient.signIn()...');
      }

      final session = await _client!.signIn(trimmedInput);

      if (kDebugMode) {
        print('✅ Sign-in successful!');
        print('   DID: ${session.sub}');
        print('   PDS: ${session.serverMetadata['issuer'] ?? 'unknown'}');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      return session;
    } on OAuthCallbackError catch (e, stackTrace) {
      // OAuth-specific errors (access denied, invalid request, etc.)
      final errorCode = e.params['error'];
      final errorDescription = e.params['error_description'] ?? e.message;

      if (kDebugMode) {
        print('❌ OAuth callback error details:');
        print('   Error code: $errorCode');
        print('   Description: $errorDescription');
        print('   Message: ${e.message}');
        print('   All params: ${e.params}');
        print('   Exception type: ${e.runtimeType}');
        print('   Exception: $e');
        print('   Stack trace:');
        print('$stackTrace');
      }

      if (errorCode == 'access_denied') {
        throw Exception('Sign in cancelled by user');
      }

      throw Exception('OAuth error: $errorDescription');
    } catch (e, stackTrace) {
      // Catch all other errors including user cancellation
      if (kDebugMode) {
        print('❌ Sign in failed - detailed error:');
        print('   Error type: ${e.runtimeType}');
        print('   Error: $e');
        print('   Stack trace:');
        print('$stackTrace');
      }

      // Check if user cancelled (flutter_web_auth_2 throws PlatformException with "CANCELED" code)
      if (e.toString().contains('CANCELED') ||
          e.toString().contains('User cancelled')) {
        throw Exception('Sign in cancelled by user');
      }

      throw Exception('Sign in failed: $e');
    }
  }

  /// Restore a previous session if available
  ///
  /// The new package handles session restoration automatically:
  /// - Loads session from secure storage
  /// - Checks token expiration
  /// - Automatically refreshes if needed
  /// - Returns null if no valid session exists
  ///
  /// Parameters:
  /// - `did`: User's DID (e.g., "did:plc:abc123")
  /// - `refresh`: Token refresh strategy:
  ///   - 'auto' (default): Refresh only if expired
  ///   - true: Force refresh even if not expired
  ///   - false: Use cached tokens even if expired
  ///
  /// Returns the restored session or null if no session found.
  Future<OAuthSession?> restoreSession(
    String did, {
    dynamic refresh = 'auto',
  }) async {
    try {
      if (_client == null) {
        throw Exception(
          'OAuth client not initialized. Call initialize() first.',
        );
      }

      if (kDebugMode) {
        print('🔄 Attempting to restore session for: $did');
      }

      // Call the new package's restore method
      final session = await _client!.restore(did, refresh: refresh);

      if (kDebugMode) {
        print('✅ Session restored successfully');
        final info = await session.getTokenInfo();
        print('   Token expires: ${info.expiresAt}');
      }

      return session;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to restore session: $e');
      }
      return null;
    }
  }

  /// Sign out and revoke session
  ///
  /// The new package handles revocation properly:
  /// - Calls server's token revocation endpoint (best-effort)
  /// - Deletes session from secure storage (always)
  /// - Emits 'deleted' event
  ///
  /// This is a complete sign-out with server-side revocation! 🎉
  Future<void> signOut(String did) async {
    try {
      if (_client == null) {
        throw Exception(
          'OAuth client not initialized. Call initialize() first.',
        );
      }

      if (kDebugMode) {
        print('👋 Signing out: $did');
      }

      // Call the new package's revoke method
      await _client!.revoke(did);

      if (kDebugMode) {
        print('✅ Sign out successful');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Sign out failed: $e');
      }
      // Re-throw to let caller handle
      rethrow;
    }
  }

  /// Get the current OAuth client instance
  ///
  /// Useful for advanced use cases like:
  /// - Listening to session events directly
  /// - Using lower-level OAuth methods
  FlutterOAuthClient? get client => _client;

  /// Clean up resources
  void dispose() {
    _onUpdatedSubscription?.cancel();
    _onDeletedSubscription?.cancel();
  }
}
