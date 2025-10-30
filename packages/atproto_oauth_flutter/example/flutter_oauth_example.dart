/// Example usage of FlutterOAuthClient for atProto OAuth authentication.
///
/// This demonstrates the complete OAuth flow for a Flutter application:
/// 1. Initialize the client
/// 2. Sign in with a handle
/// 3. Use the authenticated session
/// 4. Restore session on app restart
/// 5. Sign out (revoke session)

import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';

void main() async {
  // ========================================================================
  // 1. Initialize the OAuth client
  // ========================================================================

  final client = FlutterOAuthClient(
    clientMetadata: ClientMetadata(
      // For development: use loopback client (no client metadata URL needed)
      clientId: 'http://localhost',

      // For production: use discoverable client metadata
      // clientId: 'https://example.com/client-metadata.json',

      // Redirect URIs for your app
      // - Custom URL scheme: myapp://oauth/callback
      // - Universal links: https://example.com/oauth/callback
      redirectUris: ['myapp://oauth/callback'],

      // Scope: what permissions to request
      // - 'atproto': Full atproto access
      // - 'transition:generic': Additional permissions for legacy systems
      scope: 'atproto transition:generic',

      // Client metadata
      clientName: 'My Awesome App',
      clientUri: 'https://example.com',

      // Token binding
      dpopBoundAccessTokens: true, // Enable DPoP for security
    ),

    // Response mode (query or fragment)
    responseMode: OAuthResponseMode.query,

    // Allow HTTP only for development (never in production!)
    allowHttp: false,
  );

  // ========================================================================
  // 2. Sign in with a handle
  // ========================================================================

  try {
    print('Starting sign-in flow for alice.bsky.social...');

    // This will:
    // 1. Resolve the handle to find the authorization server
    // 2. Generate PKCE code challenge/verifier
    // 3. Generate DPoP key
    // 4. Open browser for user authentication
    // 5. Handle OAuth callback
    // 6. Exchange authorization code for tokens
    // 7. Store session securely
    final session = await client.signIn('alice.bsky.social');

    print('✓ Signed in successfully!');
    print('  DID: ${session.sub}');
    print('  Session info: ${session.info}');

    // ========================================================================
    // 3. Use the authenticated session
    // ========================================================================

    // The session has a PDS client you can use for authenticated requests
    // (This requires integrating with an atproto API client library)
    //
    // Example:
    // final agent = session.pdsClient;
    // final profile = await agent.getProfile();

    print('Session is ready for API calls');
  } on OAuthCallbackError catch (e) {
    // Handle OAuth errors (user cancelled, invalid state, etc.)
    print('OAuth callback error: ${e.error}');
    print('Description: ${e.errorDescription}');
    return;
  } catch (e) {
    print('Sign-in error: $e');
    return;
  }

  // ========================================================================
  // 4. Restore session on app restart
  // ========================================================================

  // Later, when the app restarts, restore the session:
  try {
    final did = 'did:plc:abc123'; // Get from storage or previous session

    print('Restoring session for $did...');

    // This will:
    // 1. Load session from secure storage
    // 2. Check if tokens are expired
    // 3. Automatically refresh if needed
    // 4. Return authenticated session
    final session = await client.restore(did);

    print('✓ Session restored!');
    print('  Access token expires: ${session.info['expiresAt']}');
  } catch (e) {
    print('Failed to restore session: $e');
    // Session may have been revoked or expired
    // Prompt user to sign in again
  }

  // ========================================================================
  // 5. Sign out (revoke session)
  // ========================================================================

  try {
    final did = 'did:plc:abc123';

    print('Signing out $did...');

    // This will:
    // 1. Call token revocation endpoint (best effort)
    // 2. Delete session from secure storage
    // 3. Emit 'deleted' event
    await client.revoke(did);

    print('✓ Signed out successfully');
  } catch (e) {
    print('Sign out error: $e');
    // Session is still deleted locally even if revocation fails
  }

  // ========================================================================
  // Advanced: Listen to session events
  // ========================================================================

  // Listen for session updates (token refresh, etc.)
  client.onUpdated.listen((event) {
    print('Session updated: ${event.sub}');
    print('  New access token received');
  });

  // Listen for session deletions (revoked, expired, etc.)
  client.onDeleted.listen((event) {
    print('Session deleted: ${event.sub}');
    print('  Cause: ${event.cause}');
    // Handle session deletion (navigate to sign-in screen, etc.)
  });

  // ========================================================================
  // Advanced: Custom configuration
  // ========================================================================

  // You can customize storage, caching, and crypto:
  final customClient = FlutterOAuthClient(
    clientMetadata: ClientMetadata(
      clientId: 'https://example.com/client-metadata.json',
      redirectUris: ['myapp://oauth/callback'],
    ),

    // Custom secure storage instance
    secureStorage: const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),

    // Custom PLC directory URL (for private deployments)
    plcDirectoryUrl: 'https://plc.example.com',

    // Custom handle resolver URL
    handleResolverUrl: 'https://bsky.social',
  );

  print('Custom client initialized');

  // ========================================================================
  // Platform configuration (iOS)
  // ========================================================================

  // iOS: Add URL scheme to Info.plist
  // <key>CFBundleURLTypes</key>
  // <array>
  //   <dict>
  //     <key>CFBundleURLSchemes</key>
  //     <array>
  //       <string>myapp</string>
  //     </array>
  //   </dict>
  // </array>

  // ========================================================================
  // Platform configuration (Android)
  // ========================================================================

  // Android: Add intent filter to AndroidManifest.xml
  // <intent-filter>
  //   <action android:name="android.intent.action.VIEW" />
  //   <category android:name="android.intent.category.DEFAULT" />
  //   <category android:name="android.intent.category.BROWSABLE" />
  //   <data android:scheme="myapp" />
  // </intent-filter>

  // ========================================================================
  // Security best practices
  // ========================================================================

  // ✓ Tokens stored in secure storage (Keychain/EncryptedSharedPreferences)
  // ✓ DPoP binds tokens to cryptographic keys
  // ✓ PKCE prevents authorization code interception
  // ✓ State parameter prevents CSRF attacks
  // ✓ Automatic token refresh with concurrency control
  // ✓ Session cleanup on errors

  print('Example complete!');
}
