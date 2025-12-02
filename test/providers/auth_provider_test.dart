import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'auth_provider_test.mocks.dart';

// Generate mocks for CovesAuthService
@GenerateMocks([CovesAuthService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthProvider', () {
    late AuthProvider authProvider;
    late MockCovesAuthService mockAuthService;

    setUp(() {
      // Create mock auth service
      mockAuthService = MockCovesAuthService();

      // Create auth provider with injected mock service
      authProvider = AuthProvider(authService: mockAuthService);
    });

    group('initialize', () {
      test('should initialize with no stored session', () async {
        when(mockAuthService.initialize()).thenAnswer((_) async => {});
        when(mockAuthService.restoreSession()).thenAnswer((_) async => null);

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.isLoading, false);
        expect(authProvider.session, null);
        expect(authProvider.error, null);
      });

      test('should restore session if available', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'test.user',
        );

        when(mockAuthService.initialize()).thenAnswer((_) async => {});
        when(
          mockAuthService.restoreSession(),
        ).thenAnswer((_) async => mockSession);

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, true);
        expect(authProvider.did, 'did:plc:test123');
        expect(authProvider.handle, 'test.user');
      });

      test('should handle initialization errors gracefully', () async {
        when(mockAuthService.initialize()).thenThrow(Exception('Init failed'));

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.error, isNotNull);
        expect(authProvider.isLoading, false);
      });
    });

    group('signIn', () {
      test('should sign in successfully with valid handle', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'alice.bsky.social',
        );

        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        expect(authProvider.isAuthenticated, true);
        expect(authProvider.did, 'did:plc:test123');
        expect(authProvider.handle, 'alice.bsky.social');
        expect(authProvider.error, null);
      });

      test('should reject empty handle', () async {
        expect(() => authProvider.signIn(''), throwsA(isA<Exception>()));

        expect(authProvider.isAuthenticated, false);
      });

      test('should handle sign in errors', () async {
        when(
          mockAuthService.signIn('invalid.handle'),
        ).thenThrow(Exception('Sign in failed'));

        expect(
          () => authProvider.signIn('invalid.handle'),
          throwsA(isA<Exception>()),
        );

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.error, isNotNull);
      });
    });

    group('signOut', () {
      test('should sign out and clear state', () async {
        // First sign in
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'alice.bsky.social',
        );
        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');
        expect(authProvider.isAuthenticated, true);

        // Then sign out
        when(mockAuthService.signOut()).thenAnswer((_) async => {});

        await authProvider.signOut();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.session, null);
        expect(authProvider.did, null);
        expect(authProvider.handle, null);
      });

      test('should clear state even if server revocation fails', () async {
        // Sign in first
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'alice.bsky.social',
        );
        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        // Sign out with error
        when(mockAuthService.signOut())
            .thenThrow(Exception('Revocation failed'));

        await authProvider.signOut();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.session, null);
      });
    });

    group('getAccessToken', () {
      test('should return null when not authenticated', () async {
        final token = await authProvider.getAccessToken();
        expect(token, null);
      });

      test('should return sealed token when authenticated', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );

        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        final token = await authProvider.getAccessToken();
        expect(token, 'mock_sealed_token');
      });
    });

    group('refreshToken', () {
      test('should return false when not authenticated', () async {
        final result = await authProvider.refreshToken();
        expect(result, false);
      });

      test('should refresh token successfully', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );
        const refreshedSession = CovesSession(
          token: 'new_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );

        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);
        when(
          mockAuthService.refreshToken(),
        ).thenAnswer((_) async => refreshedSession);

        await authProvider.signIn('alice.bsky.social');
        final result = await authProvider.refreshToken();

        expect(result, true);
        expect(authProvider.session?.token, 'new_sealed_token');
      });

      test('should sign out if refresh fails', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );

        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);
        when(
          mockAuthService.refreshToken(),
        ).thenThrow(Exception('Refresh failed'));
        when(mockAuthService.signOut()).thenAnswer((_) async => {});

        await authProvider.signIn('alice.bsky.social');
        final result = await authProvider.refreshToken();

        expect(result, false);
        expect(authProvider.isAuthenticated, false);
      });
    });

    group('State Management', () {
      test('should notify listeners on state change', () async {
        var notificationCount = 0;
        authProvider.addListener(() {
          notificationCount++;
        });

        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );
        when(
          mockAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        // Should notify during sign in process
        expect(notificationCount, greaterThan(0));
      });

      test('should clear error when clearError is called', () {
        // Trigger an error state
        authProvider.clearError();
        expect(authProvider.error, null);
      });
    });
  });
}
