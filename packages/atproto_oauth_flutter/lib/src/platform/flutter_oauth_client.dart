import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../client/oauth_client.dart';
import '../session/oauth_session.dart';
import 'flutter_runtime.dart';
import 'flutter_stores.dart';

/// Flutter-specific OAuth client with sensible defaults.
///
/// This is a high-level wrapper around [OAuthClient] that provides:
/// - Automatic storage configuration (flutter_secure_storage)
/// - Platform-specific crypto (pointycastle + crypto package)
/// - In-memory caching with TTL
/// - Convenient sign-in flow (authorize + FlutterWebAuth2 + callback)
/// - Session management (restore, revoke)
///
/// Example usage:
/// ```dart
/// // Initialize client
/// final client = FlutterOAuthClient(
///   clientMetadata: ClientMetadata(
///     clientId: 'https://example.com/client-metadata.json',
///     redirectUris: ['myapp://oauth/callback'],
///     scope: 'atproto transition:generic',
///   ),
/// );
///
/// // Sign in with handle
/// try {
///   final session = await client.signIn('alice.bsky.social');
///   print('Signed in as: ${session.sub}');
///
///   // Use the session for authenticated requests
///   final agent = session.pdsClient;
///   // ... make API calls
/// } catch (e) {
///   print('Sign in failed: $e');
/// }
///
/// // Later: restore session
/// try {
///   final session = await client.restore('did:plc:abc123');
///   print('Session restored');
/// } catch (e) {
///   print('Session restoration failed: $e');
/// }
///
/// // Sign out
/// await client.revoke('did:plc:abc123');
/// ```
class FlutterOAuthClient extends OAuthClient {
  /// Creates a FlutterOAuthClient with Flutter-specific defaults.
  ///
  /// Parameters:
  /// - [clientMetadata]: Client configuration (required)
  /// - [responseMode]: OAuth response mode (default: query)
  /// - [allowHttp]: Allow HTTP for testing (default: false)
  /// - [secureStorage]: Custom secure storage instance (optional)
  /// - [dio]: Custom HTTP client (optional)
  /// - [plcDirectoryUrl]: Custom PLC directory URL (optional)
  /// - [handleResolverUrl]: Custom handle resolver URL (optional)
  ///
  /// Throws [FormatException] if client metadata is invalid.
  FlutterOAuthClient({
    required ClientMetadata clientMetadata,
    OAuthResponseMode responseMode = OAuthResponseMode.query,
    bool allowHttp = false,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    String? plcDirectoryUrl,
    String? handleResolverUrl,
  }) : super(
          OAuthClientOptions(
            // Config
            responseMode: responseMode,
            clientMetadata: clientMetadata.toJson(),
            keyset: null, // Mobile apps are public clients
            allowHttp: allowHttp,

            // Storage (Flutter-specific)
            stateStore: FlutterStateStore(),
            sessionStore: FlutterSessionStore(secureStorage),

            // Caches (in-memory with TTL)
            authorizationServerMetadataCache:
                InMemoryAuthorizationServerMetadataCache(),
            protectedResourceMetadataCache:
                InMemoryProtectedResourceMetadataCache(),
            dpopNonceCache: InMemoryDpopNonceCache(),
            didCache: FlutterDidCache(),
            handleCache: FlutterHandleCache(),

            // Platform implementation
            runtimeImplementation: const FlutterRuntime(),

            // HTTP client
            dio: dio,

            // Optional overrides
            plcDirectoryUrl: plcDirectoryUrl,
            handleResolverUrl: handleResolverUrl,
          ),
        );

