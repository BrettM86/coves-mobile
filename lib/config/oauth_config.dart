import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';

/// OAuth Configuration for atProto
///
/// This configuration provides ClientMetadata for the new atproto_oauth_flutter package.
/// The new package handles proper decentralized OAuth discovery (works with ANY PDS).
class OAuthConfig {
  // OAuth Server Configuration
  // Cloudflare Worker that hosts client-metadata.json and handles OAuth callbacks
  static const String oauthServerUrl =
      'https://lingering-darkness-50a6.brettmay0212.workers.dev';

  // Custom URL scheme for deep linking
  // Must match AndroidManifest.xml intent filters
  // Using the same format as working Expo implementation
  static const String customScheme =
      'dev.workers.brettmay0212.lingering-darkness-50a6';

  // API Configuration
  // Using adb reverse port forwarding, phone can access via localhost
  // Setup: adb reverse tcp:8081 tcp:8081
  static const String apiUrl = 'http://localhost:8081';

  // Derived OAuth URLs
  static const String clientId = '$oauthServerUrl/client-metadata.json';

  // IMPORTANT: Private-use URI schemes (RFC 8252) require SINGLE slash, not double!
  // Correct:   dev.workers.example:/oauth/callback
  // Incorrect: dev.workers.example://oauth/callback
  static const String customSchemeCallback = '$customScheme:/oauth/callback';

  // HTTPS callback (fallback for PDS that don't support custom URI schemes)
  static const String httpsCallback = '$oauthServerUrl/oauth/callback';

  // OAuth Scopes - recommended scope for atProto
  static const String scope = 'atproto transition:generic';

  // Client name for display during authorization
  static const String clientName = 'Coves';

  /// Create ClientMetadata for the FlutterOAuthClient
  ///
  /// This configures the OAuth client with:
  /// - Discoverable client ID (HTTPS URL to metadata JSON)
  /// - HTTPS callback (primary - works with all PDS servers)
  /// - Custom URL scheme (fallback - requires PDS support)
  /// - DPoP enabled for token security
  /// - Proper scopes for atProto access
  static ClientMetadata createClientMetadata() {
    return const ClientMetadata(
      clientId: clientId,
      // Use HTTPS as PRIMARY - prevents browser re-navigation that invalidates auth codes
      // Custom scheme as fallback (Worker page redirects to custom scheme anyway)
      redirectUris: [httpsCallback, customSchemeCallback],
      scope: scope,
      clientName: clientName,
      dpopBoundAccessTokens: true, // Enable DPoP for security
      applicationType: 'native',
      grantTypes: ['authorization_code', 'refresh_token'],
      tokenEndpointAuthMethod: 'none', // Public client (mobile apps)
    );
  }
}
