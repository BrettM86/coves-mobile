/// Internal state data stored during OAuth authorization flow.
///
/// This contains ephemeral data needed to complete the OAuth flow,
/// such as PKCE code verifiers, state parameters, and nonces.
class InternalStateData {
  /// The OAuth issuer URL
  final String iss;

  /// The DPoP key used for this authorization
  final Map<String, dynamic> dpopKey;

  /// Client authentication method (serialized as Map or String)
  ///
  /// Can be:
  /// - A Map containing {method: 'private_key_jwt', kid: '...'} for private key JWT
  /// - A Map containing {method: 'none'} for no authentication
  /// - A String 'legacy' for backwards compatibility
  /// - null (defaults to 'legacy' when loading)
  final dynamic authMethod;

  /// PKCE code verifier for authorization code flow
  final String? verifier;

  /// The redirect URI used during authorization
  /// MUST match exactly during token exchange
  final String? redirectUri;

  /// Application state to preserve across the OAuth flow
  final String? appState;

  const InternalStateData({
    required this.iss,
    required this.dpopKey,
    this.authMethod,
    this.verifier,
    this.redirectUri,
    this.appState,
  });

  /// Creates an instance from a JSON map.
  factory InternalStateData.fromJson(Map<String, dynamic> json) {
    return InternalStateData(
      iss: json['iss'] as String,
      dpopKey: json['dpopKey'] as Map<String, dynamic>,
      authMethod: json['authMethod'], // Can be Map or String
      verifier: json['verifier'] as String?,
      redirectUri: json['redirectUri'] as String?,
      appState: json['appState'] as String?,
    );
  }

  /// Converts this instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'iss': iss, 'dpopKey': dpopKey};

    if (authMethod != null) json['authMethod'] = authMethod;
    if (verifier != null) json['verifier'] = verifier;
    if (redirectUri != null) json['redirectUri'] = redirectUri;
    if (appState != null) json['appState'] = appState;

    return json;
  }
}

/// Abstract storage interface for OAuth state data.
///
/// Implementations should store state data temporarily during the OAuth flow.
/// This data is typically short-lived and can be cleared after successful
/// authorization or timeout.
///
/// Example implementation using in-memory storage:
/// ```dart
/// class MemoryStateStore implements StateStore {
///   final Map<String, InternalStateData> _store = {};
///
///   @override
///   Future<InternalStateData?> get(String key) async => _store[key];
///
///   @override
///   Future<void> set(String key, InternalStateData data) async {
///     _store[key] = data;
///   }
///
///   @override
///   Future<void> del(String key) async {
///     _store.remove(key);
///   }
/// }
/// ```
abstract class StateStore {
  /// Retrieves state data for the given key.
  ///
  /// Returns `null` if no data exists for the key.
  Future<InternalStateData?> get(String key);

  /// Stores state data for the given key.
  ///
  /// Overwrites any existing data for the key.
  Future<void> set(String key, InternalStateData data);

  /// Deletes state data for the given key.
  ///
  /// Does nothing if no data exists for the key.
  Future<void> del(String key);

  /// Optionally clears all state data.
  ///
  /// Implementations may choose not to implement this method.
  Future<void> clear() async {
    // Default implementation does nothing
  }
}
