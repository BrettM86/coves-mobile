# OAuth Implementation Guide for Coves Flutter

## Overview

This document outlines the OAuth implementation for Coves, a forum-like atProto social media platform. We're using the `atproto_oauth` package (v0.1.0) to authenticate users against their Personal Data Servers (PDS) in the decentralized atProto network.

## ⚠️ Important: Decentralized Authentication

**atProto is a decentralized protocol** - users can be on ANY Personal Data Server (PDS), not just bsky.social!

### How Handle Resolution Works

The OAuth flow must support users from any PDS:

1. **Handle Resolver** (`service: 'bsky.social'` parameter)
   - This is a service that can resolve ANY atProto handle to a DID
   - Example: `alice.pds.example.com` → `did:plc:abc123`
   - Bluesky provides a public resolver that works for all atProto handles
   - **This is NOT the authorization server!**

2. **PDS Discovery** (automatic via DID document)
   - User's DID document contains their PDS URL
   - Fetch `did:plc:abc123` → Find PDS endpoint in service array
   - Example: `https://alice-pds.example.com`

3. **OAuth Authorization Server Discovery** (automatic)
   - Each PDS has its own OAuth server
   - Discovered from: `https://alice-pds.example.com/.well-known/oauth-authorization-server`
   - **Users are redirected to THEIR PDS's auth server, not always bsky.social**

### Testing Decentralization

When testing sign-in, check the debug logs:

```dart
🔍 OAuth Authorization URL: https://example-pds.com/oauth/authorize?...
🔍 Authorization server host: example-pds.com
```

✅ **Correct**: `authUrl.host` matches the user's PDS
❌ **Wrong**: `authUrl.host` is always `bsky.app` regardless of handle

If users on different PDSes can sign in (not just bsky.social users), then decentralization is working correctly!

---

## ✅ What's Already Been Completed

### 1. Project Setup & Dependencies

**File:** [`pubspec.yaml`](./pubspec.yaml)

All required OAuth packages are installed and configured:
- ✅ `atproto_oauth: ^0.1.0` - Official atProto OAuth client
- ✅ `flutter_web_auth_2: ^4.1.0` - Browser-based OAuth flow
- ✅ `flutter_secure_storage: ^9.2.2` - Encrypted token storage
- ✅ `go_router: ^16.3.0` - Navigation with deep linking support
- ✅ `provider: ^6.1.5+1` - State management

### 2. OAuth Configuration

**File:** [`lib/config/oauth_config.dart`](./lib/config/oauth_config.dart)

Complete OAuth configuration matching your Cloudflare Worker setup:

```dart
class OAuthConfig {
  // OAuth Server (Cloudflare Worker)
  static const String oauthServerUrl =
    'https://lingering-darkness-50a6.brettmay0212.workers.dev';

  // Custom URL scheme for deep linking
  static const String customScheme =
    'dev.workers.brettmay0212.lingering-darkness-50a6';

  // Client metadata URL (hosted on your Cloudflare Worker)
  static const String clientId = '$oauthServerUrl/client-metadata.json';

  // OAuth callback URL
  static const String redirectUri = '$oauthServerUrl/oauth/callback';

  // atProto scopes
  static const String scope = 'atproto transition:generic';

  // Handle resolver (uses Bluesky's resolver)
  static const String handleResolver = 'https://bsky.social';
}
```

**Key Points:**
- ✅ All URLs point to your Cloudflare Worker
- ✅ Client metadata is hosted at `/client-metadata.json`
- ✅ Custom scheme matches your app configuration
- ✅ Scopes allow full atProto access

### 3. OAuth Service Foundation

**File:** [`lib/services/oauth_service.dart`](./lib/services/oauth_service.dart)

OAuth service skeleton with proper architecture:

