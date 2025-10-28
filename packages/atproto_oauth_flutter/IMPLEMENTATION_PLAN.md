# Implementation Plan: atproto_oauth_flutter

## Overview
1:1 port of `@atproto/oauth-client` from TypeScript to Dart/Flutter

**Source:** `/home/bretton/Code/atproto/packages/oauth/oauth-client/`
**Target:** `/home/bretton/Code/coves_flutter/packages/atproto_oauth_flutter/`

## Implementation Chunks

### Chunk 1: Foundation Layer ✅
**Files to port:**
- `src/constants.ts` → `lib/src/constants.dart`
- `src/types.ts` → `lib/src/types.dart`
- `src/errors/*.ts` → `lib/src/errors/*.dart`
- `src/util.ts` → `lib/src/util.dart`

**Dependencies:** None (pure types and utilities)
**Estimated LOC:** ~300 lines

### Chunk 2: Crypto & DPoP Layer
**Files to port:**
- `src/runtime-implementation.ts` → `lib/src/runtime/runtime_implementation.dart`
- `src/runtime.ts` → `lib/src/runtime/runtime.dart`
- `src/fetch-dpop.ts` → `lib/src/dpop/fetch_dpop.dart`
- `src/lock.ts` → `lib/src/utils/lock.dart`

**Dependencies:** Chunk 1 (types, errors)
**Dart packages:** `crypto`, `pointycastle`, `convert`
**Estimated LOC:** ~500 lines

### Chunk 3: Identity Resolution
**Files to port:**
- `src/identity-resolver.ts` → `lib/src/identity/identity_resolver.dart`

**Dependencies:** Chunk 1, Chunk 2
**Estimated LOC:** ~200 lines

### Chunk 4: OAuth Protocol Layer
**Files to port:**
- `src/oauth-authorization-server-metadata-resolver.ts` → `lib/src/oauth/authorization_server_metadata_resolver.dart`
- `src/oauth-protected-resource-metadata-resolver.ts` → `lib/src/oauth/protected_resource_metadata_resolver.dart`
- `src/oauth-resolver.ts` → `lib/src/oauth/oauth_resolver.dart`
- `src/oauth-client-auth.ts` → `lib/src/oauth/client_auth.dart`
- `src/validate-client-metadata.ts` → `lib/src/oauth/validate_client_metadata.dart`
- `src/oauth-callback-error.ts` → `lib/src/errors/oauth_callback_error.dart`
- `src/oauth-resolver-error.ts` → `lib/src/errors/oauth_resolver_error.dart`
- `src/oauth-response-error.ts` → `lib/src/errors/oauth_response_error.dart`

**Dependencies:** Chunk 1, Chunk 2, Chunk 3
**Estimated LOC:** ~800 lines

### Chunk 5: Session Management
**Files to port:**
- `src/session-getter.ts` → `lib/src/session/session_getter.dart`
- `src/state-store.ts` → `lib/src/session/state_store.dart`
- `src/oauth-session.ts` → `lib/src/session/oauth_session.dart`

**Dependencies:** Chunk 1, Chunk 2
**Estimated LOC:** ~400 lines

### Chunk 6: Core OAuth Client
**Files to port:**
- `src/oauth-server-agent.ts` → `lib/src/client/oauth_server_agent.dart`
- `src/oauth-server-factory.ts` → `lib/src/client/oauth_server_factory.dart`
- `src/oauth-client.ts` → `lib/src/client/oauth_client.dart`

**Dependencies:** All previous chunks
**Estimated LOC:** ~700 lines

### Chunk 7: Flutter Platform Layer (NEW)
**Files to create:**
- `lib/src/platform/flutter_stores.dart` - Secure storage implementations
- `lib/src/platform/flutter_runtime.dart` - Flutter crypto implementations
- `lib/src/platform/flutter_oauth_client.dart` - Flutter-specific client
- `lib/atproto_oauth_flutter.dart` - Main export file

**Dependencies:** All previous chunks, Flutter packages
**Estimated LOC:** ~300 lines

## Agent Execution Plan

Each chunk will be implemented by a sub-agent with:
1. **Implementation Agent** - Ports TypeScript to Dart
2. **Review Agent** - Reviews for bugs, best practices, API compatibility

## Success Criteria

- [ ] All TypeScript files ported to Dart
- [ ] API matches Expo package (same method signatures)
- [ ] Zero compilation errors
- [ ] Proper decentralization (PDS discovery works)
- [ ] Works with bretton.dev (custom PDS)

## Testing Plan

After all chunks complete:
1. Unit tests for each module
2. Integration test with bretton.dev
3. Integration test with bsky.social
4. Session persistence test
5. Token refresh test
