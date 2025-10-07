import { ExpoOAuthClient } from '@atproto/oauth-client-expo';
import { config } from '@/constants/config';

/**
 * Initialize the OAuth client
 * This handles all OAuth complexity: DPoP, PKCE, PAR, token management
 */
export const oauthClient = new ExpoOAuthClient({
  // Client metadata - must match hosted client-metadata.json
  clientMetadata: {
    client_id: config.clientMetadata.client_id,
    client_name: config.clientMetadata.client_name,
    client_uri: config.clientMetadata.client_uri,
    redirect_uris: config.clientMetadata.redirect_uris,
    scope: config.clientMetadata.scope,
    grant_types: config.clientMetadata.grant_types,
    response_types: config.clientMetadata.response_types,
    application_type: config.clientMetadata.application_type,
    token_endpoint_auth_method: config.clientMetadata.token_endpoint_auth_method,
    dpop_bound_access_tokens: config.clientMetadata.dpop_bound_access_tokens,
  },

  // Handle resolver - resolves atProto handles to DID documents
  handleResolver: 'https://bsky.social', // Use Bluesky's resolver

  // Response mode - use 'query' for native apps
  responseMode: 'query',

  // MMKV storage is used by default for encrypted session storage
});

/**
 * Initialize the client and restore any existing sessions
 * @param storedDid - The DID of a previously authenticated user (if any)
 */
export async function initializeOAuth(storedDid?: string | null) {
  try {
    console.log('Initializing OAuth client...');

    // Only try to restore if we have a stored DID
    if (!storedDid) {
      console.log('No stored DID found, skipping session restore');
      return null;
    }

    console.log('Attempting to restore session for:', storedDid);
    const session = await oauthClient.restore(storedDid);

    if (session) {
      console.log('Successfully restored session for:', session.sub);
      return session;
    }

    console.log('No valid session found');
    return null;
  } catch (error) {
    console.error('Failed to restore session:', error);
    return null;
  }
}

/**
 * Sign in with an atProto handle
 */
export async function signIn(handle: string) {
  // This triggers the full OAuth flow:
  // 1. Handle resolution
  // 2. PAR (Pushed Authorization Request)
  // 3. Opens browser for authorization
  // 4. Handles callback with DPoP
  // 5. Stores session in MMKV
  const result = await oauthClient.signIn(handle, {
    signal: new AbortController().signal,
    // Force HTTPS redirect URI (works better on Android than custom schemes)
    redirect_uri: process.env.EXPO_PUBLIC_OAUTH_REDIRECT_URI!,
  });

  // Check the result status
  if (result.status === 'error') {
    throw result.error;
  }

  if (result.status !== 'success') {
    throw new Error(`Authentication cancelled: ${result.status}`);
  }

  return result.session;
}

/**
 * Sign out
 */
export async function signOut(sub: string) {
  try {
    await oauthClient.revoke(sub);
    console.log('Signed out successfully');
  } catch (error) {
    console.error('Sign out failed:', error);
    throw error;
  }
}
