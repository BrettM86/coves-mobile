import 'package:dio/dio.dart';

import 'did_helpers.dart';
import 'identity_resolver_error.dart';

/// Options for handle resolution.
class ResolveHandleOptions {
  /// Whether to bypass cache
  final bool noCache;

  /// Cancellation token for the request
  final CancelToken? cancelToken;

  const ResolveHandleOptions({this.noCache = false, this.cancelToken});
}

/// Interface for resolving atProto handles to DIDs.
abstract class HandleResolver {
  /// Resolves an atProto handle to a DID.
  ///
  /// Returns null if the handle doesn't resolve to a DID (but no error occurred).
  /// Throws [HandleResolverError] if an unexpected error occurs during resolution.
  Future<String?> resolve(String handle, [ResolveHandleOptions? options]);
}

/// XRPC-based handle resolver that uses com.atproto.identity.resolveHandle.
///
/// This resolver makes HTTP requests to an atProto XRPC service (typically
/// a PDS or entryway service) to resolve handles.
class XrpcHandleResolver implements HandleResolver {
  /// The base URL of the XRPC service
  final Uri serviceUrl;

  /// HTTP client for making requests
  final Dio dio;

  XrpcHandleResolver(String serviceUrl, {Dio? dio})
    : serviceUrl = Uri.parse(serviceUrl),
      dio = dio ?? Dio();

  @override
  Future<String?> resolve(
    String handle, [
    ResolveHandleOptions? options,
  ]) async {
    final url = serviceUrl.resolve('/xrpc/com.atproto.identity.resolveHandle');
    final uri = url.replace(queryParameters: {'handle': handle});

    try {
      final response = await dio.getUri(
        uri,
        options: Options(
          headers: {if (options?.noCache ?? false) 'Cache-Control': 'no-cache'},
          validateStatus: (status) {
            // Allow 400 and 200 status codes
            return status == 200 || status == 400;
          },
        ),
        cancelToken: options?.cancelToken,
      );

      final data = response.data;

      // Handle 400 Bad Request (expected for invalid/unresolvable handles)
      if (response.statusCode == 400) {
        if (data is Map<String, dynamic>) {
          final error = data['error'] as String?;
          final message = data['message'] as String?;

          // Expected response for handle that doesn't exist
          if (error == 'InvalidRequest' &&
              message == 'Unable to resolve handle') {
            return null;
          }
        }

        throw HandleResolverError(
          'Invalid response from resolveHandle method: ${response.data}',
        );
      }

      // Handle successful response
      if (response.statusCode == 200) {
        if (data is! Map<String, dynamic>) {
          throw HandleResolverError(
            'Invalid response format from resolveHandle method',
          );
        }

        final did = data['did'];
        if (did is! String) {
          throw HandleResolverError(
            'Missing or invalid DID in resolveHandle response',
          );
        }

        // Validate that it's a proper atProto DID
        if (!isAtprotoDid(did)) {
          throw HandleResolverError(
            'Invalid DID returned from resolveHandle method: $did',
          );
        }

        return did;
      }

      throw HandleResolverError(
        'Unexpected status code from resolveHandle method: ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw HandleResolverError('Handle resolution was cancelled');
      }

      throw HandleResolverError('Failed to resolve handle: ${e.message}', e);
    } catch (e) {
      if (e is HandleResolverError) rethrow;

      throw HandleResolverError('Unexpected error resolving handle: $e', e);
    }
  }
}

/// Cached handle resolver that wraps another resolver with caching.
class CachedHandleResolver implements HandleResolver {
  final HandleResolver _resolver;
  final HandleCache _cache;

  CachedHandleResolver(this._resolver, [HandleCache? cache])
    : _cache = cache ?? InMemoryHandleCache();

  @override
  Future<String?> resolve(
    String handle, [
    ResolveHandleOptions? options,
  ]) async {
    // Check cache first unless noCache is set
    if (!(options?.noCache ?? false)) {
      final cached = await _cache.get(handle);
      if (cached != null) {
        return cached;
      }
    }

    // Resolve and cache
    final did = await _resolver.resolve(handle, options);
    if (did != null) {
      await _cache.set(handle, did);
    }

    return did;
  }

  /// Clears the cache
  Future<void> clearCache() => _cache.clear();
}

/// Interface for caching handle resolution results.
abstract class HandleCache {
  Future<String?> get(String handle);
  Future<void> set(String handle, String did);
  Future<void> clear();
}

/// Simple in-memory handle cache with expiration.
class InMemoryHandleCache implements HandleCache {
  final Map<String, _CacheEntry> _cache = {};
  final Duration _ttl;

  InMemoryHandleCache({Duration? ttl}) : _ttl = ttl ?? const Duration(hours: 1);

  @override
  Future<String?> get(String handle) async {
    final entry = _cache[handle];
    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(handle);
      return null;
    }

    return entry.did;
  }

  @override
  Future<void> set(String handle, String did) async {
    _cache[handle] = _CacheEntry(did: did, expiresAt: DateTime.now().add(_ttl));
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }
}

class _CacheEntry {
  final String did;
  final DateTime expiresAt;

  _CacheEntry({required this.did, required this.expiresAt});
}
