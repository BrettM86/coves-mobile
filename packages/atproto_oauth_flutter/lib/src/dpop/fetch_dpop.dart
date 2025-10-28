import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Key;

import '../runtime/runtime_implementation.dart';

/// A simple key-value store interface for storing DPoP nonces.
///
/// This is a simplified Dart version of @atproto-labs/simple-store.
/// Implementations can use:
/// - In-memory Map (for testing)
/// - SharedPreferences (for persistence)
/// - Secure storage (for sensitive data)
abstract class SimpleStore<K, V> {
  /// Get a value by key. Returns null if not found.
  FutureOr<V?> get(K key);

  /// Set a value for a key.
  FutureOr<void> set(K key, V value);

  /// Delete a value by key.
  FutureOr<void> del(K key);

  /// Clear all values (optional).
  FutureOr<void> clear();
}

/// In-memory implementation of SimpleStore for DPoP nonces.
///
/// This is used as the default nonce store. Nonces are ephemeral and
/// don't need to be persisted across app restarts.
class InMemoryStore<K, V> implements SimpleStore<K, V> {
  final Map<K, V> _store = {};

  @override
  V? get(K key) => _store[key];

  @override
  void set(K key, V value) => _store[key] = value;

  @override
  void del(K key) => _store.remove(key);

  @override
  void clear() => _store.clear();
}

/// Options for configuring the DPoP fetch wrapper.
class DpopFetchWrapperOptions {
  /// The cryptographic key used to sign DPoP proofs.
  final Key key;

  /// Store for caching DPoP nonces per origin.
  final SimpleStore<String, String> nonces;

  /// List of algorithms supported by the server (optional).
  /// If not provided, the key's first algorithm will be used.
  final List<String>? supportedAlgs;

  /// Function to compute SHA-256 hash (required for DPoP).
  /// Should return base64url-encoded hash.
  final Future<String> Function(String input) sha256;

  /// Whether the target server is an authorization server (true)
  /// or resource server (false).
  ///
  /// This affects how "use_dpop_nonce" errors are detected:
  /// - Authorization servers return 400 with JSON error
  /// - Resource servers return 401 with WWW-Authenticate header
  ///
  /// If null, both patterns will be checked.
  final bool? isAuthServer;

  const DpopFetchWrapperOptions({
    required this.key,
    required this.nonces,
    this.supportedAlgs,
    required this.sha256,
    this.isAuthServer,
  });
}

