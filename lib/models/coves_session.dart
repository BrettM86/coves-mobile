import 'dart:convert';

/// Coves Session Model
///
/// Simplified session model for the backend OAuth flow.
/// The backend handles all the complexity (DPoP, PKCE, token refresh)
/// and gives us a sealed token that's opaque to the client.
///
/// This replaces the complex TokenSet + DPoP keys from atproto_oauth_flutter.
class CovesSession {
  const CovesSession({
    required this.token,
    required this.did,
    required this.sessionId,
    this.handle,
  });

  /// Create a session from OAuth callback parameters
  ///
  /// Expected URL format (RFC 8252 private-use URI scheme):
  /// `social.coves:/callback?token=...&did=...&session_id=...&handle=...`
  factory CovesSession.fromCallbackUri(Uri uri) {
    final token = uri.queryParameters['token'];
    final did = uri.queryParameters['did'];
    final sessionId = uri.queryParameters['session_id'];
    final handle = uri.queryParameters['handle'];

    if (token == null || token.isEmpty) {
      throw const FormatException('Missing required parameter: token');
    }
    if (did == null || did.isEmpty) {
      throw const FormatException('Missing required parameter: did');
    }
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('Missing required parameter: session_id');
    }

    return CovesSession(
      token: Uri.decodeComponent(token),
      did: did,
      sessionId: sessionId,
      handle: handle,
    );
  }

  /// Create a session from JSON (for storage restoration)
  factory CovesSession.fromJson(Map<String, dynamic> json) {
    return CovesSession(
      token: json['token'] as String,
      did: json['did'] as String,
      sessionId: json['session_id'] as String,
      handle: json['handle'] as String?,
    );
  }

  /// Create a session from a JSON string
  factory CovesSession.fromJsonString(String jsonString) {
    return CovesSession.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// The sealed session token (AES-256-GCM encrypted by backend)
  ///
  /// This token is opaque to the client - we just store and send it.
  /// Use in Authorization header: `Authorization: Bearer $token`
  final String token;

  /// User's DID (decentralized identifier)
  ///
  /// Example: did:plc:abc123
  final String did;

  /// Session ID for refresh operations
  ///
  /// The backend uses this to identify the session for token refresh.
  final String sessionId;

  /// User's handle (optional)
  ///
  /// Example: alice.bsky.social
  /// May be null if the backend didn't include it in the callback.
  final String? handle;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'did': did,
      'session_id': sessionId,
      if (handle != null) 'handle': handle,
    };
  }

  /// Convert to JSON string for storage
  String toJsonString() => jsonEncode(toJson());

  /// Create a copy with updated token (for refresh)
  CovesSession copyWithToken(String newToken) {
    return CovesSession(
      token: newToken,
      did: did,
      sessionId: sessionId,
      handle: handle,
    );
  }

  @override
  String toString() {
    return 'CovesSession(did: $did, handle: $handle, sessionId: $sessionId)';
  }
}
