import 'dart:convert';
import 'dart:typed_data';

import '../utils/lock.dart';
import 'runtime_implementation.dart';

/// Main runtime class that wraps a RuntimeImplementation and provides
/// high-level cryptographic operations for OAuth.
///
/// This class handles:
/// - Key generation with algorithm preference sorting
/// - SHA-256 hashing with base64url encoding
/// - Nonce generation
/// - PKCE (Proof Key for Code Exchange) generation
/// - JWK thumbprint calculation
///
/// All operations use the underlying RuntimeImplementation for
/// platform-specific cryptographic primitives.
class Runtime {
  final RuntimeImplementation _implementation;

  /// Whether the implementation provides a custom lock mechanism.
  final bool hasImplementationLock;

  /// The lock function to use (either custom or local fallback).
  final RuntimeLock usingLock;

  Runtime(this._implementation)
      : hasImplementationLock = _implementation.requestLock != null,
        usingLock = _implementation.requestLock ?? requestLocalLock;

  /// Generates a cryptographic key that supports the given algorithms.
  ///
  /// The algorithms are sorted by preference before being passed to the
  /// key factory. This ensures consistent key selection across platforms.
  ///
  /// Algorithm preference order (most to least preferred):
  /// 1. ES256K (secp256k1)
  /// 2. ES256, ES384, ES512 (elliptic curve, shorter keys first)
  /// 3. PS256, PS384, PS512 (RSA-PSS, shorter keys first)
  /// 4. RS256, RS384, RS512 (RSA-PKCS1, shorter keys first)
  /// 5. Other algorithms (maintain original order)
  ///
  /// Example:
  /// ```dart
  /// final key = await runtime.generateKey(['ES256', 'RS256', 'ES384']);
  /// // Returns key supporting ES256 (preferred over RS256 and ES384)
  /// ```
  Future<Key> generateKey(List<String> algs) async {
    final algsSorted = List<String>.from(algs)..sort(_compareAlgos);
    return _implementation.createKey(algsSorted);
  }

  /// Computes the SHA-256 hash of the input text and returns it as base64url.
  ///
  /// This is used extensively in OAuth for:
  /// - PKCE code challenge (S256 method)
  /// - JWK thumbprint calculation
  /// - DPoP access token hash (ath claim)
  ///
  /// Example:
  /// ```dart
  /// final hash = await runtime.sha256('hello world');
  /// // Returns base64url-encoded SHA-256 hash
  /// ```
  Future<String> sha256(String text) async {
    final bytes = utf8.encode(text);
    final digest = await _implementation.digest(
      Uint8List.fromList(bytes),
      const DigestAlgorithm.sha256(),
    );
    return _base64UrlEncode(digest);
  }

  /// Generates a cryptographically secure random nonce.
  ///
  /// The nonce is base64url-encoded and has the specified byte length
  /// (default 16 bytes = 128 bits of entropy).
  ///
  /// Used for:
  /// - OAuth state parameter
  /// - OIDC nonce parameter
  /// - DPoP jti (JWT ID) claim
  ///
  /// Example:
  /// ```dart
  /// final nonce = await runtime.generateNonce(); // 16 bytes
  /// final longNonce = await runtime.generateNonce(32); // 32 bytes
  /// ```
  Future<String> generateNonce([int length = 16]) async {
    final bytes = await _implementation.getRandomValues(length);
    return _base64UrlEncode(bytes);
  }

  /// Generates PKCE (Proof Key for Code Exchange) parameters.
  ///
  /// PKCE is a security extension for OAuth that prevents authorization code
  /// interception attacks. It's required for public clients (mobile/desktop apps).
  ///
  /// Returns a map with:
  /// - `verifier`: Random code verifier (base64url-encoded)
  /// - `challenge`: SHA-256 hash of verifier (base64url-encoded)
  /// - `method`: 'S256' (indicating SHA-256 hashing method)
  ///
  /// The verifier should be stored securely and sent during token exchange.
  /// The challenge is sent during authorization.
  ///
  /// See: https://datatracker.ietf.org/doc/html/rfc7636
  ///
  /// Example:
  /// ```dart
  /// final pkce = await runtime.generatePKCE();
  /// // Use pkce['challenge'] in authorization request
  /// // Store pkce['verifier'] for token exchange
  /// ```
  Future<Map<String, String>> generatePKCE([int? byteLength]) async {
    final verifier = await _generateVerifier(byteLength);
    final challenge = await sha256(verifier);
    return {
      'verifier': verifier,
      'challenge': challenge,
      'method': 'S256',
    };
  }

