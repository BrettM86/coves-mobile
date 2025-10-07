import { View, Text, Pressable } from 'react-native';
import { useAuthStore } from '@/stores/authStore';

export default function FeedScreen() {
  const { handle, did, logout } = useAuthStore();

  return (
    <View className="flex-1 items-center justify-center p-6">
      <Text className="text-2xl font-bold mb-4">Feed</Text>
      <Text className="text-gray-600 mb-2">Logged in as: {handle}</Text>
      <Text className="text-gray-400 text-xs mb-6">{did}</Text>

      <Pressable
        className="bg-red-500 rounded-lg px-6 py-3"
        onPress={logout}
      >
        <Text className="text-white font-semibold">Sign Out</Text>
      </Pressable>
    </View>
  );
}
