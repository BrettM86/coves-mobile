import 'dart:async';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../dpop/fetch_dpop.dart';
import '../errors/token_invalid_error.dart';
import '../errors/token_revoked_error.dart';
import '../oauth/oauth_server_agent.dart';

/// Type alias for AtprotoDid (user's DID)
typedef AtprotoDid = String;

/// Type alias for AtprotoOAuthScope
typedef AtprotoOAuthScope = String;

/// Placeholder for OAuthAuthorizationServerMetadata
/// Will be properly typed in later chunks
typedef OAuthAuthorizationServerMetadata = Map<String, dynamic>;

/// Information about the current token.
class TokenInfo {
  /// When the token expires (null if no expiration)
  final DateTime? expiresAt;

  /// Whether the token is expired (null if no expiration)
  final bool? expired;

  /// The scope of access granted
  final AtprotoOAuthScope scope;

  /// The issuer URL
  final String iss;

  /// The audience (resource server)
  final String aud;

  /// The subject (user's DID)
  final AtprotoDid sub;

  TokenInfo({
    this.expiresAt,
    this.expired,
    required this.scope,
    required this.iss,
    required this.aud,
    required this.sub,
  });
}

/// Abstract interface for session management.
///
/// This will be implemented by SessionGetter in session_getter.dart.
/// We define it here to avoid circular dependencies.
abstract class SessionGetterInterface {
  Future<Session> get(AtprotoDid sub, {bool? noCache, bool? allowStale});

  Future<void> delStored(AtprotoDid sub, [Object? cause]);
}

/// Represents an active OAuth session.
///
/// A session is created after successful authentication and provides methods
/// for making authenticated requests and managing the session lifecycle.
class Session {
  /// The DPoP key used for this session (serialized as Map for storage)
  final Map<String, dynamic> dpopKey;

  /// The client authentication method (serialized as Map or String for storage).
  /// Can be:
  /// - A Map containing {method: 'private_key_jwt', kid: '...'} for private key JWT
  /// - A Map containing {method: 'none'} for no authentication
  /// - A String 'legacy' for backwards compatibility
  /// - null (defaults to 'legacy' when loading)
  final dynamic authMethod;

  /// The token set containing access and refresh tokens
  final TokenSet tokenSet;

  const Session({
    required this.dpopKey,
    this.authMethod,
    required this.tokenSet,
  });

  /// Creates a Session from JSON.
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      dpopKey: json['dpopKey'] as Map<String, dynamic>,
      authMethod: json['authMethod'], // Can be Map or String
      tokenSet: TokenSet.fromJson(json['tokenSet'] as Map<String, dynamic>),
    );
  }

  /// Converts this Session to JSON.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'dpopKey': dpopKey,
      'tokenSet': tokenSet.toJson(),
    };

    if (authMethod != null) json['authMethod'] = authMethod;

    return json;
  }
}

/// Represents an active OAuth session with methods for authenticated requests.
///
/// This class wraps an OAuth session and provides:
/// - Automatic token refresh on expiry
/// - DPoP-protected requests
/// - Session lifecycle management (sign out)
///
/// Example:
/// ```dart
/// final session = OAuthSession(
///   server: oauthServer,
///   sub: 'did:plc:abc123',
///   sessionGetter: sessionGetter,
/// );
///
/// // Make an authenticated request
/// final response = await session.fetchHandler('/api/posts');
///
/// // Get token information
/// final info = await session.getTokenInfo();
/// print('Token expires at: ${info.expiresAt}');
///
/// // Sign out
/// await session.signOut();
/// ```
class OAuthSession {
  /// The OAuth server agent
  final OAuthServerAgent server;

  /// The subject (user's DID)
  final AtprotoDid sub;

  /// The session getter for retrieving and refreshing tokens
  final SessionGetterInterface sessionGetter;

  /// Dio instance with DPoP interceptor for authenticated requests
  final Dio _dio;

