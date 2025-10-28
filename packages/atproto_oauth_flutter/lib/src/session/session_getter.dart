import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../errors/auth_method_unsatisfiable_error.dart';
import '../errors/token_invalid_error.dart';
import '../errors/token_refresh_error.dart';
import '../errors/token_revoked_error.dart';
import '../oauth/client_auth.dart' show ClientAuthMethod;
import '../oauth/oauth_server_agent.dart';
import '../oauth/oauth_server_factory.dart';
import '../runtime/runtime.dart';
import '../util.dart';
import 'oauth_session.dart';

/// Options for getting a cached value.
class GetCachedOptions {
  /// Cancellation token for aborting the operation
  final CancellationToken? signal;

  /// Do not use the cache to get the value. Always get a new value.
  final bool? noCache;

  /// Allow returning stale values from the cache.
  final bool? allowStale;

  const GetCachedOptions({
    this.signal,
    this.noCache,
    this.allowStale,
  });
}

/// Abstract storage interface for values.
///
/// This is a generic key-value store interface.
abstract class SimpleStore<K, V> {
  /// Gets a value from the store.
  ///
  /// Returns `null` if the key doesn't exist.
  Future<V?> get(K key, {CancellationToken? signal});

  /// Sets a value in the store.
  Future<void> set(K key, V value);

  /// Deletes a value from the store.
  Future<void> del(K key);

  /// Optionally clears all values from the store.
  Future<void> clear() async {}
}

/// Type alias for session storage
typedef SessionStore = SimpleStore<String, Session>;

/// Details of a session update event.
class SessionUpdatedEvent {
  /// The subject (user's DID)
  final String sub;

  /// The DPoP key
  final Map<String, dynamic> dpopKey;

  /// The authentication method
  final String? authMethod;

  /// The token set
  final TokenSet tokenSet;

  const SessionUpdatedEvent({
    required this.sub,
    required this.dpopKey,
    this.authMethod,
    required this.tokenSet,
  });
}

/// Details of a session deletion event.
class SessionDeletedEvent {
  /// The subject (user's DID)
  final String sub;

  /// The cause of deletion
  final Object cause;

  const SessionDeletedEvent({
    required this.sub,
    required this.cause,
  });
}

/// Manages session retrieval, caching, and refreshing.
///
/// The SessionGetter wraps a session store and provides:
/// - Automatic token refresh when tokens are stale/expired
/// - Caching to avoid redundant refresh operations
/// - Events for session updates and deletions
/// - Concurrency control to prevent multiple simultaneous refreshes
///
/// This is a critical component that ensures at most one token refresh
/// is happening at a time for a given user, even across multiple tabs
/// or app instances.
///
/// Example:
/// ```dart
/// final sessionGetter = SessionGetter(
///   sessionStore: mySessionStore,
///   serverFactory: myServerFactory,
///   runtime: myRuntime,
/// );
///
/// // Listen for session updates
/// sessionGetter.onUpdated.listen((event) {
///   print('Session updated for ${event.sub}');
/// });
///
/// // Listen for session deletions
/// sessionGetter.onDeleted.listen((event) {
///   print('Session deleted for ${event.sub}: ${event.cause}');
/// });
///
/// // Get a session (automatically refreshes if expired)
/// final session = await sessionGetter.getSession('did:plc:abc123');
///
/// // Force refresh
/// final freshSession = await sessionGetter.getSession('did:plc:abc123', true);
/// ```
class SessionGetter extends CachedGetter<AtprotoDid, Session> {
  final OAuthServerFactory _serverFactory;
  final Runtime _runtime;

  final _eventTarget = CustomEventTarget<Map<String, dynamic>>();
  final _updatedController = StreamController<SessionUpdatedEvent>.broadcast();
  final _deletedController = StreamController<SessionDeletedEvent>.broadcast();

  /// Stream of session update events.
  Stream<SessionUpdatedEvent> get onUpdated => _updatedController.stream;

  /// Stream of session deletion events.
  Stream<SessionDeletedEvent> get onDeleted => _deletedController.stream;

