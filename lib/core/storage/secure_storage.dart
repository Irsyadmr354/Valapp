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
  static const keyEntitlementExpiresAt = 'entitlement_expires_at';

  /// Single JSON blob holding ALL active-session fields. Written atomically
  /// (one [write]) as the source of truth so credentials are never observed in
  /// a partially-written state (P0: the previous 8-key `Future.wait` could
  /// leave a torn session if interrupted mid-way). The individual keys above
  /// are kept in sync as a fast read path for the interceptor/background task
  /// and as a migration fallback.
  static const keyActiveSession = 'active_session_snapshot_v2';
  static const keyRiotCookiesRaw = 'riot_cookies_raw';

  /// Generates a per-account secure storage key for Riot session cookies.
  static String keyRiotCookiesFor(String puuid) => '${keyRiotCookiesRaw}_$puuid';

  /// Conservative estimate — Riot does not expose entitlement token TTL.
  /// Tune here if stale-400 errors persist after proactive refresh.
  static const entitlementTokenLifetime = Duration(minutes: 55);

  static const proactiveRefreshWindow = Duration(minutes: 5);

  // ── Methods ─────────────────────────────────────────────────────────────────

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();

  Future<void> writeEntitlementExpiry(DateTime expiresAt) => write(
        keyEntitlementExpiresAt,
        expiresAt.toIso8601String(),
      );
}