  /// Creates a new OAuth session.
  ///
  /// Parameters:
  /// - [server]: The OAuth server agent
  /// - [sub]: The subject (user's DID)
  /// - [sessionGetter]: The session getter for token management
  OAuthSession({
    required this.server,
    required this.sub,
    required this.sessionGetter,
  }) : _dio = Dio() {
    // Add DPoP interceptor for authenticated requests to resource servers
    _dio.interceptors.add(
      createDpopInterceptor(
        DpopFetchWrapperOptions(
          key: server.dpopKey,
          nonces: server.dpopNonces,
          sha256: server.runtime.sha256,
          isAuthServer: false, // Resource server requests (PDS)
        ),
      ),
    );
  }

  /// Alias for [sub]
  AtprotoDid get did => sub;

  /// The server metadata
  OAuthAuthorizationServerMetadata get serverMetadata => server.serverMetadata;

  /// Gets the current token set.
  ///
  /// Parameters:
  /// - [refresh]: When `true`, forces a token refresh even if not expired.
  ///   When `false`, uses cached tokens even if expired.
  ///   When `'auto'`, refreshes only if expired (default).
  Future<TokenSet> _getTokenSet(dynamic refresh) async {
    final session = await sessionGetter.get(
      sub,
      noCache: refresh == true,
      allowStale: refresh == false,
    );

    return session.tokenSet;
  }

  /// Gets information about the current token.
  ///
  /// Parameters:
  /// - [refresh]: When `true`, forces a token refresh even if not expired.
  ///   When `false`, uses cached tokens even if expired.
  ///   When `'auto'`, refreshes only if expired (default).
  Future<TokenInfo> getTokenInfo([dynamic refresh = 'auto']) async {
    final tokenSet = await _getTokenSet(refresh);
    final expiresAtStr = tokenSet.expiresAt;
    final expiresAt =
        expiresAtStr != null ? DateTime.parse(expiresAtStr) : null;

    return TokenInfo(
      expiresAt: expiresAt,
      expired:
          expiresAt != null
              ? expiresAt.isBefore(
                DateTime.now().subtract(Duration(seconds: 5)),
              )
              : null,
      scope: tokenSet.scope,
      iss: tokenSet.iss,
      aud: tokenSet.aud,
      sub: tokenSet.sub,
    );
  }

  /// Signs out the user.
  ///
  /// This revokes the access token and deletes the session from storage.
  /// Even if revocation fails, the session is removed locally.
  Future<void> signOut() async {
    try {
      final tokenSet = await _getTokenSet(false);
      await server.revoke(tokenSet.accessToken);
    } finally {
      await sessionGetter.delStored(sub, TokenRevokedError(sub));
    }
  }

