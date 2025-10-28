# atProto Identity Resolution Layer

## Overview

This module implements the **critical identity resolution functionality** for atProto decentralization. It resolves atProto handles and DIDs to discover where user data is actually stored (their Personal Data Server).

## Why This Matters

**This is the most important code for decentralization in atProto.**

Without this layer:
- Apps hardcode `bsky.social` as the only server
- Users can't use custom domains
- Self-hosting is impossible
- atProto becomes centralized

With this layer:
- ✅ Users host data on any PDS they choose
- ✅ Custom domain handles work (e.g., `alice.example.com`)
- ✅ Identity is portable (change PDS without losing DID)
- ✅ True decentralization is achieved

## Architecture

### Resolution Flow

```
Handle/DID Input
    ↓
Is it a DID? ──Yes──→ DID Resolution
    ↓                      ↓
    No                DID Document
    ↓                      ↓
Handle Resolution    Extract Handle
    ↓                      ↓
    DID                Validate Handle ←→ DID
    ↓                      ↓
DID Resolution        Return IdentityInfo
    ↓
DID Document
    ↓
Validate Handle in Doc
    ↓
Extract PDS URL
    ↓
Return IdentityInfo
```

### Key Components

#### 1. IdentityResolver
Main interface for resolving identities. Use `AtprotoIdentityResolver` for the standard implementation.

```dart
final resolver = AtprotoIdentityResolver.withDefaults(
  handleResolverUrl: 'https://bsky.social',
);

// Resolve to PDS URL (most common use case)
final pdsUrl = await resolver.resolveToPds('alice.example.com');

// Get full identity info
final info = await resolver.resolve('alice.example.com');
print('DID: ${info.did}');
print('Handle: ${info.handle}');
print('PDS: ${info.pdsUrl}');
```

#### 2. HandleResolver
Resolves atProto handles (e.g., `alice.bsky.social`) to DIDs using XRPC.

**Resolution Methods:**
- XRPC: Uses `com.atproto.identity.resolveHandle` endpoint
- DNS TXT record: Checks `_atproto.{handle}` (not implemented yet)
- .well-known: Checks `https://{handle}/.well-known/atproto-did` (not implemented yet)

Current implementation uses XRPC, which works for all handles.

#### 3. DidResolver
Resolves DIDs to DID documents.

