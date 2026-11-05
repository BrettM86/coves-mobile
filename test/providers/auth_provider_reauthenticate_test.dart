import 'dart:async';

import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _oauthChannel = MethodChannel('flutter_web_auth_2');

const _aliceCallback =
    'social.coves:/callback?token=old-sealed-token&did=did:plc:alice'
    '&session_id=old-session-id&handle=alice.test';
const _aliceNoHandleCallback =
    'social.coves:/callback?token=old-sealed-token&did=did:plc:alice'
    '&session_id=old-session-id';
const _aliceNewCallback =
    'social.coves:/callback?token=new-sealed-token&did=did:plc:alice'
    '&session_id=new-session-id&handle=alice.test';
const _malloryCallback =
    'social.coves:/callback?token=mallory-sealed-token&did=did:plc:mallory'
    '&session_id=mallory-session-id&handle=mallory.test';
const _missingTokenCallback =
    'social.coves:/callback?did=did:plc:alice&session_id=new-session-id'
    '&handle=alice.test';

const _tokens = [
  'old-sealed-token',
  'new-sealed-token',
  'mallory-sealed-token',
  'refreshed-sealed-token',
];

/// Secure storage whose `write` throws once [armed], and whose next write
/// can be held at a gate; otherwise it uses the same in-memory mock store as
/// a plain `FlutterSecureStorage`.
class _ArmableWriteStorage extends FlutterSecureStorage {
  _ArmableWriteStorage();

  bool armed = false;
  Completer<void>? _gateReached;
  Completer<void>? _gate;

  /// Holds the next write until [releaseGate]; the returned future completes
  /// when that write has reached the gate. Later writes pass straight through.
  Future<void> gateNextWrite() {
    _gate = Completer<void>();
    _gateReached = Completer<void>();
    return _gateReached!.future;
  }

  void releaseGate() => _gate!.complete();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (armed) {
      throw PlatformException(code: 'write-failed');
    }
    final gate = _gate;
    final gateReached = _gateReached;
    if (gate != null && gateReached != null && !gateReached.isCompleted) {
      gateReached.complete();
      return gate.future.then((_) => super.write(key: key, value: value));
    }
    return super.write(key: key, value: value);
  }
}

class _Harness {
  _Harness(this.dio, this.storage, this.service, this.provider);

  final Dio dio;
  final _ArmableWriteStorage storage;
  final CovesAuthService service;
  final AuthProvider provider;
  final List<String> oauthUrls = [];
  final List<(bool, String?)> notifications = [];

  /// The bearer token each logout request carried.
  final List<String?> logoutTokens = [];

  /// Points the fake OAuth flow at [respond], recording each requested URL.
  void answerOAuth(Future<Object?> Function() respond) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_oauthChannel, (call) async {
          if (call.method != 'authenticate') {
            return null;
          }
          final args = call.arguments as Map<Object?, Object?>;
          oauthUrls.add(args['url']! as String);
          return respond();
        });
  }

  /// Holds the OAuth flow open until [release] is called with a callback
  /// URL; the returned future completes once the flow has been requested.
  Future<void> holdOAuth(Completer<String> release) {
    final reached = Completer<void>();
    answerOAuth(() {
      if (!reached.isCompleted) {
        reached.complete();
      }
      return release.future;
    });
    return reached.future;
  }

  /// Answers backend requests by path: `/oauth/refresh` with [refreshStatus]
  /// (200 returns `refreshed-sealed-token`) and `/oauth/logout` with 200.
  void answerBackend({int refreshStatus = 200}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/oauth/refresh') {
            if (refreshStatus == 200) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'sealed_token': 'refreshed-sealed-token',
                    'access_token': 'unused',
                  },
                ),
              );
            } else {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: refreshStatus,
                  ),
                ),
              );
            }
            return;
          }
          if (options.path == '/oauth/logout') {
            final header = options.headers['Authorization'] as String?;
            logoutTokens.add(header?.replaceFirst('Bearer ', ''));
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 200),
            );
            return;
          }
          handler.reject(
            DioException(requestOptions: options, error: 'unexpected'),
          );
        },
      ),
    );
  }

  /// Expects provider, service and storage all signed out.
  Future<void> expectSignedOutEverywhere() async {
    expect(provider.isAuthenticated, false);
    expect(provider.session, null);
    expect(service.session, null, reason: 'service session must stay null');
    expect(
      await storedSession() == null,
      true,
      reason: 'storage must be empty so a cold start stays signed out',
    );
  }

  /// Expects the session for [token] in provider, service and storage,
  /// compared by equality so token values are never printed.
  Future<void> expectSessionEverywhere(String token) async {
    final tokens = (
      provider.session?.token,
      service.session?.token,
      (await storedSession())?.$1,
    );
    expect(
      tokens == (token, token, token),
      true,
      reason:
          'mismatched locations (provider, service, storage): '
          '${(tokens.$1 != token, tokens.$2 != token, tokens.$3 != token)}',
    );
  }

  Future<ReauthenticationResult> reauthenticate() async {
    oauthUrls.clear();
    void listener() =>
        notifications.add((provider.isAuthenticated, provider.did));
    provider.addListener(listener);
    try {
      return await provider.reauthenticate();
    } finally {
      provider.removeListener(listener);
    }
  }

  Future<CovesSessionSnapshot?> storedSession() async {
    final fresh = CovesAuthService.createTestInstance(
      dio: Dio(),
      storage: const FlutterSecureStorage(),
    );
    final session = await fresh.restoreSession();
    return session == null
        ? null
        : (session.token, session.sessionId, session.did, session.handle);
  }
}

