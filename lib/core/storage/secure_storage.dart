import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper around [FlutterSecureStorage] for all sensitive credentials.
/// Keys are defined as static constants so there are no magic strings.
class SecureStorage {
  SecureStorage._();

  static final SecureStorage instance = SecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── Key Constants ──────────────────────────────────────────────────────────

  static const keyAccessToken = 'access_token';
  static const keyIdToken = 'id_token';
  static const keyEntitlementToken = 'entitlement_token';
  static const keyPuuid = 'puuid';
  static const keyRegion = 'region';
  static const keyShard = 'shard';
  static const keyExpiresAt = 'token_expires_at';

  // ── Methods ─────────────────────────────────────────────────────────────────

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();

  /// Returns true if all required auth credentials are present.
  Future<bool> hasCredentials() async {
    final accessToken = await _storage.read(key: keyAccessToken);
    final entitlementToken = await _storage.read(key: keyEntitlementToken);
    final puuid = await _storage.read(key: keyPuuid);
    return accessToken != null &&
        entitlementToken != null &&
        puuid != null;
  }

  /// Returns whether the stored access token is still valid (> 5 min left).
  Future<bool> isTokenValid() async {
    final expiresAtStr = await _storage.read(key: keyExpiresAt);
    if (expiresAtStr == null) return false;
    try {
      final expiresAt = DateTime.parse(expiresAtStr);
      return DateTime.now()
          .isBefore(expiresAt.subtract(const Duration(minutes: 5)));
    } catch (_) {
      return false;
    }
  }
}