```dart
class OAuthService {
  OAuthClient? _client;
  final _storage = const FlutterSecureStorage();

  // Storage keys - properly named for atProto decentralization
  static const _keyAccessToken = 'atproto_oauth_access_token';
  static const _keyRefreshToken = 'atproto_oauth_refresh_token';
  static const _keyDid = 'atproto_did';
  static const _keyHandle = 'atproto_handle';

  Future<void> initialize() async {
    // Fetches client metadata from Cloudflare Worker
    final metadata = await getClientMetadata(OAuthConfig.clientId);
    _client = OAuthClient(metadata, service: 'bsky.social');
  }

  // Methods ready for implementation:
  Future<OAuthSession> signIn(String handle) async { /* ... */ }
  Future<OAuthSession?> restoreSession() async { /* ... */ }
  Future<void> signOut() async { /* ... */ }
}
```

**What's Ready:**
- ✅ Singleton pattern for service
- ✅ Client initialization with metadata fetching
- ✅ Secure storage using `flutter_secure_storage`
- ✅ Storage keys properly named for atProto (not app-specific)
- ✅ Session management methods scaffolded

**Important Design Decision:**
Storage keys use `atproto_*` prefix instead of `coves_*` to reflect that credentials belong to the user's PDS, not to Coves. This follows the decentralized architecture principle where the user owns their identity.

### 4. Authentication State Management

**File:** [`lib/providers/auth_provider.dart`](./lib/providers/auth_provider.dart)

Complete auth provider using `ChangeNotifier`:

```dart
class AuthProvider with ChangeNotifier {
  final OAuthService _oauthService = OAuthService();

  // State
  OAuthSession? _session;
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _error;
  String? _did;
  String? _handle;

  // Methods
  Future<void> initialize() async { /* Restores session */ }
  Future<void> signIn(String handle) async { /* OAuth flow */ }
  Future<void> signOut() async { /* Revokes & clears */ }
  void clearError() { /* Error handling */ }
}
```

**What's Ready:**
- ✅ Reactive state management with `ChangeNotifier`
- ✅ Loading states for UI feedback
- ✅ Error handling
- ✅ Session persistence
- ✅ Integrated with `OAuthService`

### 5. Android Deep Link Configuration

**File:** [`android/app/src/main/AndroidManifest.xml`](./android/app/src/main/AndroidManifest.xml)

Deep links configured for OAuth callbacks:

```xml
<!-- HTTPS deep link for OAuth callback -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>

    <data
        android:scheme="https"
        android:host="lingering-darkness-50a6.brettmay0212.workers.dev"
        android:pathPrefix="/oauth/callback"/>
</intent-filter>

<!-- Custom scheme fallback -->
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>

    <data android:scheme="dev.workers.brettmay0212.lingering-darkness-50a6"/>
</intent-filter>
```

**What's Ready:**
- ✅ HTTPS deep links (preferred on Android)
- ✅ Custom scheme fallback
- ✅ Auto-verify for App Links
- ✅ Matches OAuth redirect URIs

### 6. Login UI

**File:** [`lib/screens/auth/login_screen.dart`](./lib/screens/auth/login_screen.dart)

Professional login screen with:
- ✅ Handle input with validation
- ✅ Loading states
- ✅ Error handling with SnackBar
- ✅ Help dialog explaining handles
- ✅ Integration with AuthProvider
- ✅ Navigation to feed on success

### 7. App-Level Integration

**File:** [`lib/main.dart`](./lib/main.dart)