  /// Sign in with an atProto handle, DID, or URL.
  ///
  /// This is a convenience method that:
  /// 1. Initiates authorization flow ([authorize])
  /// 2. Opens browser with FlutterWebAuth2
  /// 3. Handles OAuth callback
  /// 4. Returns authenticated session
  ///
  /// The [input] can be:
  /// - An atProto handle: "alice.bsky.social"
  /// - A DID: "did:plc:..."
  /// - A PDS URL: "https://pds.example.com"
  /// - An authorization server URL: "https://auth.example.com"
  ///
  /// The [options] can specify:
  /// - redirectUri: Override default redirect URI
  /// - state: Application state to preserve
  /// - scope: Override default scope
  /// - Other OIDC parameters (prompt, display, etc.)
  ///
  /// Returns an [OAuthSession] with authenticated access.
  ///
  /// Throws:
  /// - [FormatException] if parameters are invalid
  /// - [OAuthResolverError] if identity resolution fails
  /// - [OAuthCallbackError] if authentication fails
  /// - [Exception] if user cancels (flutter_web_auth_2 throws PlatformException)
  ///
  /// Example:
  /// ```dart
  /// // Simple sign in
  /// final session = await client.signIn('alice.bsky.social');
  ///
  /// // With custom state
  /// final session = await client.signIn(
  ///   'alice.bsky.social',
  ///   options: AuthorizeOptions(state: 'my-app-state'),
  /// );
  /// ```
  Future<OAuthSession> signIn(
    String input, {
    AuthorizeOptions? options,
    CancelToken? cancelToken,
  }) async {
    // CRITICAL: Use HTTPS redirect URI for OAuth (prevents browser retry)
    // but listen for CUSTOM SCHEME in FlutterWebAuth2 (only custom schemes can be intercepted)
    // The HTTPS page will redirect to custom scheme, triggering the callback
    final redirectUri = options?.redirectUri ?? clientMetadata.redirectUris.first;

    if (!clientMetadata.redirectUris.contains(redirectUri)) {
      throw FormatException('Invalid redirect_uri: $redirectUri');
    }

    // Find the custom scheme redirect URI from the list
    // FlutterWebAuth2 can ONLY intercept custom schemes, not HTTPS
    final customSchemeUri = clientMetadata.redirectUris.firstWhere(
      (uri) => !uri.startsWith('http://') && !uri.startsWith('https://'),
      orElse: () => redirectUri, // Fallback to primary if no custom scheme found
    );

    final callbackUrlScheme = _extractScheme(customSchemeUri);

    // Step 1: Start OAuth authorization flow
    final authUrl = await authorize(
      input,
      options: options != null
          ? AuthorizeOptions(
              redirectUri: redirectUri,
              state: options.state,
              scope: options.scope,
              nonce: options.nonce,
              dpopJkt: options.dpopJkt,
              maxAge: options.maxAge,
              claims: options.claims,
              uiLocales: options.uiLocales,
              idTokenHint: options.idTokenHint,
              display: options.display ?? 'touch', // Mobile-friendly default
              prompt: options.prompt,
              authorizationDetails: options.authorizationDetails,
            )
          : AuthorizeOptions(
              redirectUri: redirectUri,
              display: 'touch', // Mobile-friendly default
            ),
      cancelToken: cancelToken,
    );

    // Step 2: Open browser for user authentication
    if (kDebugMode) {
      print('🔐 Opening browser for OAuth...');
      print('   Auth URL: $authUrl');
      print('   OAuth redirect URI (PDS will redirect here): $redirectUri');
      print('   FlutterWebAuth2 callback scheme (listening for): $callbackUrlScheme');
    }

    String? callbackUrl;
    try {
      if (kDebugMode) {
        print('📱 Calling FlutterWebAuth2.authenticate()...');
      }

      callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: callbackUrlScheme,
        options: const FlutterWebAuth2Options(
          // Use ephemeral session to force browser to close immediately
          // This prevents browser retry that can invalidate the authorization code
          preferEphemeral: true,
          timeout: 300, // 5 minutes timeout
        ),
      );

      if (kDebugMode) {
        print('✅ FlutterWebAuth2 returned successfully!');
        print('   Callback URL: $callbackUrl');
        print('   ⏱️  Callback received at: ${DateTime.now().toIso8601String()}');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ FlutterWebAuth2.authenticate() threw an error:');
        print('   Error type: ${e.runtimeType}');
        print('   Error message: $e');
        print('   Stack trace: $stackTrace');
      }
      rethrow;
    }

    // Step 3: Parse callback URL parameters
    final uri = Uri.parse(callbackUrl);
    final params = responseMode == OAuthResponseMode.fragment
        ? _parseFragment(uri.fragment)
        : Map<String, String>.from(uri.queryParameters);

    if (kDebugMode) {
      print('🔄 Parsing callback parameters...');
      print('   Response mode: $responseMode');
      print('   Callback params: $params');
    }

    // Step 4: Complete OAuth flow
    if (kDebugMode) {
      print('📞 Calling callback() to exchange code for tokens...');
      print('   Redirect URI: $redirectUri');
    }

    final result = await callback(
      params,
      options: CallbackOptions(redirectUri: redirectUri),
      cancelToken: cancelToken,
    );

    if (kDebugMode) {
      print('✅ Token exchange successful!');
      print('   Session DID: ${result.session.sub}');
    }

    return result.session;
  }

  /// Extracts the URL scheme from a redirect URI.
  ///
  /// Examples:
  /// - "myapp://oauth/callback" → "myapp"
  /// - "https://example.com/callback" → "https"
  String _extractScheme(String redirectUri) {
    final uri = Uri.parse(redirectUri);
    return uri.scheme;
  }

  /// Parses URL fragment into a parameter map.
  ///
  /// The fragment may start with '#' which we strip.
  Map<String, String> _parseFragment(String fragment) {
    // Remove leading '#' if present
    final clean = fragment.startsWith('#') ? fragment.substring(1) : fragment;
    if (clean.isEmpty) return {};

    final params = <String, String>{};
    for (final pair in clean.split('&')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        params[Uri.decodeComponent(parts[0])] = Uri.decodeComponent(parts[1]);
      }
    }
    return params;
  }
}