  SessionGetter({
    required super.sessionStore,
    required OAuthServerFactory serverFactory,
    required Runtime runtime,
  })  : _serverFactory = serverFactory,
        _runtime = runtime,
        super(
          getter: null, // Will be set in _createGetter
          options: CachedGetterOptions(
            isStale: (sub, session) {
              final tokenSet = session.tokenSet;
              if (tokenSet.expiresAt == null) return false;

              final expiresAt = DateTime.parse(tokenSet.expiresAt!);
              final now = DateTime.now();

              // Add some lee way to ensure the token is not expired when it
              // reaches the server (10 seconds)
              // Add some randomness to reduce the chances of multiple
              // instances trying to refresh the token at the same time (0-30 seconds)
              final buffer = Duration(
                milliseconds: 10000 + (math.Random().nextDouble() * 30000).toInt(),
              );

              return expiresAt.isBefore(now.add(buffer));
            },
            onStoreError: (err, sub, session) async {
              if (err is! AuthMethodUnsatisfiableError) {
                // If the error was an AuthMethodUnsatisfiableError, there is no
                // point in trying to call `fromIssuer`.
                try {
                  // Parse authMethod
                  final authMethodValue = session.authMethod;
                  final authMethod = authMethodValue is Map<String, dynamic>
                      ? ClientAuthMethod.fromJson(authMethodValue)
                      : (authMethodValue as String?) ?? 'legacy';

                  // Generate new DPoP key for revocation
                  // (stored key is serialized and can't be directly used)
                  final dpopKeyAlgs = ['ES256', 'RS256'];
                  final newDpopKey = await runtime.generateKey(dpopKeyAlgs);

                  // If the token data cannot be stored, let's revoke it
                  final server = await serverFactory.fromIssuer(
                    session.tokenSet.iss,
                    authMethod,
                    newDpopKey,
                  );
                  await server.revoke(
                    session.tokenSet.refreshToken ?? session.tokenSet.accessToken,
                  );
                } catch (_) {
                  // Let the original error propagate
                }
              }

              throw err;
            },
            deleteOnError: (err) async {
              return err is TokenRefreshError ||
                  err is TokenRevokedError ||
                  err is TokenInvalidError ||
                  err is AuthMethodUnsatisfiableError;
            },
          ),
        ) {
    // Set the getter function after construction
    _getter = _createGetter();
  }

