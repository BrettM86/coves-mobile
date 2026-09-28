import 'dart:async';

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
        when(mockAuthService.restoreSession())
            .thenAnswer((_) async => mockSession);
        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.valid);

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, true);
        expect(authProvider.did, 'did:plc:test123');
        expect(authProvider.handle, 'test.user');

        // Let the background validation probe finish.
        await pumpEventQueue();
        expect(authProvider.isAuthenticated, true);
      });

      test('should handle initialization errors gracefully', () async {
        when(mockAuthService.initialize()).thenThrow(Exception('Init failed'));

        await authProvider.initialize();

        expect(authProvider.isAuthenticated, false);
        expect(authProvider.error, isNotNull);
        expect(authProvider.isLoading, false);
      });
    });

    group('startup session validation', () {
      const mockSession = CovesSession(
        token: 'mock_sealed_token',
        did: 'did:plc:test123',
        sessionId: 'session123',
        handle: 'test.user',
      );

      setUp(() {
        when(mockAuthService.initialize()).thenAnswer((_) async => {});
        when(mockAuthService.restoreSession())
            .thenAnswer((_) async => mockSession);
      });

      test('should stay signed in when the session validates', () async {
        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.valid);

        await authProvider.initialize();
        await pumpEventQueue();

        expect(authProvider.isAuthenticated, true);
        verify(mockAuthService.validateSession()).called(1);
        verifyNever(mockAuthService.refreshToken());
      });

      test(
        'should keep the session when validation is indeterminate (offline)',
        () async {
          when(mockAuthService.validateSession())
              .thenAnswer((_) async => SessionValidationResult.indeterminate);

          await authProvider.initialize();
          await pumpEventQueue();

          // Being offline is not evidence the session is dead.
          expect(authProvider.isAuthenticated, true);
          verifyNever(mockAuthService.refreshToken());
          verifyNever(mockAuthService.signOut());
        },
      );

      test('should refresh and stay signed in when the backend rejects the '
          'token but refresh succeeds', () async {
        const refreshedSession = CovesSession(
          token: 'refreshed_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'test.user',
        );

        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.invalid);
        when(mockAuthService.refreshToken())
            .thenAnswer((_) async => refreshedSession);

        await authProvider.initialize();
        await pumpEventQueue();

        expect(authProvider.isAuthenticated, true);
        expect(authProvider.session?.token, 'refreshed_sealed_token');
        verify(mockAuthService.refreshToken()).called(1);
      });

      test('should bump restoredSessionRecoveryCount when a rejected '
          'restored session is recovered by refresh', () async {
        const refreshedSession = CovesSession(
          token: 'refreshed_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'test.user',
        );

        final refreshGate = Completer<CovesSession>();
        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.invalid);
        when(mockAuthService.refreshToken())
            .thenAnswer((_) => refreshGate.future);

        await authProvider.initialize();
        await pumpEventQueue();
        expect(authProvider.restoredSessionRecoveryCount, 0);

        final countsSeenByListeners = <int>[];
        authProvider.addListener(
          () => countsSeenByListeners.add(
            authProvider.restoredSessionRecoveryCount,
          ),
        );
        refreshGate.complete(refreshedSession);
        await pumpEventQueue();

        // Same DID before and after, so listeners can only tell the
        // anonymous-served reads apart through this counter.
        expect(authProvider.did, 'did:plc:test123');
        expect(authProvider.restoredSessionRecoveryCount, 1);
        expect(countsSeenByListeners, [1]);
      });

      for (final result in [
        SessionValidationResult.valid,
        SessionValidationResult.indeterminate,
      ]) {
        test('should not bump restoredSessionRecoveryCount when validation '
            'is $result', () async {
          when(mockAuthService.validateSession())
              .thenAnswer((_) async => result);

          await authProvider.initialize();
          await pumpEventQueue();

          expect(authProvider.restoredSessionRecoveryCount, 0);
        });
      }

      test('should not bump restoredSessionRecoveryCount when the refresh '
          'after a rejected probe fails transiently', () async {
        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.invalid);
        when(mockAuthService.refreshToken())
            .thenThrow(Exception('Token refresh failed: 503'));

        await authProvider.initialize();
        await pumpEventQueue();

        expect(authProvider.restoredSessionRecoveryCount, 0);
      });

      group('when a 401 on another startup request refreshes first', () {
        const refreshedSession = CovesSession(
          token: 'refreshed_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'test.user',
        );

        test('should bump restoredSessionRecoveryCount once, and the rejected '
            'probe that resolves afterwards should not refresh '
            'again', () async {
          final validationGate = Completer<SessionValidationResult>();
          when(mockAuthService.validateSession())
              .thenAnswer((_) => validationGate.future);
          when(mockAuthService.refreshToken())
              .thenAnswer((_) async => refreshedSession);

          await authProvider.initialize();

          // The auth interceptor's refresh after a timeline 401.
          final refreshed = await authProvider.refreshToken();

          expect(refreshed, isTrue);
          expect(authProvider.did, 'did:plc:test123');
          expect(authProvider.restoredSessionRecoveryCount, 1);

          validationGate.complete(SessionValidationResult.invalid);
          await pumpEventQueue();

          expect(authProvider.session?.token, 'refreshed_sealed_token');
          expect(authProvider.restoredSessionRecoveryCount, 1);
          verify(mockAuthService.refreshToken()).called(1);
        });

        for (final probeAdoptsFirst in [true, false]) {
          test('should bump restoredSessionRecoveryCount once when the probe '
              'and the interceptor share one refresh (probe adopts it '
              '${probeAdoptsFirst ? 'first' : 'second'})', () async {
            final refreshGate = Completer<CovesSession>();
            final validationGate = Completer<SessionValidationResult>();
            when(mockAuthService.validateSession())
                .thenAnswer((_) => validationGate.future);
            // The service shares one in-flight refresh between callers.
            when(mockAuthService.refreshToken())
                .thenAnswer((_) => refreshGate.future);

            await authProvider.initialize();

            Future<bool>? interceptorRefresh;
            if (!probeAdoptsFirst) {
              interceptorRefresh = authProvider.refreshToken();
            }
            validationGate.complete(SessionValidationResult.invalid);
            await pumpEventQueue();
            interceptorRefresh ??= authProvider.refreshToken();

            final countsSeenByListeners = <int>[];
            authProvider.addListener(
              () => countsSeenByListeners.add(
                authProvider.restoredSessionRecoveryCount,
              ),
            );
            refreshGate.complete(refreshedSession);
            expect(await interceptorRefresh, isTrue);
            await pumpEventQueue();

            expect(authProvider.session?.token, 'refreshed_sealed_token');
            expect(authProvider.restoredSessionRecoveryCount, 1);
            expect(countsSeenByListeners.last, 1);
          });
        }

        test('should not bump restoredSessionRecoveryCount when the refresh '
            'lands after the probe accepted the restored token', () async {
          final refreshGate = Completer<CovesSession>();
          final validationGate = Completer<SessionValidationResult>();
          when(mockAuthService.validateSession())
              .thenAnswer((_) => validationGate.future);
          when(mockAuthService.refreshToken())
              .thenAnswer((_) => refreshGate.future);

          await authProvider.initialize();
          final interceptorRefresh = authProvider.refreshToken();

          validationGate.complete(SessionValidationResult.valid);
          await pumpEventQueue();
          refreshGate.complete(refreshedSession);

          expect(await interceptorRefresh, isTrue);
          expect(authProvider.session?.token, 'refreshed_sealed_token');
          expect(authProvider.restoredSessionRecoveryCount, 0);
        });

        test('should not bump restoredSessionRecoveryCount for a routine '
            'refresh after the probe accepted the restored token', () async {
          when(mockAuthService.validateSession())
              .thenAnswer((_) async => SessionValidationResult.valid);
          when(mockAuthService.refreshToken())
              .thenAnswer((_) async => refreshedSession);

          await authProvider.initialize();
          await pumpEventQueue();

          expect(await authProvider.refreshToken(), isTrue);
          expect(authProvider.restoredSessionRecoveryCount, 0);
        });
      });

      test('should sign out when the backend definitively rejects the token '
          'and the refresh 401s (dead session)', () async {
        when(mockAuthService.validateSession())
            .thenAnswer((_) async => SessionValidationResult.invalid);
        when(mockAuthService.refreshToken())
            .thenThrow(const SessionExpiredException());
        when(mockAuthService.signOut()).thenAnswer((_) async => {});

        await authProvider.initialize();
        await pumpEventQueue();

        // Dead session is cleared: listeners rebuild into signed-out UI
        // instead of silently degrading to anonymous browsing.
        expect(authProvider.isAuthenticated, false);
        expect(authProvider.session, isNull);
        verifyNever(mockAuthService.signOut());
      });

      test(
        'should keep the session when the refresh fails transiently after '
        'an invalid verdict (backend blip must not destroy a live session)',
        () async {
          when(mockAuthService.validateSession())
              .thenAnswer((_) async => SessionValidationResult.invalid);
          when(mockAuthService.refreshToken())
              .thenThrow(Exception('Token refresh failed: 503'));

          await authProvider.initialize();
          await pumpEventQueue();

          // The 401 verdict could itself be a transient backend failure;
          // only a refresh 401 (SessionExpiredException) proves death.
          expect(authProvider.isAuthenticated, true);
          expect(authProvider.session?.token, 'mock_sealed_token');
          verifyNever(mockAuthService.signOut());
        },
      );

      test('should not touch a NEW session when a stale invalid verdict '
          'resolves after sign-out + re-login', () async {
        const newSession = CovesSession(
          token: 'new_account_token',
          did: 'did:plc:other456',
          sessionId: 'session456',
          handle: 'other.user',
        );

        final validationGate = Completer<SessionValidationResult>();
        when(mockAuthService.validateSession())
            .thenAnswer((_) => validationGate.future);
        when(mockAuthService.signOut()).thenAnswer((_) async => {});
        when(mockAuthService.signIn('other.user'))
            .thenAnswer((_) async => newSession);

        await authProvider.initialize();

        // User signs out and into a different account while the old
        // session's probe is still in flight.
        await authProvider.signOut();
        await authProvider.signIn('other.user');
        clearInteractions(mockAuthService);

        validationGate.complete(SessionValidationResult.invalid);
        await pumpEventQueue();

        // The stale verdict must not refresh or sign out the new session.
        expect(authProvider.isAuthenticated, true);
        expect(authProvider.session?.token, 'new_account_token');
        verifyNever(mockAuthService.refreshToken());
        verifyNever(mockAuthService.signOut());
      });

      test(
        'should keep the session when the probe throws unexpectedly',
        () async {
          when(mockAuthService.validateSession())
              .thenThrow(Exception('unexpected'));

          await authProvider.initialize();
          await pumpEventQueue();

          // The outermost catch is a fire-and-forget boundary: a probe
          // failure must never crash startup or alter auth state.
          expect(authProvider.isAuthenticated, true);
          expect(authProvider.error, isNull);
          verifyNever(mockAuthService.signOut());
        },
      );

      test(
        'should ignore a stale invalid verdict after the user signed out',
        () async {
          final validationGate = Completer<SessionValidationResult>();
          when(mockAuthService.validateSession())
              .thenAnswer((_) => validationGate.future);
          when(mockAuthService.signOut()).thenAnswer((_) async => {});

          await authProvider.initialize();
          expect(authProvider.isAuthenticated, true);

          // User signs out while the probe is still in flight.
          await authProvider.signOut();
          clearInteractions(mockAuthService);

          validationGate.complete(SessionValidationResult.invalid);
          await pumpEventQueue();

          // The stale verdict must not trigger another refresh/sign-out.
          verifyNever(mockAuthService.refreshToken());
          verifyNever(mockAuthService.signOut());
        },
      );
    });

    group('signIn', () {
      test('should sign in successfully with valid handle', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
          handle: 'alice.bsky.social',
        );

        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);

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

      test(
        'should rethrow SignInCancelledException without setting error state',
        () async {
          when(mockAuthService.signIn('alice.bsky.social'))
              .thenThrow(const SignInCancelledException());

          // Record the error value at every notification: no notification
          // should ever carry an error state for a user cancel.
          final observedErrors = <String?>[];
          authProvider.addListener(() {
            observedErrors.add(authProvider.error);
          });

          await expectLater(
            authProvider.signIn('alice.bsky.social'),
            throwsA(isA<SignInCancelledException>()),
          );

          expect(authProvider.error, null);
          expect(authProvider.isLoading, false);
          expect(authProvider.isAuthenticated, false);
          expect(observedErrors, everyElement(isNull));
        },
      );

      test('should handle sign in errors', () async {
        when(mockAuthService.signIn('invalid.handle'))
            .thenThrow(Exception('Sign in failed'));

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
        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);

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

      for (final failure in <Object>[
        Exception('Revocation failed'),
        StateError('Plugin failed'),
      ]) {
        test(
          'retains state and allows retry after ${failure.runtimeType}',
          () async {
            // Sign in first
            const mockSession = CovesSession(
              token: 'mock_sealed_token',
              did: 'did:plc:test123',
              sessionId: 'session123',
              handle: 'alice.bsky.social',
            );
            when(mockAuthService.signIn('alice.bsky.social'))
                .thenAnswer((_) async => mockSession);

            await authProvider.signIn('alice.bsky.social');

            // Sign out with error
            when(mockAuthService.signOut()).thenThrow(failure);

            await authProvider.signOut();

            expect(authProvider.isAuthenticated, true);
            expect(authProvider.session, mockSession);
            expect(authProvider.error, "Couldn't sign out. Please try again.");
            expect(authProvider.isLoading, false);

            when(mockAuthService.signOut()).thenAnswer((_) async {});
            await authProvider.signOut();
            expect(authProvider.isAuthenticated, false);
            expect(authProvider.session, isNull);
            expect(authProvider.error, isNull);
            expect(authProvider.isLoading, false);
          },
        );
      }
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

        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);

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

        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);
        when(mockAuthService.refreshToken())
            .thenAnswer((_) async => refreshedSession);

        await authProvider.signIn('alice.bsky.social');
        final result = await authProvider.refreshToken();

        expect(result, true);
        expect(authProvider.session?.token, 'new_sealed_token');
        // A routine refresh is not a restored-session recovery: nothing was
        // served anonymously, so feeds must not refetch.
        expect(authProvider.restoredSessionRecoveryCount, 0);
      });

      test('should sign out when refresh is definitively rejected '
          '(SessionExpiredException)', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );

        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);
        when(mockAuthService.refreshToken())
            .thenThrow(const SessionExpiredException());
        when(mockAuthService.signOut()).thenAnswer((_) async => {});

        await authProvider.signIn('alice.bsky.social');
        final result = await authProvider.refreshToken();

        expect(result, false);
        expect(authProvider.isAuthenticated, false);
        verifyNever(mockAuthService.signOut());
      });

      test('should keep the session when refresh fails transiently', () async {
        const mockSession = CovesSession(
          token: 'mock_sealed_token',
          did: 'did:plc:test123',
          sessionId: 'session123',
        );

        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);
        when(mockAuthService.refreshToken())
            .thenThrow(Exception('Refresh failed: network error'));

        await authProvider.signIn('alice.bsky.social');
        final result = await authProvider.refreshToken();

        // A 5xx or network drop during refresh is not evidence the session
        // is dead - the user must stay signed in.
        expect(result, false);
        expect(authProvider.isAuthenticated, true);
        verifyNever(mockAuthService.signOut());
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
        when(mockAuthService.signIn('alice.bsky.social'))
            .thenAnswer((_) async => mockSession);

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
