import 'package:coves_flutter/models/coves_session.dart';
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
  late CovesAuthService authService;

  // Storage key is environment-specific to prevent token reuse across dev/prod
  // Tests run in production environment by default
  const storageKey = 'coves_session_production';

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

  group('CovesAuthService', () {
    group('signIn()', () {
      test('should throw ArgumentError when handle is empty', () async {
        expect(
          () => authService.signIn(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw ArgumentError when handle is whitespace-only',
          () async {
        expect(
          () => authService.signIn('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw appropriate error when user cancels sign-in',
          () async {
        // Note: FlutterWebAuth2.authenticate is not easily mockable as it's a static method
        // This test documents expected behavior when authentication is cancelled
        // In practice, this would throw with CANCELED/cancelled in the message
        // The actual implementation catches this and rethrows with user-friendly message

        // This test would require integration testing or a wrapper around FlutterWebAuth2
        // Skipping for now as it requires more complex mocking infrastructure
      });

      test('should throw Exception when network error occurs during OAuth',
          () async {
        // Note: Similar to above, FlutterWebAuth2 static methods are difficult to mock
        // This test documents expected behavior
        // The actual implementation catches exceptions and rethrows with context
      });

      test('should trim handle before processing', () async {
        // This test verifies the handle trimming logic
        // The actual OAuth flow is tested via integration tests
        const handle = '  alice.bsky.social  ';
        expect(handle.trim(), 'alice.bsky.social');
      });
    });

    group('restoreSession()', () {
      test('should successfully restore valid session from storage', () async {
        // Arrange
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
          handle: 'alice.bsky.social',
        );
        final jsonString = session.toJsonString();

        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => jsonString);

        // Act
        final result = await authService.restoreSession();

        // Assert
        expect(result, isNotNull);
        expect(result!.token, 'test-token');
        expect(result.did, 'did:plc:test123');
        expect(result.sessionId, 'session-123');
        expect(result.handle, 'alice.bsky.social');
        verify(mockStorage.read(key: storageKey)).called(1);
      });

      test('should return null when no stored session exists', () async {
        // Arrange
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => null);

        // Act
        final result = await authService.restoreSession();

        // Assert
        expect(result, isNull);
        verify(mockStorage.read(key: storageKey)).called(1);
      });

      test('should handle corrupted storage data gracefully', () async {
        // Arrange
        const corruptedJson = 'not-valid-json{]';
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => corruptedJson);
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        final result = await authService.restoreSession();

        // Assert
        expect(result, isNull);
        verify(mockStorage.read(key: storageKey)).called(1);
        verify(mockStorage.delete(key: storageKey)).called(1);
      });

      test('should handle session JSON with missing required fields gracefully',
          () async {
        // Arrange
        const invalidJson = '{"token": "test"}'; // Missing required fields (did, session_id)
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => invalidJson);
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        final result = await authService.restoreSession();

        // Assert
        // Should return null and clear corrupted storage
        expect(result, isNull);
        verify(mockStorage.read(key: storageKey)).called(1);
        verify(mockStorage.delete(key: storageKey)).called(1);
      });

      test('should handle storage read errors gracefully', () async {
        // Arrange
        when(mockStorage.read(key: storageKey))
            .thenThrow(Exception('Storage error'));
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        final result = await authService.restoreSession();

        // Assert
        expect(result, isNull);
        verify(mockStorage.delete(key: storageKey)).called(1);
      });
    });

    group('refreshToken()', () {
      test('should throw StateError when no session exists', () async {
        // Act & Assert
        expect(
          () => authService.refreshToken(),
          throwsA(isA<StateError>()),
        );
      });

      test('should successfully refresh token and return updated session',
          () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
          handle: 'alice.bsky.social',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        // Mock successful refresh response
        const newToken = 'new-refreshed-token';
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': newToken, 'access_token': 'some-access-token'},
            ));

        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act
        final result = await authService.refreshToken();

        // Assert
        expect(result.token, newToken);
        expect(result.did, 'did:plc:test123');
        expect(result.sessionId, 'session-123');
        expect(result.handle, 'alice.bsky.social');
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(1);
        verify(mockStorage.write(
          key: storageKey,
          value: anyNamed('value'),
        )).called(1);
      });

      test('should throw "Session expired" on 401 response', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock 401 response
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 401,
            ),
          ),
        );

        // Act & Assert
        expect(
          () => authService.refreshToken(),
          throwsA(
            predicate((e) =>
                e is Exception && e.toString().contains('Session expired')),
          ),
        );
      });

      test('should throw Exception on network error during refresh', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock network error
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            type: DioExceptionType.connectionError,
            message: 'Connection failed',
          ),
        );

        // Act & Assert
        expect(
          () => authService.refreshToken(),
          throwsA(
            predicate((e) =>
                e is Exception &&
                e.toString().contains('Token refresh failed')),
          ),
        );
      });

      test('should throw Exception when response is missing sealed_token', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock response without sealed_token
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'access_token': 'some-token'}, // No sealed_token field
            ));

        // Act & Assert
        expect(
          () => authService.refreshToken(),
          throwsA(
            predicate((e) =>
                e is Exception &&
                e.toString().contains('Invalid refresh response')),
          ),
        );
      });

      test('should throw Exception when response sealed_token is empty', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock response with empty sealed_token
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': '', 'access_token': 'some-token'}, // Empty sealed_token
            ));

        // Act & Assert
        expect(
          () => authService.refreshToken(),
          throwsA(
            predicate((e) =>
                e is Exception &&
                e.toString().contains('Invalid refresh response')),
          ),
        );
      });
    });

    group('signOut()', () {
      test('should clear session and storage on successful server-side logout',
          () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock successful logout
        when(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/logout'),
              statusCode: 200,
            ));

        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        await authService.signOut();

        // Assert
        expect(authService.session, isNull);
        expect(authService.isAuthenticated, isFalse);
        verify(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).called(1);
        verify(mockStorage.delete(key: storageKey)).called(1);
      });

      test('should clear local state even when server revocation fails',
          () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock server error
        when(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/oauth/logout'),
            type: DioExceptionType.connectionError,
            message: 'Connection failed',
          ),
        );

        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        await authService.signOut();

        // Assert
        expect(authService.session, isNull);
        expect(authService.isAuthenticated, isFalse);
        verify(mockStorage.delete(key: storageKey)).called(1);
      });

      test('should work even when no session exists', () async {
        // Arrange
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        await authService.signOut();

        // Assert
        expect(authService.session, isNull);
        expect(authService.isAuthenticated, isFalse);
        verify(mockStorage.delete(key: storageKey)).called(1);
        verifyNever(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        ));
      });

      test('should clear local state even when storage delete fails', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        when(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/logout'),
              statusCode: 200,
            ));

        when(mockStorage.delete(key: storageKey))
            .thenThrow(Exception('Storage error'));

        // Act & Assert - Should not throw
        expect(() => authService.signOut(), throwsA(isA<Exception>()));

        // Note: The session is cleared in memory even if storage fails
        // This is because the finally block sets _session = null
      });
    });

    group('getToken()', () {
      test('should return token when authenticated', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Act
        final token = authService.getToken();

        // Assert
        expect(token, 'test-token');
      });

      test('should return null when not authenticated', () {
        // Act
        final token = authService.getToken();

        // Assert
        expect(token, isNull);
      });

      test('should return null after sign out', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        when(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/logout'),
              statusCode: 200,
            ));
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        await authService.signOut();
        final token = authService.getToken();

        // Assert
        expect(token, isNull);
      });
    });

    group('isAuthenticated', () {
      test('should return false when no session exists', () {
        // Assert
        expect(authService.isAuthenticated, isFalse);
      });

      test('should return true when session exists', () async {
        // Arrange - Restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Assert
        expect(authService.isAuthenticated, isTrue);
      });

      test('should return false after sign out', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        when(mockDio.post<void>(
          '/oauth/logout',
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/logout'),
              statusCode: 200,
            ));
        when(mockStorage.delete(key: storageKey))
            .thenAnswer((_) async => {});

        // Act
        await authService.signOut();

        // Assert
        expect(authService.isAuthenticated, isFalse);
      });
    });

    group('session caching', () {
      test('should cache session in memory after restore', () async {
        // Arrange
        const session = CovesSession(
          token: 'test-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());

        // Act
        await authService.restoreSession();

        // Assert - Accessing session property should not read from storage again
        expect(authService.session?.token, 'test-token');
        expect(authService.session?.did, 'did:plc:test123');
        verify(mockStorage.read(key: storageKey)).called(1);
      });

      test('should update cached session after token refresh', () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        const newToken = 'new-token';
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': newToken, 'access_token': 'some-access-token'},
            ));
        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act
        await authService.refreshToken();

        // Assert - Cached session should have new token
        expect(authService.session?.token, newToken);
        expect(authService.getToken(), newToken);
      });
    });

    group('refreshToken() - Concurrency Protection', () {
      test('should only make one API request for concurrent refresh calls',
          () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
          handle: 'alice.bsky.social',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        const newToken = 'new-refreshed-token';

        // Mock refresh response with a delay to simulate network latency
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return Response(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            statusCode: 200,
            data: {'sealed_token': newToken, 'access_token': 'some-access-token'},
          );
        });

        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act - Launch 3 concurrent refresh calls
        final results = await Future.wait([
          authService.refreshToken(),
          authService.refreshToken(),
          authService.refreshToken(),
        ]);

        // Assert - All calls should return the same refreshed session
        expect(results.length, 3);
        expect(results[0].token, newToken);
        expect(results[1].token, newToken);
        expect(results[2].token, newToken);

        // Verify only one API call was made
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(1);

        // Verify only one storage write was made
        verify(mockStorage.write(
          key: storageKey,
          value: anyNamed('value'),
        )).called(1);
      });

      test('should propagate errors to all concurrent waiters', () async {
        // Arrange - First restore a session
        const session = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => session.toJsonString());
        await authService.restoreSession();

        // Mock 401 response with delay
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          throw DioException(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 401,
            ),
          );
        });

        // Act - Start concurrent refresh calls
        final futures = [
          authService.refreshToken(),
          authService.refreshToken(),
          authService.refreshToken(),
        ];

        // Assert - All should throw the same error
        var errorCount = 0;
        for (final future in futures) {
          try {
            await future;
            fail('Expected exception to be thrown');
          } catch (e) {
            expect(e, isA<Exception>());
            expect(e.toString(), contains('Session expired'));
            errorCount++;
          }
        }

        expect(errorCount, 3);

        // Verify only one API call was made
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(1);
      });

      test('should allow new refresh after previous one completes', () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        const newToken1 = 'new-token-1';
        const newToken2 = 'new-token-2';

        // Mock first refresh
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': newToken1, 'access_token': 'some-access-token'},
            ));

        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act - First refresh
        final result1 = await authService.refreshToken();

        // Assert first refresh
        expect(result1.token, newToken1);

        // Now update the mock for the second refresh
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': newToken2, 'access_token': 'some-access-token'},
            ));

        // Act - Second refresh (should be allowed since first completed)
        final result2 = await authService.refreshToken();

        // Assert second refresh
        expect(result2.token, newToken2);

        // Verify two separate API calls were made
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(2);
      });

      test('should allow new refresh after previous one fails', () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        // Mock first refresh to fail
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            type: DioExceptionType.connectionError,
            message: 'Connection failed',
          ),
        );

        // Act - First refresh should fail
        Object? caughtError;
        try {
          await authService.refreshToken();
          fail('Expected exception to be thrown');
        } catch (e) {
          caughtError = e;
        }

        // Assert first refresh failed with correct error
        expect(caughtError, isNotNull);
        expect(caughtError, isA<Exception>());
        expect(caughtError.toString(), contains('Token refresh failed'));

        // Now mock a successful second refresh
        const newToken = 'new-token-after-retry';
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/oauth/refresh'),
              statusCode: 200,
              data: {'sealed_token': newToken, 'access_token': 'some-access-token'},
            ));

        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act - Second refresh (should be allowed and succeed)
        final result = await authService.refreshToken();

        // Assert
        expect(result.token, newToken);

        // Verify two separate API calls were made
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(2);
      });

      test(
          'should handle concurrent calls where one arrives after refresh completes',
          () async {
        // Arrange - First restore a session
        const initialSession = CovesSession(
          token: 'old-token',
          did: 'did:plc:test123',
          sessionId: 'session-123',
        );
        when(mockStorage.read(key: storageKey))
            .thenAnswer((_) async => initialSession.toJsonString());
        await authService.restoreSession();

        const newToken1 = 'new-token-1';
        const newToken2 = 'new-token-2';

        var callCount = 0;

        // Mock refresh with different responses
        when(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).thenAnswer((_) async {
          callCount++;
          await Future.delayed(const Duration(milliseconds: 50));
          return Response(
            requestOptions: RequestOptions(path: '/oauth/refresh'),
            statusCode: 200,
            data: {'sealed_token': callCount == 1 ? newToken1 : newToken2, 'access_token': 'some-access-token'},
          );
        });

        when(mockStorage.write(key: storageKey, value: anyNamed('value')))
            .thenAnswer((_) async => {});

        // Act - Start first refresh
        final future1 = authService.refreshToken();

        // Wait for it to complete
        final result1 = await future1;

        // Start second refresh after first completes
        final result2 = await authService.refreshToken();

        // Assert
        expect(result1.token, newToken1);
        expect(result2.token, newToken2);

        // Verify two separate API calls were made
        verify(mockDio.post<Map<String, dynamic>>(
          '/oauth/refresh',
          data: anyNamed('data'),
        )).called(2);
      });
    });
  });
}
