import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/exceptions/auth_exception.dart';

/// Unifies reconnect and data invalidation logic across all presentation screens.
///
/// If stored credentials exist:
/// - If accessToken is not expired, fast-refreshes only the entitlement token (<200ms).
/// - If accessToken is expired, runs silent reauth.
/// - Invalidate credentials and target data providers.
/// - If unrecoverable auth failure occurs, triggers [onPermanentAuthFailure] (e.g. redirect to login).
Future<void> reconnectAndInvalidate(
  WidgetRef ref, {
  required VoidCallback invalidateData,
  VoidCallback? onPermanentAuthFailure,
}) async {
  try {
    final local = ref.read(credentialsLocalSourceProvider);
    final creds = await local.load();
    if (creds != null && !creds.isExpired) {
      final authRepo = await ref.read(authRepositoryProvider.future);
      await authRepo.refreshEntitlementOnly(creds);
    } else if (creds != null) {
      final authRepo = await ref.read(authRepositoryProvider.future);
      await authRepo.reauth();
    }
    ref.invalidate(currentCredentialsProvider);
    invalidateData();
  } on InvalidSessionException catch (e) {
    debugPrint('[SessionReconnect] Permanent session error: $e');
    onPermanentAuthFailure?.call();
  } on TokenExpiredException catch (e) {
    debugPrint('[SessionReconnect] Token expired error: $e');
    onPermanentAuthFailure?.call();
  } catch (e) {
    debugPrint('[SessionReconnect] Non-permanent reconnect attempt: $e');
    // For transient/network errors, preserve session and still invalidate to retry provider fetch
    ref.invalidate(currentCredentialsProvider);
    invalidateData();
  }
}