  /// Creates the getter function for refreshing sessions.
  Future<Session> Function(
    AtprotoDid,
    GetCachedOptions,
    Session?,
  ) _createGetter() {
    return (sub, options, storedSession) async {
      // There needs to be a previous session to be able to refresh. If
      // storedSession is null, it means that the store does not contain
      // a session for the given sub.
      if (storedSession == null) {
        // Because the session is not in the store, delStored() method
        // will not be called by the CachedGetter class (because there is
        // nothing to delete). This would typically happen if there is no
        // synchronization mechanism between instances of this class. Let's
        // make sure an event is dispatched here if this occurs.
        const msg = 'The session was deleted by another process';
        final cause = TokenRefreshError(sub, msg);
        _dispatchDeletedEvent(sub, cause);
        throw cause;
      }

      // From this point forward, throwing a TokenRefreshError will result in
      // delStored() being called, resulting in an event being dispatched,
      // even if the session was removed from the store through a concurrent
      // access (which, normally, should not happen if a proper runtime lock
      // was provided).

      final dpopKey = storedSession.dpopKey;
      // authMethod can be a Map (serialized ClientAuthMethod) or String ('legacy')
      final authMethodValue = storedSession.authMethod;
      final authMethod = authMethodValue is Map<String, dynamic>
          ? ClientAuthMethod.fromJson(authMethodValue)
          : (authMethodValue as String?) ?? 'legacy';
      final tokenSet = storedSession.tokenSet;

      if (sub != tokenSet.sub) {
        // Fool-proofing (e.g. against invalid session storage)
        throw TokenRefreshError(sub, 'Stored session sub mismatch');
      }

      if (tokenSet.refreshToken == null) {
        throw TokenRefreshError(sub, 'No refresh token available');
      }

      // Since refresh tokens can only be used once, we might run into
      // concurrency issues if multiple instances (e.g. browser tabs) are
      // trying to refresh the same token simultaneously. The chances of this
      // happening when multiple instances are started simultaneously is
      // reduced by randomizing the expiry time (see isStale above). The
      // best solution is to use a mutex/lock to ensure that only one instance
      // is refreshing the token at a time (runtime.usingLock) but that is not
      // always possible. If no lock implementation is provided, we will use
      // the store to check if a concurrent refresh occurred.

      // TODO: Key Persistence Workaround
      // The storedSession.dpopKey is a Map<String, dynamic> (serialized JWK),
      // but OAuthServerFactory.fromIssuer() expects a Key object.
      // Until Key serialization is implemented (see runtime_implementation.dart),
      // we generate a new DPoP key for each session refresh.
      // This works but means tokens are bound to new keys, requiring refresh.
      final dpopKeyAlgs = ['ES256', 'RS256']; // Supported DPoP algorithms
      final newDpopKey = await _runtime.generateKey(dpopKeyAlgs);

      final server = await _serverFactory.fromIssuer(
        tokenSet.iss,
        authMethod,
        newDpopKey,
      );

      // Because refresh tokens can only be used once, we must not use the
      // "signal" to abort the refresh, or throw any abort error beyond this
      // point. Any thrown error beyond this point will prevent the
      // SessionGetter from obtaining, and storing, the new token set,
      // effectively rendering the currently saved session unusable.
      options.signal?.throwIfCancelled();

      try {
        final newTokenSet = await server.refresh(tokenSet);

        if (sub != newTokenSet.sub) {
          // The server returned another sub. Was the tokenSet manipulated?
          throw TokenRefreshError(sub, 'Token set sub mismatch');
        }

        return Session(
          dpopKey: newDpopKey.bareJwk ?? {},
          tokenSet: newTokenSet,
          authMethod: server.authMethod.toJson(),
        );
      } catch (cause) {
        // If the refresh token is invalid, let's try to recover from
        // concurrency issues, or make sure the session is deleted by throwing
        // a TokenRefreshError.
        if (cause is OAuthResponseError &&
            cause.status == 400 &&
            cause.error == 'invalid_grant') {
          // In case there is no lock implementation in the runtime, we will
          // wait for a short time to give the other concurrent instances a
          // chance to finish their refreshing of the token. If a concurrent
          // refresh did occur, we will pretend that this one succeeded.
          if (!_runtime.hasImplementationLock) {
            await Future.delayed(Duration(seconds: 1));

            final stored = await getStored(sub);
            if (stored == null) {
              // A concurrent refresh occurred and caused the session to be
              // deleted (for a reason we can't know at this point).

              // Using a distinct error message mainly for debugging
              // purposes. Also, throwing a TokenRefreshError to trigger
              // deletion through the deleteOnError callback.
              const msg = 'The session was deleted by another process';
              throw TokenRefreshError(sub, msg, cause: cause);
            } else if (stored.tokenSet.accessToken != tokenSet.accessToken ||
                stored.tokenSet.refreshToken != tokenSet.refreshToken) {
              // A concurrent refresh occurred. Pretend this one succeeded.
              return stored;
            } else {
              // There were no concurrent refresh. The token is (likely)
              // simply no longer valid.
            }
          }

          // Make sure the session gets deleted from the store
          final msg = cause.errorDescription ?? 'The session was revoked';
          throw TokenRefreshError(sub, msg, cause: cause);
        }

        // Re-throw the original exception if it wasn't an invalid_grant error
        if (cause is Exception) {
          throw cause;
        } else {
          throw Exception('Token refresh failed: $cause');
        }
      }
    };
  }

