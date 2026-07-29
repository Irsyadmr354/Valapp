import '../../../core/storage/secure_storage.dart';
import '../domain/models/credentials.dart';

/// Reads and writes [Credentials] to/from [SecureStorage].
class CredentialsLocalSource {
  const CredentialsLocalSource(this._storage);

  final SecureStorage _storage;

  /// Returns [Credentials] if all required keys are present, otherwise null.
  Future<Credentials?> load() async {
    final accessToken = await _storage.read(SecureStorage.keyAccessToken);
    final idToken = await _storage.read(SecureStorage.keyIdToken);
    final entitlementToken =
        await _storage.read(SecureStorage.keyEntitlementToken);
    final puuid = await _storage.read(SecureStorage.keyPuuid);
    final region = await _storage.read(SecureStorage.keyRegion);
    final shard = await _storage.read(SecureStorage.keyShard);
    final expiresAtStr = await _storage.read(SecureStorage.keyExpiresAt);

    if (accessToken == null ||
        entitlementToken == null ||
        puuid == null ||
        region == null ||
        shard == null) {
      return null;
    }

    final expiresAt = expiresAtStr != null
        ? DateTime.tryParse(expiresAtStr) ?? DateTime.now()
        : DateTime.now();

    return Credentials(
      accessToken: accessToken,
      idToken: idToken ?? '',
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: region,
      shard: shard,
      expiresAt: expiresAt,
    );
  }

  Future<void> save(Credentials creds) async {
    await Future.wait([
      _storage.write(SecureStorage.keyAccessToken, creds.accessToken),
      _storage.write(SecureStorage.keyIdToken, creds.idToken),
      _storage.write(SecureStorage.keyEntitlementToken, creds.entitlementToken),
      _storage.write(SecureStorage.keyPuuid, creds.puuid),
      _storage.write(SecureStorage.keyRegion, creds.region),
      _storage.write(SecureStorage.keyShard, creds.shard),
      _storage.write(
          SecureStorage.keyExpiresAt, creds.expiresAt.toIso8601String()),
    ]);
  }

  Future<void> clear() => _storage.deleteAll();
}
