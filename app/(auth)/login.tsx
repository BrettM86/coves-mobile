import { useState } from 'react';
import { View, Text, TextInput, Pressable, Alert, ActivityIndicator } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { isValidHandle } from '@atproto/syntax';
import { useAuthStore } from '@/stores/authStore';

export default function LoginScreen() {
  const [handle, setHandle] = useState('');
  const { login, isLoading, error, clearError } = useAuthStore();

  const handleLogin = async () => {
    const trimmedHandle = handle.trim().toLowerCase();

    if (!trimmedHandle) {
      Alert.alert('Error', 'Please enter your handle');
      return;
    }

    // Validate handle format using @atproto/syntax
    if (!isValidHandle(trimmedHandle)) {
      Alert.alert(
        'Invalid Handle',
        'Please enter a valid atProto handle (e.g., username.bsky.social)'
      );
      return;
    }

    try {
      clearError();
      await login(trimmedHandle);
      // Navigation will happen automatically via _layout.tsx
    } catch (error) {
      // Ignore "dismiss" errors - they're expected when the deep link works
      if (error instanceof Error && error.message.includes('dismiss')) {
        return;
      }

      Alert.alert(
        'Login Failed',
        error instanceof Error ? error.message : 'Please try again'
      );
    }
  };

  // DEV ONLY: Clear storage
  const handleClearStorage = async () => {
    try {
      await AsyncStorage.clear();
      Alert.alert('Success', 'Storage cleared! Restart the app.');
    } catch {
      Alert.alert('Error', 'Failed to clear storage');
    }
  };

  return (
    <View className="flex-1 bg-slate-900 px-6 justify-center">
      {/* Coves Logo/Header */}
      <View className="items-center mb-12">
        <Text className="text-6xl mb-4">🏞️</Text>
        <Text className="text-5xl font-bold text-white mb-2">Coves</Text>
        <Text className="text-slate-400 text-base">
          Your atProto community
        </Text>
      </View>

      {/* Input Section */}
      <View className="mb-6">
        <Text className="text-sm font-medium text-slate-300 mb-2">
          atProto Handle or DID
        </Text>
        <TextInput
          className="bg-slate-800 border border-slate-700 rounded-xl px-4 py-4 text-base text-white"
          placeholder="your-handle.bsky.social"
          placeholderTextColor="#64748b"
          value={handle}
          onChangeText={setHandle}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          editable={!isLoading}
        />
      </View>

      {/* Error Message */}
      {error && (
        <View className="mb-6 p-4 bg-red-950 border border-red-800 rounded-xl">
          <Text className="text-red-200 text-sm">{error}</Text>
        </View>
      )}

      {/* Sign In Button */}
      <Pressable
        className={`bg-blue-600 rounded-xl py-4 items-center ${
          isLoading ? 'opacity-50' : ''
        }`}
        onPress={handleLogin}
        disabled={isLoading}
      >
        {isLoading ? (
          <ActivityIndicator color="white" />
        ) : (
          <Text className="text-white font-bold text-base">Sign In</Text>
        )}
      </Pressable>

      {/* Footer */}
      <Text className="text-xs text-slate-500 mt-8 text-center">
        Powered by atProto • OAuth 2.0 + DPoP
      </Text>

      {/* DEV ONLY: Clear Storage Button */}
      {__DEV__ && (
        <Pressable
          className="mt-4 py-2"
          onPress={handleClearStorage}
        >
          <Text className="text-xs text-slate-600 text-center">
            [DEV] Clear Storage
          </Text>
        </Pressable>
      )}
    </View>
  );
}
