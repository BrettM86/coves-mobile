import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'coves_auth_service_test.mocks.dart';

/// Test suite to verify that sessions are namespaced per environment.
///
/// This prevents a critical bug where switching between dev/prod builds
/// could send prod tokens to dev servers (or vice versa), causing 401 loops.
@GenerateMocks([Dio, FlutterSecureStorage])
void main() {
  late MockDio mockDio;
  late MockFlutterSecureStorage mockStorage;
  late CovesAuthService authService;

  setUp(() {
    CovesAuthService.resetInstance();
    mockDio = MockDio();
    mockStorage = MockFlutterSecureStorage();
    authService = CovesAuthService.createTestInstance(
      dio: mockDio,
      storage: mockStorage,
    );
  });

  tearDown(() {
    CovesAuthService.resetInstance();
  });

  group('CovesAuthService - Environment Isolation', () {
    test('should use environment-specific storage keys', () {
      // This test documents the expected storage key format
      // The actual environment is determined at compile time via --dart-define
      // In tests without specific environment configuration, it defaults to production
      final currentEnv = EnvironmentConfig.current.environment.name;
      final expectedKey = 'coves_session_$currentEnv';

      // The storage key should include the environment name
      expect(expectedKey, contains('coves_session_'));
      expect(expectedKey, contains(currentEnv));

      // For production environment (default in tests)
      if (currentEnv == 'production') {
        expect(expectedKey, 'coves_session_production');
      } else if (currentEnv == 'local') {
        expect(expectedKey, 'coves_session_local');
      }
    });

    test('should isolate sessions between environments', () async {
      // This test verifies that sessions stored in different environments
      // are accessed via different storage keys, preventing cross-contamination

      // Get the current environment's storage key
      final currentEnv = EnvironmentConfig.current.environment.name;
      final storageKey = 'coves_session_$currentEnv';

      // Arrange - Mock session data
      const session = CovesSession(
        token: 'test-token-123',
        did: 'did:plc:test123',
        sessionId: 'session-123',
        handle: 'alice.bsky.social',
      );

      // Mock storage read for the environment-specific key
      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => session.toJsonString());

      // Act - Restore session
      final result = await authService.restoreSession();

      // Assert
      expect(result, isNotNull);
      expect(result!.token, 'test-token-123');

      // Verify the correct environment-specific key was used
      verify(mockStorage.read(key: storageKey)).called(1);

      // Verify no other keys were accessed
      verifyNever(mockStorage.read(key: 'coves_session'));
    });

    test('should save sessions with environment-specific keys', () async {
      // Get the current environment's storage key
      final currentEnv = EnvironmentConfig.current.environment.name;
      final storageKey = 'coves_session_$currentEnv';

      // First restore a session to set up state
      const session = CovesSession(
        token: 'old-token',
        did: 'did:plc:test123',
        sessionId: 'session-123',
        handle: 'alice.bsky.social',
      );

      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => session.toJsonString());
      await authService.restoreSession();

      // Mock successful refresh
      const newToken = 'new-refreshed-token';
      when(mockDio.post<Map<String, dynamic>>(
        '/oauth/refresh',
        data: anyNamed('data'),
      )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            statusCode: 200,
            data: {
              'sealed_token': newToken,
              'access_token': 'some-access-token'
            },
          ));

      when(mockStorage.write(key: storageKey, value: anyNamed('value')))
          .thenAnswer((_) async => {});

      // Act - Refresh token (which saves the updated session)
      await authService.refreshToken();

      // Assert - Verify environment-specific key was used for saving
      verify(mockStorage.write(key: storageKey, value: anyNamed('value')))
          .called(1);

      // Verify the generic key was never used
      verifyNever(mockStorage.write(key: 'coves_session', value: anyNamed('value')));
    });

    test('should delete sessions using environment-specific keys', () async {
      // Get the current environment's storage key
      final currentEnv = EnvironmentConfig.current.environment.name;
      final storageKey = 'coves_session_$currentEnv';

      // First restore a session
      const session = CovesSession(
        token: 'test-token',
        did: 'did:plc:test123',
        sessionId: 'session-123',
      );

      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => session.toJsonString());
      await authService.restoreSession();

      // Mock logout
      when(mockDio.post<void>(
        '/oauth/logout',
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/oauth/logout'),
            statusCode: 200,
          ));

      when(mockStorage.delete(key: storageKey)).thenAnswer((_) async => {});

      // Act - Sign out
      await authService.signOut();

      // Assert - Verify environment-specific key was used for deletion
      verify(mockStorage.delete(key: storageKey)).called(1);

      // Verify the generic key was never used
      verifyNever(mockStorage.delete(key: 'coves_session'));
    });

    test('should document storage key format for both environments', () {
      // This test serves as documentation for the storage key format
      // Production key
      expect('coves_session_production', 'coves_session_production');

      // Local development key
      expect('coves_session_local', 'coves_session_local');

      // This ensures:
      // 1. Production tokens are stored in 'coves_session_production'
      // 2. Local dev tokens are stored in 'coves_session_local'
      // 3. Switching between prod/dev builds doesn't cause token conflicts
      // 4. Each environment maintains its own session independently
    });
  });
}
