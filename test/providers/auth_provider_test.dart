import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider_test.mocks.dart';

// Generate mocks for OAuthService and OAuthSession only
@GenerateMocks([OAuthService, OAuthSession])

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthProvider', () {
    late AuthProvider authProvider;
    late MockOAuthService mockOAuthService;

    setUp(() {
      // Mock SharedPreferences
      SharedPreferences.setMockInitialValues({});

      // Create mock OAuth service
      mockOAuthService = MockOAuthService();

      // Create auth provider with injected mock service
      authProvider = AuthProvider(oauthService: mockOAuthService);
    });

    tearDown(() {
      authProvider.dispose();
    });

    group('initialize', () {
      test('should initialize with no stored session', () async {
        when(mockOAuthService.initialize()).thenAnswer((_) async => {});

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.isLoading, false);
        expect(authProvider.session, null);
        expect(authProvider.error, null);
      });

      test('should restore session if DID is stored', () async {
        // Set up mock stored DID
        SharedPreferences.setMockInitialValues({
          'current_user_did': 'did:plc:test123',
        });

        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');

        when(mockOAuthService.initialize()).thenAnswer((_) async => {});
        when(
          mockOAuthService.restoreSession('did:plc:test123'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, true);
        expect(authProvider.did, 'did:plc:test123');
      });

      test('should handle initialization errors gracefully', () async {
        when(mockOAuthService.initialize()).thenThrow(Exception('Init failed'));

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.error, isNotNull);
        expect(authProvider.isLoading, false);
      });
    });

    group('signIn', () {
      test('should sign in successfully with valid handle', () async {
        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');

        when(
          mockOAuthService.signIn('alice.bsky.social'),
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
          mockOAuthService.signIn('invalid.handle'),
        ).thenThrow(Exception('Sign in failed'));

        expect(
          () => authProvider.signIn('invalid.handle'),
          throwsA(isA<Exception>()),
        );

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.error, isNotNull);
      });

      test('should store DID in SharedPreferences after sign in', () async {
        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');

        when(
          mockOAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('current_user_did'), 'did:plc:test123');
      });
    });

    group('signOut', () {
      test('should sign out and clear state', () async {
        // First sign in
        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');
        when(
          mockOAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');
        expect(authProvider.isAuthenticated, true);

        // Then sign out
        when(
          mockOAuthService.signOut('did:plc:test123'),
        ).thenAnswer((_) async => {});

        await authProvider.signOut();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.session, null);
        expect(authProvider.did, null);
        expect(authProvider.handle, null);
      });

      test('should clear DID from SharedPreferences', () async {
        // Sign in first
        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');
        when(
          mockOAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        // Sign out
        when(
          mockOAuthService.signOut('did:plc:test123'),
        ).thenAnswer((_) async => {});

        await authProvider.signOut();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('current_user_did'), null);
      });

      test('should clear state even if server revocation fails', () async {
        // Sign in first
        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');
        when(
          mockOAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        // Sign out with error
        when(
          mockOAuthService.signOut('did:plc:test123'),
        ).thenThrow(Exception('Revocation failed'));

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

      // Note: Testing getAccessToken requires mocking internal OAuth classes
      // that are not exported from atproto_oauth_flutter package.
      // These tests would need integration testing or a different approach.

      test('should return null when not authenticated (skipped - needs integration test)', () async {
        // This test is skipped as it requires mocking internal OAuth classes
        // that cannot be mocked with mockito
      }, skip: true);

      test('should sign out user if token refresh fails (skipped - needs integration test)', () async {
        // This test demonstrates the critical fix for issue #7
        // Token refresh failure should trigger sign out
        // Skipped as it requires mocking internal OAuth classes
      }, skip: true);
    });

    group('State Management', () {
      test('should notify listeners on state change', () async {
        var notificationCount = 0;
        authProvider.addListener(() {
          notificationCount++;
        });

        final mockSession = MockOAuthSession();
        when(mockSession.sub).thenReturn('did:plc:test123');
        when(
          mockOAuthService.signIn('alice.bsky.social'),
        ).thenAnswer((_) async => mockSession);

        await authProvider.signIn('alice.bsky.social');

        // Should notify during sign in process
        expect(notificationCount, greaterThan(0));
      });

      test('should clear error when clearError is called', () {
        // Simulate an error state
        when(mockOAuthService.signIn('invalid')).thenThrow(Exception('Error'));

        // This would set error state
        // Then clear it
        authProvider.clearError();
        expect(authProvider.error, null);
      });
    });
  });
}
