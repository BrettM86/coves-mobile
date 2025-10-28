# Flutter Platform Layer

This directory contains Flutter-specific implementations of the atproto OAuth client.

## Overview

The platform layer provides concrete implementations of all the abstract interfaces needed for OAuth to work on Flutter:

1. **Storage** (`flutter_stores.dart`) - Secure session storage and caching
2. **Cryptography** (`flutter_runtime.dart`) - Key generation, hashing, random values
3. **Key Management** (`flutter_key.dart`) - EC key implementation with pointycastle
4. **High-level API** (`flutter_oauth_client.dart`) - Easy-to-use Flutter OAuth client

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   FlutterOAuthClient                         │
│                    (High-level API)                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      OAuthClient                             │
│                   (Core OAuth logic)                         │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Storage   │    │   Runtime   │    │    Key      │
│   (secure   │    │   (crypto)  │    │ (signing)   │
│   storage)  │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘
        │                  │                   │
        ▼                  ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   flutter_  │    │   crypto/   │    │ pointycastle│
│   secure_   │    │ Random.     │    │   (ECDSA)   │
│   storage   │    │   secure()  │    │             │
└─────────────┘    └─────────────┘    └─────────────┘
```

## Files

### `flutter_stores.dart`

Implements storage and caching:

- **FlutterSessionStore**: Persists OAuth sessions in secure storage
  - iOS: Keychain
  - Android: EncryptedSharedPreferences
  - Stores tokens, DPoP keys, and auth methods

- **FlutterStateStore**: Ephemeral OAuth state (in-memory)
  - PKCE verifiers
  - State parameters
  - Application state

- **Cache Implementations**: In-memory caches with TTL
  - `InMemoryAuthorizationServerMetadataCache`: OAuth server metadata (1 min TTL)
  - `InMemoryProtectedResourceMetadataCache`: Resource server metadata (1 min TTL)
  - `InMemoryDpopNonceCache`: DPoP nonces (10 min TTL)
  - `FlutterDidCache`: DID documents (1 min TTL)
  - `FlutterHandleCache`: Handle → DID mappings (1 min TTL)

### `flutter_runtime.dart`

Implements cryptographic operations:

- **FlutterRuntime**: Platform-specific crypto implementation
  - `createKey`: EC key generation (ES256/ES384/ES512/ES256K)
  - `digest`: SHA-256/384/512 hashing
  - `getRandomValues`: Cryptographically secure random bytes
  - `requestLock`: Local (in-memory) locking for token refresh

Uses:
- `crypto` package for SHA hashing
- `Random.secure()` for randomness
- `utils/lock.dart` for concurrency control

### `flutter_key.dart`

Implements EC key management:

- **FlutterKey**: Elliptic Curve key for JWT signing
  - Supports ES256, ES384, ES512, ES256K
  - Uses `pointycastle` for ECDSA operations
  - Implements `Key` interface from runtime layer
  - Serializable (for session storage)

Features:
- Secure key generation with `FortunaRandom`
- JWT signing (compact format)
- JWK representation (public and private)
- Key reconstruction from JSON

### `flutter_oauth_client.dart`

High-level Flutter API:

- **FlutterOAuthClient**: Easy-to-use OAuth client
  - Pre-configured storage and caching
  - Automatic FlutterWebAuth2 integration
  - Simplified sign-in flow
  - Session management helpers

Key method:
```dart
// One-liner sign in!
final session = await client.signIn('alice.bsky.social');
```

This handles:
1. Authorization URL generation
2. Browser launch (FlutterWebAuth2)
3. Callback handling
4. Token exchange
5. Session storage

## Security Features

### 1. Secure Storage

Tokens are **never** stored in plain text:

- **iOS**: Stored in Keychain with device encryption
- **Android**: EncryptedSharedPreferences with AES-256

### 2. DPoP (Demonstrating Proof of Possession)

Tokens are cryptographically bound to EC keys:

- Prevents token theft (stolen tokens are useless without the key)
- Keys stored alongside tokens in secure storage
- Every API request includes a signed DPoP proof

### 3. PKCE (Proof Key for Code Exchange)

Protects authorization codes from interception:

- Random code verifier generated for each flow
- Challenge sent to server (SHA-256 hash of verifier)
- Verifier required to exchange code for tokens

### 4. Concurrency Control

Prevents race conditions in token refresh:

- Local lock ensures only one refresh at a time
- Reduces chances of using refresh token twice
- Handles concurrent requests gracefully

### 5. Automatic Cleanup

Sessions are automatically deleted on errors:

- Token refresh failures
- Invalid token errors
- Auth method unsatisfiable errors
- Revocation (local and remote)

## Usage

### Basic Usage

```dart
import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';

