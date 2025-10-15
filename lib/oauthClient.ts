import { ExpoOAuthClient } from '@atproto/oauth-client-expo';
import Constants from 'expo-constants';

/**
 * Get configuration value from Expo Constants
 * Works in both Expo Go (expoConfig) and native builds (manifestExtra)
 */
function getConfig(key: string): string {
  // Try multiple sources in order:
  // 1. expoConfig.extra (Expo Go, dev builds)
  // 2. manifestExtra (native builds via EAS)
  // 3. process.env (fallback)
  const value =
    Constants.expoConfig?.extra?.[key] ??
    Constants.manifest2?.extra?.expoClient?.extra?.[key] ??
    Constants.manifest?.extra?.[key] ??
    process.env[key];

  if (!value) {
    throw new Error(
      `Missing required configuration: ${key}\n` +
        `Please ensure it's set in app.config.js extra field.\n` +
        `See .env.example for required variables.`
    );
  }

  return value;
}

// Get OAuth configuration - will throw if not properly configured
const CLIENT_ID = getConfig('EXPO_PUBLIC_OAUTH_CLIENT_ID');
const CLIENT_URI = getConfig('EXPO_PUBLIC_OAUTH_CLIENT_URI');
const REDIRECT_URI = getConfig('EXPO_PUBLIC_OAUTH_REDIRECT_URI');
const CUSTOM_SCHEME = getConfig('EXPO_PUBLIC_CUSTOM_SCHEME');

// Build the custom scheme callback URI
const CUSTOM_SCHEME_CALLBACK = `${CUSTOM_SCHEME}:/oauth/callback`;

/**
 * Initialize the OAuth client
 * This handles all OAuth complexity: DPoP, PKCE, PAR, token management
 */
export const oauthClient = new ExpoOAuthClient({
  // Client metadata - must match hosted client-metadata.json
  clientMetadata: {
    client_id: CLIENT_ID,
    client_name: 'Coves',
    client_uri: CLIENT_URI,
    redirect_uris: [
      REDIRECT_URI, // HTTPS redirect (works better on Android)
      CUSTOM_SCHEME_CALLBACK, // Fallback custom scheme
    ],
    scope: 'atproto transition:generic',
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    application_type: 'native',
    token_endpoint_auth_method: 'none', // Public client
    dpop_bound_access_tokens: true,
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
    if (__DEV__) {
      console.log('Initializing OAuth client...');
      console.log('Client ID:', CLIENT_ID);
      console.log('Redirect URI:', REDIRECT_URI);
    }

    // Only try to restore if we have a stored DID
    if (!storedDid) {
      if (__DEV__) {
        console.log('No stored DID found, skipping session restore');
      }
      return null;
    }

    if (__DEV__) {
      console.log('Attempting to restore session for:', storedDid);
    }
    const session = await oauthClient.restore(storedDid);

    if (session) {
      if (__DEV__) {
        console.log('Successfully restored session for:', session.sub);
      }
      return session;
    }

    if (__DEV__) {
      console.log('No valid session found');
    }
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
    redirect_uri: REDIRECT_URI,
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
    if (__DEV__) {
      console.log('Signed out successfully');
    }
  } catch (error) {
    console.error('Sign out failed:', error);
    throw error;
  }
}
