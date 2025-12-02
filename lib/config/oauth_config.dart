/// OAuth Configuration for Coves Backend OAuth
///
/// This configuration supports the backend's mobile OAuth flow.
/// The backend handles all OAuth complexity (PKCE, DPoP, token exchange).
///
/// Uses private-use URI scheme per atproto spec (RFC 8252):
/// - Format: social.coves:/callback (single slash!)
/// - Works on both Android and iOS without Universal Links complexity
class OAuthConfig {
  // Custom URL scheme for deep linking
  // Must match AndroidManifest.xml and Info.plist
  // Uses reverse domain format per atproto spec
  static const String customScheme = 'social.coves';

  // Redirect URI using private-use URI scheme (RFC 8252)
  // IMPORTANT: Single slash after scheme per RFC 8252!
  static const String _redirectUri = '$customScheme:/callback';

  /// Get the redirect URI (same for all environments)
  static String get redirectUri => _redirectUri;

  /// Get the callback scheme for FlutterWebAuth2
  static String get callbackScheme => customScheme;

  // OAuth Scopes - recommended scope for atProto
  static const String scope = 'atproto transition:generic';

  // Client name for display during authorization
  static const String clientName = 'Coves';
}