Auth provider wrapped around entire app:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authProvider = AuthProvider();
  await authProvider.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: authProvider,
      child: const CovesApp(),
    ),
  );
}
```

**What's Ready:**
- ✅ Provider initialization before app starts
- ✅ Session restoration on app launch
- ✅ Global state access via `Provider.of<AuthProvider>(context)`

---

## 🚧 What Needs to Be Implemented

### Phase 1: Complete OAuth Flow (High Priority)

#### 1.1 Implement `signIn()` Method

**File to Update:** [`lib/services/oauth_service.dart`](./lib/services/oauth_service.dart)

**Current Status:** Method stub exists but returns `UnimplementedError`

**What to Implement:**

```dart
Future<OAuthSession> signIn(String handle) async {
  try {
    if (_client == null) {
      throw Exception('OAuth client not initialized');
    }

    // Step 1: Use atproto_oauth to resolve handle and build auth URL
    // The package handles:
    // - DID resolution from handle
    // - Finding the user's authorization server
    // - Generating PKCE challenge/verifier
    // - Building PAR (Pushed Authorization Request)
    // - Generating DPoP keys

    final authRequest = await _client!.authorize(
      identifier: handle,
      // The package will use the client metadata we fetched
    );

    // Step 2: Open browser for user authorization
    // This opens the user's PDS authorization page
    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: authRequest.authorizationUrl.toString(),
      callbackUrlScheme: OAuthConfig.customScheme,
    );

    // Step 3: Extract authorization code from callback
    final uri = Uri.parse(callbackUrl);
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];

    if (code == null) {
      throw Exception('No authorization code received');
    }

    // Step 4: Exchange code for tokens with DPoP
    // The package handles:
    // - Token exchange request
    // - DPoP proof generation
    // - Token validation
    final session = await _client!.callback(
      uri: uri,
      // Package manages PKCE and state internally
    );

    // Step 5: Extract and store session data
    final tokens = OAuthSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      did: session.sub, // User's DID
      handle: handle,
    );

    await _storeSession(tokens);

    return tokens;
  } catch (e) {
    print('Sign in failed: $e');
    rethrow;
  }
}
```

**Key Implementation Notes:**
- Use `atproto_oauth`'s built-in methods for authorization flow
- The package handles complex atProto specifics (DPoP, PKCE, PAR)
- Store DID (not just handle) as the canonical user identifier
- Handle browser cancellation gracefully

**References:**
- [atproto_oauth package docs](https://pub.dev/packages/atproto_oauth)
- [flutter_web_auth_2 docs](https://pub.dev/packages/flutter_web_auth_2)

#### 1.2 Implement `restoreSession()` Method

**What to Implement:**

```dart
Future<OAuthSession?> restoreSession() async {
  try {
    final did = await _storage.read(key: _keyDid);

    if (did == null) {
      return null; // No stored session
    }

    if (_client == null) {
      throw Exception('OAuth client not initialized');
    }

    // Check if we have a valid session for this DID
    // The atproto_oauth package manages session storage internally
    // We may need to use their session restoration methods

    final session = await _client!.restore(did);

    if (session != null) {
      // Session still valid, return it
      final handle = await _storage.read(key: _keyHandle);

      return OAuthSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        did: did,
        handle: handle ?? '',
      );
    }

    // Session expired, try to refresh
    final refreshToken = await _storage.read(key: _keyRefreshToken);

    if (refreshToken != null) {
      final newSession = await _refreshSession(did, refreshToken);
      await _storeSession(newSession);
      return newSession;
    }

    // No valid session, user needs to log in again
    await _clearSession();
    return null;

  } catch (e) {
    print('Failed to restore session: $e');
    await _clearSession();
    return null;
  }
}
```

**Key Implementation Notes:**
- Always validate stored sessions before using them
- Attempt token refresh if access token expired but refresh token valid
- Clear invalid sessions to prevent auth loops
- The `atproto_oauth` package may handle session restoration internally

#### 1.3 Implement Token Refresh

**What to Implement:**

```dart
Future<OAuthSession> _refreshSession(String did, String refreshToken) async {
  if (_client == null) {
    throw Exception('OAuth client not initialized');
  }

  // Use atproto_oauth's refresh method
  final newSession = await _client!.refresh(
    refreshToken: refreshToken,
    // Package handles DPoP proof for refresh
  );

  final handle = await _storage.read(key: _keyHandle);

  return OAuthSession(
    accessToken: newSession.accessToken,
    refreshToken: newSession.refreshToken ?? refreshToken,
    did: did,
    handle: handle ?? '',
  );
}
```

#### 1.4 Implement `signOut()` Method

**What to Implement:**

```dart
Future<void> signOut() async {
  try {
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    final did = await _storage.read(key: _keyDid);

    // Revoke tokens on the authorization server
    if (_client != null && refreshToken != null) {
      try {
        await _client!.revoke(
          token: refreshToken,
          // May need DID or other params
        );
      } catch (e) {
        print('Token revocation failed (continuing with local logout): $e');
        // Continue even if revocation fails (network issues, etc.)
      }
    }

    // Clear local session
    await _clearSession();

  } catch (e) {
    print('Sign out failed: $e');
    // Always clear local session even if errors occur
    await _clearSession();
  }
}
```

**Key Implementation Notes:**
- Always attempt to revoke tokens on server
- Don't fail if revocation fails (might be offline)
- Always clear local storage

---

### Phase 2: API Integration (Medium Priority)

#### 2.1 Create atProto API Client

**File to Create:** `lib/services/atproto_api_service.dart`

The `atproto_oauth` package provides an `OAuthSession` that can be used with the `@atproto/api` equivalent for Dart. You'll need to create an API service that uses the authenticated session.

**What to Implement:**

```dart
import 'package:atproto/atproto.dart'; // If available
import 'oauth_service.dart';

