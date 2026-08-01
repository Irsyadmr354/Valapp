import 'dart:async';

/// A simple per-key async mutex lock. Ensures only one async operation
/// runs at a time for a given key, queuing others until it completes.
class AsyncLock {
  static final Map<String, Future<void>> _locks = {};

  static Future<T> run<T>(String key, Future<T> Function() action) async {
    while (_locks[key] != null) {
      try {
        await _locks[key];
      } catch (_) {}
    }
    final completer = Completer<void>();
    _locks[key] = completer.future;
    try {
      return await action();
    } finally {
      completer.complete();
      _locks.remove(key);
    }
  }
}
