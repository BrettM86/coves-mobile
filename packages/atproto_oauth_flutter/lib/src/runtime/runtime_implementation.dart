import 'dart:async';
import 'dart:typed_data';

/// Represents a cryptographic key that can sign and verify JWTs.
///
/// This is a placeholder for the Key class from @atproto/jwk.
/// In the full implementation, this should be imported from the jwk package.
///
/// The Key class contains:
/// - JWK representation (public and private)
/// - Supported algorithms
/// - createJwt() method for signing
/// - verifyJwt() method for verification
///
/// ## TODO: Key Serialization
///
/// This class needs serialization support to persist DPoP keys in session storage:
///
/// 1. Add `Map<String, dynamic> toJson()` method:
///    - Should serialize the full JWK (including private key components)
///    - Must be secure - never log or expose
///    - Used when storing sessions
///
/// 2. Add `static Key fromJson(Map<String, dynamic> json)` factory:
///    - Should reconstruct a Key from serialized JWK
///    - Must validate the JWK structure
///    - Used when restoring sessions from storage
///
/// ## Current Workaround
///
/// Without serialization, DPoP keys are regenerated on each app restart.
/// This works but has drawbacks:
/// - Tokens from previous keys become invalid (require refresh)
/// - Server-side DPoP nonce cache misses
/// - Slightly slower session restoration
///
/// This is acceptable for now but should be fixed before production.
abstract class Key {
  /// Create a signed JWT with the given header and payload.
  Future<String> createJwt(
    Map<String, dynamic> header,
    Map<String, dynamic> payload,
  );

  /// The list of algorithms this key supports.
  List<String> get algorithms;

  /// The bare JWK (public key components only, for DPoP proofs).
  /// Returns null for symmetric keys.
  Map<String, dynamic>? get bareJwk;

  /// The key ID (kid) from the JWK.
  /// Returns null if the key doesn't have a kid.
  String? get kid;

  /// The usage of this key ('sign' or 'enc').
  String get usage;

  // TODO: Uncomment these when implementing serialization:
  // Map<String, dynamic> toJson();
  // static Key fromJson(Map<String, dynamic> json);
}

/// Factory function that creates a cryptographic key for the given algorithms.
///
/// The key should support at least one of the provided algorithms.
/// Algorithms are typically in order of preference.
///
/// Common algorithms:
/// - ES256, ES384, ES512 (Elliptic Curve)
/// - ES256K (secp256k1)
/// - RS256, RS384, RS512 (RSA)
/// - PS256, PS384, PS512 (RSA-PSS)
typedef RuntimeKeyFactory = FutureOr<Key> Function(List<String> algs);

/// Generates cryptographically secure random bytes.
///
/// Returns a Uint8List of the specified length filled with random bytes.
/// Must use a cryptographically secure random number generator.
typedef RuntimeRandomValues = FutureOr<Uint8List> Function(int length);

/// Digest algorithm specification.
class DigestAlgorithm {
  /// The hash algorithm name: 'sha256', 'sha384', or 'sha512'.
  final String name;

  const DigestAlgorithm({required this.name});

  const DigestAlgorithm.sha256() : name = 'sha256';
  const DigestAlgorithm.sha384() : name = 'sha384';
  const DigestAlgorithm.sha512() : name = 'sha512';
}

/// Computes a cryptographic hash (digest) of the input data.
///
/// The algorithm specifies which hash function to use (SHA-256, SHA-384, SHA-512).
/// Returns the hash as a Uint8List.
typedef RuntimeDigest =
    FutureOr<Uint8List> Function(Uint8List data, DigestAlgorithm alg);

/// Acquires a lock for the given name and executes the function while holding the lock.
///
/// This ensures that only one execution of the function can run at a time for a given lock name.
/// This is critical for preventing race conditions during token refresh operations.
///
/// Example:
/// ```dart
/// final result = await requestLock('token-refresh', () async {
///   // Critical section - only one execution at a time
///   return await refreshToken();
/// });
/// ```
typedef RuntimeLock =
    Future<T> Function<T>(String name, FutureOr<T> Function() fn);

/// Platform-specific runtime implementation for cryptographic operations.
///
/// This interface defines the core cryptographic primitives needed for OAuth:
/// - Key generation (createKey)
/// - Random number generation (getRandomValues)
/// - Cryptographic hashing (digest)
/// - Optional locking mechanism (requestLock)
///
/// Implementations must use secure cryptographic libraries:
/// - For Dart: pointycastle (ECDSA), crypto (SHA hashing)
/// - Random values must come from dart:math.Random.secure()
///
/// Security considerations:
/// - Keys must be generated using cryptographically secure randomness
/// - Private keys must never be logged or exposed
/// - Hash functions must be collision-resistant (SHA-256 minimum)
/// - Lock implementation should prevent race conditions in token refresh
abstract class RuntimeImplementation {
  /// Creates a cryptographic key that supports at least one of the given algorithms.
  ///
  /// The algorithms list is typically sorted by preference, with the most preferred first.
  ///
  /// For OAuth DPoP, common algorithm preferences are:
  /// - ES256K (secp256k1) - preferred for atproto
  /// - ES256, ES384, ES512 (NIST curves)
  /// - PS256, PS384, PS512 (RSA-PSS)
  /// - RS256, RS384, RS512 (RSA-PKCS1)
  ///
  /// Throws if no suitable key can be generated for any of the algorithms.
  RuntimeKeyFactory get createKey;

  /// Generates cryptographically secure random bytes.
  ///
  /// MUST use a cryptographically secure random number generator.
  /// In Dart, use Random.secure() from dart:math.
  ///
  /// Never use a regular Random() - this is a security vulnerability.
  RuntimeRandomValues get getRandomValues;

  /// Computes a cryptographic hash of the input data.
  ///
  /// Supported algorithms: SHA-256, SHA-384, SHA-512
  ///
  /// Implementation should use the crypto package's sha256, sha384, sha512.
  RuntimeDigest get digest;

  /// Optional platform-specific lock implementation.
  ///
  /// If provided, this will be used to prevent concurrent token refresh operations.
  /// If not provided, a local (in-memory) lock implementation will be used as fallback.
  ///
  /// The lock should be:
  /// - Re-entrant safe (same isolate can acquire multiple times)
  /// - Fair (FIFO order)
  /// - Automatically released on error
  ///
  /// For Flutter apps, the default local lock is usually sufficient.
  /// For multi-process scenarios, you may need a platform-specific implementation.
  RuntimeLock? get requestLock;
}
