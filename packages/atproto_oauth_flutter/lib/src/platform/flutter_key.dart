import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pointycastle;

import '../runtime/runtime_implementation.dart';

/// Flutter implementation of Key using pointycastle for cryptographic operations.
///
/// Supports EC keys with the following algorithms:
/// - ES256 (P-256/secp256r1)
/// - ES384 (P-384/secp384r1)
/// - ES512 (P-521/secp521r1) - Note: P-521, not P-512
/// - ES256K (secp256k1)
///
/// This class handles:
/// - Key generation with secure randomness
/// - JWT signing (ES256/ES384/ES512/ES256K)
/// - JWK representation (public and private components)
/// - Serialization/deserialization for session storage
class FlutterKey implements Key {
  /// The EC private key (contains both private and public components)
  final pointycastle.ECPrivateKey privateKey;

  /// The EC public key
  final pointycastle.ECPublicKey publicKey;

  /// The algorithm this key supports
  final String algorithm;

  /// Optional key ID
  final String? _kid;

  /// Creates a FlutterKey from EC key components.
  FlutterKey({
    required this.privateKey,
    required this.publicKey,
    required this.algorithm,
    String? kid,
  }) : _kid = kid;

  @override
  List<String> get algorithms => [algorithm];

  @override
  String? get kid => _kid;

  @override
  String get usage => 'sign';

  @override
  Map<String, dynamic>? get bareJwk {
    // Return public key components only (no private key 'd')
    final jwk = _ecPublicKeyToJwk(publicKey, algorithm);
    if (_kid != null) {
      jwk['kid'] = _kid;
    }
    return jwk;
  }

  /// Full JWK including private key components.
  ///
  /// WARNING: This contains sensitive key material. Never log or expose.
  /// Only use for secure storage.
  Map<String, dynamic> get privateJwk {
    final jwk = _ecPrivateKeyToJwk(privateKey, publicKey, algorithm);
    if (_kid != null) {
      jwk['kid'] = _kid;
    }
    return jwk;
  }

  @override
  Future<String> createJwt(
    Map<String, dynamic> header,
    Map<String, dynamic> payload,
  ) async {
    // Build JWT header
    final jwtHeader = <String, dynamic>{
      'typ': 'JWT',
      'alg': algorithm,
      ...header,
    };
    if (_kid != null) {
      jwtHeader['kid'] = _kid;
    }

    // Encode header and payload
    final headerB64 = _base64UrlEncode(utf8.encode(json.encode(jwtHeader)));
    final payloadB64 = _base64UrlEncode(utf8.encode(json.encode(payload)));

    // Create signing input
    final signingInput = '$headerB64.$payloadB64';
    final signingBytes = utf8.encode(signingInput);

    // Sign with appropriate algorithm
    final signature = _signEcdsa(signingBytes, privateKey, algorithm);

    // Encode signature
    final signatureB64 = _base64UrlEncode(signature);

    // Return compact JWT
    return '$signingInput.$signatureB64';
  }

  /// Generates a new FlutterKey for the given algorithms.
  ///
  /// Returns a key supporting the first compatible algorithm from the list.
  ///
  /// Throws [UnsupportedError] if no compatible algorithm is found.
  static Future<FlutterKey> generate(List<String> algs) async {
    // Try algorithms in order
    for (final alg in algs) {
      switch (alg) {
        case 'ES256':
          return _generateECKey('ES256', 'P-256');
        case 'ES384':
          return _generateECKey('ES384', 'P-384');
        case 'ES512':
          return _generateECKey('ES512', 'P-521'); // Note: P-521, not P-512
        case 'ES256K':
          return _generateECKey('ES256K', 'secp256k1');
      }
    }

    throw UnsupportedError(
      'No supported algorithm found in: ${algs.join(", ")}',
    );
  }

