import '../errors/oauth_resolver_error.dart';
import '../identity/did_document.dart';
import '../identity/identity_resolver.dart';
import 'authorization_server_metadata_resolver.dart';
import 'protected_resource_metadata_resolver.dart';

/// Complete result of OAuth resolution from an identity.
class ResolvedOAuthIdentityFromIdentity {
  /// The resolved identity information
  final IdentityInfo identityInfo;

  /// The authorization server metadata
  final Map<String, dynamic> metadata;

  /// The PDS URL
  final Uri pds;

  const ResolvedOAuthIdentityFromIdentity({
    required this.identityInfo,
    required this.metadata,
    required this.pds,
  });
}

/// Result of OAuth resolution from a service URL.
class ResolvedOAuthIdentityFromService {
  /// The authorization server metadata
  final Map<String, dynamic> metadata;

  /// Optional identity info (only present if resolved from handle/DID)
  final IdentityInfo? identityInfo;

  const ResolvedOAuthIdentityFromService({
    required this.metadata,
    this.identityInfo,
  });
}

/// Options for OAuth resolution.
typedef ResolveOAuthOptions = GetCachedOptions;

/// Main OAuth resolver that combines identity and metadata resolution.
///
/// This class orchestrates the complete OAuth discovery flow:
///
/// 1. **From handle/DID** (resolveFromIdentity):
///    - Resolve handle → DID (if needed)
///    - Fetch DID document
///    - Extract PDS URL from DID document
///    - Fetch protected resource metadata from PDS
///    - Extract authorization server(s) from resource metadata
///    - Fetch authorization server metadata
///    - Verify PDS is protected by the authorization server
///
/// 2. **From URL** (resolveFromService):
///    - Try as PDS URL (fetch protected resource metadata)
///    - Extract authorization server from metadata
///    - Fallback: try as authorization server directly
///
/// This is the critical piece that enables decentralization - users can
/// host their data on any PDS, and we discover the OAuth server dynamically.
class OAuthResolver {
  final IdentityResolver identityResolver;
  final OAuthProtectedResourceMetadataResolver protectedResourceMetadataResolver;
  final OAuthAuthorizationServerMetadataResolver authorizationServerMetadataResolver;

  OAuthResolver({
    required this.identityResolver,
    required this.protectedResourceMetadataResolver,
    required this.authorizationServerMetadataResolver,
  });

  /// Resolves OAuth metadata from an input (handle, DID, or URL).
  ///
  /// The [input] can be:
  /// - An atProto handle (e.g., "alice.bsky.social")
  /// - A DID (e.g., "did:plc:...")
  /// - A PDS URL (e.g., "https://pds.example.com")
  /// - An authorization server URL (e.g., "https://auth.example.com")
  ///
  /// Returns metadata for the authorization server. The identityInfo
  /// is only present if input was a handle or DID.
  Future<ResolvedOAuthIdentityFromService> resolve(
    String input, [
    ResolveOAuthOptions? options,
  ]) async {
    // Detect if input is a URL (starts with http:// or https://)
    if (RegExp(r'^https?://').hasMatch(input)) {
      return resolveFromService(input, options);
    } else {
      final result = await resolveFromIdentity(input, options);
      return ResolvedOAuthIdentityFromService(
        metadata: result.metadata,
        identityInfo: result.identityInfo,
      );
    }
  }

  /// Resolves OAuth metadata from a service URL (PDS or authorization server).
  ///
  /// This method:
  /// 1. First tries to resolve as a PDS (protected resource)
  /// 2. If that fails, tries to resolve as an authorization server directly
  ///
  /// This allows both "login with PDS URL" and "login with auth server URL"
  /// flows, useful when users forget their handle or for compatibility.
  Future<ResolvedOAuthIdentityFromService> resolveFromService(
    String input, [
    ResolveOAuthOptions? options,
  ]) async {
    try {
      // Assume first that input is a PDS URL (as required by ATPROTO)
      final metadata = await getResourceServerMetadata(input, options);
      return ResolvedOAuthIdentityFromService(metadata: metadata);
    } catch (err) {
      // Check if request was cancelled - note: Dio's CancelToken doesn't have throwIfCanceled()
      // We rely on Dio throwing CancelError automatically

      if (err is OAuthResolverError) {
        try {
          // Fallback to trying to fetch as an issuer (Entryway/Authorization Server)
          final issuerUri = Uri.tryParse(input);
          if (issuerUri != null && issuerUri.hasScheme) {
            final metadata =
                await getAuthorizationServerMetadata(input, options);
            return ResolvedOAuthIdentityFromService(metadata: metadata);
          }
        } catch (_) {
          // Fallback failed, throw original error
        }
      }

      rethrow;
    }
  }

