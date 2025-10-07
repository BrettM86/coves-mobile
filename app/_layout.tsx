import { useEffect } from 'react';
import { Stack, useRouter, useSegments } from 'expo-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import ErrorBoundary from 'react-native-error-boundary';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useAuthStore } from '@/stores/authStore';
import { ActivityIndicator, View, Text, Pressable } from 'react-native';
import '@/global.css';

// Polyfill DOMException for abort controller
if (typeof global.DOMException === 'undefined') {
  global.DOMException = class DOMException extends Error {
    constructor(message?: string, name?: string) {
      super(message);
      this.name = name || 'DOMException';
    }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any;
}

const queryClient = new QueryClient();

// Error fallback component
function ErrorFallback({ error, resetError }: { error: Error; resetError: () => void }) {
  const logout = useAuthStore((state) => state.logout);

  const handleSignOut = async () => {
    await logout();
    resetError();
  };

  return (
    <View className="flex-1 items-center justify-center bg-slate-900 px-6">
      <Text className="text-6xl mb-4">⚠️</Text>
      <Text className="text-2xl font-bold text-white mb-2">Something went wrong</Text>
      <Text className="text-slate-400 text-center mb-6">
        {error.message || 'An unexpected error occurred'}
      </Text>
      <View className="gap-3">
        <Pressable
          className="bg-blue-600 rounded-xl px-6 py-3"
          onPress={resetError}
        >
          <Text className="text-white font-bold text-center">Try Again</Text>
        </Pressable>
        <Pressable
          className="bg-slate-700 rounded-xl px-6 py-3"
          onPress={handleSignOut}
        >
          <Text className="text-white font-bold text-center">Sign Out</Text>
        </Pressable>
      </View>
    </View>
  );
}

function RootNavigator() {
  const segments = useSegments();
  const router = useRouter();
  const { isAuthenticated, isLoading, initialize } = useAuthStore();

  // Initialize auth on app start
  useEffect(() => {
    initialize();
  }, []);

  // Handle navigation based on auth state
  useEffect(() => {
    if (isLoading) return;

    const inAuthGroup = segments[0] === '(auth)';

    if (!isAuthenticated && !inAuthGroup) {
      // Redirect to login
      router.replace('/(auth)/login');
    } else if (isAuthenticated && inAuthGroup) {
      // Redirect to app
      router.replace('/(tabs)');
    }
  }, [isAuthenticated, isLoading, segments]);

  if (isLoading) {
    return (
      <View className="flex-1 items-center justify-center">
        <ActivityIndicator size="large" />
      </View>
    );
  }

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(auth)" />
      <Stack.Screen name="(tabs)" />
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <ErrorBoundary FallbackComponent={ErrorFallback}>
        <QueryClientProvider client={queryClient}>
          <RootNavigator />
        </QueryClientProvider>
      </ErrorBoundary>
    </GestureHandlerRootView>
  );
}