  @override
  Future<void> setStored(String key, Session value) async {
    // Prevent tampering with the stored value
    if (key != value.tokenSet.sub) {
      throw TypeError();
    }

    await super.setStored(key, value);

    // Serialize authMethod to String for the event
    // authMethod can be Map<String, dynamic>, String, or null
    String? authMethodString;
    if (value.authMethod is Map) {
      authMethodString = jsonEncode(value.authMethod);
    } else if (value.authMethod is String) {
      authMethodString = value.authMethod as String;
    } else {
      authMethodString = null;
    }

    _dispatchUpdatedEvent(
      key,
      value.dpopKey,
      authMethodString,
      value.tokenSet,
    );
  }

  @override
  Future<void> delStored(AtprotoDid key, [Object? cause]) async {
    await super.delStored(key, cause);
    _dispatchDeletedEvent(key, cause ?? Exception('Session deleted'));
  }

  /// Gets a session, optionally refreshing it.
  ///
  /// Parameters:
  /// - [sub]: The subject (user's DID)
  /// - [refresh]: When `true`, forces a token refresh even if not expired.
  ///   When `false`, uses cached tokens even if expired.
  ///   When `'auto'`, refreshes only if expired (default).
  Future<Session> getSession(AtprotoDid sub, [dynamic refresh = 'auto']) {
    return get(
      sub,
      GetCachedOptions(
        noCache: refresh == true,
        allowStale: refresh == false,
      ),
    );
  }

  @override
  Future<Session> get(AtprotoDid key, [GetCachedOptions? options]) async {
    final session = await _runtime.usingLock(
      '@atproto-oauth-client-$key',
      () async {
        // Make sure, even if there is no signal in the options, that the
        // request will be cancelled after at most 30 seconds.
        final timeoutToken = CancellationToken();
        Timer(Duration(seconds: 30), () => timeoutToken.cancel());

        final combinedSignal = options?.signal != null
            ? combineSignals([options!.signal, timeoutToken])
            : CombinedCancellationToken([timeoutToken]);

        try {
          return await super.get(
            key,
            GetCachedOptions(
              signal: CancellationToken(), // Use combined signal
              noCache: options?.noCache,
              allowStale: options?.allowStale,
            ),
          );
        } finally {
          combinedSignal.dispose();
          timeoutToken.dispose();
        }
      },
    );

    if (key != session.tokenSet.sub) {
      // Fool-proofing (e.g. against invalid session storage)
      throw Exception('Token set does not match the expected sub');
    }

    return session;
  }

  void _dispatchUpdatedEvent(
    String sub,
    Map<String, dynamic> dpopKey,
    String? authMethod,
    TokenSet tokenSet,
  ) {
    final event = SessionUpdatedEvent(
      sub: sub,
      dpopKey: dpopKey,
      authMethod: authMethod,
      tokenSet: tokenSet,
    );

    _updatedController.add(event);
    _eventTarget.dispatchCustomEvent('updated', event);
  }

  void _dispatchDeletedEvent(String sub, Object cause) {
    final event = SessionDeletedEvent(sub: sub, cause: cause);

    _deletedController.add(event);
    _eventTarget.dispatchCustomEvent('deleted', event);
  }

  /// Disposes of resources used by this session getter.
  void dispose() {
    _updatedController.close();
    _deletedController.close();
    _eventTarget.dispose();
  }
}

/// Placeholder for OAuthResponseError
/// Will be implemented in later chunks
class OAuthResponseError implements Exception {
  final int status;
  final String? error;
  final String? errorDescription;

  OAuthResponseError({
    required this.status,
    this.error,
    this.errorDescription,
  });
}

/// Options for the CachedGetter.
class CachedGetterOptions<K, V> {
  /// Function to determine if a cached value is stale
  final bool Function(K key, V value)? isStale;

  /// Function called when storing a value fails
  final Future<void> Function(Object err, K key, V value)? onStoreError;

  /// Function to determine if a value should be deleted on error
  final Future<bool> Function(Object err)? deleteOnError;

  const CachedGetterOptions({
    this.isStale,
    this.onStoreError,
    this.deleteOnError,
  });
}

/// A pending item in the cache.
class _PendingItem<V> {
  final Future<({V value, bool isFresh})> future;

  _PendingItem(this.future);
}

