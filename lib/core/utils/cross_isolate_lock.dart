import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cross-ISOLATE (and cross-process) mutual exclusion built on atomic file
/// creation.
///
/// Why this exists (audit H2): [AsyncLock] is per-isolate, so the workmanager
/// background isolate and the main isolate could interleave read-modify-write
/// cycles on the same persisted ledger (e.g. wishlist notification dedupe)
/// and produce duplicate notifications. A lock FILE claimed with
/// `create(exclusive: true)` is honoured by every isolate in the process.
///
/// Semantics:
/// - Acquire: exclusive-create wins; losers poll until the holder deletes it.
/// - Stale recovery: a lock older than [staleAfter] is stolen — protects
///   against a crashed/killed process that never released the file.
/// - Fallback: when no base directory is available (unit-test env), the body
///   simply runs unserialised — same-isolate callers are expected to already
///   hold an [AsyncLock].
class CrossIsolateLock {
  CrossIsolateLock._();

  static Future<Directory?>? _baseDirFuture;

  /// Injectable for tests: point locks at a temp directory.
  static void overrideBaseDir(Future<Directory?> Function() resolver) {
    _baseDirFuture = resolver();
  }

  static Future<Directory?> _resolveBaseDir() {
    return _baseDirFuture ??= () async {
      try {
        return await getApplicationSupportDirectory();
      } catch (_) {
        return null;
      }
    }();
  }

  static Future<T> run<T>(
    String key,
    Future<T> Function() action, {
    Duration staleAfter = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async {
    final base = await _resolveBaseDir();
    if (base == null || key.isEmpty) return action();

    final lockFile = File(
      '${base.path}${Platform.pathSeparator}locks'
      '${Platform.pathSeparator}$key.lock',
    );

    while (true) {
      try {
        await lockFile.parent.create(recursive: true);
        final claimed = await lockFile.create(exclusive: true, recursive: true);
        await claimed.writeAsString(DateTime.now().toIso8601String());
        break;
      } on FileSystemException {
        // Someone else holds the lock. Steal it only when provably stale.
        try {
          final modified = await lockFile.lastModified();
          if (DateTime.now().difference(modified) > staleAfter) {
            try {
              await lockFile.delete();
            } catch (_) {}
            await Future<void>.delayed(pollInterval);
            continue;
          }
        } catch (_) {}
        await Future<void>.delayed(pollInterval);
      } catch (_) {
        // Unexpected FS failure — degrade to unserialised execution rather
        // than blocking the caller forever.
        return action();
      }
    }

    try {
      return await action();
    } finally {
      try {
        await lockFile.delete();
      } catch (_) {}
    }
  }
}
