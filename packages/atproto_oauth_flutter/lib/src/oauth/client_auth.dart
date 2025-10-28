import '../constants.dart';
import '../errors/auth_method_unsatisfiable_error.dart';
import '../runtime/runtime.dart';
import '../runtime/runtime_implementation.dart';
import '../types.dart';

/// Represents a client authentication method.
///
/// OAuth supports different ways for clients to authenticate with the
/// authorization server:
/// - 'none': Public client (no secret), only client_id
/// - 'private_key_jwt': Confidential client using JWT signed with private key
class ClientAuthMethod {
  final String method;
  final String? kid; // Key ID for private_key_jwt method

  const ClientAuthMethod.none() : method = 'none', kid = null;

  const ClientAuthMethod.privateKeyJwt(this.kid) : method = 'private_key_jwt';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClientAuthMethod &&
        other.method == method &&
        other.kid == kid;
  }

  @override
  int get hashCode => method.hashCode ^ kid.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      if (kid != null) 'kid': kid,
    };
  }

  factory ClientAuthMethod.fromJson(Map<String, dynamic> json) {
    final method = json['method'] as String;
    if (method == 'none') {
      return const ClientAuthMethod.none();
    } else if (method == 'private_key_jwt') {
      return ClientAuthMethod.privateKeyJwt(json['kid'] as String);
    }
    throw FormatException('Unknown auth method: $method');
  }
}

/// Credential payload to include in OAuth requests.
class OAuthClientCredentials {
  /// Client identifier
  final String clientId;

  /// Client assertion type (for private_key_jwt)
  final String? clientAssertionType;

  /// Client assertion JWT (for private_key_jwt)
  final String? clientAssertion;

  const OAuthClientCredentials({
    required this.clientId,
    this.clientAssertionType,
    this.clientAssertion,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'client_id': clientId};
    if (clientAssertionType != null) {
      map['client_assertion_type'] = clientAssertionType;
    }
    if (clientAssertion != null) {
      map['client_assertion'] = clientAssertion;
    }
    return map;
  }
}

/// Result of creating client credentials.
class ClientCredentialsResult {
  /// Optional HTTP headers (e.g., Authorization header for client_secret_basic)
  final Map<String, String>? headers;

  /// Payload to include in the request body
  final OAuthClientCredentials payload;

  const ClientCredentialsResult({
    this.headers,
    required this.payload,
  });
}

/// Factory function that creates client credentials.
typedef ClientCredentialsFactory = Future<ClientCredentialsResult> Function();

/// Negotiates the client authentication method to use.
///
/// This function:
/// 1. Checks that the server supports the client's auth method
/// 2. For private_key_jwt, finds a suitable key from the keyset
/// 3. Returns the negotiated auth method
///
/// The ATPROTO spec requires that authorization servers support both
/// "none" and "private_key_jwt", and clients use one or the other.
///
/// Throws:
/// - Error if server doesn't support client's auth method
/// - Error if private_key_jwt is used but no suitable key is found
ClientAuthMethod negotiateClientAuthMethod(
  Map<String, dynamic> serverMetadata,
  ClientMetadata clientMetadata,
  Keyset? keyset,
) {
  final method = clientMetadata.tokenEndpointAuthMethod;

  // Check that the server supports this method
  final methods = _supportedMethods(serverMetadata);
  if (!methods.contains(method)) {
    throw StateError(
      'The server does not support "$method" authentication. '
      'Supported methods are: ${methods.join(', ')}.',
    );
  }

  if (method == 'private_key_jwt') {
    // Invalid client configuration
    if (keyset == null) {
      throw StateError('A keyset is required for private_key_jwt');
    }

    final algs = _supportedAlgs(serverMetadata);

    // Find a suitable key
    // We can't use keyset.findPrivateKey here because we need to ensure
    // the key has a "kid" property (required for JWT headers)
    for (final key in keyset.keys) {
      if (key.kid != null &&
          key.usage == 'sign' &&
          key.algorithms.any((a) => algs.contains(a))) {
        return ClientAuthMethod.privateKeyJwt(key.kid!);
      }
    }

    throw StateError(
      algs.contains(fallbackAlg)
          ? 'Client authentication method "$method" requires at least one "$fallbackAlg" signing key with a "kid" property'
          : 'Authorization server requires "$method" authentication method, but does not support "$fallbackAlg" algorithm.',
    );
  }

  if (method == 'none') {
    return const ClientAuthMethod.none();
  }

  throw StateError(
    'The ATProto OAuth spec requires that client use either "none" or "private_key_jwt" authentication method.' +
        (method == 'client_secret_basic'
            ? ' You might want to explicitly set "token_endpoint_auth_method" to one of those values in the client metadata document.'
            : ' You set "$method" which is not allowed.'),
  );
}