class AtProtoApiService {
  final OAuthService _oauthService;

  AtProtoApiService(this._oauthService);

  /// Create an authenticated API client
  Future<ATProto?> getClient() async {
    final session = await _oauthService.restoreSession();

    if (session == null) {
      return null;
    }

    // Create API client with session
    // The exact API depends on available Dart atProto packages
    return ATProto(
      service: session.pdsUrl, // User's PDS URL
      session: Session(
        accessJwt: session.accessToken,
        refreshJwt: session.refreshToken,
        did: session.did,
        handle: session.handle,
      ),
    );
  }

  /// Fetch user profile
  Future<Profile> getProfile(String actor) async {
    final client = await getClient();
    if (client == null) throw Exception('Not authenticated');

    return await client.getProfile(actor: actor);
  }

  /// Fetch feed
  Future<Feed> getFeed({int limit = 50}) async {
    final client = await getClient();
    if (client == null) throw Exception('Not authenticated');

    return await client.getTimeline(limit: limit);
  }

  /// Create post
  Future<void> createPost(String text) async {
    final client = await getClient();
    if (client == null) throw Exception('Not authenticated');

    await client.createRecord(
      collection: 'app.bsky.feed.post',
      record: {
        'text': text,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }
}
```

**Research Needed:**
- Check if there's a Dart equivalent of `@atproto/api`
- The `atproto_oauth` package documentation should specify how to use sessions with API calls
- May need to create HTTP client wrapper for atProto APIs

#### 2.2 Handle Token Expiration in API Calls

Implement automatic token refresh when API calls fail due to expired tokens:

```dart
Future<T> _withAutoRefresh<T>(Future<T> Function() apiCall) async {
  try {
    return await apiCall();
  } on UnauthorizedError {
    // Token expired, try to refresh
    final session = await _oauthService.restoreSession();
    if (session == null) {
      throw Exception('Session expired, please log in again');
    }

    // Retry API call with new token
    return await apiCall();
  }
}
```

---

### Phase 3: Enhanced Error Handling (Medium Priority)

#### 3.1 Specific Error Types

**File to Create:** `lib/models/auth_errors.dart`

```dart
class AuthError implements Exception {
  final String message;
  final AuthErrorType type;

  AuthError(this.message, this.type);
}

enum AuthErrorType {
  networkError,
  invalidHandle,
  serverError,
  userCancelled,
  tokenExpired,
  unknown,
}
```

#### 3.2 User-Friendly Error Messages

Update `AuthProvider` to provide actionable error messages:

```dart
String _getErrorMessage(Exception e) {
  if (e is AuthError) {
    switch (e.type) {
      case AuthErrorType.networkError:
        return 'Unable to connect. Check your internet connection.';
      case AuthErrorType.invalidHandle:
        return 'Invalid handle. Use format: user.domain.com';
      case AuthErrorType.userCancelled:
        return 'Sign in was cancelled.';
      case AuthErrorType.tokenExpired:
        return 'Your session expired. Please sign in again.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }
  return e.toString();
}
```

---

### Phase 4: Session Lifecycle (Low Priority)

#### 4.1 Automatic Token Refresh

Implement background token refresh before expiration:

```dart
class AuthProvider with ChangeNotifier {
  Timer? _refreshTimer;

  void _scheduleTokenRefresh(DateTime expiresAt) {
    _refreshTimer?.cancel();

    // Refresh 5 minutes before expiration
    final refreshTime = expiresAt.subtract(Duration(minutes: 5));
    final delay = refreshTime.difference(DateTime.now());

    if (delay.isNegative) {
      _refreshTokenNow();
      return;
    }

    _refreshTimer = Timer(delay, _refreshTokenNow);
  }

  Future<void> _refreshTokenNow() async {
    try {
      await _oauthService.restoreSession(); // Triggers refresh
    } catch (e) {
      print('Auto-refresh failed: $e');
    }
  }
}
```

#### 4.2 Handle App Lifecycle

React to app going to background/foreground:

```dart
class AuthProvider with ChangeNotifier, WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground, validate session
      _validateSession();
    }
  }

  Future<void> _validateSession() async {
    if (!_isAuthenticated) return;

    // Check if session is still valid
    final session = await _oauthService.restoreSession();
    if (session == null) {
      // Session expired while app was in background
      _isAuthenticated = false;
      _session = null;
      notifyListeners();
    }
  }
}
```

---

## 📚 Resources & References

### atProto OAuth Specifications
- [atProto OAuth Spec](https://atproto.com/specs/oauth)
- [DPoP (Demonstrating Proof-of-Possession)](https://datatracker.ietf.org/doc/html/rfc9449)
- [PKCE (Proof Key for Code Exchange)](https://datatracker.ietf.org/doc/html/rfc7636)

### Package Documentation
- [`atproto_oauth` on pub.dev](https://pub.dev/packages/atproto_oauth)
- [`flutter_web_auth_2` on pub.dev](https://pub.dev/packages/flutter_web_auth_2)
- [`flutter_secure_storage` on pub.dev](https://pub.dev/packages/flutter_secure_storage)

### Cloudflare Worker
Your OAuth server is hosted at:
- Base URL: `https://lingering-darkness-50a6.brettmay0212.workers.dev`
- Client Metadata: `https://lingering-darkness-50a6.brettmay0212.workers.dev/client-metadata.json`
- Callback: `https://lingering-darkness-50a6.brettmay0212.workers.dev/oauth/callback`

---

## 🧪 Testing Strategy

### Unit Tests

**File to Create:** `test/services/oauth_service_test.dart`

```dart
void main() {
  group('OAuthService', () {
    late OAuthService service;

    setUp(() {
      service = OAuthService();
    });

    test('initialize fetches client metadata', () async {
      await service.initialize();
      expect(service._client, isNotNull);
    });

    test('signIn returns session on success', () async {
      final session = await service.signIn('test.bsky.social');
      expect(session.did, isNotEmpty);
      expect(session.accessToken, isNotEmpty);
    });

    // Add more tests...
  });
}
```

### Integration Tests

Test the full OAuth flow on a real device:

1. Open app (should show landing page)
2. Tap "Sign in"
3. Enter valid handle
4. Browser opens showing PDS authorization page
5. User authorizes
6. App receives callback and completes sign in
7. User is redirected to feed
8. Close app and reopen (should restore session)

---

## 🔐 Security Considerations

### Current Implementation ✅
- ✅ Tokens stored in encrypted `flutter_secure_storage`
- ✅ DPoP prevents token theft
- ✅ PKCE prevents authorization code interception
- ✅ HTTPS deep links preferred over custom schemes
- ✅ Storage keys properly scoped to atProto (not app-specific)

### To Verify ⚠️
- ⚠️ Client metadata hosted securely on Cloudflare Worker
- ⚠️ Redirect URIs match exactly (no wildcards)
- ⚠️ Token refresh implemented securely
- ⚠️ Session validation on app resume

---

## 📝 Implementation Checklist

### Phase 1: Core OAuth Flow
- [ ] Implement `signIn()` with atproto_oauth authorize flow
- [ ] Implement callback handling and token exchange
- [ ] Implement `restoreSession()` with validation
- [ ] Implement token refresh logic
- [ ] Implement `signOut()` with server-side revocation
- [ ] Test full sign in flow on device
- [ ] Test session restoration
- [ ] Test sign out

### Phase 2: API Integration
- [ ] Research Dart atProto API packages
- [ ] Create `AtProtoApiService`
- [ ] Implement profile fetching
- [ ] Implement feed fetching
- [ ] Implement post creation
- [ ] Add automatic token refresh to API calls

### Phase 3: Error Handling
- [ ] Create typed error classes
- [ ] Add user-friendly error messages
- [ ] Handle network errors gracefully
- [ ] Handle authorization cancellation
- [ ] Add error recovery flows

### Phase 4: Session Lifecycle
- [ ] Implement automatic token refresh
- [ ] Add app lifecycle observers
- [ ] Validate session on app resume
- [ ] Handle session expiration gracefully

### Phase 5: Testing & Polish
- [ ] Write unit tests for OAuth service
- [ ] Write integration tests for full flow
- [ ] Test on slow/unstable networks
- [ ] Test session restoration edge cases
- [ ] Add loading indicators for all async operations
- [ ] Add success/error feedback to user

---

## 🎯 Next Immediate Steps

1. **Study the `atproto_oauth` Package**
   - Read the package documentation thoroughly
   - Look for example code or test files
   - Understand the `authorize()` and `callback()` methods

2. **Implement Basic Sign In**
   - Start with `signIn()` method
   - Get the authorization URL working
   - Test browser opening and callback

3. **Test on Real Device**
   - Use your actual Bluesky handle for testing
   - Verify deep links work correctly
   - Check token storage

4. **Implement Session Restoration**
   - Add `restoreSession()` logic
   - Test app restart with active session
   - Verify token refresh works

---

## 💡 Tips & Best Practices

1. **Always validate sessions** before making API calls
2. **Log OAuth flows** in debug mode for troubleshooting
3. **Handle offline gracefully** - cache data when possible
4. **Never log tokens** - even in debug builds
5. **Test token expiration** by manually invalidating tokens
6. **Use atomic operations** for session updates to prevent race conditions
7. **Clear sessions on security errors** to prevent auth loops

---

## 🐛 Common Issues & Solutions

### Issue: "Authorization cancelled"
**Solution:** User may have closed browser - handle gracefully, don't show error

### Issue: Deep link not opening app
**Solution:** Check AndroidManifest.xml intent filters, verify URL scheme matches exactly

### Issue: "Client not initialized"
**Solution:** Ensure `initialize()` is called before any OAuth operations

### Issue: Token refresh failing
**Solution:** Check if refresh token is still valid, may need full re-authentication

---

## 📞 Need Help?

- **atProto Discord**: [atproto.com/community](https://atproto.com/community)
- **Bluesky API Docs**: [docs.bsky.app](https://docs.bsky.app)
- **Package Issues**: [atproto_oauth GitHub](https://github.com/myConsciousness/atproto.dart)

---

**Last Updated:** 2025-10-27
**Flutter Version:** 3.7.2
**Dart Version:** 3.7.2
**Package Version:** atproto_oauth ^0.1.0
