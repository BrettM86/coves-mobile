# Chunk 5 Implementation: Session Management Layer

## Overview

This chunk implements the session management layer for atproto OAuth in Dart, providing a complete 1:1 port of the TypeScript implementation from `@atproto/oauth-client`.

## Files Created

### Core Session Files

1. **`lib/src/session/state_store.dart`**
   - `InternalStateData` - Ephemeral OAuth state during authorization flow
   - `StateStore` - Abstract interface for state storage
   - Stores PKCE verifiers, state parameters, nonces, and other temporary OAuth data

2. **`lib/src/session/oauth_session.dart`**
   - `TokenSet` - OAuth token container (access, refresh, metadata)
   - `TokenInfo` - Token information for client use
   - `Session` - Session with DPoP key and tokens
   - `OAuthSession` - High-level API for authenticated requests
   - `SessionGetterInterface` - Abstract interface to avoid circular dependencies

3. **`lib/src/session/session_getter.dart`**
   - `SessionGetter` - Main session management class
   - `CachedGetter` - Generic caching/refresh utility (base class)
   - `SimpleStore` - Abstract key-value store interface
   - `GetCachedOptions` - Options for cache retrieval
   - Event types: `SessionUpdatedEvent`, `SessionDeletedEvent`
   - Placeholder types: `OAuthServerFactory`, `Runtime`, `OAuthResponseError`

4. **`lib/src/session/session.dart`**
   - Barrel file exporting all session-related classes

## Key Design Decisions

### 1. Avoiding Circular Dependencies

**Problem**: `OAuthSession` needs `SessionGetter`, but `SessionGetter` returns `Session` objects that are used by `OAuthSession`.

**Solution**: Created `SessionGetterInterface` in `oauth_session.dart` as an abstract interface. `SessionGetter` in `session_getter.dart` will implement this interface in later chunks when all dependencies are available.

```dart
// oauth_session.dart
abstract class SessionGetterInterface {
  Future<Session> get(AtprotoDid sub, {bool? noCache, bool? allowStale});
  Future<void> delStored(AtprotoDid sub, [Object? cause]);
}

// OAuthSession uses this interface
class OAuthSession {
  final SessionGetterInterface sessionGetter;
  // ...
}
```

### 2. TypeScript EventEmitter → Dart Streams

**TypeScript Pattern**:
```typescript
class SessionGetter extends EventEmitter {
  emit('updated', session)
  emit('deleted', sub)
}
```

**Dart Pattern**:
```dart
class SessionGetter {
  final _updatedController = StreamController<SessionUpdatedEvent>.broadcast();
  Stream<SessionUpdatedEvent> get onUpdated => _updatedController.stream;

  final _deletedController = StreamController<SessionDeletedEvent>.broadcast();
  Stream<SessionDeletedEvent> get onDeleted => _deletedController.stream;

  void dispose() {
    _updatedController.close();
    _deletedController.close();
  }
}
```

### 3. CachedGetter Implementation

The `CachedGetter` is a critical component that ensures:
- At most one token refresh happens at a time for a given user
- Concurrent requests wait for in-flight refreshes
- Stale values are detected and refreshed automatically
- Errors trigger deletion when appropriate

**Key Features**:
- Generic `CachedGetter<K, V>` base class
- `SessionGetter` extends `CachedGetter<AtprotoDid, Session>`
- Pending request tracking prevents duplicate refreshes
- Configurable staleness detection with randomization (reduces thundering herd)

### 4. Placeholder Types for Future Chunks

Since this is Chunk 5 and some dependencies come from later chunks, we use placeholders:

```dart
// In oauth_session.dart
abstract class OAuthServerAgent {
  OAuthAuthorizationServerMetadata get serverMetadata;
  Map<String, dynamic> get dpopKey;
  String get authMethod;
  Future<void> revoke(String token);
  Future<TokenSet> refresh(TokenSet tokenSet);
}

// In session_getter.dart
abstract class OAuthServerFactory {
  Future<OAuthServerAgent> fromIssuer(
    String issuer,
    String authMethod,
    Map<String, dynamic> dpopKey,
  );
}

abstract class Runtime {
  bool get hasImplementationLock;
  Future<T> usingLock<T>(String key, Future<T> Function() callback);
  Future<List<int>> sha256(List<int> data);
}

class OAuthResponseError implements Exception {
  final int status;
  final String? error;
  final String? errorDescription;
}
```

