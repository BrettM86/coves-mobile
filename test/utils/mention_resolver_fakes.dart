import 'dart:async';

import 'package:coves_flutter/utils/rich_text_composer.dart';

/// A [MentionResolver] answering from fixed tables
///
/// Records each lookup as it starts (`user <handle>` or `community <name>`)
/// and as it completes. An identifier with a gate waits for that gate before
/// answering; one with an error throws it; one missing from its table is not
/// found (null).
class FakeMentionResolver implements MentionResolver {
  FakeMentionResolver({
    this.handles = const {},
    this.communities = const {},
    this.errors = const {},
    this.gates = const {},
  });

  /// DID returned for each handle
  final Map<String, String> handles;

  /// DID returned for each community name or name@origin
  final Map<String, String> communities;

  /// Exception thrown for each lookup key (`user <handle>` or
  /// `community <name>`)
  final Map<String, Exception> errors;

  /// Gate each lookup key waits on before answering
  final Map<String, Completer<void>> gates;

  final List<String> started = [];
  final List<String> completed = [];

  @override
  Future<String?> resolveHandle(String handle) =>
      _lookUp('user $handle', handles[handle]);

  @override
  Future<String?> resolveCommunity(String community) =>
      _lookUp('community $community', communities[community]);

  Future<String?> _lookUp(String key, String? did) async {
    started.add(key);
    final gate = gates[key];
    if (gate != null) {
      await gate.future;
    }
    completed.add(key);
    final error = errors[key];
    if (error != null) {
      throw error;
    }
    return did;
  }
}