typedef CovesSessionSnapshot = (String, String, String, String?);

/// Signs in through the fake OAuth flow with [initialCallback] as
/// [signInInput].
Future<_Harness> _signedIn({
  String signInInput = 'alice.test',
  String initialCallback = _aliceCallback,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final storage = _ArmableWriteStorage();
  final dio = Dio();
  final service = CovesAuthService.createTestInstance(
    dio: dio,
    storage: storage,
  );
  final harness = _Harness(
    dio,
    storage,
    service,
    AuthProvider(authService: service),
  )..answerOAuth(() async => initialCallback);
  await harness.provider.signIn(signInInput);
  expect(harness.provider.isAuthenticated, true);
  expect(harness.provider.session?.token, 'old-sealed-token');
  return harness;
}

/// Runs [body] while capturing print and debugPrint output into [logs].
Future<void> _capturingLogs(
  List<String> logs,
  Future<void> Function() body,
) async {
  final originalDebugPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  try {
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logs.add(line),
      ),
    );
  } finally {
    debugPrint = originalDebugPrint;
  }
}

void _expectNoTokenLogged(List<String> logs) {
  for (final token in _tokens) {
    expect(
      logs.where((line) => line.contains(token)),
      isEmpty,
      reason: 'token $token must never be logged',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_oauthChannel, null);
  });

  group('AuthProvider.reauthenticate same account', () {
    test('replaces the session in provider, service and storage', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn();
        harness.answerOAuth(() async => _aliceNewCallback);

        final result = await harness.reauthenticate();

        expect(result, ReauthenticationResult.success);
        expect(harness.oauthUrls, hasLength(1));
        expect(harness.oauthUrls.single, contains('alice.test'));

        final providerSession = harness.provider.session!;
        expect(providerSession.token, 'new-sealed-token');
        expect(providerSession.sessionId, 'new-session-id');
        expect(providerSession.did, 'did:plc:alice');
        expect(providerSession.handle, 'alice.test');

        final serviceSession = harness.service.session!;
        expect(serviceSession.token, 'new-sealed-token');
        expect(serviceSession.sessionId, 'new-session-id');
        expect(serviceSession.did, 'did:plc:alice');
        expect(serviceSession.handle, 'alice.test');

        expect(await harness.storedSession(), (
          'new-sealed-token',
          'new-session-id',
          'did:plc:alice',
          'alice.test',
        ));

        expect(harness.provider.isAuthenticated, true);
        expect(harness.provider.error, null);
        expect(
          harness.notifications.every((n) => n == (true, 'did:plc:alice')),
          true,
          reason: 'notifications: ${harness.notifications}',
        );
      });
      _expectNoTokenLogged(logs);
    });

    test('a token refresh paused in its storage write does not overwrite '
        'the reauthenticated session', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn();
        harness.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path == '/oauth/refresh') {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'sealed_token': 'refreshed-sealed-token',
                      'access_token': 'unused',
                    },
                  ),
                );
                return;
              }
              handler.reject(
                DioException(requestOptions: options, error: 'unexpected'),
              );
            },
          ),
        );

        final refreshWriteReached = harness.storage.gateNextWrite();
        final refresh = harness.provider.refreshToken();
        await refreshWriteReached;

        harness.answerOAuth(() async => _aliceNewCallback);
        final result = await harness.reauthenticate();
        expect(result, ReauthenticationResult.success);

        harness.storage.releaseGate();
        await refresh;
        await pumpEventQueue();

        // (provider, service, storage) in one record so a failure names
        // every location the refresh overwrote. Compared by equality only;
        // token values are never printed on success.
        final tokens = (
          harness.provider.session?.token,
          harness.service.session?.token,
          (await harness.storedSession())?.$1,
        );
        const expected = 'new-sealed-token';
        final stale = (
          tokens.$1 != expected,
          tokens.$2 != expected,
          tokens.$3 != expected,
        );
        expect(
          tokens == (expected, expected, expected),
          true,
          reason: 'stale-token locations (provider, service, storage): $stale',
        );
      });
      _expectNoTokenLogged(logs);
    });

    test('signs in by DID when the session has no handle', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn(
          signInInput: 'did:plc:alice',
          initialCallback: _aliceNoHandleCallback,
        );
        expect(harness.provider.session?.handle, null);
        harness.answerOAuth(() async => _aliceNewCallback);

        final result = await harness.reauthenticate();

        expect(result, ReauthenticationResult.success);
        expect(harness.oauthUrls, hasLength(1));
        final url = Uri.decodeComponent(harness.oauthUrls.single);
        expect(url, contains('did:plc:alice'));
        expect(harness.provider.session?.token, 'new-sealed-token');
      });
      _expectNoTokenLogged(logs);
    });
  });

  group('AuthProvider.reauthenticate non-success outcomes', () {
    // (name, OAuth response, fail the storage write, expected result)
    final rows =
        <(String, Future<Object?> Function(), bool, ReauthenticationResult)>[
          (
            'cancel',
            () async => throw PlatformException(code: 'CANCELED'),
            false,
            ReauthenticationResult.cancelled,
          ),
          (
            'other platform failure',
            () async => throw PlatformException(code: 'NETWORK_ERROR'),
            false,
            ReauthenticationResult.failed,
          ),
          (
            'callback missing token',
            () async => _missingTokenCallback,
            false,
            ReauthenticationResult.failed,
          ),
          (
            'different DID',
            () async => _malloryCallback,
            false,
            ReauthenticationResult.differentAccount,
          ),
          (
            'storage write fails after same-DID callback',
            () async => _aliceNewCallback,
            true,
            ReauthenticationResult.failed,
          ),
        ];

    for (final (name, respond, failStorageWrite, expected) in rows) {
      test('$name leaves the current session unchanged', () async {
        final logs = <String>[];
        await _capturingLogs(logs, () async {
          final harness = await _signedIn();
          harness.answerOAuth(respond);
          harness.storage.armed = failStorageWrite;

          final result = await harness.reauthenticate();

          expect(result, expected);

          final providerSession = harness.provider.session!;
          expect(providerSession.token, 'old-sealed-token');
          expect(providerSession.did, 'did:plc:alice');

          final serviceSession = harness.service.session!;
          expect(serviceSession.token, 'old-sealed-token');
          expect(serviceSession.did, 'did:plc:alice');

          expect(await harness.storedSession(), (
            'old-sealed-token',
            'old-session-id',
            'did:plc:alice',
            'alice.test',
          ));

          expect(harness.provider.isAuthenticated, true);
          expect(harness.provider.did, 'did:plc:alice');
          expect(harness.provider.error, null);
          expect(
            harness.notifications.every((n) => n == (true, 'did:plc:alice')),
            true,
            reason: 'notifications: ${harness.notifications}',
          );
        });
        _expectNoTokenLogged(logs);
      });
    }
  });

  group('AuthProvider.reauthenticate with the session changing during the '
      'browser flow', () {
    test('a refresh adopted mid-flow still succeeds', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend();
        final release = Completer<String>();
        final flowReached = harness.holdOAuth(release);

        final reauth = harness.reauthenticate();
        await flowReached;
        expect(await harness.provider.refreshToken(), true);
        expect(harness.provider.session?.sessionId, 'old-session-id');
        release.complete(_aliceNewCallback);

        expect(await reauth, ReauthenticationResult.success);
        await harness.expectSessionEverywhere('new-sealed-token');
        expect(harness.provider.isAuthenticated, true);
      });
      _expectNoTokenLogged(logs);
    });

    test('expiry mid-flow fails and stays signed out', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend(refreshStatus: 401);
        final release = Completer<String>();
        final flowReached = harness.holdOAuth(release);

        final reauth = harness.reauthenticate();
        await flowReached;
        expect(await harness.provider.refreshToken(), false);
        release.complete(_aliceNewCallback);

        expect(await reauth, ReauthenticationResult.failed);
        await harness.expectSignedOutEverywhere();
      });
      _expectNoTokenLogged(logs);
    });

    test('sign-out mid-flow fails and stays signed out', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend();
        final release = Completer<String>();
        final flowReached = harness.holdOAuth(release);

        final reauth = harness.reauthenticate();
        await flowReached;
        await harness.provider.signOut();
        release.complete(_aliceNewCallback);

        expect(await reauth, ReauthenticationResult.failed);
        await harness.expectSignedOutEverywhere();
      });
      _expectNoTokenLogged(logs);
    });
  });

  group('AuthProvider.reauthenticate with the session changing during its '
      'storage write', () {
    test('a refresh committed during the write is overtaken by the new '
        'session everywhere', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend()
          ..answerOAuth(() async => _aliceNewCallback);
        final reauthWriteReached = harness.storage.gateNextWrite();

        final reauth = harness.reauthenticate();
        await reauthWriteReached;
        expect(await harness.provider.refreshToken(), true);
        harness.storage.releaseGate();

        expect(await reauth, ReauthenticationResult.success);
        await harness.expectSessionEverywhere('new-sealed-token');
      });
      _expectNoTokenLogged(logs);
    });

    test('sign-out during the write waits for it, revokes the new session '
        'and leaves nothing stored', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend()
          ..answerOAuth(() async => _aliceNewCallback);
        final reauthWriteReached = harness.storage.gateNextWrite();

        final reauth = harness.reauthenticate();
        await reauthWriteReached;
        final signOut = harness.provider.signOut();
        await pumpEventQueue();
        harness.storage.releaseGate();
        await reauth;
        await signOut;

        await harness.expectSignedOutEverywhere();
        expect(
          harness.logoutTokens.length == 1 &&
              harness.logoutTokens.single == 'new-sealed-token',
          true,
          reason: 'logout must revoke the session that was live',
        );
      });
      _expectNoTokenLogged(logs);
    });

    test('expiry during the write fails and leaves nothing stored', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend(refreshStatus: 401)
          ..answerOAuth(() async => _aliceNewCallback);
        final reauthWriteReached = harness.storage.gateNextWrite();

        final reauth = harness.reauthenticate();
        await reauthWriteReached;
        expect(await harness.provider.refreshToken(), false);
        harness.storage.releaseGate();

        expect(await reauth, ReauthenticationResult.failed);
        await harness.expectSignedOutEverywhere();
      });
      _expectNoTokenLogged(logs);
    });
  });

  group('CovesAuthService.refreshToken discarded by a reauthentication', () {
    test('still throws SessionRefreshDiscardedException when rewriting '
        'storage fails', () async {
      final logs = <String>[];
      await _capturingLogs(logs, () async {
        final harness = await _signedIn()
          ..answerBackend();
        final refreshWriteReached = harness.storage.gateNextWrite();
        final refresh = harness.service.refreshToken();
        await refreshWriteReached;

        harness.answerOAuth(() async => _aliceNewCallback);
        expect(await harness.reauthenticate(), ReauthenticationResult.success);
        harness.storage.armed = true;
        harness.storage.releaseGate();

        await expectLater(
          refresh,
          throwsA(isA<SessionRefreshDiscardedException>()),
        );
        expect(harness.service.session?.sessionId, 'new-session-id');
      });
      _expectNoTokenLogged(logs);
    });
  });
}