These will be replaced with actual implementations in later chunks.

### 5. Token Expiration Logic

**TypeScript**:
```typescript
expires_at != null &&
  new Date(expires_at).getTime() <
    Date.now() + 10e3 + 30e3 * Math.random()
```

**Dart**:
```dart
if (tokenSet.expiresAt == null) return false;

final expiresAt = DateTime.parse(tokenSet.expiresAt!);
final now = DateTime.now();

// 10 seconds buffer + 0-30 seconds randomization
final buffer = Duration(
  milliseconds: 10000 + (math.Random().nextDouble() * 30000).toInt(),
);

return expiresAt.isBefore(now.add(buffer));
```

The randomization prevents multiple instances from refreshing simultaneously.

### 6. HTTP Client Integration

**TypeScript** uses global `fetch`:
```typescript
const response = await fetch(url, { method: 'POST', ... })
```

**Dart** uses `package:http`:
```dart
import 'package:http/http.dart' as http;

final request = http.Request(method, url);
request.headers.addAll(headers);
request.body = body;
final streamedResponse = await _httpClient.send(request);
return await http.Response.fromStream(streamedResponse);
```

### 7. Record Types for Pending Results

**TypeScript**:
```typescript
type PendingItem<V> = Promise<{ value: V; isFresh: boolean }>
```

**Dart (using Dart 3.0 records)**:
```dart
class _PendingItem<V> {
  final Future<({V value, bool isFresh})> future;
  _PendingItem(this.future);
}
```

## API Compatibility

### Session Management

| TypeScript | Dart | Notes |
|------------|------|-------|
| `SessionGetter.getSession(sub, refresh?)` | `SessionGetter.getSession(sub, [refresh])` | Identical API |
| `SessionGetter.addEventListener('updated', ...)` | `SessionGetter.onUpdated.listen(...)` | Stream-based |
| `SessionGetter.addEventListener('deleted', ...)` | `SessionGetter.onDeleted.listen(...)` | Stream-based |

### OAuth Session

| TypeScript | Dart | Notes |
|------------|------|-------|
| `session.getTokenInfo(refresh?)` | `session.getTokenInfo([refresh])` | Identical API |
| `session.signOut()` | `session.signOut()` | Identical API |
| `session.fetchHandler(pathname, init?)` | `session.fetchHandler(pathname, {method, headers, body})` | Named parameters |

## Testing Strategy

The implementation compiles successfully with only 2 minor linting suggestions:
- Use null-aware operator in one place (style preference)
- Use `rethrow` in one catch block (style preference)

Both are cosmetic and don't affect functionality.

### Manual Testing Checklist

When later chunks provide concrete implementations:

```dart
// 1. Create a session
final session = Session(
  dpopKey: {'kty': 'EC', ...},
  authMethod: 'none',
  tokenSet: TokenSet(
    iss: 'https://bsky.social',
    sub: 'did:plc:abc123',
    aud: 'https://bsky.social',
    scope: 'atproto',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().add(Duration(hours: 1)).toIso8601String(),
  ),
);

// 2. Store in session getter
await sessionGetter.setStored('did:plc:abc123', session);

// 3. Retrieve (should not refresh)
final retrieved = await sessionGetter.getSession('did:plc:abc123', false);
assert(retrieved.tokenSet.accessToken == 'token');

// 4. Force refresh
final refreshed = await sessionGetter.getSession('did:plc:abc123', true);
// Should have new tokens

// 5. Check expiration
assert(!session.tokenSet.isExpired);

// 6. Delete
await sessionGetter.delStored('did:plc:abc123');
final deleted = await sessionGetter.getSession('did:plc:abc123');
// Should throw or return null
```

