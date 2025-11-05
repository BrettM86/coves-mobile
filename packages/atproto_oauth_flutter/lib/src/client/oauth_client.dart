import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../dpop/fetch_dpop.dart' show InMemoryStore;
import '../errors/auth_method_unsatisfiable_error.dart';
import '../errors/oauth_callback_error.dart';
import '../errors/token_revoked_error.dart';
import '../identity/constants.dart';
import '../identity/did_helpers.dart' show assertAtprotoDid;
import '../identity/did_resolver.dart' show DidCache;
import '../identity/handle_resolver.dart' show HandleCache;
import '../identity/identity_resolver.dart';
import '../oauth/authorization_server_metadata_resolver.dart' as auth_resolver;
import '../oauth/client_auth.dart';
import '../oauth/oauth_resolver.dart';
import '../oauth/oauth_server_agent.dart';
import '../oauth/oauth_server_factory.dart';
import '../oauth/protected_resource_metadata_resolver.dart';
import '../oauth/validate_client_metadata.dart';
import '../platform/flutter_key.dart';
import '../runtime/runtime.dart' as runtime_lib;
import '../runtime/runtime_implementation.dart';
import '../session/oauth_session.dart'
    show OAuthSession, Session, SessionGetterInterface;
import '../session/session_getter.dart';
import '../session/state_store.dart';
import '../types.dart';
import '../util.dart';

// Re-export types needed for OAuthClientOptions
export '../identity/did_resolver.dart' show DidCache, DidResolver;
export '../identity/handle_resolver.dart' show HandleCache, HandleResolver;
export '../identity/identity_resolver.dart' show IdentityResolver;
export '../oauth/authorization_server_metadata_resolver.dart'
    show AuthorizationServerMetadataCache;
export '../oauth/oauth_server_agent.dart' show DpopNonceCache;
export '../oauth/protected_resource_metadata_resolver.dart'
    show ProtectedResourceMetadataCache;
export '../runtime/runtime_implementation.dart' show RuntimeImplementation, Key;
export '../oauth/client_auth.dart' show Keyset;
export '../session/session_getter.dart'
    show SessionStore, SessionUpdatedEvent, SessionDeletedEvent;
export '../session/state_store.dart' show StateStore, InternalStateData;
export '../types.dart' show ClientMetadata, AuthorizeOptions, CallbackOptions;

/// OAuth response mode.
enum OAuthResponseMode {
  /// Parameters in query string (default, most compatible)
  query('query'),

  /// Parameters in URL fragment (for single-page apps)
  fragment('fragment');

  final String value;
  const OAuthResponseMode(this.value);

  @override
  String toString() => value;
}

/// Options for constructing an OAuthClient.
///
/// This includes all configuration, storage, and service dependencies
/// needed to implement the complete OAuth flow.
class OAuthClientOptions {
  // Config
  /// Response mode for OAuth (query or fragment)
  final OAuthResponseMode responseMode;

  /// Client metadata (validated before use)
  final Map<String, dynamic> clientMetadata;

  /// Optional keyset for confidential clients (private_key_jwt)
  final Keyset? keyset;

  /// Whether to allow HTTP connections (for development only)
  ///
  /// This affects:
  /// - OAuth authorization/resource servers
  /// - did:web document fetching
  ///
  /// Note: PLC directory connections are controlled separately.
  final bool allowHttp;

  // Stores
  /// Storage for OAuth state during authorization flow
  final StateStore stateStore;

  /// Storage for session tokens
  final SessionStore sessionStore;

  /// Optional cache for authorization server metadata
  final auth_resolver.AuthorizationServerMetadataCache?
  authorizationServerMetadataCache;

  /// Optional cache for protected resource metadata
  final ProtectedResourceMetadataCache? protectedResourceMetadataCache;

  /// Optional cache for DPoP nonces
  final DpopNonceCache? dpopNonceCache;

