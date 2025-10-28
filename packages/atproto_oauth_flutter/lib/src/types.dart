// Note: These types are not prefixed with `OAuth` because they are not specific
// to OAuth. They are specific to this package. OAuth specific types will be in
// a separate oauth-types module or imported from an external package.

// TODO: These types currently reference schemas from @atproto/oauth-types which
// need to be ported to Dart. For now, we're using Map<String, dynamic> as placeholders.
// These will be replaced with proper typed classes once oauth-types is ported.

/// Options for initiating an authorization request.
///
/// Omits client_id, response_mode, response_type, login_hint,
/// code_challenge, and code_challenge_method from OAuthAuthorizationRequestParameters
/// as these are managed internally.
class AuthorizeOptions {
  /// Optional URI to redirect to after authorization
  final String? redirectUri;

  /// Optional state parameter for CSRF protection
  final String? state;

  /// Optional scope parameter defining requested permissions
  final String? scope;

  /// Optional nonce parameter for replay protection
  final String? nonce;

  /// Optional DPoP JKT (JSON Web Key Thumbprint)
  final String? dpopJkt;

  /// Optional max age in seconds for authentication
  final int? maxAge;

  /// Optional claims parameter
  final Map<String, dynamic>? claims;

  /// Optional UI locales
  final String? uiLocales;

  /// Optional ID token hint
  final String? idTokenHint;

  /// Optional display mode
  final String? display;

  /// Optional prompt value
  final String? prompt;

  /// Optional authorization details
  final Map<String, dynamic>? authorizationDetails;

  const AuthorizeOptions({
    this.redirectUri,
    this.state,
    this.scope,
    this.nonce,
    this.dpopJkt,
    this.maxAge,
    this.claims,
    this.uiLocales,
    this.idTokenHint,
    this.display,
    this.prompt,
    this.authorizationDetails,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (redirectUri != null) map['redirect_uri'] = redirectUri;
    if (state != null) map['state'] = state;
    if (scope != null) map['scope'] = scope;
    if (nonce != null) map['nonce'] = nonce;
    if (dpopJkt != null) map['dpop_jkt'] = dpopJkt;
    if (maxAge != null) map['max_age'] = maxAge;
    if (claims != null) map['claims'] = claims;
    if (uiLocales != null) map['ui_locales'] = uiLocales;
    if (idTokenHint != null) map['id_token_hint'] = idTokenHint;
    if (display != null) map['display'] = display;
    if (prompt != null) map['prompt'] = prompt;
    if (authorizationDetails != null) {
      map['authorization_details'] = authorizationDetails;
    }
    return map;
  }
}

/// Options for handling OAuth callback.
class CallbackOptions {
  /// Optional redirect URI that was used in the authorization request
  final String? redirectUri;

  const CallbackOptions({this.redirectUri});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (redirectUri != null) map['redirect_uri'] = redirectUri;
    return map;
  }
}

/// Client metadata for OAuth configuration.
///
/// TODO: This extends the base oauthClientMetadataSchema with specific
/// client_id validation. Once oauth-types is ported, this will properly
/// validate client_id as either discoverable or loopback type.
class ClientMetadata {
  /// Client identifier (either discoverable HTTPS URI or loopback URI)
  final String? clientId;

  /// Array of redirect URIs
  final List<String> redirectUris;

  /// Response types supported by the client
  final List<String> responseTypes;

  /// Grant types supported by the client
  final List<String> grantTypes;

  /// Optional scope
  final String? scope;

  /// Token endpoint authentication method
  final String tokenEndpointAuthMethod;

  /// Optional token endpoint authentication signing algorithm
  final String? tokenEndpointAuthSigningAlg;

  /// Optional userinfo signed response algorithm
  final String? userinfoSignedResponseAlg;

  /// Optional userinfo encrypted response algorithm
  final String? userinfoEncryptedResponseAlg;

  /// Optional JWKS URI
  final String? jwksUri;

  /// Optional JWKS
  final Map<String, dynamic>? jwks;

  /// Application type (web or native)
  final String applicationType;

  /// Subject type (public or pairwise)
  final String subjectType;

  /// Optional request object signing algorithm
  final String? requestObjectSigningAlg;

  /// Optional ID token signed response algorithm
  final String? idTokenSignedResponseAlg;

  /// Authorization signed response algorithm
  final String authorizationSignedResponseAlg;

  /// Optional authorization encrypted response encoding
  final String? authorizationEncryptedResponseEnc;

  /// Optional authorization encrypted response algorithm
  final String? authorizationEncryptedResponseAlg;

  /// Optional client name
  final String? clientName;

  /// Optional client URI
  final String? clientUri;

  /// Optional policy URI
  final String? policyUri;

  /// Optional terms of service URI
  final String? tosUri;

  /// Optional logo URI
  final String? logoUri;

  /// Optional default max age
  final int? defaultMaxAge;

  /// Optional require auth time
  final bool? requireAuthTime;

  /// Optional contact emails
  final List<String>? contacts;

  /// Optional TLS client certificate bound access tokens
  final bool? tlsClientCertificateBoundAccessTokens;

  /// Optional DPoP bound access tokens
  final bool? dpopBoundAccessTokens;

  /// Optional authorization details types
  final List<String>? authorizationDetailsTypes;