  /// Resolves OAuth metadata from a handle or DID.
  ///
  /// This is the primary OAuth discovery flow:
  /// 1. Resolve handle → DID → DID document (via IdentityResolver)
  /// 2. Extract PDS URL from DID document
  /// 3. Get protected resource metadata from PDS
  /// 4. Extract authorization server(s)
  /// 5. Get authorization server metadata
  /// 6. Verify PDS is protected by the auth server
  Future<ResolvedOAuthIdentityFromIdentity> resolveFromIdentity(
    String input, [
    ResolveOAuthOptions? options,
  ]) async {
    final identityInfo = await resolveIdentity(
      input,
      options != null
          ? ResolveIdentityOptions(
              noCache: options.noCache,
              cancelToken: options.cancelToken,
            )
          : null,
    );

    final pds = _extractPdsUrl(identityInfo.didDoc);

    final metadata = await getResourceServerMetadata(pds, options);

    return ResolvedOAuthIdentityFromIdentity(
      identityInfo: identityInfo,
      metadata: metadata,
      pds: pds,
    );
  }

  /// Resolves an identity (handle or DID) to IdentityInfo.
  ///
  /// Wraps the IdentityResolver with proper error handling.
  Future<IdentityInfo> resolveIdentity(
    String input, [
    ResolveIdentityOptions? options,
  ]) async {
    try {
      return await identityResolver.resolve(input, options);
    } catch (cause) {
      throw OAuthResolverError.from(
        cause,
        'Failed to resolve identity: $input',
      );
    }
  }

  /// Gets authorization server metadata for an issuer.
  ///
  /// Wraps the AuthorizationServerMetadataResolver with proper error handling.
  Future<Map<String, dynamic>> getAuthorizationServerMetadata(
    String issuer, [
    GetCachedOptions? options,
  ]) async {
    try {
      return await authorizationServerMetadataResolver.get(issuer, options);
    } catch (cause) {
      throw OAuthResolverError.from(
        cause,
        'Failed to resolve OAuth server metadata for issuer: $issuer',
      );
    }
  }

  /// Gets authorization server metadata for a protected resource (PDS).
  ///
  /// This method:
  /// 1. Fetches protected resource metadata
  /// 2. Validates exactly one authorization server is listed (ATPROTO requirement)
  /// 3. Fetches authorization server metadata
  /// 4. Verifies the PDS is in the auth server's protected_resources list
  Future<Map<String, dynamic>> getResourceServerMetadata(
    dynamic pdsUrl, [
    GetCachedOptions? options,
  ]) async {
    try {
      final rsMetadata =
          await protectedResourceMetadataResolver.get(pdsUrl, options);

      // ATPROTO requires exactly one authorization server
      final authServers = rsMetadata['authorization_servers'];
      if (authServers is! List || authServers.length != 1) {
        throw OAuthResolverError(
          authServers == null || (authServers as List).isEmpty
              ? 'No authorization servers found for PDS: $pdsUrl'
              : 'Unable to determine authorization server for PDS: $pdsUrl',
        );
      }

      final issuer = authServers[0] as String;

      final asMetadata = await getAuthorizationServerMetadata(issuer, options);

      // Verify PDS is protected by this authorization server
      // https://www.rfc-editor.org/rfc/rfc9728.html#section-4
      final protectedResources = asMetadata['protected_resources'];
      if (protectedResources != null) {
        final resource = rsMetadata['resource'] as String;
        if (!(protectedResources as List).contains(resource)) {
          throw OAuthResolverError(
            'PDS "$pdsUrl" not protected by issuer "$issuer"',
          );
        }
      }

      return asMetadata;
    } catch (cause) {
      throw OAuthResolverError.from(
        cause,
        'Failed to resolve OAuth server metadata for resource: $pdsUrl',
      );
    }
  }

  /// Extracts the PDS URL from a DID document.
  ///
  /// Throws OAuthResolverError if no PDS URL is found.
  Uri _extractPdsUrl(DidDocument document) {
    // Find the atproto_pds service
    final service = document.service?.firstWhere(
      (s) => _isAtprotoPersonalDataServerService(s, document),
      orElse: () => throw OAuthResolverError(
        'Identity "${document.id}" does not have a PDS URL',
      ),
    );

    if (service == null) {
      throw OAuthResolverError(
        'Identity "${document.id}" does not have a PDS URL',
      );
    }

    try {
      return Uri.parse(service.serviceEndpoint as String);
    } catch (cause) {
      throw OAuthResolverError(
        'Invalid PDS URL in DID document: ${service.serviceEndpoint}',
        cause: cause,
      );
    }
  }

  /// Checks if a service is an AtprotoPersonalDataServer.
  bool _isAtprotoPersonalDataServerService(
    DidService service,
    DidDocument document,
  ) {
    if (service.serviceEndpoint is! String) return false;
    if (service.type != 'AtprotoPersonalDataServer') return false;

    // Check service ID
    final id = service.id;
    if (id.startsWith('#')) {
      return id == '#atproto_pds';
    } else {
      return id == '${document.id}#atproto_pds';
    }
  }
}
