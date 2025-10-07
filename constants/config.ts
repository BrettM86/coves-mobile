const isDev = __DEV__;

// Get environment variables from expo-constants
// These are set via EXPO_PUBLIC_* prefix in .env files
const getEnvVar = (key: string, fallback: string = ''): string => {
  return process.env[key] || fallback;
};

export const config = {
  // Client metadata
  // Note: For OAuth to work, you need to host client-metadata.json at this URL
  clientMetadata: {
    client_id: getEnvVar('EXPO_PUBLIC_OAUTH_CLIENT_ID'),
    client_name: 'Coves',
    client_uri: getEnvVar('EXPO_PUBLIC_OAUTH_CLIENT_URI'),
    redirect_uris: [
      getEnvVar('EXPO_PUBLIC_OAUTH_REDIRECT_URI'), // HTTPS redirect (works better on Android)
      'dev.workers.brettmay0212.lingering-darkness-50a6:/oauth/callback', // Fallback custom scheme
    ],
    scope: 'atproto transition:generic',
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    application_type: 'native',
    token_endpoint_auth_method: 'none', // Public client
    dpop_bound_access_tokens: true,
  },

  // API endpoints (for your Coves backend if needed)
  apiUrl: getEnvVar('EXPO_PUBLIC_API_URL', isDev ? 'http://localhost:8081' : 'https://api.coves.app'),
};