  /// Optional cache for DID documents
  final DidCache? didCache;

  /// Optional cache for handle → DID resolutions
  final HandleCache? handleCache;

  // Services
  /// Platform-specific cryptographic operations
  final RuntimeImplementation runtimeImplementation;

  /// Optional HTTP client (Dio instance)
  final Dio? dio;

  /// Optional custom identity resolver
  final IdentityResolver? identityResolver;

  /// PLC directory URL (for DID resolution)
  final String? plcDirectoryUrl;

  /// Handle resolver URL (for handle → DID resolution)
  final String? handleResolverUrl;

  const OAuthClientOptions({
    required this.responseMode,
    required this.clientMetadata,
    this.keyset,
    this.allowHttp = false,
    required this.stateStore,
    required this.sessionStore,
    this.authorizationServerMetadataCache,
    this.protectedResourceMetadataCache,
    this.dpopNonceCache,
    this.didCache,
    this.handleCache,
    required this.runtimeImplementation,
    this.dio,
    this.identityResolver,
    this.plcDirectoryUrl,
    this.handleResolverUrl,
  });
}

/// Result of a successful OAuth callback.
class CallbackResult {
  /// The authenticated session
  final OAuthSession session;

  /// The application state from the original authorize call
  final String? state;

  const CallbackResult({required this.session, this.state});
}

/// Options for fetching client metadata from a discoverable client ID.
class OAuthClientFetchMetadataOptions {
  /// The discoverable client ID (HTTPS URL)
  final String clientId;

  /// Optional HTTP client
  final Dio? dio;

  /// Optional cancellation token
  final CancelToken? cancelToken;

  const OAuthClientFetchMetadataOptions({
    required this.clientId,
    this.dio,
    this.cancelToken,
  });
}

/// Main OAuth client for atProto OAuth flows.
///
/// This is the primary class that developers interact with. It orchestrates:
/// - Authorization flow (authorize → callback)
/// - Session restoration (restore)
/// - Token revocation (revoke)
/// - Session lifecycle events
///
/// Usage:
/// ```dart
/// final client = OAuthClient(
///   clientMetadata: {
///     'client_id': 'https://example.com/client-metadata.json',
///     'redirect_uris': ['myapp://oauth/callback'],
///     'scope': 'atproto',
///   },
///   responseMode: OAuthResponseMode.query,
///   stateStore: MyStateStore(),
///   sessionStore: MySessionStore(),
///   runtimeImplementation: MyRuntimeImplementation(),
/// );
///
/// // Start authorization
/// final authUrl = await client.authorize('alice.bsky.social');
///
/// // Handle callback
/// final result = await client.callback(callbackParams);
/// print('Signed in as: ${result.session.sub}');
///
/// // Restore session later
/// final session = await client.restore('did:plc:abc123');
///
/// // Revoke session
/// await client.revoke('did:plc:abc123');
/// ```
class OAuthClient extends CustomEventTarget<Map<String, dynamic>> {
  // Config
  /// Validated client metadata
  final ClientMetadata clientMetadata;

  /// OAuth response mode (query or fragment)
  final OAuthResponseMode responseMode;

  /// Optional keyset for confidential clients
  final Keyset? keyset;

  // Services
  /// Runtime for cryptographic operations
  final runtime_lib.Runtime runtime;

  /// HTTP client
  final Dio dio;

  /// OAuth resolver for identity → metadata
  final OAuthResolver oauthResolver;

  /// Factory for creating OAuth server agents
  final OAuthServerFactory serverFactory;

  // Stores
  /// Session management with automatic refresh
  final SessionGetter _sessionGetter;

  /// OAuth state storage
  final StateStore _stateStore;

  // Event streams
  final StreamController<SessionUpdatedEvent> _updatedController =
      StreamController<SessionUpdatedEvent>.broadcast();
  final StreamController<SessionDeletedEvent> _deletedController =
      StreamController<SessionDeletedEvent>.broadcast();