  /// Calculates the JWK thumbprint (jkt) for a given JSON Web Key.
  ///
  /// The thumbprint is a hash of the key's essential components, used to
  /// uniquely identify a key. For DPoP, this binds tokens to specific keys.
  ///
  /// The calculation follows RFC 7638:
  /// 1. Extract required components based on key type (kty)
  /// 2. Create canonical JSON representation
  /// 3. Compute SHA-256 hash
  /// 4. Base64url-encode the result
  ///
  /// Required components by key type:
  /// - EC: crv, kty, x, y
  /// - OKP: crv, kty, x
  /// - RSA: e, kty, n
  /// - oct: k, kty
  ///
  /// See: https://datatracker.ietf.org/doc/html/rfc7638
  ///
  /// Example:
  /// ```dart
  /// final thumbprint = await runtime.calculateJwkThumbprint(jwk);
  /// // Returns base64url-encoded SHA-256 hash of key components
  /// ```
  Future<String> calculateJwkThumbprint(Map<String, dynamic> jwk) async {
    final components = _extractJktComponents(jwk);
    final data = jsonEncode(components);
    return sha256(data);
  }

  /// Generates a PKCE code verifier.
  ///
  /// The verifier is a cryptographically random string that:
  /// - Has length between 43-128 characters (32-96 bytes before encoding)
  /// - Is base64url-encoded
  /// - SHOULD be 32 bytes (43 chars) per RFC 7636 recommendations
  ///
  /// See: https://datatracker.ietf.org/doc/html/rfc7636#section-4.1
  Future<String> _generateVerifier([int? byteLength]) async {
    final length = byteLength ?? 32;

    if (length < 32 || length > 96) {
      throw ArgumentError(
        'Invalid code_verifier length: must be between 32 and 96 bytes',
      );
    }

    final bytes = await _implementation.getRandomValues(length);
    return _base64UrlEncode(bytes);
  }

  /// Base64url encodes a byte array without padding.
  ///
  /// Base64url encoding is standard base64 with URL-safe characters:
  /// - '+' becomes '-'
  /// - '/' becomes '_'
  /// - Padding ('=') is removed
  ///
  /// This is the encoding used throughout OAuth and JWT specifications.
  String _base64UrlEncode(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Extracts the required components from a JWK for thumbprint calculation.
///
/// This follows RFC 7638 which specifies exactly which fields to include
/// in the thumbprint hash for each key type.
///
/// The components are returned in a Map that will be serialized to JSON
/// in lexicographic order (Dart's jsonEncode naturally does this).
///
/// Throws ArgumentError if:
/// - Required fields are missing
/// - Key type (kty) is unsupported
Map<String, String> _extractJktComponents(Map<String, dynamic> jwk) {
  String getRequired(String field) {
    final value = jwk[field];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('"$field" parameter missing or invalid');
    }
    return value;
  }

  final kty = getRequired('kty');

  switch (kty) {
    case 'EC':
      // Elliptic Curve keys (ES256, ES384, ES512, ES256K)
      return {
        'crv': getRequired('crv'),
        'kty': kty,
        'x': getRequired('x'),
        'y': getRequired('y'),
      };

    case 'OKP':
      // Octet Key Pair (EdDSA)
      return {
        'crv': getRequired('crv'),
        'kty': kty,
        'x': getRequired('x'),
      };

    case 'RSA':
      // RSA keys (RS256, RS384, RS512, PS256, PS384, PS512)
      return {
        'e': getRequired('e'),
        'kty': kty,
        'n': getRequired('n'),
      };

    case 'oct':
      // Symmetric keys (HS256, HS384, HS512)
      return {
        'k': getRequired('k'),
        'kty': kty,
      };

    default:
      throw ArgumentError(
        '"kty" (Key Type) parameter missing or unsupported: $kty',
      );
  }
}

/// Compares two algorithm strings for preference ordering.
///
/// Algorithm preference order:
/// 1. ES256K (secp256k1) - always most preferred
/// 2. ES* (Elliptic Curve) - prefer shorter keys
///    - ES256 > ES384 > ES512
/// 3. PS* (RSA-PSS) - prefer shorter keys
///    - PS256 > PS384 > PS512
/// 4. RS* (RSA-PKCS1) - prefer shorter keys
///    - RS256 > RS384 > RS512
/// 5. Other algorithms - maintain original order
///
/// Returns:
/// - Negative if `a` is preferred over `b`
/// - Positive if `b` is preferred over `a`
/// - Zero if no preference (maintain order)
int _compareAlgos(String a, String b) {
  // ES256K is always most preferred
  if (a == 'ES256K') return -1;
  if (b == 'ES256K') return 1;

  // Check algorithm families in preference order: ES > PS > RS
  for (final prefix in ['ES', 'PS', 'RS']) {
    if (a.startsWith(prefix)) {
      if (b.startsWith(prefix)) {
        // Both have same prefix, prefer shorter key length
        // Extract the number (e.g., "256" from "ES256")
        final aLen = int.tryParse(a.substring(2, 5)) ?? 0;
        final bLen = int.tryParse(b.substring(2, 5)) ?? 0;

        // Prefer shorter keys (256 < 384 < 512)
        return aLen - bLen;
      }
      // 'a' has the prefix, 'b' doesn't - prefer 'a'
      return -1;
    } else if (b.startsWith(prefix)) {
      // 'b' has the prefix, 'a' doesn't - prefer 'b'
      return 1;
    }
  }

  // No known preference, maintain original order
  return 0;
}
