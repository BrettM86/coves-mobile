import 'package:dio/dio.dart';

import '../runtime/runtime.dart';
import '../runtime/runtime_implementation.dart';
import '../types.dart';
import 'authorization_server_metadata_resolver.dart';
import 'client_auth.dart';
import 'oauth_resolver.dart';
import 'oauth_server_agent.dart';

/// Factory for creating OAuth server agents.
///
/// This factory:
/// 1. Stores common configuration (client metadata, runtime, resolver, etc.)
/// 2. Creates OAuthServerAgent instances for specific issuers
/// 3. Handles both new sessions and restored sessions (with legacy support)
///
/// The factory pattern allows reusing configuration across multiple agents
/// and simplifies session restoration.
class OAuthServerFactory {
  final ClientMetadata clientMetadata;
  final Runtime runtime;
  final OAuthResolver resolver;
  final Dio dio;
  final Keyset? keyset;
  final DpopNonceCache dpopNonceCache;

  /// Creates a server factory with the given configuration.
  ///
  /// [clientMetadata] is the validated client metadata.
  /// [runtime] provides cryptographic operations.
  /// [resolver] handles OAuth metadata discovery.
  /// [dio] is the HTTP client.
  /// [keyset] is optional (only needed for confidential clients).
  /// [dpopNonceCache] stores DPoP nonces per origin.
  OAuthServerFactory({
    required this.clientMetadata,
    required this.runtime,
    required this.resolver,
    required this.dio,
    this.keyset,
    required this.dpopNonceCache,
  });

  /// Creates an OAuth server agent from an issuer URL.
  ///
  /// This method:
  /// 1. Fetches authorization server metadata for the issuer
  /// 2. Uses the provided authMethod or negotiates one (for legacy sessions)
  /// 3. Creates an OAuthServerAgent with the metadata
  ///
  /// [issuer] is the authorization server URL.
  /// [authMethod] is the authentication method to use.
  ///   - For new sessions, pass the result of negotiateClientAuthMethod
  ///   - For legacy sessions (before authMethod was stored), pass 'legacy'
  ///     and the method will be negotiated automatically
  /// [dpopKey] is the DPoP signing key.
  /// [options] are optional cache/cancellation options.
  ///
  /// The 'legacy' authMethod is for backwards compatibility with sessions
  /// created before we started storing the authMethod. Support for this
  /// may be removed in the future.
  ///
  /// Throws [AuthMethodUnsatisfiableError] if auth method cannot be satisfied.
  Future<OAuthServerAgent> fromIssuer(
    String issuer,
    dynamic authMethod, // ClientAuthMethod or 'legacy'
    Key dpopKey, [
    GetCachedOptions? options,
  ]) async {
    final serverMetadata =
        await resolver.getAuthorizationServerMetadata(issuer, options);

    ClientAuthMethod finalAuthMethod;
    if (authMethod == 'legacy') {
      // Backwards compatibility: compute auth method from metadata
      finalAuthMethod = negotiateClientAuthMethod(
        serverMetadata,
        clientMetadata,
        keyset,
      );
    } else {
      finalAuthMethod = authMethod as ClientAuthMethod;
    }

    return fromMetadata(serverMetadata, finalAuthMethod, dpopKey);
  }

  /// Creates an OAuth server agent from authorization server metadata.
  ///
  /// This is useful when you already have the metadata cached.
  ///
  /// [serverMetadata] is the authorization server metadata.
  /// [authMethod] is the authentication method to use.
  /// [dpopKey] is the DPoP signing key.
  ///
  /// Throws [AuthMethodUnsatisfiableError] if auth method cannot be satisfied.
  OAuthServerAgent fromMetadata(
    Map<String, dynamic> serverMetadata,
    ClientAuthMethod authMethod,
    Key dpopKey,
  ) {
    return OAuthServerAgent(
      authMethod: authMethod,
      dpopKey: dpopKey,
      serverMetadata: serverMetadata,
      clientMetadata: clientMetadata,
      dpopNonces: dpopNonceCache,
      oauthResolver: resolver,
      runtime: runtime,
      keyset: keyset,
      dio: dio,
    );
  }
}
