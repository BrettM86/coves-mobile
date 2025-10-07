import { useEffect, useState } from 'react';
import { View, ActivityIndicator, Text } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { oauthClient } from '@/lib/oauthClient';
import { createAgent } from '@/lib/api';
import { useAuthStore } from '@/stores/authStore';

/**
 * OAuth Callback Handler
 *
 * This route is triggered when the deep link opens the app after authorization.
 * We manually complete the OAuth flow here since expo-web-browser reports "dismiss"
 * when the deep link triggers.
 */
export default function OAuthCallback() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    handleCallback();
  }, []);

  async function handleCallback() {
    try {
      console.log('OAuth callback received with params:', params);

      // Build URLSearchParams from the query params
      const searchParams = new URLSearchParams();
      Object.entries(params).forEach(([key, value]) => {
        if (value) searchParams.append(key, String(value));
      });

      // Complete the OAuth flow manually
      const { session } = await oauthClient.callback(searchParams, {
        redirect_uri: process.env.EXPO_PUBLIC_OAUTH_REDIRECT_URI!,
      });

      // Create agent and get profile
      const agent = createAgent(session);
      const profile = await agent.getProfile({ actor: session.sub });

      // Update auth store using proper action
      useAuthStore.getState().completeOAuthCallback(session, agent, profile.data.handle);

      console.log('OAuth login successful!');
      router.replace('/(tabs)');
    } catch (err) {
      console.error('OAuth callback failed:', err);
      setError(err instanceof Error ? err.message : 'Login failed');

      // Redirect back to login after error
      setTimeout(() => {
        router.replace('/(auth)/login');
      }, 2000);
    }
  }

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20 }}>
      {error ? (
        <Text style={{ color: 'red', textAlign: 'center' }}>{error}</Text>
      ) : (
        <>
          <ActivityIndicator size="large" />
          <Text style={{ marginTop: 20 }}>Completing login...</Text>
        </>
      )}
    </View>
  );
}