/// Creates a Dio interceptor that adds DPoP (Demonstrating Proof of Possession)
/// headers to HTTP requests.
///
/// DPoP is a security mechanism that binds access tokens to cryptographic keys,
/// preventing token theft and replay attacks. It works by:
///
/// 1. Creating a JWT proof signed with a private key
/// 2. Including the proof in a DPoP header
/// 3. Including the access token hash (ath) in the proof
/// 4. Handling nonce-based replay protection
///
/// The interceptor automatically:
/// - Generates DPoP proofs for each request
/// - Caches and reuses server-provided nonces
/// - Retries requests when server requires a fresh nonce
/// - Handles both authorization and resource server error formats
///
/// See: https://datatracker.ietf.org/doc/html/rfc9449
///
/// Example:
/// ```dart
/// final dio = Dio();
/// final options = DpopFetchWrapperOptions(
///   key: myKey,
///   nonces: InMemoryStore(),
///   sha256: runtime.sha256,
/// );
/// dio.interceptors.add(createDpopInterceptor(options));
/// ```
Interceptor createDpopInterceptor(DpopFetchWrapperOptions options) {
  // Negotiate algorithm once at creation time
  final alg = _negotiateAlg(options.key, options.supportedAlgs);

  return InterceptorsWrapper(
    onRequest: (requestOptions, handler) async {
      try {
        // Extract authorization header for ath calculation
        final authHeader = requestOptions.headers['Authorization'] as String?;
        final String? ath;
        if (authHeader != null && authHeader.startsWith('DPoP ')) {
          ath = await options.sha256(authHeader.substring(5));
        } else {
          ath = null;
        }

        final uri = requestOptions.uri;
        final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

        final htm = requestOptions.method;
        final htu = _buildHtu(uri.toString());

        // Try to get cached nonce for this origin
        String? initNonce;
        try {
          initNonce = await options.nonces.get(origin);
        } catch (_) {
          // Ignore nonce retrieval errors
        }

        // Build and add DPoP proof
        final initProof = await _buildProof(
          options.key,
          alg,
          htm,
          htu,
          initNonce,
          ath,
        );
        requestOptions.headers['DPoP'] = initProof;

        handler.next(requestOptions);
      } catch (e) {
        handler.reject(
          DioException(
            requestOptions: requestOptions,
            error: 'Failed to create DPoP proof: $e',
            type: DioExceptionType.unknown,
          ),
        );
      }
    },
    onResponse: (response, handler) async {
      try {
        final uri = response.requestOptions.uri;

        if (kDebugMode && uri.path.contains('/token')) {
          print('🟢 DPoP interceptor onResponse triggered');
          print('   URL: ${uri.path}');
          print('   Status: ${response.statusCode}');
        }

        // Check for DPoP-Nonce header in response
        final nextNonce = response.headers.value('dpop-nonce');

        if (nextNonce != null) {
          // Extract origin from request
          final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

          // Store the fresh nonce for future requests
          try {
            await options.nonces.set(origin, nextNonce);
            if (kDebugMode && uri.path.contains('/token')) {
              print('   Cached nonce: ${nextNonce.substring(0, 20)}...');
            }
          } catch (_) {
            // Ignore nonce storage errors
          }
        } else if (kDebugMode && uri.path.contains('/token')) {
          print('   No nonce in response');
        }

        handler.next(response);
      } catch (e) {
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: 'Failed to process DPoP nonce: $e',
            type: DioExceptionType.unknown,
          ),
        );
      }
    },
    onError: (error, handler) async {
      final response = error.response;
      if (response == null) {
        handler.next(error);
        return;
      }

      final uri = response.requestOptions.uri;

      if (kDebugMode && uri.path.contains('/token')) {
        print('🔴 DPoP interceptor onError triggered');
        print('   URL: ${uri.path}');
        print('   Status: ${response.statusCode}');
        print('   Has validateStatus: ${response.requestOptions.validateStatus != null}');
      }

      // Check for DPoP-Nonce in error response
      final nextNonce = response.headers.value('dpop-nonce');

      if (nextNonce != null) {
        // Extract origin
        final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

        // Store the fresh nonce for future requests
        try {
          await options.nonces.set(origin, nextNonce);
          if (kDebugMode && uri.path.contains('/token')) {
            print('   Cached nonce: ${nextNonce.substring(0, 20)}...');
          }
        } catch (_) {
          // Ignore nonce storage errors
        }

        // Check if this is a "use_dpop_nonce" error
        final isNonceError = await _isUseDpopNonceError(
          response,
          options.isAuthServer,
        );

        if (kDebugMode && uri.path.contains('/token')) {
          print('   Is use_dpop_nonce error: $isNonceError');
        }

        if (isNonceError) {
          // IMPORTANT: Do NOT retry for token endpoint!
          // Retrying the token exchange can consume the authorization code,
          // causing "Invalid code" errors on the retry.
          //
          // Instead, we rely on pre-fetching the nonce before critical operations
          // (like authorization code exchange) to ensure we have a valid nonce
          // from the start.
          //
          // We still cache the nonce for future requests, but we don't retry
          // this particular request.
          final isTokenEndpoint = uri.path.contains('/token') ||
                                   uri.path.endsWith('/token');

          if (kDebugMode && isTokenEndpoint) {
            print('⚠️ DPoP nonce error on token endpoint - NOT retrying');
            print('   Cached fresh nonce for future requests');
          }

          if (isTokenEndpoint) {
            // Don't retry - just pass through the error with the nonce cached
            handler.next(error);
            return;
          }

          // For non-token endpoints, retry is safe
          if (kDebugMode) {
            print('🔄 DPoP retry for non-token endpoint: ${uri.path}');
          }

          try {
            final authHeader =
                response.requestOptions.headers['Authorization'] as String?;
            final String? ath;
            if (authHeader != null && authHeader.startsWith('DPoP ')) {
              ath = await options.sha256(authHeader.substring(5));
            } else {
              ath = null;
            }

            final htm = response.requestOptions.method;
            final htu = _buildHtu(uri.toString());

            final nextProof = await _buildProof(
              options.key,
              alg,
              htm,
              htu,
              nextNonce,
              ath,
            );

            // Clone request options and update DPoP header
            final retryOptions = Options(
              method: response.requestOptions.method,
              headers: {
                ...response.requestOptions.headers,
                'DPoP': nextProof,
              },
            );

            // Retry the request
            final dio = Dio();
            final retryResponse = await dio.request(
              response.requestOptions.path,
              options: retryOptions,
              data: response.requestOptions.data,
              queryParameters: response.requestOptions.queryParameters,
            );

            handler.resolve(retryResponse);
            return;
          } catch (retryError) {
            // If retry fails, return the retry error
            if (retryError is DioException) {
              handler.next(retryError);
            } else {
              handler.next(
                DioException(
                  requestOptions: response.requestOptions,
                  error: retryError,
                  type: DioExceptionType.unknown,
                ),
              );
            }
            return;
          }
        }
      }

      if (kDebugMode && uri.path.contains('/token')) {
        print('🔴 DPoP interceptor passing error through (no retry)');
      }

      handler.next(error);
    },
  );
}

