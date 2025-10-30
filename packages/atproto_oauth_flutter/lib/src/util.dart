import 'dart:async';

/// Returns the input if it's a String, otherwise returns null.
String? ifString<V>(V v) => v is String ? v : null;

/// Extracts the MIME type from Content-Type header.
///
/// Example: "application/json; charset=utf-8" -> "application/json"
String? contentMime(Map<String, String> headers) {
  final contentType = headers['content-type'];
  if (contentType == null) return null;
  return contentType.split(';')[0].trim();
}

/// Event detail map for custom event handling.
///
/// This is a simplified version of TypeScript's CustomEvent pattern,
/// adapted for Dart using StreamController and typed events.
///
/// Example:
/// ```dart
/// final target = CustomEventTarget();
/// final subscription = target.addEventListener('myEvent', (String detail) {
///   print('Received: $detail');
/// });
///
/// // Later, to remove the listener:
/// subscription.cancel();
/// ```
class CustomEventTarget<EventDetailMap> {
  final Map<String, StreamController<dynamic>> _controllers = {};

  /// Add an event listener for a specific event type.
  ///
  /// Returns a [StreamSubscription] that can be cancelled to remove the listener.
  ///
  /// Throws [TypeError] if an event type is already registered with a different type parameter.
  ///
  /// Example:
  /// ```dart
  /// final subscription = target.addEventListener('event', (detail) => print(detail));
  /// subscription.cancel(); // Remove this specific listener
  /// ```
  StreamSubscription<T> addEventListener<T>(
    String type,
    void Function(T detail) callback,
  ) {
    final existingController = _controllers[type];

    // Check if a controller already exists with a different type
    if (existingController != null &&
        existingController is! StreamController<T>) {
      throw TypeError();
    }

    final controller =
        _controllers.putIfAbsent(type, () => StreamController<T>.broadcast())
            as StreamController<T>;

    return controller.stream.listen(callback);
  }

  /// Dispatch a custom event with detail data.
  ///
  /// Returns true if the event was dispatched successfully.
  bool dispatchCustomEvent<T>(String type, T detail) {
    final controller = _controllers[type];
    if (controller == null) return false;

    (controller as StreamController<T>).add(detail);
    return true;
  }

  /// Dispose of all stream controllers.
  ///
  /// Call this when the event target is no longer needed to prevent memory leaks.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

/// Combines multiple cancellation tokens into a single cancellable operation.
///
/// This is a Dart adaptation of the TypeScript combineSignals function.
/// Since Dart doesn't have AbortSignal/AbortController, we use CancellationToken
/// pattern with StreamController.
///
/// The returned controller will be cancelled if any of the input tokens are cancelled.
class CombinedCancellationToken {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  final List<StreamSubscription<void>> _subscriptions = [];
  bool _isCancelled = false;
  Object? _reason;

  CombinedCancellationToken(List<CancellationToken?> tokens) {
    for (final token in tokens) {
      if (token != null) {
        if (token.isCancelled) {
          cancel(Exception('Operation was cancelled: ${token.reason}'));
          return;
        }

        final subscription = token.stream.listen((_) {
          cancel(Exception('Operation was cancelled: ${token.reason}'));
        });
        _subscriptions.add(subscription);
      }
    }
  }

  /// Whether this operation has been cancelled.
  bool get isCancelled => _isCancelled;

  /// The reason for cancellation, if any.
  Object? get reason => _reason;

  /// Stream that emits when the operation is cancelled.
  Stream<void> get stream => _controller.stream;

  /// Cancel the operation with an optional reason.
  void cancel([Object? reason]) {
    if (_isCancelled) return;

    _isCancelled = true;
    _reason = reason ?? Exception('Operation was cancelled');

    _controller.add(null);
    dispose();
  }

  /// Clean up resources.
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _controller.close();
  }
}

/// Represents a cancellable operation.
///
/// This is a Dart equivalent of AbortSignal in JavaScript.
class CancellationToken {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool _isCancelled = false;
  Object? _reason;

  CancellationToken();

  /// Whether this operation has been cancelled.
  bool get isCancelled => _isCancelled;

  /// The reason for cancellation, if any.
  Object? get reason => _reason;

  /// Stream that emits when the operation is cancelled.
  Stream<void> get stream => _controller.stream;

  /// Cancel the operation with an optional reason.
  void cancel([Object? reason]) {
    if (_isCancelled) return;

    _isCancelled = true;
    _reason = reason ?? Exception('Operation was cancelled');
    _controller.add(null);
  }

  /// Throw an exception if the operation has been cancelled.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw _reason ?? Exception('Operation was cancelled');
    }
  }

  /// Dispose of the stream controller.
  void dispose() {
    _controller.close();
  }
}

/// Combines multiple cancellation tokens into a single token.
///
/// If any of the input tokens are cancelled, the returned token will also be cancelled.
/// The returned token should be disposed when no longer needed.
CombinedCancellationToken combineSignals(List<CancellationToken?> signals) {
  return CombinedCancellationToken(signals);
}
