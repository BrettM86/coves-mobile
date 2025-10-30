import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../identity/did_document.dart';
import '../identity/did_resolver.dart';
import '../identity/handle_resolver.dart';
import '../oauth/authorization_server_metadata_resolver.dart';
import '../oauth/oauth_server_agent.dart';
import '../oauth/protected_resource_metadata_resolver.dart';
import '../session/oauth_session.dart';
import '../session/session_getter.dart';
import '../session/state_store.dart';
import '../util.dart';

// ============================================================================
// Session and State Storage (uses flutter_secure_storage)
// ============================================================================

/// Flutter implementation of SessionStore using flutter_secure_storage.
///
/// This stores OAuth sessions (tokens and keys) in the device's secure storage:
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences
///
/// Sessions are persisted across app restarts and are encrypted at rest.
///
/// Example:
/// ```dart
/// final store = FlutterSessionStore();
/// await store.set('did:plc:abc123', session);
/// final restored = await store.get('did:plc:abc123');
/// ```
class FlutterSessionStore implements SessionStore {
  final FlutterSecureStorage _storage;
  static const _prefix = 'atproto_session_';

  FlutterSessionStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  @override
  Future<Session?> get(String key, {CancellationToken? signal}) async {
    try {
      final json = await _storage.read(key: _prefix + key);
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return Session.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> set(String key, Session value) async {
    final json = jsonEncode(value.toJson());
    await _storage.write(key: _prefix + key, value: json);
  }

  @override
  Future<void> del(String key) async {
    await _storage.delete(key: _prefix + key);
  }

  @override
  Future<void> clear() async {
    // Delete all session keys
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}

/// Flutter implementation of StateStore for ephemeral OAuth state.
///
/// This stores temporary state data during the OAuth authorization flow.
/// State data includes PKCE verifiers, nonces, and application state.
///
/// Uses in-memory storage since state is short-lived (only needed during the
/// authorization flow, which typically completes within minutes).
///
/// Example:
/// ```dart
/// final store = FlutterStateStore();
/// await store.set('state123', InternalStateData(...));
/// final state = await store.get('state123');
/// await store.del('state123'); // Clean up after use
/// ```
class FlutterStateStore implements StateStore {
  final Map<String, InternalStateData> _store = {};

  @override
  Future<InternalStateData?> get(String key) async {
    return _store[key];
  }

  @override
  Future<void> set(String key, InternalStateData data) async {
    _store[key] = data;
  }

  @override
  Future<void> del(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

// ============================================================================
// In-Memory Caches with TTL
// ============================================================================

/// Base class for in-memory caches with time-to-live (TTL).
///
/// This provides a generic caching mechanism with automatic expiration.
/// Cached items are stored with a timestamp and are considered stale
/// after the TTL period.
class _InMemoryCache<V> {
  final Map<String, _CacheEntry<V>> _cache = {};
  final Duration _ttl;

  _InMemoryCache(this._ttl);

  Future<V?> get(String key) async {
    final entry = _cache[key];
    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }

    return entry.value;
  }

  Future<void> set(String key, V value) async {
    _cache[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(_ttl),
    );
  }

  Future<void> del(String key) async {
    _cache.remove(key);
  }

  Future<void> clear() async {
    _cache.clear();
  }

  /// Removes expired entries from the cache.
  void purge() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }
}

/// Cache entry with expiration time.
class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;

  _CacheEntry({required this.value, required this.expiresAt});
}

/// In-memory cache for OAuth Authorization Server metadata.
///
/// Caches metadata fetched from /.well-known/oauth-authorization-server
/// to avoid redundant network requests.
///
/// Default TTL: 1 minute (metadata rarely changes)
///
/// Example:
/// ```dart
/// final cache = InMemoryAuthorizationServerMetadataCache();
/// await cache.set('https://auth.example.com', metadata);
/// final cached = await cache.get('https://auth.example.com');
/// ```
class InMemoryAuthorizationServerMetadataCache
    implements AuthorizationServerMetadataCache {
  final _InMemoryCache<Map<String, dynamic>> _cache;

  InMemoryAuthorizationServerMetadataCache({
    Duration ttl = const Duration(minutes: 1),
  }) : _cache = _InMemoryCache(ttl);

  @override
  Future<Map<String, dynamic>?> get(String key, {CancellationToken? signal}) =>
      _cache.get(key);

  @override
  Future<void> set(String key, Map<String, dynamic> value) =>
      _cache.set(key, value);

  @override
  Future<void> del(String key) => _cache.del(key);

  @override
  Future<void> clear() => _cache.clear();
}

/// In-memory cache for OAuth Protected Resource metadata.
///
/// Caches metadata fetched from /.well-known/oauth-protected-resource
/// to avoid redundant network requests.
///
/// Default TTL: 1 minute (metadata rarely changes)
///
/// Example:
/// ```dart
/// final cache = InMemoryProtectedResourceMetadataCache();
/// await cache.set('https://pds.example.com', metadata);
/// ```
class InMemoryProtectedResourceMetadataCache
    implements ProtectedResourceMetadataCache {
  final _InMemoryCache<Map<String, dynamic>> _cache;

  InMemoryProtectedResourceMetadataCache({
    Duration ttl = const Duration(minutes: 1),
  }) : _cache = _InMemoryCache(ttl);

  @override
  Future<Map<String, dynamic>?> get(String key, {CancellationToken? signal}) =>
      _cache.get(key);

  @override
  Future<void> set(String key, Map<String, dynamic> value) =>
      _cache.set(key, value);

  @override
  Future<void> del(String key) => _cache.del(key);

  @override
  Future<void> clear() => _cache.clear();
}

/// In-memory cache for DPoP nonces.
///
/// DPoP nonces are server-provided values used for replay protection.
/// They're cached per authorization/resource server origin.
///
/// Default TTL: 10 minutes (nonces typically have short lifetimes)
///
/// Example:
/// ```dart
/// final cache = InMemoryDpopNonceCache();
/// await cache.set('https://auth.example.com', 'nonce123');
/// final nonce = await cache.get('https://auth.example.com');
/// ```
class InMemoryDpopNonceCache implements DpopNonceCache {
  final _InMemoryCache<String> _cache;

  InMemoryDpopNonceCache({Duration ttl = const Duration(minutes: 10)})
    : _cache = _InMemoryCache(ttl);

  @override
  Future<String?> get(String key, {CancellationToken? signal}) =>
      _cache.get(key);

  @override
  Future<void> set(String key, String value) => _cache.set(key, value);

  @override
  Future<void> del(String key) => _cache.del(key);

  @override
  Future<void> clear() => _cache.clear();
}

/// In-memory cache for DID documents.
///
/// Caches resolved DID documents (from DidDocument class) to avoid redundant
/// resolution requests.
///
/// Default TTL: 1 minute (DID documents can change but not frequently)
///
/// Note: DidDocument is a complex class, but it has toJson/fromJson methods.
/// We store the JSON representation and reconstruct on retrieval.
///
/// Example:
/// ```dart
/// final cache = FlutterDidCache();
/// await cache.set('did:plc:abc123', didDocument);
/// final doc = await cache.get('did:plc:abc123');
/// ```
class FlutterDidCache implements DidCache {
  final _InMemoryCache<DidDocument> _cache;

  FlutterDidCache({Duration ttl = const Duration(minutes: 1)})
    : _cache = _InMemoryCache(ttl);

  @override
  Future<DidDocument?> get(String key) => _cache.get(key);

  @override
  Future<void> set(String key, DidDocument value) => _cache.set(key, value);

  @override
  Future<void> clear() => _cache.clear();
}

/// In-memory cache for handle → DID resolutions.
///
/// Caches the resolution of atProto handles (e.g., "alice.bsky.social") to DIDs.
/// The cache stores simple string mappings (handle → DID).
///
/// Default TTL: 1 minute (handles can be reassigned but not frequently)
///
/// Example:
/// ```dart
/// final cache = FlutterHandleCache();
/// await cache.set('alice.bsky.social', 'did:plc:abc123');
/// final did = await cache.get('alice.bsky.social');
/// ```
class FlutterHandleCache implements HandleCache {
  final _InMemoryCache<String> _cache;

  FlutterHandleCache({Duration ttl = const Duration(minutes: 1)})
    : _cache = _InMemoryCache(ttl);

  @override
  Future<String?> get(String key) => _cache.get(key);

  @override
  Future<void> set(String key, String value) => _cache.set(key, value);

  @override
  Future<void> clear() => _cache.clear();
}