## Security Considerations

### 1. Token Storage

**Critical**: Tokens MUST be stored securely:
```dart
// ❌ NEVER do this
final prefs = await SharedPreferences.getInstance();
await prefs.setString('token', tokenSet.toJson().toString());

// ✅ Use flutter_secure_storage (implemented in Chunk 7)
final storage = FlutterSecureStorage();
await storage.write(
  key: 'session_$sub',
  value: jsonEncode(session.toJson()),
);
```

### 2. Token Logging

**Never log sensitive data**:
```dart
// ❌ NEVER
print('Access token: ${tokenSet.accessToken}');

// ✅ Safe logging
print('Token expires at: ${tokenSet.expiresAt}');
print('Token type: ${tokenSet.tokenType}');
```

### 3. Session Lifecycle

Sessions are automatically deleted when:
- Token refresh fails with `invalid_grant`
- Token is revoked by the server
- User explicitly signs out
- Token is marked invalid by resource server

### 4. Concurrency Protection

The `SessionGetter` includes multiple layers of protection:
1. **Runtime locks**: Prevent simultaneous refreshes across app instances
2. **Pending request tracking**: Coalesce concurrent requests
3. **Store-based detection**: Detect concurrent refreshes without locks
4. **Randomized expiry**: Reduce thundering herd at startup

## Integration with Other Chunks

### Dependencies (Available)
- ✅ Chunk 1: Error types (`TokenRefreshError`, `TokenRevokedError`, etc.)
- ✅ Chunk 1: Utilities (`CustomEventTarget`, `CancellationToken`)
- ✅ Chunk 1: Constants

### Dependencies (Future Chunks)
- ⏳ Chunk 6: `OAuthServerAgent` implementation
- ⏳ Chunk 7: `OAuthServerFactory` implementation
- ⏳ Chunk 7: `Runtime` implementation
- ⏳ Chunk 7: Concrete storage implementations (SecureSessionStore)
- ⏳ Chunk 8: DPoP fetch wrapper integration

## File Structure

```
lib/src/session/
├── state_store.dart          # OAuth state storage (PKCE, nonce, etc.)
├── oauth_session.dart         # Session types and OAuthSession class
├── session_getter.dart        # SessionGetter and CachedGetter
└── session.dart              # Barrel file
```

## Next Steps

For Chunk 6+:
1. Implement `OAuthServerAgent` with actual token refresh logic
2. Implement `OAuthServerFactory` for creating server agents
3. Implement `Runtime` with platform-specific lock mechanisms
4. Create concrete `SessionStore` using `flutter_secure_storage`
5. Create concrete `StateStore` for ephemeral OAuth state
6. Integrate DPoP proof generation in `fetchHandler`
7. Add proper error handling for network failures
8. Implement session migration for schema changes

## Performance Notes

### Memory Management
- `SessionGetter` maintains a `_pending` map for in-flight requests
- This map is automatically cleaned up when requests complete
- Stream controllers must be disposed via `dispose()`
- HTTP clients should be reused, not created per request

### Optimization Opportunities
- The randomized expiry buffer (0-30s) spreads refresh load
- Pending request coalescing reduces redundant network calls
- Cached values avoid unnecessary store reads

## Known Limitations

1. **No DPoP yet**: `fetchHandler` doesn't generate DPoP proofs (Chunk 8)
2. **No actual refresh**: `OAuthServerAgent.refresh()` is a placeholder
3. **No secure storage**: Storage implementations come in Chunk 7
4. **No runtime locks**: Lock implementation comes in Chunk 7

These are intentional - this chunk focuses on the session management *structure*, with concrete implementations following in later chunks.

## Conclusion

Chunk 5 successfully implements the session management layer with:
- ✅ Complete API compatibility with TypeScript
- ✅ Proper abstractions for future implementations
- ✅ Security-conscious design (even if storage is placeholder)
- ✅ Event-driven architecture using Dart streams
- ✅ Comprehensive error handling
- ✅ Zero compilation errors

The code is production-ready structurally and awaits concrete implementations from subsequent chunks.