// Initialize
final client = FlutterOAuthClient(
  clientMetadata: ClientMetadata(
    clientId: 'https://example.com/client-metadata.json',
    redirectUris: ['myapp://oauth/callback'],
  ),
);

// Sign in
final session = await client.signIn('alice.bsky.social');

// Use session
print('Signed in as: ${session.sub}');

// Restore later
final restored = await client.restore(session.sub);

// Sign out
await client.revoke(session.sub);
```

### Custom Configuration

```dart
final client = FlutterOAuthClient(
  clientMetadata: ClientMetadata(
    clientId: 'https://example.com/client-metadata.json',
    redirectUris: ['myapp://oauth/callback'],
  ),

  // Custom secure storage
  secureStorage: FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  ),

  // Development mode
  allowHttp: true,

  // Custom PLC directory
  plcDirectoryUrl: 'https://plc.example.com',
);
```

## Testing

The platform layer is designed to be testable:

1. **Mock Storage**: Provide test implementation of `SessionStore`
2. **Mock Runtime**: Provide test implementation of `RuntimeImplementation`
3. **Mock Keys**: Use fixed test keys instead of random generation

Example:

```dart
// Test storage that uses in-memory map
class TestSessionStore implements SessionStore {
  final Map<String, Session> _store = {};

  @override
  Future<Session?> get(String key, {CancellationToken? signal}) async {
    return _store[key];
  }

  @override
  Future<void> set(String key, Session value) async {
    _store[key] = value;
  }

  // ... etc
}

// Use in tests
final client = OAuthClient(
  OAuthClientOptions(
    // ... other options
    sessionStore: TestSessionStore(),
  ),
);
```

## Platform Setup

### iOS

Add URL scheme to `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myapp</string>
    </array>
  </dict>
</array>
```

### Android

Add intent filter to `AndroidManifest.xml`:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="myapp" />
</intent-filter>
```

## Dependencies

- `flutter_secure_storage: ^9.2.2` - Secure token storage
- `flutter_web_auth_2: ^4.1.0` - Browser-based OAuth flow
- `pointycastle: ^3.9.1` - Elliptic Curve cryptography
- `crypto: ^3.0.3` - SHA hashing

## Known Limitations

### 1. Key Serialization

Currently, DPoP keys are regenerated on each app restart. This works but has drawbacks:

- Tokens bound to old keys become invalid (require refresh)
- Slight performance impact on session restoration

**Fix**: Implement proper `Key` serialization in `flutter_key.dart`:
- Add `toJson()` method that includes private key components
- Add `fromJson()` factory that reconstructs the key
- Store serialized keys in session storage

### 2. Local Lock Only

The lock implementation is in-memory and doesn't work across:
- Multiple isolates
- Multiple processes
- Multiple app instances

For most Flutter apps, this is fine. For advanced use cases, implement a platform-specific lock.

### 3. Cache TTLs

Cache TTLs are fixed (1 minute for most caches). Consider making these configurable if your app has different caching requirements.

## Future Improvements

1. **Key Persistence**: Implement proper key serialization (see above)
2. **Platform Locks**: Add iOS/Android native lock implementations
3. **Configurable TTLs**: Allow cache TTL customization
4. **Background Refresh**: Support token refresh in background
5. **Biometric Auth**: Optional biometric unlock for sessions
6. **Migration Helpers**: Tools for migrating from other OAuth libraries

## See Also

- [Example usage](../../example/flutter_oauth_example.dart)
- [Main library docs](../../atproto_oauth_flutter.dart)
- [Core OAuth client](../client/oauth_client.dart)
