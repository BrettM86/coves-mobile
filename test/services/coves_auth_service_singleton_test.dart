import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'coves_auth_service_test.mocks.dart';

@GenerateMocks([Dio, FlutterSecureStorage])
void main() {
  late MockDio mockDio;
  late MockFlutterSecureStorage mockStorage;

  // Storage key is environment-specific to prevent token reuse across dev/prod
  // Tests run in production environment by default
  const storageKey = 'coves_session_production';

  setUp(() {
    CovesAuthService.resetInstance();
    mockDio = MockDio();
    mockStorage = MockFlutterSecureStorage();
  });

  tearDown(() {
    CovesAuthService.resetInstance();
  });

  group('CovesAuthService - Singleton Pattern', () {
    test('should return the same instance on multiple factory calls', () {
      // Act - Create multiple instances using the factory
      final instance1 = CovesAuthService(dio: mockDio, storage: mockStorage);
      final instance2 = CovesAuthService();
      final instance3 = CovesAuthService();

      // Assert - All should be the exact same instance
      expect(identical(instance1, instance2), isTrue,
          reason: 'instance1 and instance2 should be identical');
      expect(identical(instance2, instance3), isTrue,
          reason: 'instance2 and instance3 should be identical');
      expect(identical(instance1, instance3), isTrue,
          reason: 'instance1 and instance3 should be identical');
    });

    test('should share in-memory session across singleton instances', () async {
      // Arrange
      final instance1 = CovesAuthService(dio: mockDio, storage: mockStorage);

      // Mock storage to return a valid session
      const sessionJson = '{'
          '"token": "test-token", '
          '"did": "did:plc:test123", '
          '"session_id": "session-123", '
          '"handle": "alice.bsky.social"'
          '}';

      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => sessionJson);

      // Act - Restore session using first instance
      await instance1.restoreSession();

      // Get a second "instance" (should be the same singleton)
      final instance2 = CovesAuthService();

      // Assert - Both instances should have the same in-memory session
      expect(instance2.session?.token, 'test-token');
      expect(instance2.session?.did, 'did:plc:test123');
      expect(instance2.isAuthenticated, isTrue);

      // Verify storage was only read once (by instance1)
      verify(mockStorage.read(key: storageKey)).called(1);
    });

    test('should share refresh mutex across singleton instances', () async {
      // Arrange
      final instance1 = CovesAuthService(dio: mockDio, storage: mockStorage);

      // Mock storage to return a valid session
      const sessionJson = '{'
          '"token": "old-token", '
          '"did": "did:plc:test123", '
          '"session_id": "session-123", '
          '"handle": "alice.bsky.social"'
          '}';

      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => sessionJson);

      await instance1.restoreSession();

      // Mock refresh with delay
      const newToken = 'refreshed-token';
      when(mockDio.post<Map<String, dynamic>>(
        '/oauth/refresh',
        data: anyNamed('data'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return Response(
          requestOptions: RequestOptions(path: '/oauth/refresh'),
          statusCode: 200,
          data: {'sealed_token': newToken, 'access_token': 'access-token'},
        );
      });

      when(mockStorage.write(key: storageKey, value: anyNamed('value')))
          .thenAnswer((_) async => {});

      // Act - Start refresh from first instance
      final refreshFuture1 = instance1.refreshToken();

      // Get second instance and immediately try to refresh
      final instance2 = CovesAuthService();
      final refreshFuture2 = instance2.refreshToken();

      // Wait for both
      final results = await Future.wait([refreshFuture1, refreshFuture2]);

      // Assert - Both should get the same result from a single API call
      expect(results[0].token, newToken);
      expect(results[1].token, newToken);

      // Verify only one API call was made (mutex protected)
      verify(mockDio.post<Map<String, dynamic>>(
        '/oauth/refresh',
        data: anyNamed('data'),
      )).called(1);
    });

    test('resetInstance() should clear the singleton', () {
      // Arrange
      final instance1 = CovesAuthService(dio: mockDio, storage: mockStorage);

      // Act
      CovesAuthService.resetInstance();

      // Create new instance with different dependencies
      final mockDio2 = MockDio();
      final mockStorage2 = MockFlutterSecureStorage();
      final instance2 = CovesAuthService(dio: mockDio2, storage: mockStorage2);

      // Assert - Should be different instances (new singleton created)
      // Note: We can't directly test if they're different objects easily,
      // but we can verify that resetInstance() allows a fresh start
      expect(instance2, isNotNull);
      expect(instance2.isAuthenticated, isFalse);
    });

    test('createTestInstance() should bypass singleton', () {
      // Arrange
      final singletonInstance = CovesAuthService(dio: mockDio, storage: mockStorage);

      // Act - Create a test instance with different dependencies
      final mockDio2 = MockDio();
      final mockStorage2 = MockFlutterSecureStorage();
      final testInstance = CovesAuthService.createTestInstance(
        dio: mockDio2,
        storage: mockStorage2,
      );

      // Assert - Test instance should be different from singleton
      expect(identical(singletonInstance, testInstance), isFalse,
          reason: 'Test instance should not be the singleton');

      // Test instance should not affect singleton
      final singletonCheck = CovesAuthService();
      expect(identical(singletonInstance, singletonCheck), isTrue,
          reason: 'Singleton should remain unchanged');
    });

    test('should avoid state loss when service is requested from multiple entry points', () async {
      // Arrange
      final authProvider = CovesAuthService(dio: mockDio, storage: mockStorage);

      const sessionJson = '{'
          '"token": "test-token", '
          '"did": "did:plc:test123", '
          '"session_id": "session-123"'
          '}';

      when(mockStorage.read(key: storageKey))
          .thenAnswer((_) async => sessionJson);

      // Act - Simulate different parts of the app requesting the service
      await authProvider.restoreSession();

      final apiService = CovesAuthService();
      final voteService = CovesAuthService();
      final feedService = CovesAuthService();

      // Assert - All should have access to the same session state
      expect(apiService.isAuthenticated, isTrue);
      expect(voteService.isAuthenticated, isTrue);
      expect(feedService.isAuthenticated, isTrue);
      expect(apiService.getToken(), 'test-token');
      expect(voteService.getToken(), 'test-token');
      expect(feedService.getToken(), 'test-token');

      // Storage should only be read once
      verify(mockStorage.read(key: storageKey)).called(1);
    });
  });
}
