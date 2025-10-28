import 'dart:async';

import '../runtime/runtime_implementation.dart';

/// A map storing active locks by name.
///
/// Each lock is represented as a Future that completes when the lock is released.
/// This allows queuing of operations waiting for the same lock.
final Map<Object, Future<void>> _locks = {};

/// Acquires a lock for the given name.
///
/// Returns a function that releases the lock when called.
/// The lock is automatically added to the queue of pending operations.
///
/// This implements a fair (FIFO) mutex pattern where operations are executed
/// in the order they acquire the lock.
Future<void Function()> _acquireLocalLock(Object name) {
  final completer = Completer<void Function()>();

  // Get the previous lock in the queue (or a resolved promise if none)
  final prev = _locks[name] ?? Future.value();

  // Create a completer for the release function
  final releaseCompleter = Completer<void>();

  // Chain onto the previous lock
  final next = prev.then((_) {
    // This runs when we've acquired the lock
    return releaseCompleter.future;
  });

  // Store our lock as the new tail of the queue
  _locks[name] = next;

  // Resolve the acquire promise with the release function
  prev.then((_) {
    void release() {
      // Only delete the lock if it's still the current one
      // (it might have been replaced by a newer lock)
      if (_locks[name] == next) {
        _locks.remove(name);
      }

      // Complete the release, allowing the next operation to proceed
      if (!releaseCompleter.isCompleted) {
        releaseCompleter.complete();
      }
    }

    completer.complete(release);
  });

  return completer.future;
}

/// Executes a function while holding a named lock.
///
/// This is a local (in-memory) lock implementation that prevents concurrent
/// execution of the same operation within a single isolate/process.
///
/// The lock is automatically released when the function completes or throws an error.
///
/// Example:
/// ```dart
/// final result = await requestLocalLock('my-operation', () async {
///   // Only one execution at a time for 'my-operation'
///   return await performCriticalOperation();
/// });
/// ```
///
/// Use cases:
/// - Token refresh (prevent multiple simultaneous refresh requests)
/// - Database transactions
/// - File operations
/// - Any operation that must not run concurrently with itself
///
/// Note: This is an in-memory lock. It does not work across:
/// - Multiple isolates
/// - Multiple processes
/// - Multiple app instances
///
/// For cross-process locking, implement a platform-specific RuntimeLock.
Future<T> requestLocalLock<T>(
  String name,
  FutureOr<T> Function() fn,
) async {
  // Acquire the lock and get the release function
  final release = await _acquireLocalLock(name);

  try {
    // Execute the function while holding the lock
    return await fn();
  } finally {
    // Always release the lock, even if the function throws
    release();
  }
}

/// Convenience getter that returns the requestLocalLock function as a RuntimeLock.
///
/// This can be used as the default implementation for RuntimeImplementation.requestLock.
RuntimeLock get requestLocalLockImpl => requestLocalLock;
