import 'dart:async';

/// A simple per-key async mutex lock. Ensures only one async operation
/// runs at a time for a given key, queuing others until it completes.
class AsyncLock {
  static final Map<String, Future<void>> _locks = {};

  static Future<T> run<T>(String key, Future<T> Function() action) async {
    // Capture the current tail so we wait for it, then replace it
    // with a new completer that we own. Using a chain of completers
    // rather than a bare Future avoids a subtle issue where an
    // exception thrown by [action] would propagate into every waiter
    // that chains on the raw future — each waiter should see only
    // its own result/error.
    final previous = _locks[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _locks[key] = completer.future;

    // Wait for the predecessor to finish (success or error — we
    // don't care which, we just need it to be done).
    try {
      await previous;
    } catch (_) {
      // Ignore predecessor errors — we only want to wait for the slot.
    }

    try {
      return await action();
    } finally {
      // Release this slot. If no other waiter has replaced _locks[key]
      // in the meantime we can clean up the map entry entirely.
      completer.complete();
      if (_locks[key] == completer.future) {
        _locks.remove(key);
      }
    }
  }
}