  /// Reconstructs a FlutterKey from serialized JWK data.
  ///
  /// This is used when restoring sessions from storage.
  factory FlutterKey.fromJwk(Map<String, dynamic> jwk) {
    final kty = jwk['kty'] as String?;
    if (kty != 'EC') {
      throw FormatException('Unsupported key type: $kty');
    }

    final crv = jwk['crv'] as String?;
    final alg = jwk['alg'] as String?;
    final kid = jwk['kid'] as String?;

    if (crv == null || alg == null) {
      throw FormatException('Missing required JWK fields');
    }

    // Parse key components
    final x = _base64UrlDecode(jwk['x'] as String);
    final y = _base64UrlDecode(jwk['y'] as String);
    final d = jwk['d'] != null ? _base64UrlDecode(jwk['d'] as String) : null;

    if (d == null) {
      throw FormatException('Private key component (d) is required');
    }

    // Get curve
    final curve = _getCurveForName(crv);

    // Reconstruct public key
    final publicKey = pointycastle.ECPublicKey(
      curve.curve.createPoint(
        _bytesToBigInt(x),
        _bytesToBigInt(y),
      ),
      curve,
    );

    // Reconstruct private key
    final privateKey = pointycastle.ECPrivateKey(_bytesToBigInt(d), curve);

    return FlutterKey(
      privateKey: privateKey,
      publicKey: publicKey,
      algorithm: alg,
      kid: kid,
    );
  }

  /// Serializes this key to JSON (for session storage).
  ///
  /// WARNING: Contains private key material. Store securely.
  Map<String, dynamic> toJson() => privateJwk;

  // ============================================================================
  // Private helper methods
  // ============================================================================

  /// Generates an EC key pair for the given algorithm and curve.
  static Future<FlutterKey> _generateECKey(
    String algorithm,
    String curveName,
  ) async {
    final curve = _getCurveForName(curveName);

    // Create secure random generator
    final secureRandom = pointycastle.FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(pointycastle.KeyParameter(Uint8List.fromList(seeds)));

    // Generate key pair
    final keyGen = pointycastle.ECKeyGenerator();
    keyGen.init(
      pointycastle.ParametersWithRandom(
        pointycastle.ECKeyGeneratorParameters(curve),
        secureRandom,
      ),
    );

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as pointycastle.ECPrivateKey;
    final publicKey = keyPair.publicKey as pointycastle.ECPublicKey;

    return FlutterKey(
      privateKey: privateKey,
      publicKey: publicKey,
      algorithm: algorithm,
    );
  }

  /// Gets the EC domain parameters for a given curve name.
  static pointycastle.ECDomainParameters _getCurveForName(String name) {
    // Use pointycastle's standard curve implementations
    switch (name) {
      case 'P-256':
      case 'prime256v1':
      case 'secp256r1':
        return pointycastle.ECCurve_secp256r1();
      case 'P-384':
      case 'secp384r1':
        return pointycastle.ECCurve_secp384r1();
      case 'P-521':
      case 'secp521r1':
        return pointycastle.ECCurve_secp521r1();
      case 'secp256k1':
        return pointycastle.ECCurve_secp256k1();
      default:
        throw UnsupportedError('Unsupported curve: $name');
    }
  }

  /// Gets the curve name for JWK representation.
  static String _getCurveName(String algorithm) {
    switch (algorithm) {
      case 'ES256':
        return 'P-256';
      case 'ES384':
        return 'P-384';
      case 'ES512':
        return 'P-521';
      case 'ES256K':
        return 'secp256k1';
      default:
        throw UnsupportedError('Unsupported algorithm: $algorithm');
    }
  }

  /// Gets the hash algorithm for signing.
  static String _getHashAlgorithm(String algorithm) {
    switch (algorithm) {
      case 'ES256':
      case 'ES256K':
        return 'SHA-256';
      case 'ES384':
        return 'SHA-384';
      case 'ES512':
        return 'SHA-512';
      default:
        throw UnsupportedError('Unsupported algorithm: $algorithm');
    }
  }

  /// Signs data using ECDSA with deterministic signatures (RFC 6979).
  ///
  /// This uses deterministic ECDSA which doesn't require a source of randomness,
  /// making it more secure and avoiding SecureRandom initialization issues.
  static Uint8List _signEcdsa(
    List<int> data,
    pointycastle.ECPrivateKey privateKey,
    String algorithm,
  ) {
    // Get the appropriate hash algorithm for this signing algorithm
    final hashAlg = _getHashAlgorithm(algorithm);

    // Build deterministic ECDSA signer name (e.g., "SHA-256/DET-ECDSA")
    final signerName = '$hashAlg/DET-ECDSA';

    // Use deterministic ECDSA signer (RFC 6979) - no randomness required!
    final signer = pointycastle.Signer(signerName);
    signer.init(
      true, // signing mode
      pointycastle.PrivateKeyParameter<pointycastle.ECPrivateKey>(privateKey),
    );

    // Sign the data (signer will hash it internally)
    final signature = signer.generateSignature(Uint8List.fromList(data)) as pointycastle.ECSignature;

    // Encode as IEEE P1363 format (r || s)
    final r = _bigIntToBytes(signature.r, _getSignatureLength(algorithm));
    final s = _bigIntToBytes(signature.s, _getSignatureLength(algorithm));

    return Uint8List.fromList([...r, ...s]);
  }

