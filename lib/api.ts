import { Agent } from '@atproto/api';
import { OAuthSession } from '@atproto/oauth-client';

/**
 * Custom error class for API errors
 */
export class ApiError extends Error {
  constructor(
    message: string,
    public cause?: Error,
    public isNetworkError: boolean = false
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * Wraps API calls with error handling for offline/network errors
 */
async function withErrorHandling<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    // Check if it's a network error
    if (error instanceof Error) {
      const errorMessage = error.message.toLowerCase();
      const isNetworkError =
        errorMessage.includes('network') ||
        errorMessage.includes('offline') ||
        errorMessage.includes('fetch') ||
        errorMessage.includes('connection');

      if (isNetworkError) {
        throw new ApiError(
          'Unable to connect. Please check your internet connection.',
          error,
          true
        );
      }
    }

    // Re-throw other errors as ApiError
    throw new ApiError(
      error instanceof Error ? error.message : 'An unexpected error occurred',
      error instanceof Error ? error : undefined
    );
  }
}

/**
 * Create an authenticated API agent
 * The Agent automatically handles token refresh using the OAuthSession
 */
export function createAgent(session: OAuthSession): Agent {
  return new Agent(session);
}

/**
 * Example: Fetch user profile
 */
export async function getProfile(agent: Agent, actor: string) {
  return withErrorHandling(async () => {
    const response = await agent.getProfile({ actor });
    return response.data;
  });
}

/**
 * Example: Create a post
 */
export async function createPost(agent: Agent, text: string) {
  return withErrorHandling(async () => {
    const response = await agent.post({
      text,
      createdAt: new Date().toISOString(),
    });
    return response;
  });
}

/**
 * Example: Get timeline
 */
export async function getTimeline(agent: Agent, limit = 50) {
  return withErrorHandling(async () => {
    const response = await agent.getTimeline({ limit });
    return response.data;
  });
}
