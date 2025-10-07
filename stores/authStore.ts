import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { OAuthSession } from '@atproto/oauth-client';
import { Agent } from '@atproto/api';
import { initializeOAuth, signIn, signOut } from '@/lib/oauthClient';
import { createAgent } from '@/lib/api';

interface AuthState {
  // Session state
  session: OAuthSession | null;
  agent: Agent | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;

  // User info
  did: string | null;
  handle: string | null;

  // Actions
  initialize: () => Promise<void>;
  login: (handle: string) => Promise<void>;
  logout: () => Promise<void>;
  completeOAuthCallback: (session: OAuthSession, agent: Agent, handle: string) => void;
  clearError: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      session: null,
      agent: null,
      isAuthenticated: false,
      isLoading: true,
      error: null,
      did: null,
      handle: null,

      initialize: async () => {
        try {
          set({ isLoading: true, error: null });

          // Get stored DID from persisted state
          const { did: storedDid } = get();

          // Initialize OAuth client and restore session if we have a DID
          const session = await initializeOAuth(storedDid);

          if (session) {
            const agent = createAgent(session);

            // Get user info from session
            const profile = await agent.getProfile({ actor: session.sub });

            set({
              session,
              agent,
              isAuthenticated: true,
              did: session.sub,
              handle: profile.data.handle,
              isLoading: false,
            });
          } else {
            // If we had a stored DID but couldn't restore session, clear it
            if (storedDid) {
              console.log('Failed to restore session, clearing stored credentials');
              set({
                did: null,
                handle: null,
                isLoading: false,
              });
            } else {
              set({ isLoading: false });
            }
          }
        } catch (error) {
          console.error('Failed to initialize auth:', error);
          // Clear stored credentials on error
          set({
            isLoading: false,
            did: null,
            handle: null,
            error: error instanceof Error ? error.message : 'Failed to initialize',
          });
        }
      },

  login: async (handle: string) => {
    try {
      set({ isLoading: true, error: null });

      // Perform OAuth sign in
      const session = await signIn(handle);
      const agent = createAgent(session);

      // Get user profile
      const profile = await agent.getProfile({ actor: session.sub });

      // Only set DID/handle after successful login
      set({
        session,
        agent,
        isAuthenticated: true,
        did: session.sub,
        handle: profile.data.handle,
        isLoading: false,
      });
    } catch (error) {
      // If the error is "dismiss", the deep link worked and the callback handler will complete the login
      // So we just set loading to false and let the callback handler take over
      if (error instanceof Error && error.message.includes('dismiss')) {
        console.log('Browser dismissed - waiting for deep link callback to complete login');
        set({ isLoading: false });
        return;
      }

      console.error('Login failed:', error);
      // Clear any DID that might have been set during failed attempt
      set({
        isLoading: false,
        did: null,
        handle: null,
        session: null,
        agent: null,
        isAuthenticated: false,
        error: error instanceof Error ? error.message : 'Login failed',
      });
      throw error;
    }
  },

  logout: async () => {
    try {
      const { did } = get();
      if (did) {
        await signOut(did);
      }

      set({
        session: null,
        agent: null,
        isAuthenticated: false,
        did: null,
        handle: null,
        error: null,
      });
    } catch (error) {
      console.error('Logout failed:', error);
      set({
        error: error instanceof Error ? error.message : 'Logout failed',
      });
    }
  },

  completeOAuthCallback: (session: OAuthSession, agent: Agent, handle: string) => {
    set({
      session,
      agent,
      isAuthenticated: true,
      did: session.sub,
      handle,
      isLoading: false,
      error: null,
    });
  },

  clearError: () => set({ error: null }),
    }),
    {
      name: 'coves-auth-storage',
      storage: createJSONStorage(() => AsyncStorage),
      // Only persist DID and handle for session restoration
      partialize: (state) => ({
        did: state.did,
        handle: state.handle,
      }),
    }
  )
);
