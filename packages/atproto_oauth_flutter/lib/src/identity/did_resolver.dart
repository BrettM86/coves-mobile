import 'package:dio/dio.dart';

import 'constants.dart';
import 'did_document.dart';
import 'did_helpers.dart';
import 'identity_resolver_error.dart';

/// Options for DID resolution.
class ResolveDidOptions {
  /// Whether to bypass cache
  final bool noCache;

  /// Cancellation token for the request
  final CancelToken? cancelToken;

  const ResolveDidOptions({
    this.noCache = false,
    this.cancelToken,
  });
}

/// Interface for resolving DIDs to DID documents.
abstract class DidResolver {
  /// Resolves a DID to its DID document.
  ///
  /// Throws [DidResolverError] if resolution fails.
  Future<DidDocument> resolve(String did, [ResolveDidOptions? options]);
}

/// DID resolver that supports both did:plc and did:web methods.
class AtprotoDidResolver implements DidResolver {
  final DidPlcMethod _plcMethod;
  final DidWebMethod _webMethod;

  AtprotoDidResolver({
    String? plcDirectoryUrl,
    Dio? dio,
  })  : _plcMethod = DidPlcMethod(plcDirectoryUrl: plcDirectoryUrl, dio: dio),
        _webMethod = DidWebMethod(dio: dio);

  @override
  Future<DidDocument> resolve(String did, [ResolveDidOptions? options]) async {
    if (isDidPlc(did)) {
      return _plcMethod.resolve(did, options);
    } else if (isDidWeb(did)) {
      return _webMethod.resolve(did, options);
    } else {
      throw DidResolverError(
        'Unsupported DID method: ${extractDidMethod(did)}',
      );
    }
  }
}

/// Resolver for did:plc identifiers using the PLC directory.
class DidPlcMethod {
  final Uri plcDirectoryUrl;
  final Dio dio;

  DidPlcMethod({
    String? plcDirectoryUrl,
    Dio? dio,
  })  : plcDirectoryUrl = Uri.parse(plcDirectoryUrl ?? defaultPlcDirectoryUrl),
        dio = dio ?? Dio();

  Future<DidDocument> resolve(String did, [ResolveDidOptions? options]) async {
    assertDidPlc(did);

    final url = plcDirectoryUrl.resolve('/${Uri.encodeComponent(did)}');

    try {
      final response = await dio.getUri(
        url,
        options: Options(
          headers: {
            'Accept': 'application/did+ld+json,application/json',
            if (options?.noCache ?? false) 'Cache-Control': 'no-cache',
          },
          followRedirects: false,
          validateStatus: (status) => status == 200,
        ),
        cancelToken: options?.cancelToken,
      );

      if (response.data is! Map<String, dynamic>) {
        throw DidResolverError(
          'Invalid response format from PLC directory for $did',
        );
      }

      return DidDocument.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw DidResolverError('DID resolution was cancelled');
      }

      if (e.response?.statusCode == 404) {
        throw DidResolverError('DID not found: $did');
      }

      throw DidResolverError(
        'Failed to resolve DID from PLC directory: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is DidResolverError) rethrow;

      throw DidResolverError(
        'Unexpected error resolving DID: $e',
        e,
      );
    }
  }
}

/// Resolver for did:web identifiers using HTTPS.
class DidWebMethod {
  final Dio dio;

  DidWebMethod({Dio? dio}) : dio = dio ?? Dio();

  Future<DidDocument> resolve(String did, [ResolveDidOptions? options]) async {
    assertDidWeb(did);

    final baseUrl = didWebToUrl(did);

    // Try /.well-known/did.json first, then /did.json
    final urls = [
      baseUrl.resolve('/.well-known/did.json'),
      baseUrl.resolve('/did.json'),
    ];

    DioException? lastError;

    for (final url in urls) {
      try {
        final response = await dio.getUri(
          url,
          options: Options(
            headers: {
              'Accept': 'application/did+ld+json,application/json',
              if (options?.noCache ?? false) 'Cache-Control': 'no-cache',
            },
            followRedirects: false,
            validateStatus: (status) => status == 200,
          ),
          cancelToken: options?.cancelToken,
        );

        if (response.data is! Map<String, dynamic>) {
          throw DidResolverError(
            'Invalid response format from did:web for $did',
          );
        }

        final doc = DidDocument.fromJson(response.data as Map<String, dynamic>);

        // Verify the DID in the document matches
        if (doc.id != did) {
          throw DidResolverError(
            'DID mismatch: expected $did but got ${doc.id}',
          );
        }

        return doc;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          throw DidResolverError('DID resolution was cancelled');
        }

        // If not found, try the next URL
        if (e.response?.statusCode == 404) {
          lastError = e;
          continue;
        }

        // Any other error, throw immediately
        throw DidResolverError(
          'Failed to resolve did:web: ${e.message}',
          e,
        );
      } catch (e) {
        if (e is DidResolverError) rethrow;

        throw DidResolverError(
          'Unexpected error resolving did:web: $e',
          e,
        );
      }
    }

    // If we get here, all URLs failed
    throw DidResolverError(
      'DID document not found for $did',
      lastError,
    );
  }
}

/// Cached DID resolver that wraps another resolver with caching.
class CachedDidResolver implements DidResolver {
  final DidResolver _resolver;
  final DidCache _cache;

  CachedDidResolver(this._resolver, [DidCache? cache])
      : _cache = cache ?? InMemoryDidCache();

  @override
  Future<DidDocument> resolve(String did, [ResolveDidOptions? options]) async {
    // Check cache first unless noCache is set
    if (!(options?.noCache ?? false)) {
      final cached = await _cache.get(did);
      if (cached != null) {
        return cached;
      }
    }

    // Resolve and cache
    final doc = await _resolver.resolve(did, options);
    await _cache.set(did, doc);

    return doc;
  }

  /// Clears the cache
  Future<void> clearCache() => _cache.clear();
}

/// Interface for caching DID documents.
abstract class DidCache {
  Future<DidDocument?> get(String did);
  Future<void> set(String did, DidDocument document);
  Future<void> clear();
}

/// Simple in-memory DID cache with expiration.
class InMemoryDidCache implements DidCache {
  final Map<String, _CacheEntry> _cache = {};
  final Duration _ttl;

  InMemoryDidCache({Duration? ttl})
      : _ttl = ttl ?? const Duration(hours: 24);

  @override
  Future<DidDocument?> get(String did) async {
    final entry = _cache[did];
    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(did);
      return null;
    }

    return entry.document;
  }

  @override
  Future<void> set(String did, DidDocument document) async {
    _cache[did] = _CacheEntry(
      document: document,
      expiresAt: DateTime.now().add(_ttl),
    );
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }
}

class _CacheEntry {
  final DidDocument document;
  final DateTime expiresAt;

  _CacheEntry({required this.document, required this.expiresAt});
}
