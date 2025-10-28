/// atproto OAuth client for Flutter.
///
/// This library provides OAuth authentication capabilities for AT Protocol
/// (atproto) applications on Flutter/Dart platforms.
///
/// This is a 1:1 port of the TypeScript @atproto/oauth-client package to Dart.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
///
/// // 1. Initialize client
/// final client = FlutterOAuthClient(
///   clientMetadata: ClientMetadata(
///     clientId: 'https://example.com/client-metadata.json',
///     redirectUris: ['myapp://oauth/callback'],
///     scope: 'atproto transition:generic',
///   ),
/// );
///
/// // 2. Sign in with handle
/// final session = await client.signIn('alice.bsky.social');
/// print('Signed in as: ${session.sub}');
///
/// // 3. Use authenticated session
/// // (Integrate with your atproto API client)
///
/// // 4. Later: restore session
/// final restored = await client.restore(session.sub);
///
/// // 5. Sign out
/// await client.revoke(session.sub);
/// ```
///
/// ## Features
///
/// - Full OAuth 2.0 + OIDC support with PKCE
/// - DPoP (Demonstrating Proof of Possession) for token security
/// - Automatic token refresh
/// - Secure session storage (flutter_secure_storage)
/// - Handle and DID resolution
/// - PAR (Pushed Authorization Request) support
/// - Works with any atProto PDS or authorization server
///
/// ## Security
///
/// - Tokens stored in device secure storage (Keychain/EncryptedSharedPreferences)
/// - DPoP binds tokens to cryptographic keys
/// - PKCE prevents authorization code interception
/// - Automatic session cleanup on errors
///
library;

// ============================================================================
// Main API - Start here!
// ============================================================================

/// High-level Flutter OAuth client (recommended for most apps)
export 'src/platform/flutter_oauth_client.dart';

/// Router integration helpers (for go_router, auto_route, etc.)
export 'src/platform/flutter_oauth_router_helper.dart';

// ============================================================================
// Core OAuth Client
// ============================================================================

/// Core OAuth client and types (for advanced use cases)
export 'src/client/oauth_client.dart';

// ============================================================================
// Sessions
// ============================================================================

/// OAuth session types
export 'src/session/oauth_session.dart';

// ============================================================================
// Types
// ============================================================================

/// Core types and options
export 'src/types.dart';

// ============================================================================
// Platform Implementations (for custom configurations)
// ============================================================================

/// Storage implementations (for customization)
export 'src/platform/flutter_stores.dart';

/// Runtime implementation (cryptographic operations)
export 'src/platform/flutter_runtime.dart';

/// Key implementation (EC keys with pointycastle)
export 'src/platform/flutter_key.dart';

// ============================================================================
// Errors
// ============================================================================

/// All OAuth error types
export 'src/errors/errors.dart';
