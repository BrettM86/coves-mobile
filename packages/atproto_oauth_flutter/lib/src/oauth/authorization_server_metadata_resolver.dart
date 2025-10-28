import 'package:dio/dio.dart';

import '../dpop/fetch_dpop.dart';
import '../util.dart';

/// Options for getting cached values.
class GetCachedOptions {
  /// Whether to bypass cache and force a fresh fetch
  final bool noCache;

  /// Whether to allow returning stale cached values
  final bool allowStale;

  /// Optional cancellation token
  final CancelToken? cancelToken;

  const GetCachedOptions({
    this.noCache = false,
    this.allowStale = true,
    this.cancelToken,
  });
}

/// Cache interface for authorization server metadata.
///
/// Implementations should store metadata keyed by issuer URL.
typedef AuthorizationServerMetadataCache
    = SimpleStore<String, Map<String, dynamic>>;

/// Configuration for the authorization server metadata resolver.
class OAuthAuthorizationServerMetadataResolverConfig {
  /// Whether to allow HTTP (non-HTTPS) issuer URLs.
  ///
  /// Should only be true in development/test environments.
  /// Production MUST use HTTPS.
  final bool allowHttpIssuer;

  const OAuthAuthorizationServerMetadataResolverConfig({
    this.allowHttpIssuer = false,
  });
}

/// Resolves OAuth Authorization Server Metadata via RFC 8414 discovery.
///
/// This class:
/// 1. Validates issuer URLs (must be HTTPS in production)
/// 2. Fetches metadata from `{issuer}/.well-known/oauth-authorization-server`
/// 3. Validates the metadata against the spec
/// 4. Verifies issuer matches (prevents MIX-UP attacks)
/// 5. Ensures ATPROTO requirements (client_id_metadata_document)
/// 6. Caches metadata to avoid repeated fetches
///
/// See: https://datatracker.ietf.org/doc/html/rfc8414
class OAuthAuthorizationServerMetadataResolver {
  final AuthorizationServerMetadataCache _cache;
  final Dio _dio;
  final bool _allowHttpIssuer;

  /// Creates a resolver with the given cache and HTTP client.
  ///
  /// [cache] is used to store fetched metadata. Use an in-memory store for
  /// testing or a persistent store for production.
  ///
  /// [dio] is the HTTP client. If not provided, creates a default instance.
  ///
  /// [config] allows customizing behavior (e.g., allowing HTTP in tests).
  OAuthAuthorizationServerMetadataResolver(
    this._cache, {
    Dio? dio,
    OAuthAuthorizationServerMetadataResolverConfig? config,
  })  : _dio = dio ?? Dio(),
        _allowHttpIssuer = config?.allowHttpIssuer ?? false;

  /// Resolves authorization server metadata for the given issuer.
  ///
  /// The [input] should be a valid issuer identifier (typically an HTTPS URL).
  ///
  /// Returns the complete metadata as a Map. Throws if:
  /// - Input is not a valid issuer URL
  /// - HTTP is used in production (allowHttpIssuer = false)
  /// - Network request fails
  /// - Response is not valid JSON
  /// - Metadata validation fails
  /// - Issuer mismatch detected
  /// - ATPROTO requirements not met
  ///
  /// Example:
  /// ```dart
  /// final resolver = OAuthAuthorizationServerMetadataResolver(cache);
  /// final metadata = await resolver.get('https://pds.example.com');
  /// print(metadata['authorization_endpoint']);
  /// ```
  Future<Map<String, dynamic>> get(
    String input, [
    GetCachedOptions? options,
  ]) async {
    // Validate and normalize issuer URL
    final issuer = _validateIssuer(input);

    // Security check: disallow HTTP in production
    if (!_allowHttpIssuer && issuer.startsWith('http:')) {
      throw FormatException(
        'Unsecure issuer URL protocol only allowed in development and test environments',
      );
    }

    // Check cache first (unless noCache is set)
    if (options?.noCache != true) {
      final cached = await _cache.get(issuer);
      if (cached != null) {
        return cached;
      }
    }

    // Fetch fresh metadata
    final metadata = await _fetchMetadata(issuer, options);

    // Store in cache
    await _cache.set(issuer, metadata);

    return metadata;
  }

  /// Fetches metadata from the well-known endpoint.
  Future<Map<String, dynamic>> _fetchMetadata(
    String issuer,
    GetCachedOptions? options,
  ) async {
    final url = Uri.parse(issuer)
        .replace(path: '/.well-known/oauth-authorization-server')
        .toString();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {'accept': 'application/json'},
          followRedirects: false, // response must be 200 OK, no redirects
          validateStatus: (status) => status == 200,
        ),
        cancelToken: options?.cancelToken,
      );

      // Verify content type
      final contentType = contentMime(
        response.headers.map.map(
          (key, value) => MapEntry(key, value.first),
        ),
      );

      if (contentType != 'application/json') {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'Unexpected content type for "$url"',
        );
      }

      final metadata = response.data;
      if (metadata == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'Empty response body for "$url"',
        );
      }

      // Validate metadata structure
      _validateMetadata(metadata, issuer);

      return metadata;
    } on DioException catch (e) {
      if (e.response?.statusCode == 200) {
        // Already handled above, rethrow
        rethrow;
      }
      throw DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        type: e.type,
        message: 'Unexpected status code ${e.response?.statusCode ?? 'unknown'} for "$url"',
        error: e.error,
      );
    }
  }

  /// Validates an issuer identifier.
  ///
  /// Ensures the issuer is a valid URL without query or fragment.
  /// Returns the normalized issuer.
  String _validateIssuer(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null) {
      throw FormatException('Invalid issuer URL: $input');
    }

    // Issuer must not have query or fragment
    if (uri.hasQuery || uri.hasFragment) {
      throw FormatException(
        'Issuer URL must not contain query or fragment: $input',
      );
    }

    // Normalize: remove trailing slash
    final normalized = input.endsWith('/') ? input.substring(0, input.length - 1) : input;

    return normalized;
  }

  /// Validates authorization server metadata.
  ///
  /// Checks:
  /// - Required fields are present
  /// - Issuer matches expected value (MIX-UP attack prevention)
  /// - ATPROTO requirement: client_id_metadata_document_supported = true
  void _validateMetadata(Map<String, dynamic> metadata, String expectedIssuer) {
    // Validate issuer field (critical for security - prevents MIX-UP attacks)
    // https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics#name-mix-up-attacks
    // https://datatracker.ietf.org/doc/html/rfc8414#section-2
    final issuer = metadata['issuer'];
    if (issuer != expectedIssuer) {
      throw FormatException(
        'Invalid issuer: expected "$expectedIssuer", got "$issuer"',
      );
    }

    // ATPROTO requires client_id_metadata_document support
    // https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/
    final clientIdMetadataSupported =
        metadata['client_id_metadata_document_supported'];
    if (clientIdMetadataSupported != true) {
      throw FormatException(
        'Authorization server "$issuer" does not support client_id_metadata_document',
      );
    }

    // Validate required endpoints exist
    if (metadata['authorization_endpoint'] == null) {
      throw FormatException(
        'Missing required field: authorization_endpoint',
      );
    }
    if (metadata['token_endpoint'] == null) {
      throw FormatException(
        'Missing required field: token_endpoint',
      );
    }
  }
}
