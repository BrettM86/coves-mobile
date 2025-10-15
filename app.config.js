const IS_DEV = process.env.APP_VARIANT === 'development';

// OAuth Server Configuration
// Single source of truth for OAuth server URLs
const OAUTH_SERVER_URL = process.env.EXPO_PUBLIC_OAUTH_SERVER_URL;
if (!OAUTH_SERVER_URL) {
  throw new Error(
    'EXPO_PUBLIC_OAUTH_SERVER_URL is required. Please set it in your .env file.\n' +
      'Example: EXPO_PUBLIC_OAUTH_SERVER_URL=https://your-oauth-server.workers.dev'
  );
}

// Custom URL scheme for deep linking
// Production should use reverse-DNS format matching bundle ID
// Development can use a custom scheme for testing
const CUSTOM_SCHEME =
  process.env.EXPO_PUBLIC_CUSTOM_SCHEME ||
  (IS_DEV ? 'com.coves.app.dev' : 'com.coves.app');

// Build OAuth URLs from base server URL
const OAUTH_CLIENT_METADATA_URL = `${OAUTH_SERVER_URL}/client-metadata.json`;
const OAUTH_REDIRECT_URI = `${OAUTH_SERVER_URL}/oauth/callback`;

// Extract host from OAuth server URL for deep linking configuration
const OAUTH_SERVER_HOST = new URL(OAUTH_SERVER_URL).host;

module.exports = {
  expo: {
    name: 'Coves',
    slug: 'coves-mobile',
    version: '1.0.0',
    scheme: CUSTOM_SCHEME,
    orientation: 'portrait',
    icon: './assets/icon.png',
    userInterfaceStyle: 'automatic',
    newArchEnabled: true,
    splash: {
      image: './assets/splash-icon.png',
      resizeMode: 'contain',
      backgroundColor: '#ffffff',
    },
    ios: {
      bundleIdentifier: 'com.coves.app',
      supportsTablet: true,
      // iOS Universal Links - must match OAuth redirect domain
      associatedDomains: [`applinks:${OAUTH_SERVER_HOST}`],
    },
    android: {
      package: 'com.coves.app',
      adaptiveIcon: {
        foregroundImage: './assets/adaptive-icon.png',
        backgroundColor: '#ffffff',
      },
      edgeToEdgeEnabled: true,
      predictiveBackGestureEnabled: false,
      intentFilters: [
        {
          action: 'VIEW',
          autoVerify: true,
          data: [
            // HTTPS deep link - must match OAuth redirect domain
            {
              scheme: 'https',
              host: OAUTH_SERVER_HOST,
              pathPrefix: '/oauth/callback',
            },
            // Custom scheme fallback
            {
              scheme: CUSTOM_SCHEME,
            },
          ],
          category: ['BROWSABLE', 'DEFAULT'],
        },
      ],
    },
    web: {
      favicon: './assets/favicon.png',
    },
    plugins: ['expo-router'],
    extra: {
      // OAuth Configuration - built from OAUTH_SERVER_URL
      EXPO_PUBLIC_OAUTH_CLIENT_ID: OAUTH_CLIENT_METADATA_URL,
      EXPO_PUBLIC_OAUTH_CLIENT_URI: OAUTH_CLIENT_METADATA_URL,
      EXPO_PUBLIC_OAUTH_REDIRECT_URI: OAUTH_REDIRECT_URI,

      // Custom URL scheme for deep linking
      EXPO_PUBLIC_CUSTOM_SCHEME: CUSTOM_SCHEME,

      // API Configuration
      EXPO_PUBLIC_API_URL:
        process.env.EXPO_PUBLIC_API_URL ||
        (IS_DEV ? 'http://localhost:8081' : 'https://api.coves.app'),
    },
  },
};
