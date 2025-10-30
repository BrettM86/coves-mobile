import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Key;

import '../dpop/fetch_dpop.dart';
import '../errors/oauth_response_error.dart';
import '../errors/token_refresh_error.dart';
import '../runtime/runtime.dart';
import '../runtime/runtime_implementation.dart';
import '../types.dart';
import 'authorization_server_metadata_resolver.dart' show GetCachedOptions;
import 'client_auth.dart';
import 'oauth_resolver.dart';

/// Represents a token set returned from OAuth token endpoint.
class TokenSet {
  /// Issuer (authorization server URL)
  final String iss;

  /// Subject (DID of the user)
  final String sub;

  /// Audience (PDS URL)
  final String aud;

  /// Scope (space-separated list of scopes)
  final String scope;

  /// Refresh token (optional)
  final String? refreshToken;

  /// Access token
  final String accessToken;

  /// Token type (must be "DPoP" for ATPROTO)
  final String tokenType;

  /// Expiration time (ISO date string)
  final String? expiresAt;

  const TokenSet({
    required this.iss,
    required this.sub,
    required this.aud,
    required this.scope,
    this.refreshToken,
    required this.accessToken,
    required this.tokenType,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'iss': iss,
      'sub': sub,
      'aud': aud,
      'scope': scope,
      if (refreshToken != null) 'refresh_token': refreshToken,
      'access_token': accessToken,
      'token_type': tokenType,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  factory TokenSet.fromJson(Map<String, dynamic> json) {
    return TokenSet(
      iss: json['iss'] as String,
      sub: json['sub'] as String,
      aud: json['aud'] as String,
      scope: json['scope'] as String,
      refreshToken: json['refresh_token'] as String?,
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresAt: json['expires_at'] as String?,
    );
  }
}

/// DPoP nonce cache type.
typedef DpopNonceCache = SimpleStore<String, String>;

/// Agent for interacting with an OAuth authorization server.
///
/// This class handles:
/// - Token exchange (authorization code → tokens)
/// - Token refresh (refresh token → new tokens)
/// - Token revocation
/// - DPoP proof generation and nonce management
/// - Client authentication
///
/// All token requests include DPoP proofs to bind tokens to keys.
class OAuthServerAgent {
  final ClientAuthMethod authMethod;
  final Key dpopKey;
  final Map<String, dynamic> serverMetadata;
  final ClientMetadata clientMetadata;
  final DpopNonceCache dpopNonces;
  final OAuthResolver oauthResolver;
  final Runtime runtime;
  final Keyset? keyset;
  final Dio _dio;
  final ClientCredentialsFactory _clientCredentialsFactory;

  /// Creates an OAuth server agent.
  ///
  /// Throws [AuthMethodUnsatisfiableError] if the auth method cannot be satisfied.
  OAuthServerAgent({
    required this.authMethod,
    required this.dpopKey,
    required this.serverMetadata,
    required this.clientMetadata,
    required this.dpopNonces,
    required this.oauthResolver,
    required this.runtime,
    this.keyset,
    Dio? dio,
  }) : // CRITICAL: Always create a NEW Dio instance to avoid duplicate interceptors
       // If we reuse a shared Dio instance, each OAuthServerAgent will add its
       // interceptors to the same instance, causing duplicate requests!
       _dio = Dio(dio?.options ?? BaseOptions()),
       _clientCredentialsFactory = createClientCredentialsFactory(
         authMethod,
         serverMetadata,
         clientMetadata,
         runtime,
         keyset,
       ) {
    // Add debug logging interceptor (runs before DPoP interceptor)
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('/token')) {
              print(
                '📤 [BEFORE DPoP] Request headers: ${options.headers.keys.toList()}',
              );
            }
            handler.next(options);
          },
        ),
      );
    }

    // Add DPoP interceptor
    _dio.interceptors.add(
      createDpopInterceptor(
        DpopFetchWrapperOptions(
          key: dpopKey,
          nonces: dpopNonces,
          sha256: runtime.sha256,
          isAuthServer: true,
        ),
      ),
    );

    // Add final logging interceptor (runs after DPoP interceptor)
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('/token')) {
              print(
                '📤 [AFTER DPoP] Request headers: ${options.headers.keys.toList()}',
              );
              if (options.headers.containsKey('dpop')) {
                print(
                  '   DPoP header present: ${options.headers['dpop']?.toString().substring(0, 50)}...',
                );
              } else if (options.headers.containsKey('DPoP')) {
                print(
                  '   DPoP header present: ${options.headers['DPoP']?.toString().substring(0, 50)}...',
                );
              } else {
                print('   ⚠️ DPoP header MISSING!');
              }
            }
            handler.next(options);
          },
          onError: (error, handler) {
            if (error.requestOptions.uri.path.contains('/token')) {
              print('📥 Token request error: ${error.message}');
            }
            handler.next(error);
          },
        ),
      );
    }
  }

  /// The issuer (authorization server URL).
  String get issuer => serverMetadata['issuer'] as String;

  /// Revokes a token.
  ///
  /// Errors are silently ignored as revocation is best-effort.
  Future<void> revoke(String token) async {
    try {
      await _request('revocation', {'token': token});
    } catch (_) {
      // Don't care if revocation fails
    }
  }

  /// Pre-fetches a DPoP nonce from the token endpoint.
  ///
  /// This is critical for authorization code exchange because:
  /// 1. First token request without nonce → PDS consumes code + returns use_dpop_nonce error
  /// 2. Retry with nonce → "Invalid code" because already consumed
  ///
  /// Solution: Get a nonce BEFORE attempting code exchange.
  ///
  /// We make a lightweight invalid request that will fail but return a nonce.
  /// The server responds with a nonce in the DPoP-Nonce header, which the
  /// interceptor automatically caches for subsequent requests.
  Future<void> _prefetchDpopNonce() async {
    final tokenEndpoint = serverMetadata['token_endpoint'] as String?;
    if (tokenEndpoint == null) return;

    final origin = Uri.parse(tokenEndpoint);
    final originKey =
        '${origin.scheme}://${origin.host}${origin.hasPort ? ':${origin.port}' : ''}';

    // Clear any stale nonce from previous sessions
    try {
      await dpopNonces.del(originKey);
      if (kDebugMode) {
        print('🧹 Cleared stale DPoP nonce from cache');
      }
    } catch (_) {
      // Ignore deletion errors
    }

    if (kDebugMode) {
      print('⏱️  Pre-fetch starting at: ${DateTime.now().toIso8601String()}');
    }

    try {
      // Make a minimal invalid request to trigger nonce response
      // Use an invalid grant_type that will fail fast without side effects
      await _dio.post<Map<String, dynamic>>(
        tokenEndpoint,
        data: 'grant_type=invalid_prefetch',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          validateStatus: (status) => true, // Accept any status
        ),
      );
    } catch (_) {
      // Ignore all errors - we just want the nonce from the response headers
      // The DPoP interceptor will have cached it in onError or onResponse
    }

    if (kDebugMode) {
      print('⏱️  Pre-fetch completed at: ${DateTime.now().toIso8601String()}');
      final cachedNonce = await dpopNonces.get(originKey);
      print('🎫 DPoP nonce pre-fetch result:');
      print(
        '   Cached nonce: ${cachedNonce != null ? "✅ ${cachedNonce.substring(0, 20)}..." : "❌ not found"}',
      );
    }
  }

  /// Exchanges an authorization code for tokens.
  ///
  /// This is called after the user completes authorization and you receive
  /// the authorization code in the callback.
  ///
  /// [code] is the authorization code from the callback.
  /// [codeVerifier] is the PKCE code verifier (if PKCE was used).
  /// [redirectUri] is the redirect URI used in the authorization request.
  ///
  /// Returns a [TokenSet] with access token, optional refresh token, and metadata.
  ///
  /// IMPORTANT: This method verifies the issuer before returning tokens.
  /// If verification fails, the access token is automatically revoked.
  Future<TokenSet> exchangeCode(
    String code, {
    String? codeVerifier,
    String? redirectUri,
  }) async {
    // CRITICAL: DO NOT pre-fetch! Exchange immediately!
    // The pre-fetch adds ~678ms delay, during which the browser re-navigates
    // and invalidates the authorization code. We need to exchange within ~270ms.
    // If we get a nonce error, we'll handle it via the interceptor (though PDS
    // doesn't seem to require nonces for initial token exchange).

    final now = DateTime.now();

    final tokenResponse = await _request('token', {
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri ?? clientMetadata.redirectUris.first,
      'code': code,
      if (codeVerifier != null) 'code_verifier': codeVerifier,
    });

    try {
      // CRITICAL: Verify issuer before trusting the sub
      // The tokenResponse MUST always be valid before the "sub" can be trusted
      // See: https://atproto.com/specs/oauth
      final aud = await _verifyIssuer(tokenResponse['sub'] as String);

      return TokenSet(
        aud: aud,
        sub: tokenResponse['sub'] as String,
        iss: issuer,
        scope: tokenResponse['scope'] as String,
        refreshToken: tokenResponse['refresh_token'] as String?,
        accessToken: tokenResponse['access_token'] as String,
        tokenType: tokenResponse['token_type'] as String,
        expiresAt:
            tokenResponse['expires_in'] != null
                ? now
                    .add(Duration(seconds: tokenResponse['expires_in'] as int))
                    .toIso8601String()
                : null,
      );
    } catch (err) {
      // If verification fails, revoke the access token
      await revoke(tokenResponse['access_token'] as String);
      rethrow;
    }
  }

  /// Refreshes a token set using the refresh token.
  ///
  /// [tokenSet] is the current token set with a refresh_token.
  ///
  /// Returns a new [TokenSet] with fresh tokens.
  ///
  /// Throws [TokenRefreshError] if refresh fails or no refresh token is available.
  ///
  /// IMPORTANT: This method verifies the issuer before returning tokens.
  Future<TokenSet> refresh(TokenSet tokenSet) async {
    if (tokenSet.refreshToken == null) {
      throw TokenRefreshError(tokenSet.sub, 'No refresh token available');
    }

    // CRITICAL: Verify issuer BEFORE refresh to avoid unnecessary requests
    // and ensure the sub is still valid for this issuer
    final aud = await _verifyIssuer(tokenSet.sub);

    final now = DateTime.now();

    final tokenResponse = await _request('token', {
      'grant_type': 'refresh_token',
      'refresh_token': tokenSet.refreshToken,
    });

    return TokenSet(
      aud: aud,
      sub: tokenSet.sub,
      iss: issuer,
      scope: tokenResponse['scope'] as String,
      refreshToken: tokenResponse['refresh_token'] as String?,
      accessToken: tokenResponse['access_token'] as String,
      tokenType: tokenResponse['token_type'] as String,
      expiresAt:
          tokenResponse['expires_in'] != null
              ? now
                  .add(Duration(seconds: tokenResponse['expires_in'] as int))
                  .toIso8601String()
              : null,
    );
  }

  /// Verifies that the sub (DID) is indeed issued by this authorization server.
  ///
  /// This is CRITICAL for security. We must verify that the DID's PDS
  /// is protected by this authorization server before trusting tokens.
  ///
  /// Returns the user's PDS URL (the resource server).
  ///
  /// Throws if:
  /// - DID resolution fails
  /// - Issuer mismatch (user may have switched PDS or attack detected)
  Future<String> _verifyIssuer(String sub) async {
    final cancelToken = CancelToken();
    final resolved = await oauthResolver
        .resolveFromIdentity(
          sub,
          GetCachedOptions(
            noCache: true,
            allowStale: false,
            cancelToken: cancelToken,
          ),
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            cancelToken.cancel();
            throw TimeoutException('Issuer verification timed out');
          },
        );

    if (issuer != resolved.metadata['issuer']) {
      // Best case: user switched PDS
      // Worst case: attack attempt
      // Either way: MUST NOT allow this token to be used
      throw FormatException('Issuer mismatch');
    }

    return resolved.pds.toString();
  }

  /// Makes a request to an OAuth endpoint (public API).
  ///
  /// This is a generic method for making OAuth endpoint requests with proper typing.
  /// Currently supports: token, revocation, pushed_authorization_request.
  ///
  /// [endpoint] is the endpoint name.
  /// [payload] is the request body parameters.
  ///
  /// Returns the parsed JSON response.
  /// Throws [OAuthResponseError] if the server returns an error.
  Future<Map<String, dynamic>> request(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    return _request(endpoint, payload);
  }

  /// Makes a request to an OAuth endpoint (internal implementation).
  ///
  /// [endpoint] is the endpoint name (e.g., 'token', 'revocation', 'pushed_authorization_request').
  /// [payload] is the request body parameters.
  ///
  /// Returns the parsed JSON response.
  /// Throws [OAuthResponseError] if the server returns an error.
  Future<Map<String, dynamic>> _request(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final url = serverMetadata['${endpoint}_endpoint'];
    if (url == null) {
      throw StateError('No $endpoint endpoint available');
    }

    final auth = await _clientCredentialsFactory();

    final fullPayload = {...payload, ...auth.payload.toJson()};
    final encodedData = _wwwFormUrlEncode(fullPayload);

    if (kDebugMode && endpoint == 'token') {
      print('🌐 Token exchange HTTP request:');
      print('   ⏱️  Request starting at: ${DateTime.now().toIso8601String()}');
      print('   URL: $url');
      print('   Payload keys: ${fullPayload.keys.toList()}');
      print('   grant_type: ${fullPayload['grant_type']}');
      print('   client_id: ${fullPayload['client_id']}');
      print('   redirect_uri: ${fullPayload['redirect_uri']}');
      print('   code: ${fullPayload['code']?.toString().substring(0, 20)}...');
      print(
        '   code_verifier: ${fullPayload['code_verifier']?.toString().substring(0, 20)}...',
      );
      print('   Headers: ${auth.headers?.keys.toList() ?? []}');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url as String,
        data: encodedData,
        options: Options(
          headers: {
            if (auth.headers != null) ...auth.headers!,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      final data = response.data;
      if (data == null) {
        throw OAuthResponseError(response, {'error': 'empty_response'});
      }

      if (kDebugMode && endpoint == 'token') {
        print('   ✅ Token exchange successful!');
      }

      return data;
    } on DioException catch (e) {
      final response = e.response;
      if (response != null) {
        if (kDebugMode && endpoint == 'token') {
          print('   ❌ Token exchange failed:');
          print('   Status: ${response.statusCode}');
          print('   Response: ${response.data}');
        }
        throw OAuthResponseError(response, response.data);
      }
      rethrow;
    }
  }

  /// Encodes a map as application/x-www-form-urlencoded.
  String _wwwFormUrlEncode(Map<String, dynamic> payload) {
    final entries = payload.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, _stringifyValue(e.value)));

    return Uri(queryParameters: Map.fromEntries(entries)).query;
  }

  /// Converts a value to string for form encoding.
  String _stringifyValue(dynamic value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    // For complex types, use JSON encoding
    return value.toString();
  }
}

/// Timeout exception.
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