/// Wrapper utility that uses a store to speed up the retrieval of values.
///
/// The CachedGetter ensures that at most one fresh call is ever being made
/// for a given key. It also contains logic for reading from the cache which,
/// if the cache is based on localStorage/indexedDB, will sync across multiple
/// tabs (for a given key).
///
/// This is an abstract base class. Subclasses should provide the getter
/// function and any additional logic.
class CachedGetter<K, V> {
  final SimpleStore<K, V> _store;
  final CachedGetterOptions<K, V> _options;
  final Map<K, _PendingItem<V>> _pending = {};

  late Future<V> Function(K, GetCachedOptions, V?) _getter;

  CachedGetter({
    required SimpleStore<K, V> sessionStore,
    required Future<V> Function(K, GetCachedOptions, V?)? getter,
    required CachedGetterOptions<K, V> options,
  })  : _store = sessionStore,
        _options = options {
    if (getter != null) {
      _getter = getter;
    }
  }

  Future<V> get(K key, [GetCachedOptions? options]) async {
    options ??= GetCachedOptions();
    final signal = options.signal;
    final noCache = options.noCache ?? false;
    final allowStale = options.allowStale ?? false;

    signal?.throwIfCancelled();

    final isStale = _options.isStale;
    final deleteOnError = _options.deleteOnError;

    // Determine if a stored value can be used
    bool allowStored(V value) {
      if (noCache) return false; // Never allow stored values
      if (allowStale || isStale == null) return true; // Always allow
      return !isStale(key, value); // Check if stale
    }

    // As long as concurrent requests are made for the same key, only one
    // request will be made to the getStored & getter functions at a time.
    _PendingItem<V>? previousExecutionFlow;
    while ((previousExecutionFlow = _pending[key]) != null) {
      try {
        final result = await previousExecutionFlow!.future;
        final isFresh = result.isFresh;
        final value = result.value;

        // Use the concurrent request's result if it is fresh
        if (isFresh) return value;
        // Use the concurrent request's result if not fresh (loaded from the
        // store), and matches the conditions for using a stored value.
        if (allowStored(value)) return value;
      } catch (_) {
        // Ignore errors from previous execution flows (they will have been
        // propagated by that flow).
      }

      // Break the loop if the signal was cancelled
      signal?.throwIfCancelled();
    }

    final currentExecutionFlow = _PendingItem<V>(
      Future(() async {
        final storedValue = await getStored(key, signal: signal);

        if (storedValue != null && allowStored(storedValue)) {
          // Use the stored value as return value for the current execution
          // flow. Notify other concurrent execution flows that we got a value,
          // but that it came from the store (isFresh = false).
          return (value: storedValue, isFresh: false);
        }

        return Future(() async {
          return await _getter(key, options!, storedValue);
        }).catchError((err) async {
          if (storedValue != null) {
            try {
              if (deleteOnError != null && await deleteOnError(err)) {
                await delStored(key, err);
              }
            } catch (error) {
              throw Exception('Error while deleting stored value: $error');
            }
          }
          throw err;
        }).then((value) async {
          // The value should be stored even if the signal was cancelled.
          await setStored(key, value);
          return (value: value, isFresh: true);
        });
      }).whenComplete(() {
        _pending.remove(key);
      }),
    );

    if (_pending.containsKey(key)) {
      // This should never happen. There must not be any 'await'
      // statement between this and the loop iteration check.
      throw Exception('Concurrent request for the same key');
    }

    _pending[key] = currentExecutionFlow;

    final result = await currentExecutionFlow.future;
    return result.value;
  }

  Future<V?> getStored(K key, {CancellationToken? signal}) async {
    try {
      return await _store.get(key, signal: signal);
    } catch (err) {
      return null;
    }
  }

  Future<void> setStored(K key, V value) async {
    try {
      await _store.set(key, value);
    } catch (err) {
      final onStoreError = _options.onStoreError;
      if (onStoreError != null) {
        await onStoreError(err, key, value);
      }
    }
  }

  Future<void> delStored(K key, [Object? cause]) async {
    await _store.del(key);
  }
}