/// Strips query string and fragment from URL.
///
/// Per RFC 9449, the htu (HTTP URI) claim must not include query or fragment.
///
/// See: https://www.rfc-editor.org/rfc/rfc9449.html#section-4.2-4.6
String _buildHtu(String url) {
  final fragmentIndex = url.indexOf('#');
  final queryIndex = url.indexOf('?');

  final int end;
  if (fragmentIndex == -1) {
    end = queryIndex;
  } else if (queryIndex == -1) {
    end = fragmentIndex;
  } else {
    end = fragmentIndex < queryIndex ? fragmentIndex : queryIndex;
  }

  return end == -1 ? url : url.substring(0, end);
}

/// Builds a DPoP proof JWT.
///
/// The proof is a JWT with:
/// - Header: typ="dpop+jwt", alg, jwk (public key)
/// - Payload: iat, jti, htm, htu, nonce?, ath?
///
/// See: https://datatracker.ietf.org/doc/html/rfc9449#section-4.2
Future<String> _buildProof(
  Key key,
  String alg,
  String htm,
  String htu,
  String? nonce,
  String? ath,
) async {
  final jwk = key.bareJwk;
  if (jwk == null) {
    throw StateError('Only asymmetric keys can be used for DPoP proofs');
  }

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Create header
  final header = {
    'alg': alg,
    'typ': 'dpop+jwt',
    'jwk': jwk,
  };

  // Create payload
  final payload = {
    'iat': now,
    // Random jti to prevent replay attacks
    // Any collision will cause server rejection, which is acceptable
    'jti': DateTime.now().microsecondsSinceEpoch.toString(),
    'htm': htm,
    'htu': htu,
    if (nonce != null) 'nonce': nonce,
    if (ath != null) 'ath': ath,
  };

  if (kDebugMode && htu.contains('/token')) {
    print('🔐 Creating DPoP proof for token request:');
    print('   htm: $htm');
    print('   htu: $htu');
    print('   nonce: ${nonce ?? "none"}');
    print('   ath: ${ath ?? "none"}');
    print('   jwk keys: ${jwk?.keys.toList()}');
  }

  final jwt = await key.createJwt(header, payload);

  if (kDebugMode && htu.contains('/token')) {
    print('   ✅ DPoP proof created: ${jwt.substring(0, 50)}...');
  }

  return jwt;
}

/// Checks if a response indicates a "use_dpop_nonce" error.
///
/// There are two error formats depending on server type:
///
/// 1. Resource Server (RFC 6750): 401 with WWW-Authenticate header
///    WWW-Authenticate: DPoP error="use_dpop_nonce"
///
/// 2. Authorization Server: 400 with JSON body
///    {"error": "use_dpop_nonce"}
///
/// See:
/// - https://datatracker.ietf.org/doc/html/rfc9449#name-resource-server-provided-no
/// - https://datatracker.ietf.org/doc/html/rfc9449#name-authorization-server-provid
Future<bool> _isUseDpopNonceError(
  Response response,
  bool? isAuthServer,
) async {
  // Check resource server error format (401 + WWW-Authenticate)
  if (isAuthServer == null || isAuthServer == false) {
    if (response.statusCode == 401) {
      final wwwAuth = response.headers.value('www-authenticate');
      if (wwwAuth != null && wwwAuth.startsWith('DPoP')) {
        return wwwAuth.contains('error="use_dpop_nonce"');
      }
    }
  }

  // Check authorization server error format (400 + JSON error)
  if (isAuthServer == null || isAuthServer == true) {
    if (response.statusCode == 400) {
      try {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data['error'] == 'use_dpop_nonce';
        } else if (data is String) {
          // Try to parse as JSON
          final json = jsonDecode(data);
          if (json is Map<String, dynamic>) {
            return json['error'] == 'use_dpop_nonce';
          }
        }
      } catch (_) {
        // Invalid JSON or response too large, not a use_dpop_nonce error
        return false;
      }
    }
  }

  return false;
}

/// Negotiates the algorithm to use for DPoP proofs.
///
/// If supportedAlgs is provided, uses the first algorithm that the key supports.
/// Otherwise, uses the key's first algorithm.
///
/// Throws if the key doesn't support any of the server's algorithms.
String _negotiateAlg(Key key, List<String>? supportedAlgs) {
  if (supportedAlgs != null) {
    // Use order of supportedAlgs as preference
    for (final alg in supportedAlgs) {
      if (key.algorithms.contains(alg)) {
        return alg;
      }
    }
    throw StateError(
      'Key does not match any algorithm supported by the server. '
      'Key supports: ${key.algorithms}, server supports: $supportedAlgs',
    );
  }

  // No server preference, use key's first algorithm
  if (key.algorithms.isEmpty) {
    throw StateError('Key does not support any algorithms');
  }

  return key.algorithms.first;
}