  /// Makes an authenticated HTTP request to the given pathname.
  ///
  /// This method:
  /// 1. Automatically refreshes tokens if they're expired
  /// 2. Adds DPoP and Authorization headers
  /// 3. Retries once with a fresh token if the initial request fails with 401
  ///
  /// Parameters:
  /// - [pathname]: The pathname to request (relative to the audience URL)
  /// - [method]: HTTP method (default: 'GET')
  /// - [headers]: Additional headers to include
  /// - [body]: Request body
  ///
  /// Returns the HTTP response.
  ///
  /// Example:
  /// ```dart
  /// final response = await session.fetchHandler(
  ///   '/xrpc/com.atproto.repo.createRecord',
  ///   method: 'POST',
  ///   headers: {'Content-Type': 'application/json'},
  ///   body: jsonEncode({'repo': did, 'collection': 'app.bsky.feed.post', ...}),
  /// );
  /// ```
  Future<http.Response> fetchHandler(
    String pathname, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
  }) async {
    // Try to refresh the token if it's known to be expired
    final tokenSet = await _getTokenSet('auto');

    final initialUrl = Uri.parse(tokenSet.aud).resolve(pathname);
    final initialAuth = '${tokenSet.tokenType} ${tokenSet.accessToken}';

    final initialHeaders = <String, String>{
      ...?headers,
      'Authorization': initialAuth,
    };

    // Make request with DPoP - the interceptor will automatically add DPoP header
    final initialResponse = await _makeDpopRequest(
      initialUrl,
      method: method,
      headers: initialHeaders,
      body: body,
    );

    // If the token is not expired, we don't need to refresh it
    if (!_isInvalidTokenResponse(initialResponse)) {
      return initialResponse;
    }

    // Token is invalid, try to refresh
    TokenSet tokenSetFresh;
    try {
      // Force a refresh
      tokenSetFresh = await _getTokenSet(true);
    } catch (err) {
      // If refresh fails, return the original response
      return initialResponse;
    }

    // Retry with fresh token
    final finalAuth = '${tokenSetFresh.tokenType} ${tokenSetFresh.accessToken}';
    final finalUrl = Uri.parse(tokenSetFresh.aud).resolve(pathname);

    final finalHeaders = <String, String>{
      ...?headers,
      'Authorization': finalAuth,
    };

    final finalResponse = await _makeDpopRequest(
      finalUrl,
      method: method,
      headers: finalHeaders,
      body: body,
    );

    // The token was successfully refreshed, but is still not accepted by the
    // resource server. This might be due to the resource server not accepting
    // credentials from the authorization server (e.g. because some migration
    // occurred). Any ways, there is no point in keeping the session.
    if (_isInvalidTokenResponse(finalResponse)) {
      await sessionGetter.delStored(sub, TokenInvalidError(sub));
    }

    return finalResponse;
  }

  /// Makes an HTTP request with DPoP authentication.
  ///
  /// Uses Dio with DPoP interceptor which automatically adds:
  /// - DPoP header with proof JWT
  /// - Access token hash (ath) binding
  ///
  /// Throws [DioException] for network errors, timeouts, and cancellations.
  Future<http.Response> _makeDpopRequest(
    Uri url, {
    required String method,
    Map<String, String>? headers,
    dynamic body,
  }) async {
    try {
      // Make request with Dio - interceptor will add DPoP header
      final response = await _dio.requestUri(
        url,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes, // Get raw bytes for compatibility
          validateStatus: (status) =>
              true, // Don't throw on any status code
        ),
        data: body,
      );

      // Convert Dio Response to http.Response for compatibility
      return http.Response.bytes(
        response.data as List<int>,
        response.statusCode!,
        headers: response.headers.map.map(
          (key, value) => MapEntry(key, value.join(', ')),
        ),
        reasonPhrase: response.statusMessage,
      );
    } on DioException catch (e) {
      // If we have a response (4xx/5xx), convert it to http.Response
      if (e.response != null) {
        final errorResponse = e.response!;
        return http.Response.bytes(
          errorResponse.data is List<int>
              ? errorResponse.data as List<int>
              : (errorResponse.data?.toString() ?? '').codeUnits,
          errorResponse.statusCode!,
          headers: errorResponse.headers.map.map(
            (key, value) => MapEntry(key, value.join(', ')),
          ),
          reasonPhrase: errorResponse.statusMessage,
        );
      }
      // Network errors, timeouts, cancellations - rethrow
      rethrow;
    }
  }

  /// Checks if a response indicates an invalid token.
  ///
  /// See:
  /// - https://datatracker.ietf.org/doc/html/rfc6750#section-3
  /// - https://datatracker.ietf.org/doc/html/rfc9449#name-resource-server-provided-no
  bool _isInvalidTokenResponse(http.Response response) {
    if (response.statusCode != 401) return false;

    final wwwAuth = response.headers['www-authenticate'];
    return wwwAuth != null &&
        (wwwAuth.startsWith('Bearer ') || wwwAuth.startsWith('DPoP ')) &&
        wwwAuth.contains('error="invalid_token"');
  }

  /// Disposes of resources used by this session.
  void dispose() {
    _dio.close();
  }
}