  const ClientMetadata({
    this.clientId,
    required this.redirectUris,
    this.responseTypes = const ['code'],
    this.grantTypes = const ['authorization_code'],
    this.scope,
    this.tokenEndpointAuthMethod = 'client_secret_basic',
    this.tokenEndpointAuthSigningAlg,
    this.userinfoSignedResponseAlg,
    this.userinfoEncryptedResponseAlg,
    this.jwksUri,
    this.jwks,
    this.applicationType = 'web',
    this.subjectType = 'public',
    this.requestObjectSigningAlg,
    this.idTokenSignedResponseAlg,
    this.authorizationSignedResponseAlg = 'RS256',
    this.authorizationEncryptedResponseEnc,
    this.authorizationEncryptedResponseAlg,
    this.clientName,
    this.clientUri,
    this.policyUri,
    this.tosUri,
    this.logoUri,
    this.defaultMaxAge,
    this.requireAuthTime,
    this.contacts,
    this.tlsClientCertificateBoundAccessTokens,
    this.dpopBoundAccessTokens,
    this.authorizationDetailsTypes,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'redirect_uris': redirectUris,
      'response_types': responseTypes,
      'grant_types': grantTypes,
      'token_endpoint_auth_method': tokenEndpointAuthMethod,
      'application_type': applicationType,
      'subject_type': subjectType,
      'authorization_signed_response_alg': authorizationSignedResponseAlg,
    };

    if (clientId != null) map['client_id'] = clientId;
    if (scope != null) map['scope'] = scope;
    if (tokenEndpointAuthSigningAlg != null) {
      map['token_endpoint_auth_signing_alg'] = tokenEndpointAuthSigningAlg;
    }
    if (userinfoSignedResponseAlg != null) {
      map['userinfo_signed_response_alg'] = userinfoSignedResponseAlg;
    }
    if (userinfoEncryptedResponseAlg != null) {
      map['userinfo_encrypted_response_alg'] = userinfoEncryptedResponseAlg;
    }
    if (jwksUri != null) map['jwks_uri'] = jwksUri;
    if (jwks != null) map['jwks'] = jwks;
    if (requestObjectSigningAlg != null) {
      map['request_object_signing_alg'] = requestObjectSigningAlg;
    }
    if (idTokenSignedResponseAlg != null) {
      map['id_token_signed_response_alg'] = idTokenSignedResponseAlg;
    }
    if (authorizationEncryptedResponseEnc != null) {
      map['authorization_encrypted_response_enc'] =
          authorizationEncryptedResponseEnc;
    }
    if (authorizationEncryptedResponseAlg != null) {
      map['authorization_encrypted_response_alg'] =
          authorizationEncryptedResponseAlg;
    }
    if (clientName != null) map['client_name'] = clientName;
    if (clientUri != null) map['client_uri'] = clientUri;
    if (policyUri != null) map['policy_uri'] = policyUri;
    if (tosUri != null) map['tos_uri'] = tosUri;
    if (logoUri != null) map['logo_uri'] = logoUri;
    if (defaultMaxAge != null) map['default_max_age'] = defaultMaxAge;
    if (requireAuthTime != null) map['require_auth_time'] = requireAuthTime;
    if (contacts != null) map['contacts'] = contacts;
    if (tlsClientCertificateBoundAccessTokens != null) {
      map['tls_client_certificate_bound_access_tokens'] =
          tlsClientCertificateBoundAccessTokens;
    }
    if (dpopBoundAccessTokens != null) {
      map['dpop_bound_access_tokens'] = dpopBoundAccessTokens;
    }
    if (authorizationDetailsTypes != null) {
      map['authorization_details_types'] = authorizationDetailsTypes;
    }

    return map;
  }

  factory ClientMetadata.fromJson(Map<String, dynamic> json) {
    return ClientMetadata(
      clientId: json['client_id'] as String?,
      redirectUris: json['redirect_uris'] != null
          ? (json['redirect_uris'] as List<dynamic>)
              .map((e) => e as String)
              .toList()
          : [],
      responseTypes:
          json['response_types'] != null
              ? (json['response_types'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : const ['code'],
      grantTypes:
          json['grant_types'] != null
              ? (json['grant_types'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : const ['authorization_code'],
      scope: json['scope'] as String?,
      tokenEndpointAuthMethod:
          json['token_endpoint_auth_method'] as String? ??
          'client_secret_basic',
      tokenEndpointAuthSigningAlg:
          json['token_endpoint_auth_signing_alg'] as String?,
      userinfoSignedResponseAlg:
          json['userinfo_signed_response_alg'] as String?,
      userinfoEncryptedResponseAlg:
          json['userinfo_encrypted_response_alg'] as String?,
      jwksUri: json['jwks_uri'] as String?,
      jwks: json['jwks'] as Map<String, dynamic>?,
      applicationType: json['application_type'] as String? ?? 'web',
      subjectType: json['subject_type'] as String? ?? 'public',
      requestObjectSigningAlg: json['request_object_signing_alg'] as String?,
      idTokenSignedResponseAlg: json['id_token_signed_response_alg'] as String?,
      authorizationSignedResponseAlg:
          json['authorization_signed_response_alg'] as String? ?? 'RS256',
      authorizationEncryptedResponseEnc:
          json['authorization_encrypted_response_enc'] as String?,
      authorizationEncryptedResponseAlg:
          json['authorization_encrypted_response_alg'] as String?,
      clientName: json['client_name'] as String?,
      clientUri: json['client_uri'] as String?,
      policyUri: json['policy_uri'] as String?,
      tosUri: json['tos_uri'] as String?,
      logoUri: json['logo_uri'] as String?,
      defaultMaxAge: json['default_max_age'] as int?,
      requireAuthTime: json['require_auth_time'] as bool?,
      contacts:
          json['contacts'] != null
              ? (json['contacts'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : null,
      tlsClientCertificateBoundAccessTokens:
          json['tls_client_certificate_bound_access_tokens'] as bool?,
      dpopBoundAccessTokens: json['dpop_bound_access_tokens'] as bool?,
      authorizationDetailsTypes:
          json['authorization_details_types'] != null
              ? (json['authorization_details_types'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : null,
    );
  }
}