/// Creates a factory that generates client credentials.
///
/// The factory can be called multiple times to generate fresh credentials
/// (important for private_key_jwt which includes timestamps).
///
/// Throws [AuthMethodUnsatisfiableError] if:
/// - Server no longer supports the auth method
/// - Key is no longer available in the keyset
ClientCredentialsFactory createClientCredentialsFactory(
  ClientAuthMethod authMethod,
  Map<String, dynamic> serverMetadata,
  ClientMetadata clientMetadata,
  Runtime runtime,
  Keyset? keyset,
) {
  // Ensure the AS still supports the auth method
  if (!_supportedMethods(serverMetadata).contains(authMethod.method)) {
    throw AuthMethodUnsatisfiableError(
      'Client authentication method "${authMethod.method}" no longer supported',
    );
  }

  if (authMethod.method == 'none') {
    return () async => ClientCredentialsResult(
      payload: OAuthClientCredentials(clientId: clientMetadata.clientId!),
    );
  }

  if (authMethod.method == 'private_key_jwt') {
    try {
      // Find the key
      if (keyset == null) {
        throw StateError('A keyset is required for private_key_jwt');
      }

      final key = keyset.keys.firstWhere(
        (k) =>
            k.kid == authMethod.kid &&
            k.usage == 'sign' &&
            k.algorithms.any((a) => _supportedAlgs(serverMetadata).contains(a)),
        orElse: () => throw StateError('Key not found: ${authMethod.kid}'),
      );

      final alg = key.algorithms.firstWhere(
        (a) => _supportedAlgs(serverMetadata).contains(a),
        orElse: () => throw StateError('No supported algorithm found'),
      );

      // https://www.rfc-editor.org/rfc/rfc7523.html#section-3
      return () async {
        final jti = await runtime.generateNonce();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final jwt = await key.createJwt(
          {'alg': alg},
          {
            // Issuer: the client_id
            'iss': clientMetadata.clientId,
            // Subject: the client_id
            'sub': clientMetadata.clientId,
            // Audience: the authorization server
            'aud': serverMetadata['issuer'],
            // JWT ID: unique identifier
            'jti': jti,
            // Issued at
            'iat': now,
            // Expiration: 1 minute from now
            'exp': now + 60,
          },
        );

        return ClientCredentialsResult(
          payload: OAuthClientCredentials(
            clientId: clientMetadata.clientId!,
            clientAssertionType:
                'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
            clientAssertion: jwt,
          ),
        );
      };
    } catch (cause) {
      throw AuthMethodUnsatisfiableError(
        'Failed to load private key: $cause',
      );
    }
  }

  throw AuthMethodUnsatisfiableError(
    'Unsupported auth method: ${authMethod.method}',
  );
}

/// Gets the list of supported authentication methods from server metadata.
List<String> _supportedMethods(Map<String, dynamic> serverMetadata) {
  final methods = serverMetadata['token_endpoint_auth_methods_supported'];
  if (methods is List) {
    return methods.map((m) => m.toString()).toList();
  }
  return [];
}

/// Gets the list of supported signing algorithms from server metadata.
List<String> _supportedAlgs(Map<String, dynamic> serverMetadata) {
  final algs =
      serverMetadata['token_endpoint_auth_signing_alg_values_supported'];
  if (algs is List) {
    return algs.map((a) => a.toString()).toList();
  }

  // Default to ES256 as prescribed by the ATProto spec:
  // > Clients and Authorization Servers currently must support the ES256
  // > cryptographic system [for client authentication].
  // https://atproto.com/specs/oauth#confidential-client-authentication
  return [fallbackAlg];
}

/// Placeholder for Keyset class.
///
/// In the full implementation, this would come from @atproto/jwk package.
/// For now, we use a simple implementation.
class Keyset {
  final List<Key> keys;

  const Keyset(this.keys);

  int get size => keys.length;

  Map<String, dynamic> toJSON() {
    return {
      'keys': keys.map((k) => k.bareJwk).toList(),
    };
  }
}