**Supported Methods:**
- `did:plc`: Queries PLC directory (https://plc.directory)
- `did:web`: Fetches from HTTPS URLs

#### 4. DidDocument
Represents a W3C DID document with atProto-specific helpers:
- `extractPdsUrl()`: Gets the PDS endpoint
- `extractNormalizedHandle()`: Gets the validated handle

### Bi-directional Resolution

For security, we enforce **bi-directional resolution**:

1. Handle → DID resolution must succeed
2. DID document must contain the original handle
3. Both directions must agree

This prevents:
- Handle hijacking
- DID spoofing
- MITM attacks

### Caching

Built-in caching with configurable TTLs:
- **Handles**: 1 hour default (handles can change)
- **DIDs**: 24 hours default (DID docs are more stable)

Caching is automatic but can be bypassed with `noCache: true`.

## File Structure

```
identity/
├── constants.dart              # atProto constants
├── did_document.dart           # DID document representation
├── did_helpers.dart            # DID validation utilities
├── did_resolver.dart           # DID → DID document resolution
├── handle_helpers.dart         # Handle validation utilities
├── handle_resolver.dart        # Handle → DID resolution
├── identity_resolver.dart      # Main resolver (orchestrates everything)
├── identity_resolver_error.dart # Error types
├── identity.dart               # Public exports
└── README.md                   # This file
```

## Usage Examples

### Basic Resolution

```dart
import 'package:atproto_oauth_flutter/src/identity/identity.dart';

final resolver = AtprotoIdentityResolver.withDefaults(
  handleResolverUrl: 'https://bsky.social',
);

// Simple PDS lookup
final pdsUrl = await resolver.resolveToPds('alice.bsky.social');
print('PDS: $pdsUrl');
```

### Custom Configuration

```dart
// With custom caching and PLC directory
final resolver = AtprotoIdentityResolver.withDefaults(
  handleResolverUrl: 'https://bsky.social',
  plcDirectoryUrl: 'https://plc.directory/',
  didCache: InMemoryDidCache(ttl: Duration(hours: 12)),
  handleCache: InMemoryHandleCache(ttl: Duration(minutes: 30)),
);
```

### Manual Component Construction

```dart
// Build your own resolver with custom components
final dio = Dio();

final didResolver = CachedDidResolver(
  AtprotoDidResolver(dio: dio),
);

final handleResolver = CachedHandleResolver(
  XrpcHandleResolver('https://bsky.social', dio: dio),
);

final resolver = AtprotoIdentityResolver(
  didResolver: didResolver,
  handleResolver: handleResolver,
);
```

### Error Handling

```dart
try {
  final info = await resolver.resolve('invalid-handle');
} on InvalidHandleError catch (e) {
  print('Invalid handle format: $e');
} on HandleResolverError catch (e) {
  print('Handle resolution failed: $e');
} on DidResolverError catch (e) {
  print('DID resolution failed: $e');
} on IdentityResolverError catch (e) {
  print('Identity resolution failed: $e');
}
```

## Implementation Notes

### Ported from TypeScript

This implementation is a 1:1 port from the official atProto TypeScript packages:
- `@atproto-labs/identity-resolver`
- `@atproto-labs/did-resolver`
- `@atproto-labs/handle-resolver`

Source: `/home/bretton/Code/atproto/packages/oauth/oauth-client/src/identity-resolver.ts`

### Differences from TypeScript

1. **No DNS Resolution**: Dart doesn't have built-in DNS TXT lookups. We use XRPC only.
2. **Simplified Caching**: In-memory only (TypeScript has more cache backends).
3. **Dio instead of Fetch**: Using Dio HTTP client instead of global fetch.
4. **Explicit Types**: Dart's type system is more explicit than TypeScript's.

### Future Improvements

- [ ] Add DNS-over-HTTPS for handle resolution
- [ ] Implement .well-known handle resolution
- [ ] Add persistent cache backends (SQLite, Hive)
- [ ] Support custom DID methods beyond plc/web
- [ ] Add metrics and observability
- [ ] Implement resolver timeouts and retries

## Testing

Test the implementation with real handles:

```dart
// Test custom PDS
final pds1 = await resolver.resolveToPds('bretton.dev');
assert(pds1.contains('pds.bretton.dev'));

// Test Bluesky user
final pds2 = await resolver.resolveToPds('pfrazee.com');
print('Paul Frazee PDS: $pds2');

// Test from DID
final info = await resolver.resolveFromDid('did:plc:ragtjsm2j2vknwkz3zp4oxrd');
assert(info.handle == 'pfrazee.com');
```

## Security Considerations

1. **Bi-directional Validation**: Always enforced to prevent spoofing
2. **HTTPS Only**: All HTTP requests use HTTPS (except localhost for testing)
3. **No Redirects**: HTTP redirects are rejected to prevent attacks
4. **Input Validation**: All handles and DIDs are validated before use
5. **Cache Poisoning**: TTLs prevent stale data, noCache option available

## Performance

Typical resolution times (with cold cache):
- Handle → PDS: ~200-500ms (1 handle lookup + 1 DID fetch)
- DID → PDS: ~100-200ms (1 DID fetch only)
- Cached resolution: <1ms (in-memory lookup)

For production apps:
- Enable caching (default)
- Use connection pooling (Dio does this)
- Consider warming cache for known users
- Monitor resolver errors and timeouts

## References

- [atProto DID Spec](https://atproto.com/specs/did)
- [atProto Handle Spec](https://atproto.com/specs/handle)
- [W3C DID Core](https://www.w3.org/TR/did-core/)
- [PLC Directory](https://plc.directory/)
