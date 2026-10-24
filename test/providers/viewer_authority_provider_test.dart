import 'dart:async';

import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

/// Reproduces the real AuthProvider's sign-in and sign-out sequence: one
/// notification with isLoading true and the DID unchanged, then one with
/// isLoading false and the session settled.
class _LoadingAuthProvider extends FakeAuthProvider {
  bool _isLoading = false;

  @override
  bool get isLoading => _isLoading;

  void startLoading() {
    _isLoading = true;
    notifyListeners();
  }

  void finishLoading({required String? did}) {
    _isLoading = false;
    setSignedInDid(did);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'B3 restored session eagerly loads authority through the real service',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.next(options);
          },
        ),
      );
      DioAdapter(dio: dio).onGet(
        '/xrpc/social.coves.actor.getViewerAuthority',
        (server) => server.reply(200, {'instanceAdmin': true}),
      );
      final service = CovesApiService(
        sessionKeyOf: () => null,
        dio: dio,
        tokenGetter: () async => null,
      );
      final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
      final provider = ViewerAuthorityProvider(
        apiService: service,
        authProvider: auth,
      );
      addTearDown(() {
        provider.dispose();
        auth.dispose();
        service.dispose();
      });
      final seen = <ViewerAuthorityStatus>[];
      provider.addListener(() => seen.add(provider.status));

      expect(provider.status, ViewerAuthorityStatus.loading);
      await pumpEventQueue();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.path,
        '/xrpc/social.coves.actor.getViewerAuthority',
      );
      expect(requests.single.queryParameters, isEmpty);
      expect(provider.status, ViewerAuthorityStatus.instanceAdmin);
      expect(provider.isInstanceAdmin, true);
      expect(seen, [ViewerAuthorityStatus.instanceAdmin]);
    },
  );

  group('ViewerAuthorityProvider lifecycle', () {
    late _LoadingAuthProvider auth;
    late MockCovesApiService api;
    late ViewerAuthorityProvider provider;
    late List<ViewerAuthorityStatus> seen;

    void createProvider({bool disposeInTest = false}) {
      provider = ViewerAuthorityProvider(apiService: api, authProvider: auth);
      seen = [];
      provider.addListener(() => seen.add(provider.status));
      if (!disposeInTest) {
        addTearDown(() => provider.dispose());
      }
    }

    setUp(() {
      auth = _LoadingAuthProvider();
      api = MockCovesApiService();
      addTearDown(() => auth.dispose());
    });

    test('B4 signed out does not request authority, even on refresh', () async {
      createProvider();

      expect(provider.status, ViewerAuthorityStatus.signedOut);
      verifyNever(api.getViewerAuthority());
      await provider.refresh();
      expect(provider.status, ViewerAuthorityStatus.signedOut);
      expect(seen, isEmpty);
      verifyNever(api.getViewerAuthority());
    });

    test('B4 sign-in loads once and exposes a non-admin answer', () async {
      final answer = Completer<bool>();
      when(api.getViewerAuthority()).thenAnswer((_) => answer.future);
      createProvider();

      auth.setSignedInDid('did:plc:alice');
      expect(provider.status, ViewerAuthorityStatus.loading);
      answer.complete(false);
      await pumpEventQueue();

      expect(seen, [
        ViewerAuthorityStatus.loading,
        ViewerAuthorityStatus.notAdmin,
      ]);
      expect(provider.status, ViewerAuthorityStatus.notAdmin);
      expect(provider.isInstanceAdmin, false);
      verify(api.getViewerAuthority()).called(1);
    });

    test('B4 sign-out clears known authority without a new request', () async {
      when(api.getViewerAuthority()).thenAnswer((_) async => true);
      auth.setSignedInDid('did:plc:alice');
      createProvider();
      await pumpEventQueue();
      seen.clear();

      auth.setSignedInDid(null);
      expect(seen, [ViewerAuthorityStatus.signedOut]);
      expect(provider.status, ViewerAuthorityStatus.signedOut);
      expect(provider.isInstanceAdmin, false);
      verify(api.getViewerAuthority()).called(1);
    });

    test('B4 DID change reloads authority for the new account', () async {
      when(api.getViewerAuthority())
          .thenAnswer((_) async => auth.did == 'did:plc:alice');
      auth.setSignedInDid('did:plc:alice');
      createProvider();
      await pumpEventQueue();
      seen.clear();

      auth.setSignedInDid('did:plc:bob');
      await pumpEventQueue();
      expect(seen, [
        ViewerAuthorityStatus.loading,
        ViewerAuthorityStatus.notAdmin,
      ]);
      expect(provider.status, ViewerAuthorityStatus.notAdmin);
      verify(api.getViewerAuthority()).called(2);
    });

    for (final row in [
      (
        name: 'sign-out discards a late admin answer',
        action: 'signOut',
        lateAnswer: true,
        beforeLate: ViewerAuthorityStatus.signedOut,
        seenBeforeLate: [ViewerAuthorityStatus.signedOut],
      ),
      (
        name: 'sign-out discards a late 503 failure',
        action: 'signOut',
        lateAnswer: null,
        beforeLate: ViewerAuthorityStatus.signedOut,
        seenBeforeLate: [ViewerAuthorityStatus.signedOut],
      ),
      (
        name: 'DID change discards a late admin answer',
        action: 'changeDid',
        lateAnswer: true,
        beforeLate: ViewerAuthorityStatus.notAdmin,
        seenBeforeLate: [
          ViewerAuthorityStatus.loading,
          ViewerAuthorityStatus.notAdmin,
        ],
      ),
      (
        name: 'DID change discards a late 503 failure',
        action: 'changeDid',
        lateAnswer: null,
        beforeLate: ViewerAuthorityStatus.notAdmin,
        seenBeforeLate: [
          ViewerAuthorityStatus.loading,
          ViewerAuthorityStatus.notAdmin,
        ],
      ),
      (
        name: 'sign-out and same-DID sign-in discard the first answer',
        action: 'returnToAlice',
        lateAnswer: true,
        beforeLate: ViewerAuthorityStatus.loading,
        seenBeforeLate: [
          ViewerAuthorityStatus.signedOut,
          ViewerAuthorityStatus.loading,
        ],
      ),
      (
        name: 'revocation discards a late admin answer',
        action: 'revoke',
        lateAnswer: true,
        beforeLate: ViewerAuthorityStatus.revoked,
        seenBeforeLate: [ViewerAuthorityStatus.revoked],
      ),
      (
        name: 'revocation discards a late non-admin answer',
        action: 'revoke',
        lateAnswer: false,
        beforeLate: ViewerAuthorityStatus.revoked,
        seenBeforeLate: [ViewerAuthorityStatus.revoked],
      ),
    ]) {
      test('B5 ${row.name}', () async {
        final firstAnswer = Completer<bool>();
        final secondAnswer = Completer<bool>();
        var requests = 0;
        when(api.getViewerAuthority()).thenAnswer(
          (_) => requests++ == 0 ? firstAnswer.future : secondAnswer.future,
        );
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        expect(provider.status, ViewerAuthorityStatus.loading);

        switch (row.action) {
          case 'signOut':
            auth.setSignedInDid(null);
          case 'changeDid':
            auth.setSignedInDid('did:plc:bob');
            secondAnswer.complete(false);
            await pumpEventQueue();
          case 'returnToAlice':
            auth
              ..setSignedInDid(null)
              ..setSignedInDid('did:plc:alice');
          case 'revoke':
            provider.markRevoked();
        }
        expect(provider.status, row.beforeLate);
        expect(seen, row.seenBeforeLate);

        if (row.lateAnswer == null) {
          firstAnswer.completeError(
            ServerException(
              'Unavailable',
              statusCode: 503,
              errorCode: 'ModerationUnavailable',
            ),
          );
        } else {
          firstAnswer.complete(row.lateAnswer);
        }
        await pumpEventQueue();

        expect(provider.status, row.beforeLate);
        expect(seen, row.seenBeforeLate);
        expect(provider.isInstanceAdmin, false);
        if (row.action == 'revoke') {
          expect(provider.isRevoked, true);
        }
        if (row.action == 'returnToAlice') {
          secondAnswer.complete(false);
          await pumpEventQueue();
          expect(provider.status, ViewerAuthorityStatus.notAdmin);
          expect(seen, [
            ViewerAuthorityStatus.signedOut,
            ViewerAuthorityStatus.loading,
            ViewerAuthorityStatus.notAdmin,
          ]);
        }
        verify(api.getViewerAuthority()).called(
          row.action == 'changeDid' || row.action == 'returnToAlice' ? 2 : 1,
        );
      });
    }

    test('B5 an answer that settles after dispose is ignored', () async {
      for (final row in [
        (name: 'admin answer', fails: false),
        (name: '503 failure', fails: true),
      ]) {
        final answer = Completer<bool>();
        when(api.getViewerAuthority()).thenAnswer((_) => answer.future);
        auth.setSignedInDid('did:plc:alice');
        createProvider(disposeInTest: true);
        expect(provider.status, ViewerAuthorityStatus.loading);
        verify(api.getViewerAuthority()).called(1);

        provider.dispose();
        if (row.fails) {
          answer.completeError(
            ServerException(
              'Unavailable',
              statusCode: 503,
              errorCode: 'ModerationUnavailable',
            ),
          );
        } else {
          answer.complete(true);
        }
        await pumpEventQueue();
        expect(seen, isEmpty, reason: row.name);
      }
    });

    for (final (label, error) in [
      (
        '503 ModerationUnavailable',
        ServerException(
          'Unavailable',
          statusCode: 503,
          errorCode: 'ModerationUnavailable',
        ),
      ),
      ('network failure', NetworkException('Offline')),
      ('authentication failure', AuthenticationException('Expired')),
    ]) {
      test(
        'B6 $label becomes unavailable and retries on token refresh',
        () async {
          var calls = 0;
          when(api.getViewerAuthority()).thenAnswer((_) async {
            calls++;
            if (calls == 1) {
              throw error;
            }
            return true;
          });
          auth.setSignedInDid('did:plc:alice');
          createProvider();
          await pumpEventQueue();

          expect(seen, [ViewerAuthorityStatus.unavailable]);
          expect(provider.status, ViewerAuthorityStatus.unavailable);
          auth.notifyWithoutChange();
          await pumpEventQueue();
          expect(seen, [
            ViewerAuthorityStatus.unavailable,
            ViewerAuthorityStatus.loading,
            ViewerAuthorityStatus.instanceAdmin,
          ]);
          expect(provider.status, ViewerAuthorityStatus.instanceAdmin);
          verify(api.getViewerAuthority()).called(2);
        },
      );
    }

    for (final (answer, expected) in [
      (true, ViewerAuthorityStatus.instanceAdmin),
      (false, ViewerAuthorityStatus.notAdmin),
    ]) {
      test('B6 known $expected ignores same-DID token refresh', () async {
        when(api.getViewerAuthority()).thenAnswer((_) async => answer);
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        await pumpEventQueue();
        seen.clear();

        auth.notifyWithoutChange();
        await pumpEventQueue();
        expect(provider.status, expected);
        expect(seen, isEmpty);
        verify(api.getViewerAuthority()).called(1);
      });
    }

    Future<void> reachUnavailable() async {
      var calls = 0;
      when(api.getViewerAuthority()).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw NetworkException('Offline');
        }
        return true;
      });
      auth.setSignedInDid('did:plc:alice');
      createProvider();
      await pumpEventQueue();
      expect(provider.status, ViewerAuthorityStatus.unavailable);
      verify(api.getViewerAuthority()).called(1);
      seen.clear();
    }

    test(
      'B6 sign-out from unavailable sends no request while auth is loading',
      () async {
        await reachUnavailable();

        auth.startLoading();
        await pumpEventQueue();
        verifyNever(api.getViewerAuthority());
        expect(seen, isEmpty);

        auth.finishLoading(did: null);
        await pumpEventQueue();
        expect(seen, [ViewerAuthorityStatus.signedOut]);
        expect(provider.status, ViewerAuthorityStatus.signedOut);
        verifyNever(api.getViewerAuthority());
      },
    );

    test(
      'B6 same-DID sign-in from unavailable retries only after auth settles',
      () async {
        await reachUnavailable();

        auth.startLoading();
        await pumpEventQueue();
        verifyNever(api.getViewerAuthority());
        expect(seen, isEmpty);
        expect(provider.status, ViewerAuthorityStatus.unavailable);

        auth.finishLoading(did: 'did:plc:alice');
        await pumpEventQueue();
        expect(seen, [
          ViewerAuthorityStatus.loading,
          ViewerAuthorityStatus.instanceAdmin,
        ]);
        verify(api.getViewerAuthority()).called(1);
      },
    );

    test(
      'B6 refresh from known admin reloads and exposes the new answer',
      () async {
        var calls = 0;
        when(api.getViewerAuthority()).thenAnswer((_) async {
          calls++;
          return calls == 1;
        });
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        await pumpEventQueue();
        expect(provider.status, ViewerAuthorityStatus.instanceAdmin);
        seen.clear();

        await provider.refresh();
        expect(seen, [
          ViewerAuthorityStatus.loading,
          ViewerAuthorityStatus.notAdmin,
        ]);
        expect(provider.status, ViewerAuthorityStatus.notAdmin);
        verify(api.getViewerAuthority()).called(2);
      },
    );

    test('B7 revocation while signed out is ignored', () {
      createProvider();

      provider.markRevoked();
      expect(provider.status, ViewerAuthorityStatus.signedOut);
      expect(provider.isRevoked, false);
      expect(seen, isEmpty);
    });

    test('B7 revocation notifies and removes admin authority', () async {
      when(api.getViewerAuthority()).thenAnswer((_) async => true);
      auth.setSignedInDid('did:plc:alice');
      createProvider();
      await pumpEventQueue();
      seen.clear();

      provider.markRevoked();
      expect(provider.status, ViewerAuthorityStatus.revoked);
      expect(provider.isRevoked, true);
      expect(provider.isInstanceAdmin, false);
      expect(seen, [ViewerAuthorityStatus.revoked]);
    });

    test(
      'B7 revoked ignores token refresh and survives a failed refresh',
      () async {
        var calls = 0;
        when(api.getViewerAuthority()).thenAnswer((_) async {
          calls++;
          if (calls == 1) {
            return true;
          }
          throw NetworkException('Offline');
        });
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        await pumpEventQueue();
        provider.markRevoked();
        seen.clear();

        auth.notifyWithoutChange();
        await pumpEventQueue();
        expect(provider.status, ViewerAuthorityStatus.revoked);
        expect(seen, isEmpty);
        verify(api.getViewerAuthority()).called(1);

        await provider.refresh();
        expect(provider.status, ViewerAuthorityStatus.revoked);
        expect(provider.isRevoked, true);
        verify(api.getViewerAuthority()).called(1);
      },
    );

    for (final (answer, expected) in [
      (true, ViewerAuthorityStatus.instanceAdmin),
      (false, ViewerAuthorityStatus.notAdmin),
    ]) {
      test('B7 successful refresh exits revoked to $expected', () async {
        var calls = 0;
        when(api.getViewerAuthority()).thenAnswer((_) async {
          calls++;
          return calls == 1 || answer;
        });
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        await pumpEventQueue();
        provider.markRevoked();
        seen.clear();

        await provider.refresh();
        expect(provider.status, expected);
        expect(provider.isRevoked, false);
        expect(seen, [expected]);
        verify(api.getViewerAuthority()).called(2);
      });
    }

    test('B7 DID change leaves revoked and fetches new authority', () async {
      when(api.getViewerAuthority())
          .thenAnswer((_) async => auth.did == 'did:plc:alice');
      auth.setSignedInDid('did:plc:alice');
      createProvider();
      await pumpEventQueue();
      provider.markRevoked();
      seen.clear();

      auth.setSignedInDid('did:plc:bob');
      await pumpEventQueue();
      expect(provider.status, ViewerAuthorityStatus.notAdmin);
      expect(provider.isRevoked, false);
      expect(seen, [
        ViewerAuthorityStatus.loading,
        ViewerAuthorityStatus.notAdmin,
      ]);
      verify(api.getViewerAuthority()).called(2);
    });

    test(
      'B7 sign-out and new sign-in leave revoked and fetch authority',
      () async {
        when(api.getViewerAuthority()).thenAnswer((_) async => true);
        auth.setSignedInDid('did:plc:alice');
        createProvider();
        await pumpEventQueue();
        provider.markRevoked();
        seen.clear();

        auth
          ..setSignedInDid(null)
          ..setSignedInDid('did:plc:alice');
        await pumpEventQueue();
        expect(provider.status, ViewerAuthorityStatus.instanceAdmin);
        expect(provider.isRevoked, false);
        expect(seen, [
          ViewerAuthorityStatus.signedOut,
          ViewerAuthorityStatus.loading,
          ViewerAuthorityStatus.instanceAdmin,
        ]);
        verify(api.getViewerAuthority()).called(2);
      },
    );
  });
}