  /// Stream of session update events
  Stream<SessionUpdatedEvent> get onUpdated => _updatedController.stream;

  /// Stream of session deletion events
  Stream<SessionDeletedEvent> get onDeleted => _deletedController.stream;

  /// Constructs an OAuthClient with the given options.
  ///
  /// Throws [FormatException] if client metadata is invalid.
  /// Throws [TypeError] if keyset configuration is incorrect.
  OAuthClient(OAuthClientOptions options)
    : keyset = options.keyset,
      responseMode = options.responseMode,
      runtime = runtime_lib.Runtime(options.runtimeImplementation),
      dio = options.dio ?? Dio(),
      _stateStore = options.stateStore,
      clientMetadata = validateClientMetadata(
        options.clientMetadata,
        options.keyset,
      ),
      oauthResolver = _createOAuthResolver(options),
      serverFactory = _createServerFactory(options),
      _sessionGetter = _createSessionGetter(options) {
    // Proxy session events from SessionGetter
    _sessionGetter.onUpdated.listen((event) {
      _updatedController.add(event);
      dispatchCustomEvent('updated', event);
    });

    _sessionGetter.onDeleted.listen((event) {
      _deletedController.add(event);
      dispatchCustomEvent('deleted', event);
    });
  }

  /// Creates the OAuth resolver.
  static OAuthResolver _createOAuthResolver(OAuthClientOptions options) {
    final dio = options.dio ?? Dio();

    return OAuthResolver(
      identityResolver:
          options.identityResolver ??
          AtprotoIdentityResolver.withDefaults(
            handleResolverUrl:
                options.handleResolverUrl ?? 'https://bsky.social',
            plcDirectoryUrl: options.plcDirectoryUrl,
            dio: dio,
            didCache: options.didCache,
            handleCache: options.handleCache,
          ),
      protectedResourceMetadataResolver: OAuthProtectedResourceMetadataResolver(
        options.protectedResourceMetadataCache ??
            InMemoryStore<String, Map<String, dynamic>>(),
        dio: dio,
        config: OAuthProtectedResourceMetadataResolverConfig(
          allowHttpResource: options.allowHttp,
        ),
      ),
      authorizationServerMetadataResolver:
          auth_resolver.OAuthAuthorizationServerMetadataResolver(
            options.authorizationServerMetadataCache ??
                InMemoryStore<String, Map<String, dynamic>>(),
            dio: dio,
            config:
                auth_resolver.OAuthAuthorizationServerMetadataResolverConfig(
                  allowHttpIssuer: options.allowHttp,
                ),
          ),
    );
  }

  /// Creates the OAuth server factory.
  static OAuthServerFactory _createServerFactory(OAuthClientOptions options) {
    return OAuthServerFactory(
      clientMetadata: validateClientMetadata(
        options.clientMetadata,
        options.keyset,
      ),
      runtime: runtime_lib.Runtime(options.runtimeImplementation),
      resolver: _createOAuthResolver(options),
      dio: options.dio ?? Dio(),
      keyset: options.keyset,
      dpopNonceCache: options.dpopNonceCache ?? InMemoryStore<String, String>(),
    );
  }

  /// Creates the session getter.
  static SessionGetter _createSessionGetter(OAuthClientOptions options) {
    return SessionGetter(
      sessionStore: options.sessionStore,
      serverFactory: _createServerFactory(options),
      runtime: runtime_lib.Runtime(options.runtimeImplementation),
    );
  }