  /// Creates a pointycastle Digest for the given hash algorithm.
  static pointycastle.Digest _createDigest(String algorithm) {
    switch (algorithm) {
      case 'SHA-256':
        return pointycastle.SHA256Digest();
      case 'SHA-384':
        return pointycastle.SHA384Digest();
      case 'SHA-512':
        return pointycastle.SHA512Digest();
      default:
        throw UnsupportedError('Unsupported hash: $algorithm');
    }
  }

  /// Gets the signature length in bytes for the algorithm.
  static int _getSignatureLength(String algorithm) {
    switch (algorithm) {
      case 'ES256':
      case 'ES256K':
        return 32;
      case 'ES384':
        return 48;
      case 'ES512':
        return 66; // P-521 uses 66 bytes per component
      default:
        throw UnsupportedError('Unsupported algorithm: $algorithm');
    }
  }

  /// Converts an EC public key to JWK format.
  static Map<String, dynamic> _ecPublicKeyToJwk(
    pointycastle.ECPublicKey publicKey,
    String algorithm,
  ) {
    final q = publicKey.Q!;
    final curve = _getCurveName(algorithm);

    return {
      'kty': 'EC',
      'crv': curve,
      'x': _base64UrlEncode(_bigIntToBytes(q.x!.toBigInteger()!)),
      'y': _base64UrlEncode(_bigIntToBytes(q.y!.toBigInteger()!)),
      'alg': algorithm,
      'use': 'sig',
      'key_ops': ['sign'],
    };
  }

  /// Converts an EC private key to JWK format (includes private component).
  static Map<String, dynamic> _ecPrivateKeyToJwk(
    pointycastle.ECPrivateKey privateKey,
    pointycastle.ECPublicKey publicKey,
    String algorithm,
  ) {
    final jwk = _ecPublicKeyToJwk(publicKey, algorithm);
    jwk['d'] = _base64UrlEncode(_bigIntToBytes(privateKey.d!));
    return jwk;
  }

  /// Converts a BigInt to bytes with optional padding.
  static Uint8List _bigIntToBytes(BigInt number, [int? length]) {
    var bytes = _encodeBigInt(number);

    if (length != null) {
      if (bytes.length > length) {
        // Remove leading zeros
        bytes = bytes.sublist(bytes.length - length);
      } else if (bytes.length < length) {
        // Add leading zeros
        final padded = Uint8List(length);
        padded.setRange(length - bytes.length, length, bytes);
        bytes = padded;
      }
    }

    return bytes;
  }

  /// Encodes a BigInt as bytes (unsigned, big-endian).
  static Uint8List _encodeBigInt(BigInt number) {
    // Handle zero
    if (number == BigInt.zero) {
      return Uint8List.fromList([0]);
    }

    // Handle negative (should not happen for EC keys)
    if (number.isNegative) {
      throw ArgumentError('Cannot encode negative BigInt');
    }

    // Convert to bytes
    final bytes = <int>[];
    var n = number;
    while (n > BigInt.zero) {
      bytes.insert(0, (n & BigInt.from(0xff)).toInt());
      n = n >> 8;
    }

    return Uint8List.fromList(bytes);
  }

  /// Converts bytes to BigInt (unsigned, big-endian).
  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (var byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  /// Base64url encodes bytes (no padding).
  static String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Base64url decodes a string.
  static Uint8List _base64UrlDecode(String str) {
    // Add padding if needed
    var s = str;
    switch (s.length % 4) {
      case 2:
        s += '==';
        break;
      case 3:
        s += '=';
        break;
    }
    return base64Url.decode(s);
  }
}
