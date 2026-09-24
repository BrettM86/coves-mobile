import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../providers/auth_provider.dart';

/// App-level LRU cache of user profiles, keyed by DID.
///
/// Lives above the per-screen profile providers so every profile screen
/// shares one cache: a profile loaded on one screen is available to the next
/// without another request.
///
/// Cached profiles carry per-viewer `viewer` state, so the cache clears
/// itself when the user signs out or the signed-in account changes.
///
/// Every [put] is announced to the listeners registered with
/// [addPutListener], so a screen already showing that DID can adopt a
/// profile another screen refreshed (for example after an edit). This is a
/// plain callback registry rather than a `Listenable`, because the cache is
/// exposed with a plain `Provider`, which rejects Listenables.
///
/// Overlapping fetches of one DID are ordered by when they started, across
/// every provider sharing the cache: a fetch takes [nextRequestSequence]
/// before its request and passes it to [put], which rejects a result older
/// than the entry it holds. Ordering is lost when an entry is evicted.
class ProfileCache {
  ProfileCache(this._authProvider)
    : _lastSignedInDid = _signedInDid(_authProvider) {
    _authProvider.addListener(_onAuthChanged);
  }

  static const int maxEntries = 50;

  final AuthProvider _authProvider;

  /// Insertion order is access order: the first key is least recently used.
  /// Each profile is kept with the request sequence that produced it.
  final LinkedHashMap<String, ({UserProfile profile, int requestSequence})>
  _entries = LinkedHashMap();

  int _lastRequestSequence = 0;

  String? _lastSignedInDid;

  final List<void Function(UserProfile)> _putListeners = [];

  /// Increments on each sign-out or account-change clear. A caller
  /// that started a fetch under an earlier generation must not [put] its
  /// result, because it was fetched for the previous viewer.
  int get generation => _generation;
  int _generation = 0;

  static String? _signedInDid(AuthProvider authProvider) =>
      authProvider.isAuthenticated ? authProvider.did : null;

  /// Returns the cached profile for [did] and marks it most recently used.
  UserProfile? get(String did) {
    final entry = _entries.remove(did);
    if (entry != null) {
      _entries[did] = entry;
    }
    return entry?.profile;
  }

  /// A sequence number for a profile fetch about to start; later fetches get
  /// larger numbers.
  int nextRequestSequence() => ++_lastRequestSequence;

  /// The request sequence of the cached entry for [did], without marking it
  /// used; null when [did] is not cached.
  int? requestSequenceOf(String did) => _entries[did]?.requestSequence;

  /// Stores [profile] as most recently used, evicting the least recently
  /// used entry when over capacity.
  ///
  /// [requestSequence] is the [nextRequestSequence] its fetch took; a put
  /// older than the cached entry for that DID is ignored and not announced.
  /// Without one, the put counts as the newest.
  void put(UserProfile profile, {int? requestSequence}) {
    final sequence = requestSequence ?? nextRequestSequence();
    final cachedSequence = requestSequenceOf(profile.did);
    if (cachedSequence != null && sequence < cachedSequence) {
      return;
    }
    _entries
      ..remove(profile.did)
      ..[profile.did] = (profile: profile, requestSequence: sequence);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    // Copied so a listener may remove itself while being notified. A
    // throwing listener is reported and must not stop the ones after it.
    for (final listener in List.of(_putListeners)) {
      try {
        listener(profile);
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'profile cache',
            context: ErrorDescription(
              'while notifying a profile cache put listener',
            ),
          ),
        );
      }
    }
  }

  /// Calls [listener] with each profile passed to [put].
  void addPutListener(void Function(UserProfile) listener) {
    _putListeners.add(listener);
  }

  void removePutListener(void Function(UserProfile) listener) {
    _putListeners.remove(listener);
  }

  void _onAuthChanged() {
    final signedInDid = _signedInDid(_authProvider);
    if (signedInDid != _lastSignedInDid) {
      _entries.clear();
      _generation++;
    }
    _lastSignedInDid = signedInDid;
  }

  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
  }
}
