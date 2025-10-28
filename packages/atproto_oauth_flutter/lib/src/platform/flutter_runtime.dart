import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../runtime/runtime_implementation.dart';
import '../utils/lock.dart';
import 'flutter_key.dart';

/// Flutter implementation of RuntimeImplementation.
///
/// Provides cryptographic operations for OAuth flows using:
/// - pointycastle for EC key generation (via FlutterKey)
/// - crypto package for SHA hashing
/// - Random.secure() for cryptographically secure random values
/// - requestLocalLock for concurrency control
///
/// This implementation supports:
/// - ES256, ES384, ES512, ES256K (Elliptic Curve algorithms)
/// - SHA-256, SHA-384, SHA-512 (Hash algorithms)
/// - Secure random number generation
/// - Local (in-memory) locking for token refresh
///
/// Example:
/// ```dart
/// final runtime = FlutterRuntime();
///
/// // Generate a key
/// final key = await runtime.createKey(['ES256', 'ES384']);
///
/// // Hash some data
/// final hash = await runtime.digest(
///   Uint8List.fromList([1, 2, 3]),
///   DigestAlgorithm.sha256(),
/// );
///
/// // Generate random bytes
/// final random = await runtime.getRandomValues(32);
/// ```
class FlutterRuntime implements RuntimeImplementation {
  /// Creates a FlutterRuntime instance.
  const FlutterRuntime();

  @override
  RuntimeKeyFactory get createKey {
    return (List<String> algs) async {
      return FlutterKey.generate(algs);
    };
  }

  @override
  RuntimeDigest get digest {
    return (Uint8List bytes, DigestAlgorithm algorithm) async {
      switch (algorithm.name) {
        case 'sha256':
        case 'SHA-256':
          return Uint8List.fromList(crypto.sha256.convert(bytes).bytes);

        case 'sha384':
        case 'SHA-384':
          return Uint8List.fromList(crypto.sha384.convert(bytes).bytes);

        case 'sha512':
        case 'SHA-512':
          return Uint8List.fromList(crypto.sha512.convert(bytes).bytes);

        default:
          throw UnsupportedError(
            'Unsupported digest algorithm: ${algorithm.name}',
          );
      }
    };
  }

  @override
  RuntimeRandomValues get getRandomValues {
    return (int length) async {
      final random = Random.secure();
      return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)),
      );
    };
  }

  @override
  RuntimeLock get requestLock {
    // Use the local lock implementation from utils/lock.dart
    // This prevents concurrent token refresh within a single isolate
    return requestLocalLock;
  }
}
