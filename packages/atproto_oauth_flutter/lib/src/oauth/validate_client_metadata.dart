import '../constants.dart';
import '../types.dart';
import 'client_auth.dart';

/// Validates client metadata for OAuth compliance.
///
/// This function performs comprehensive validation of client metadata to ensure:
/// 1. Client ID is valid (either discoverable HTTPS or loopback)
/// 2. Required ATPROTO scope is present
/// 3. Required response_types and grant_types are present
/// 4. Authentication method is properly configured
/// 5. For private_key_jwt, keyset and JWKS are properly configured
///
/// The validation enforces ATPROTO OAuth requirements on top of standard OAuth.
///
/// Returns the validated ClientMetadata.
/// Throws TypeError if validation fails.
ClientMetadata validateClientMetadata(
  Map<String, dynamic> input,
  Keyset? keyset,
) {
  // Allow passing a keyset and omitting jwks/jwks_uri
  // The keyset will be serialized into the metadata
  Map<String, dynamic> enrichedInput = input;
  if (input['jwks'] == null &&
      input['jwks_uri'] == null &&
      keyset != null &&
      keyset.size > 0) {
    enrichedInput = {...input, 'jwks': keyset.toJSON()};
  }

  // Parse into ClientMetadata
  final metadata = ClientMetadata.fromJson(enrichedInput);

  // Validate client ID
  final clientId = metadata.clientId;
  if (clientId == null) {
    throw FormatException('Client metadata must include client_id');
  }

  if (clientId.startsWith('http:')) {
    // Loopback client ID (for development)
    _assertOAuthLoopbackClientId(clientId);
  } else {
    // Discoverable client ID (production)
    _assertOAuthDiscoverableClientId(clientId);
  }

  // Validate scope includes "atproto"
  final scopes = metadata.scope?.split(' ') ?? [];
  if (!scopes.contains('atproto')) {
    throw FormatException('Client metadata must include the "atproto" scope');
  }

  // Validate response_types
  if (!metadata.responseTypes.contains('code')) {
    throw FormatException('"response_types" must include "code"');
  }

  // Validate grant_types
  if (!metadata.grantTypes.contains('authorization_code')) {
    throw FormatException('"grant_types" must include "authorization_code"');
  }

  // Validate authentication method
  final method = metadata.tokenEndpointAuthMethod;
  final methodAlg = metadata.tokenEndpointAuthSigningAlg;

  switch (method) {
    case 'none':
      if (methodAlg != null) {
        throw FormatException(
          '"token_endpoint_auth_signing_alg" must not be provided when '
          '"token_endpoint_auth_method" is "$method"',
        );
      }
      break;

    case 'private_key_jwt':
      if (methodAlg == null) {
        throw FormatException(
          '"token_endpoint_auth_signing_alg" must be provided when '
          '"token_endpoint_auth_method" is "$method"',
        );
      }

      if (keyset == null) {
        throw FormatException(
          'Client authentication method "$method" requires a keyset',
        );
      }

      // Validate signing keys
      final signingKeys = keyset.keys.where((key) => key.kid != null).toList();

      if (signingKeys.isEmpty) {
        throw FormatException(
          'Client authentication method "$method" requires at least one '
          'active signing key with a "kid" property',
        );
      }

      if (!signingKeys.any((key) => key.algorithms.contains(fallbackAlg))) {
        throw FormatException(
          'Client authentication method "$method" requires at least one '
          'active "$fallbackAlg" signing key',
        );
      }

      // Validate JWKS
      if (metadata.jwks != null) {
        // Ensure all signing keys are in the JWKS
        final jwksKeys = (metadata.jwks!['keys'] as List?) ?? [];
        for (final key in signingKeys) {
          final found = jwksKeys.any((k) {
            if (k is! Map<String, dynamic>) return false;
            final revoked = k['revoked'] as bool?;
            return k['kid'] == key.kid && revoked != true;
          });

          if (!found) {
            throw FormatException(
              'Missing or inactive key "${key.kid}" in jwks. '
              'Make sure that every signing key of the Keyset is declared as '
              'an active key in the Metadata\'s JWKS.',
            );
          }
        }
      } else if (metadata.jwksUri != null) {
        // JWKS URI is acceptable, but we can't validate it here
        // (we don't want to download the file during validation)
      } else {
        throw FormatException(
          'Client authentication method "$method" requires a JWKS',
        );
      }
      break;

    default:
      throw FormatException(
        'Unsupported "token_endpoint_auth_method" value: $method',
      );
  }

  return metadata;
}

/// Validates that a client ID is a valid discoverable client ID.
///
/// A discoverable client ID must be an HTTPS URL that can be dereferenced
/// to get the client metadata document.
///
/// See: https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/
void _assertOAuthDiscoverableClientId(String clientId) {
  final uri = Uri.tryParse(clientId);

  if (uri == null) {
    throw FormatException('Invalid client_id URL: $clientId');
  }

  if (uri.scheme != 'https') {
    throw FormatException(
      'Discoverable client_id must use HTTPS: $clientId',
    );
  }

  if (uri.hasFragment) {
    throw FormatException(
      'Discoverable client_id must not contain a fragment: $clientId',
    );
  }

  // Validate it's a valid URL
  if (!uri.hasAuthority) {
    throw FormatException(
      'Invalid discoverable client_id URL: $clientId',
    );
  }
}

/// Validates that a client ID is a valid loopback client ID.
///
/// A loopback client ID is used for development/testing and must be:
/// - An HTTP URL (not HTTPS)
/// - Using localhost or 127.0.0.1
/// - Optionally with a port
///
/// See: https://datatracker.ietf.org/doc/html/rfc8252#section-7.3
void _assertOAuthLoopbackClientId(String clientId) {
  final uri = Uri.tryParse(clientId);

  if (uri == null) {
    throw FormatException('Invalid client_id URL: $clientId');
  }

  if (uri.scheme != 'http') {
    throw FormatException(
      'Loopback client_id must use HTTP (not HTTPS): $clientId',
    );
  }

  final host = uri.host.toLowerCase();
  if (host != 'localhost' &&
      host != '127.0.0.1' &&
      host != '[::1]' &&
      host != '::1') {
    throw FormatException(
      'Loopback client_id must use localhost or 127.0.0.1: $clientId',
    );
  }

  if (uri.hasFragment) {
    throw FormatException(
      'Loopback client_id must not contain a fragment: $clientId',
    );
  }
}
