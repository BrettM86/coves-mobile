/// Session management layer for atproto OAuth.
///
/// This module provides session storage, retrieval, and lifecycle management
/// for OAuth sessions. It includes:
///
/// - [StateStore] - Stores ephemeral OAuth state during authorization
/// - [SessionStore] - Stores persistent session data
/// - [Session] - Represents an authenticated session with tokens
/// - [TokenSet] - Contains OAuth tokens and metadata
/// - [OAuthSession] - High-level API for authenticated requests
/// - [SessionGetter] - Manages session caching and token refresh
///
/// Example:
/// ```dart
/// // Create a session store implementation
/// final sessionStore = MySessionStore();
///
/// // Create a session getter
/// final sessionGetter = SessionGetter(
///   sessionStore: sessionStore,
///   serverFactory: serverFactory,
///   runtime: runtime,
/// );
///
/// // Get a session (automatically refreshes if needed)
/// final session = await sessionGetter.getSession('did:plc:abc123');
///
/// // Create an OAuthSession for making requests
/// final oauthSession = OAuthSession(
///   server: server,
///   sub: 'did:plc:abc123',
///   sessionGetter: sessionGetter,
/// );
///
/// // Make authenticated requests
/// final response = await oauthSession.fetchHandler('/api/posts');
/// ```
library;

export 'state_store.dart';
export 'oauth_session.dart';
export 'session_getter.dart';
