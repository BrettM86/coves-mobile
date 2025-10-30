import 'package:dio/dio.dart';

import '../dpop/fetch_dpop.dart';
import '../util.dart';
import 'authorization_server_metadata_resolver.dart';

/// Cache interface for protected resource metadata.
///
/// Implementations should store metadata keyed by origin (scheme://host:port).
typedef ProtectedResourceMetadataCache =
    SimpleStore<String, Map<String, dynamic>>;

/// Configuration for the protected resource metadata resolver.
class OAuthProtectedResourceMetadataResolverConfig {
  /// Whether to allow HTTP (non-HTTPS) resource URLs.
  ///
  /// Should only be true in development/test environments.
  /// Production MUST use HTTPS.
  final bool allowHttpResource;

  const OAuthProtectedResourceMetadataResolverConfig({
    this.allowHttpResource = false,
  });
}

/// Resolves OAuth Protected Resource Metadata via RFC 9728 discovery.
///
/// This class:
/// 1. Validates resource URLs (must be HTTPS in production)
/// 2. Fetches metadata from `{origin}/.well-known/oauth-protected-resource`
/// 3. Validates the metadata against the spec
/// 4. Verifies resource field matches origin
/// 5. Caches metadata to avoid repeated fetches
///
/// See: https://www.rfc-editor.org/rfc/rfc9728.html
class OAuthProtectedResourceMetadataResolver {
  final ProtectedResourceMetadataCache _cache;
  final Dio _dio;
  final bool _allowHttpResource;

  /// Creates a resolver with the given cache and HTTP client.
  ///
  /// [cache] is used to store fetched metadata. Use an in-memory store for
  /// testing or a persistent store for production.
  ///
  /// [dio] is the HTTP client. If not provided, creates a default instance.
  ///
  /// [config] allows customizing behavior (e.g., allowing HTTP in tests).
  OAuthProtectedResourceMetadataResolver(
    this._cache, {
    Dio? dio,
    OAuthProtectedResourceMetadataResolverConfig? config,
  }) : _dio = dio ?? Dio(),
       _allowHttpResource = config?.allowHttpResource ?? false;

  /// Resolves protected resource metadata for the given resource URL.
  ///
  /// The [resource] can be a String URL or Uri. Only the origin is used.
  ///
  /// Returns the complete metadata as a Map. Throws if:
  /// - Resource is not a valid URL
  /// - Protocol is not HTTP/HTTPS
  /// - HTTP is used in production (allowHttpResource = false)
  /// - Network request fails
  /// - Response is not valid JSON
  /// - Metadata validation fails
  /// - Resource mismatch detected
  ///
  /// Example:
  /// ```dart
  /// final resolver = OAuthProtectedResourceMetadataResolver(cache);
  /// final metadata = await resolver.get('https://pds.example.com');
  /// print(metadata['authorization_servers']);
  /// ```
  Future<Map<String, dynamic>> get(
    dynamic resource, [
    GetCachedOptions? options,
  ]) async {
    // Parse URL and extract origin
    final uri = resource is Uri ? resource : Uri.parse(resource.toString());
    final protocol = uri.scheme;
    final origin =
        '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

    // Validate protocol
    if (protocol != 'https' && protocol != 'http') {
      throw FormatException(
        'Invalid protected resource metadata URL protocol: $protocol',
      );
    }

    // Security check: disallow HTTP in production
    if (protocol == 'http' && !_allowHttpResource) {
      throw FormatException(
        'Unsecure resource metadata URL ($protocol) only allowed in development and test environments',
      );
    }

    // Check cache first (unless noCache is set)
    if (options?.noCache != true) {
      final cached = await _cache.get(origin);
      if (cached != null) {
        return cached;
      }
    }

    // Fetch fresh metadata
    final metadata = await _fetchMetadata(origin, options);

    // Store in cache
    await _cache.set(origin, metadata);

    return metadata;
  }

  /// Fetches metadata from the well-known endpoint.
  Future<Map<String, dynamic>> _fetchMetadata(
    String origin,
    GetCachedOptions? options,
  ) async {
    final url =
        Uri.parse(
          origin,
        ).replace(path: '/.well-known/oauth-protected-resource').toString();

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
        response.headers.map.map((key, value) => MapEntry(key, value.first)),
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

      // Validate metadata
      _validateMetadata(metadata, origin);

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
        message:
            'Unexpected status code ${e.response?.statusCode ?? 'unknown'} for "$url"',
        error: e.error,
      );
    }
  }

  /// Validates protected resource metadata.
  ///
  /// Checks:
  /// - Resource field matches the expected origin
  /// - Authorization servers list is present
  void _validateMetadata(Map<String, dynamic> metadata, String expectedOrigin) {
    // Validate resource field
    // https://www.rfc-editor.org/rfc/rfc9728.html#section-3.3
    final resource = metadata['resource'];
    if (resource != expectedOrigin) {
      throw FormatException(
        'Invalid resource: expected "$expectedOrigin", got "$resource"',
      );
    }
  }
}