  /// Fetches client metadata from a discoverable client ID URL.
  ///
  /// This is a static helper method for fetching metadata before
  /// constructing the OAuthClient.
  ///
  /// See: https://datatracker.ietf.org/doc/draft-ietf-oauth-client-id-metadata-document/
  static Future<Map<String, dynamic>> fetchMetadata(
    OAuthClientFetchMetadataOptions options,
  ) async {
    final dio = options.dio ?? Dio();
    final clientId = options.clientId;

    try {
      final response = await dio.getUri<Map<String, dynamic>>(
        Uri.parse(clientId),
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status == 200,
          responseType: ResponseType.json,
        ),
        cancelToken: options.cancelToken,
      );

      // Validate content type
      final contentType = response.headers.value('content-type');
      final mime = contentType?.split(';')[0].trim();
      if (mime != 'application/json') {
        throw FormatException('Invalid client metadata content type: $mime');
      }

      final data = response.data;
      if (data == null) {
        throw FormatException('Empty client metadata response');
      }

      return data;
    } catch (e) {
      if (e is DioException) {
        throw Exception('Failed to fetch client metadata: ${e.message}');
      }
      rethrow;
    }
  }

  /// Exposes the identity resolver for convenience.
  IdentityResolver get identityResolver => oauthResolver.identityResolver;

  /// Returns the public JWKS for this client (for confidential clients).
  ///
  /// This is the JWKS that should be published at the client's jwks_uri
  /// or included in the client metadata.
  Map<String, dynamic> get jwks {
    if (keyset == null) {
      return {'keys': <Map<String, dynamic>>[]};
    }
    return keyset!.toJSON();
  }

  /// Initiates an OAuth authorization flow.
  ///
  /// This method:
  /// 1. Resolves the input (handle, DID, or URL) to OAuth metadata
  /// 2. Generates PKCE parameters
  /// 3. Generates DPoP key
  /// 4. Negotiates client authentication method
  /// 5. Stores internal state
  /// 6. Uses PAR (Pushed Authorization Request) if supported
  /// 7. Returns the authorization URL to open in a browser
  ///
  /// The [input] can be:
  /// - An atProto handle (e.g., "alice.bsky.social")
  /// - A DID (e.g., "did:plc:...")
  /// - A PDS URL (e.g., "https://pds.example.com")
  /// - An authorization server URL (e.g., "https://auth.example.com")
  ///
  /// The [options] can specify:
  /// - redirectUri: Override the default redirect URI
  /// - state: Application state to preserve
  /// - scope: Override the default scope
  /// - Other OIDC parameters (prompt, display, etc.)
  ///
  /// Throws [FormatException] if parameters are invalid.
  /// Throws [OAuthResolverError] if resolution fails.
  Future<Uri> authorize(
    String input, {
    AuthorizeOptions? options,
    CancelToken? cancelToken,
  }) async {
    final opts = options ?? const AuthorizeOptions();

    // Validate redirect URI
    final redirectUri = opts.redirectUri ?? clientMetadata.redirectUris.first;
    if (!clientMetadata.redirectUris.contains(redirectUri)) {
      throw FormatException('Invalid redirect_uri: $redirectUri');
    }

    // Resolve input to OAuth metadata
    final resolved = await oauthResolver.resolve(
      input,
      auth_resolver.GetCachedOptions(cancelToken: cancelToken),
    );

    final metadata = resolved.metadata;

    // Generate PKCE
    final pkce = await runtime.generatePKCE();

    // Generate DPoP key
    final dpopAlgs = metadata['dpop_signing_alg_values_supported'] as List?;
    final dpopKey = await runtime.generateKey(
      dpopAlgs?.cast<String>() ?? [fallbackAlg],
    );

    // Compute DPoP JWK thumbprint for authorization requests.
    // Required by RFC 9449 §7 to bind the subsequently issued code to this key.
    final bareJwk = dpopKey.bareJwk;
    if (bareJwk == null) {
      throw StateError('DPoP key must provide a public JWK representation');
    }
    final generatedDpopJkt = await runtime.calculateJwkThumbprint(bareJwk);

    // Negotiate client authentication method
    final authMethod = negotiateClientAuthMethod(
      metadata,
      clientMetadata,
      keyset,
    );

    // Generate state parameter
    final state = await runtime.generateNonce();

    // Store internal state for callback validation
    // IMPORTANT: Store the FULL private JWK, not just bareJwk (public key only)
    // We need the private key to restore the DPoP key during token exchange
    final dpopKeyJwk = (dpopKey as dynamic).privateJwk ?? dpopKey.bareJwk ?? {};

    if (kDebugMode) {
      print('🔑 Storing DPoP key for authorization flow');
    }

    await _stateStore.set(
      state,
      InternalStateData(
        iss: metadata['issuer'] as String,
        dpopKey: dpopKeyJwk,
        authMethod: authMethod.toJson(),
        verifier: pkce['verifier'] as String,
        redirectUri: redirectUri, // Store the exact redirectUri used in PAR
        appState: opts.state,
      ),
    );

    // Build authorization request parameters
    final parameters = <String, String>{
      'client_id': clientMetadata.clientId!,
      'redirect_uri': redirectUri,
      'code_challenge': pkce['challenge'] as String,
      'code_challenge_method': pkce['method'] as String,
      'state': state,
      'response_mode': responseMode.value,
      'response_type': 'code',
      'scope': opts.scope ?? clientMetadata.scope ?? 'atproto',
      'dpop_jkt': opts.dpopJkt ?? generatedDpopJkt,
    };

    // Add login hint if we have identity info
    if (resolved.identityInfo != null) {
      final handle = resolved.identityInfo!.handle;
      final did = resolved.identityInfo!.did;
      if (handle != handleInvalid) {
        parameters['login_hint'] = handle;
      } else {
        parameters['login_hint'] = did;
      }
    }

    // Add optional parameters from options
    if (opts.nonce != null) parameters['nonce'] = opts.nonce!;
    if (opts.display != null) parameters['display'] = opts.display!;
    if (opts.prompt != null) parameters['prompt'] = opts.prompt!;
    if (opts.maxAge != null) parameters['max_age'] = opts.maxAge.toString();
    if (opts.uiLocales != null) parameters['ui_locales'] = opts.uiLocales!;
    if (opts.idTokenHint != null) {
      parameters['id_token_hint'] = opts.idTokenHint!;
    }

    // Build authorization URL
    final authorizationUrl = Uri.parse(
      metadata['authorization_endpoint'] as String,
    );

    // Validate authorization endpoint protocol
    if (authorizationUrl.scheme != 'https' &&
        authorizationUrl.scheme != 'http') {
      throw FormatException(
        'Invalid authorization endpoint protocol: ${authorizationUrl.scheme}',
      );
    }

    // Use PAR (Pushed Authorization Request) if supported
    final parEndpoint =
        metadata['pushed_authorization_request_endpoint'] as String?;
    final requiresPar =
        metadata['require_pushed_authorization_requests'] as bool? ?? false;

    if (parEndpoint != null) {
      // Server supports PAR, use it
      final server = await serverFactory.fromMetadata(
        metadata,
        authMethod,
        dpopKey,
      );

      final parResponse = await server.request(
        'pushed_authorization_request',
        parameters,
      );

      final requestUri = parResponse['request_uri'] as String;

      // Return simplified URL with just request_uri
      return authorizationUrl.replace(
        queryParameters: {
          'client_id': clientMetadata.clientId!,
          'request_uri': requestUri,
        },
      );
    } else if (requiresPar) {
      throw Exception(
        'Server requires pushed authorization requests (PAR) but no PAR endpoint is available',
      );
    } else {
      // No PAR support, use direct authorization request
      final fullUrl = authorizationUrl.replace(queryParameters: parameters);

      // Check URL length (2048 byte limit for some browsers)
      final urlLength = fullUrl.toString().length;
      if (urlLength >= 2048) {
        throw Exception('Login URL too long ($urlLength bytes)');
      }

      return fullUrl;
    }
  }

  /// Handles the OAuth callback after user authorization.
  ///
  /// This method:
  /// 1. Validates the state parameter
  /// 2. Retrieves stored internal state
  /// 3. Checks for error responses
  /// 4. Validates issuer (if provided)
  /// 5. Exchanges authorization code for tokens
  /// 6. Creates and stores session
  /// 7. Cleans up state
  ///
  /// The [params] should be the query parameters from the callback URL.
  ///
  /// The [options] can specify:
  /// - redirectUri: Must match the one used in authorize()
  ///
  /// Returns a [CallbackResult] with the session and application state.
  ///
  /// Throws [OAuthCallbackError] if the callback contains errors or is invalid.
  Future<CallbackResult> callback(
    Map<String, String> params, {
    CallbackOptions? options,
    CancelToken? cancelToken,
  }) async {
    final opts = options ?? const CallbackOptions();

    // Check for JARM (not supported)
    final responseJwt = params['response'];
    if (responseJwt != null) {
      throw OAuthCallbackError(params, message: 'JARM not supported');
    }

    // Extract parameters
    final issuerParam = params['iss'];
    final stateParam = params['state'];
    final errorParam = params['error'];
    final codeParam = params['code'];

    // Validate state parameter
    if (stateParam == null) {
      throw OAuthCallbackError(params, message: 'Missing "state" parameter');
    }

    // Retrieve internal state
    final stateData = await _stateStore.get(stateParam);
    if (stateData == null) {
      throw OAuthCallbackError(
        params,
        message: 'Unknown authorization session "$stateParam"',
      );
    }

    // Prevent replay attacks - delete state immediately
    await _stateStore.del(stateParam);

    try {
      // Check for error response
      if (errorParam != null) {
        throw OAuthCallbackError(params, state: stateData.appState);
      }

      // Validate authorization code
      if (codeParam == null) {
        throw OAuthCallbackError(
          params,
          message: 'Missing "code" query param',
          state: stateData.appState,
        );
      }

      // Create OAuth server agent
      final authMethod =
          stateData.authMethod != null
              ? ClientAuthMethod.fromJson(
                stateData.authMethod as Map<String, dynamic>,
              )
              : const ClientAuthMethod.none(); // Legacy fallback

      // Restore dpopKey from stored private JWK
      // Restore DPoP key with error handling for corrupted JWK data
      final FlutterKey dpopKey;
      try {
        dpopKey = FlutterKey.fromJwk(
          stateData.dpopKey as Map<String, dynamic>,
        );
        if (kDebugMode) {
          print('🔓 DPoP key restored successfully for token exchange');
        }
      } catch (e) {
        throw Exception(
          'Failed to restore DPoP key from stored state: $e. '
          'The stored key may be corrupted. Please try authenticating again.',
        );
      }

      final server = await serverFactory.fromIssuer(
        stateData.iss,
        authMethod,
        dpopKey,
        auth_resolver.GetCachedOptions(cancelToken: cancelToken),
      );

      // Validate issuer if provided
      if (issuerParam != null) {
        if (server.issuer.isEmpty) {
          throw OAuthCallbackError(
            params,
            message: 'Issuer not found in metadata',
            state: stateData.appState,
          );
        }
        if (server.issuer != issuerParam) {
          throw OAuthCallbackError(
            params,
            message: 'Issuer mismatch',
            state: stateData.appState,
          );
        }
      } else if (server
              .serverMetadata['authorization_response_iss_parameter_supported'] ==
          true) {
        throw OAuthCallbackError(
          params,
          message: 'iss missing from the response',
          state: stateData.appState,
        );
      }

      // Exchange authorization code for tokens
      // CRITICAL: Use the EXACT same redirectUri that was used during authorization
      // The redirectUri in the token exchange MUST match the one in the PAR request
      final redirectUriForExchange =
          stateData.redirectUri ??
          opts.redirectUri ??
          clientMetadata.redirectUris.first;

      if (kDebugMode) {
        print('🔄 Exchanging authorization code for tokens:');
        print('   Code: ${codeParam.substring(0, 20)}...');
        print(
          '   Code verifier: ${stateData.verifier?.substring(0, 20) ?? "none"}...',
        );
        print('   Redirect URI: $redirectUriForExchange');
        print(
          '   Redirect URI source: ${stateData.redirectUri != null ? "stored" : "fallback"}',
        );
        print('   Issuer: ${server.issuer}');
      }

      final tokenSet = await server.exchangeCode(
        codeParam,
        codeVerifier: stateData.verifier,
        redirectUri: redirectUriForExchange,
      );

      try {
        if (kDebugMode) {
          print('💾 Storing session for: ${tokenSet.sub}');
        }

        // Store session
        await _sessionGetter.setStored(
          tokenSet.sub,
          Session(
            dpopKey: stateData.dpopKey,
            authMethod: authMethod.toJson(),
            tokenSet: tokenSet,
          ),
        );

        if (kDebugMode) {
          print('✅ Session stored successfully');
          print('🎯 Creating session wrapper...');
        }

        // Create session wrapper
        final session = _createSession(server, tokenSet.sub);

        if (kDebugMode) {
          print('✅ Session wrapper created');
          print('🎉 OAuth callback complete!');
        }

        return CallbackResult(session: session, state: stateData.appState);
      } catch (err, stackTrace) {
        // If session storage failed, revoke the tokens
        if (kDebugMode) {
          print('❌ Session storage/creation failed:');
          print('   Error: $err');
          print('   Stack trace: $stackTrace');
        }
        await server.revoke(tokenSet.refreshToken ?? tokenSet.accessToken);
        rethrow;
      }
    } catch (err, stackTrace) {
      // Ensure appState is available in error
      if (kDebugMode) {
        print('❌ Callback error (outer catch):');
        print('   Error type: ${err.runtimeType}');
        print('   Error: $err');
        print('   Stack trace: $stackTrace');
      }
      throw OAuthCallbackError.from(err, params, stateData.appState);
    }
  }

  /// Restores a stored session.
  ///
  /// This method:
  /// 1. Retrieves session from storage
  /// 2. Checks if tokens are expired
  /// 3. Automatically refreshes tokens if needed (based on [refresh])
  /// 4. Creates OAuthServerAgent
  /// 5. Returns live OAuthSession
  ///
  /// The [sub] is the user's DID.
  ///
  /// The [refresh] parameter controls token refresh:
  /// - `true`: Force refresh even if not expired
  /// - `false`: Use cached tokens even if expired
  /// - `'auto'`: Refresh only if expired (default)
  ///
  /// Throws [Exception] if session doesn't exist.
  /// Throws [TokenRefreshError] if refresh fails.
  /// Throws [AuthMethodUnsatisfiableError] if auth method can't be satisfied.
  Future<OAuthSession> restore(
    String sub, {
    dynamic refresh = 'auto',
    CancelToken? cancelToken,
  }) async {
    // Validate DID format
    assertAtprotoDid(sub);

    // Get session (automatically refreshes if needed based on refresh param)
    final session = await _sessionGetter.getSession(sub, refresh);

    try {
      // Determine auth method (with legacy fallback)
      final authMethod =
          session.authMethod != null
              ? ClientAuthMethod.fromJson(
                session.authMethod as Map<String, dynamic>,
              )
              : const ClientAuthMethod.none(); // Legacy

      // Restore dpopKey from stored private JWK with error handling
      // CRITICAL FIX: Use the stored key instead of generating a new one
      // This ensures DPoP proofs match the token binding
      final FlutterKey dpopKey;
      try {
        dpopKey = FlutterKey.fromJwk(
          session.dpopKey as Map<String, dynamic>,
        );
      } catch (e) {
        // If key is corrupted, delete the session and force re-authentication
        await _sessionGetter.delStored(
          sub,
          Exception('Corrupted DPoP key in stored session: $e'),
        );
        throw Exception(
          'Failed to restore DPoP key for session. The stored key is corrupted. '
          'Please authenticate again.',
        );
      }

      // Create server agent
      final server = await serverFactory.fromIssuer(
        session.tokenSet.iss,
        authMethod,
        dpopKey,
        auth_resolver.GetCachedOptions(
          noCache: refresh == true,
          allowStale: refresh == false,
          cancelToken: cancelToken,
        ),
      );

      return _createSession(server, sub);
    } catch (err) {
      // If auth method can't be satisfied, delete the session
      if (err is AuthMethodUnsatisfiableError) {
        await _sessionGetter.delStored(sub, err);
      }
      rethrow;
    }
  }

  /// Revokes a session.
  ///
  /// This method:
  /// 1. Retrieves session from storage
  /// 2. Calls token revocation endpoint
  /// 3. Deletes session from storage
  ///
  /// The [sub] is the user's DID.
  ///
  /// Token revocation is best-effort - even if the revocation request fails,
  /// the local session is still deleted.
  Future<void> revoke(String sub, {CancelToken? cancelToken}) async {
    // Validate DID format
    assertAtprotoDid(sub);

    // Get session (allow stale tokens for revocation)
    final session = await _sessionGetter.get(
      sub,
      const GetCachedOptions(allowStale: true),
    );

    // Try to revoke tokens on the server
    try {
      final authMethod =
          session.authMethod != null
              ? ClientAuthMethod.fromJson(
                session.authMethod as Map<String, dynamic>,
              )
              : const ClientAuthMethod.none(); // Legacy

      // Restore dpopKey from stored private JWK with error handling
      // CRITICAL FIX: Use the stored key instead of generating a new one
      // This ensures DPoP proofs match the token binding
      final FlutterKey dpopKey;
      try {
        dpopKey = FlutterKey.fromJwk(
          session.dpopKey as Map<String, dynamic>,
        );
      } catch (e) {
        // If key is corrupted, skip server-side revocation
        // The finally block will still delete the local session
        if (kDebugMode) {
          print('⚠️  Cannot revoke on server: corrupted DPoP key ($e)');
          print('   Local session will still be deleted');
        }
        return;
      }

      final server = await serverFactory.fromIssuer(
        session.tokenSet.iss,
        authMethod,
        dpopKey,
        auth_resolver.GetCachedOptions(cancelToken: cancelToken),
      );

      await server.revoke(session.tokenSet.accessToken);
    } finally {
      // Always delete local session, even if revocation failed
      await _sessionGetter.delStored(sub, TokenRevokedError(sub));
    }
  }

  /// Creates an OAuthSession wrapper.
  ///
  /// Internal helper for creating session objects from server agents.
  OAuthSession _createSession(OAuthServerAgent server, String sub) {
    // Create a wrapper that implements SessionGetterInterface
    final sessionGetterWrapper = _SessionGetterWrapper(_sessionGetter);

    return OAuthSession(
      server: server,
      sub: sub,
      sessionGetter: sessionGetterWrapper,
    );
  }

  /// Disposes of resources used by this client.
  ///
  /// Call this when the client is no longer needed to prevent memory leaks.
  @override
  void dispose() {
    _updatedController.close();
    _deletedController.close();
    _sessionGetter.dispose();
    super.dispose();
  }
}

/// Wrapper to adapt SessionGetter to SessionGetterInterface
class _SessionGetterWrapper implements SessionGetterInterface {
  final SessionGetter _getter;

  _SessionGetterWrapper(this._getter);

  @override
  Future<Session> get(String sub, {bool? noCache, bool? allowStale}) async {
    return _getter.get(
      sub,
      GetCachedOptions(
        noCache: noCache ?? false,
        allowStale: allowStale ?? false,
      ),
    );
  }

  @override
  Future<void> delStored(String sub, [Object? cause]) {
    return _getter.delStored(sub, cause);
  }
}
