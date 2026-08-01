import 'dart:convert';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/async_lock.dart';
import '../domain/models/credentials.dart';

/// Class representing a saved account profile.
class SavedAccountProfile {
  final String puuid;
  final String displayName;
  final String region;
  final String shard;
  final Credentials credentials;

  const SavedAccountProfile({
    required this.puuid,
    required this.displayName,
    required this.region,
    required this.shard,
    required this.credentials,
  });

  Map<String, dynamic> toJson() => {
        'puuid': puuid,
        'displayName': displayName,
        'region': region,
        'shard': shard,
        'accessToken': credentials.accessToken,
        'idToken': credentials.idToken,
        'entitlementToken': credentials.entitlementToken,
        'expiresAt': credentials.expiresAt.toIso8601String(),
        'entitlementExpiresAt': credentials.entitlementExpiresAt.toIso8601String(),
      };

  factory SavedAccountProfile.fromJson(Map<String, dynamic> json) {
    final creds = Credentials(
      accessToken: json['accessToken'] as String? ?? '',
      idToken: json['idToken'] as String? ?? '',
      entitlementToken: json['entitlementToken'] as String? ?? '',
      puuid: json['puuid'] as String? ?? '',
      region: json['region'] as String? ?? 'ap',
      shard: json['shard'] as String? ?? 'ap',
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ?? DateTime.now(),
      entitlementExpiresAt:
          DateTime.tryParse(json['entitlementExpiresAt'] as String? ?? '') ?? DateTime.now(),
    );

    return SavedAccountProfile(
      puuid: json['puuid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Valorant Account',
      region: json['region'] as String? ?? 'ap',
      shard: json['shard'] as String? ?? 'ap',
      credentials: creds,
    );
  }
}

/// Reads and writes [Credentials] and multi-account profiles to/from [SecureStorage].
class CredentialsLocalSource {
  const CredentialsLocalSource(this._storage);

  final SecureStorage _storage;
  static const _keySavedAccounts = 'valapp_saved_accounts_v1';

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
    final entitlementExpiresAtStr =
        await _storage.read(SecureStorage.keyEntitlementExpiresAt);

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
    final entitlementExpiresAt = entitlementExpiresAtStr != null
        ? DateTime.tryParse(entitlementExpiresAtStr) ?? DateTime.now()
        : DateTime.now();

    return Credentials(
      accessToken: accessToken,
      idToken: idToken ?? '',
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: region,
      shard: shard,
      expiresAt: expiresAt,
      entitlementExpiresAt: entitlementExpiresAt,
    );
  }

  Future<void> save(Credentials creds, {String? displayName}) async {
    await AsyncLock.run('credentials_save', () async {
      await Future.wait([
        _storage.write(SecureStorage.keyAccessToken, creds.accessToken),
        _storage.write(SecureStorage.keyIdToken, creds.idToken),
        _storage.write(SecureStorage.keyEntitlementToken, creds.entitlementToken),
        _storage.write(SecureStorage.keyPuuid, creds.puuid),
        _storage.write(SecureStorage.keyRegion, creds.region),
        _storage.write(SecureStorage.keyShard, creds.shard),
        _storage.write(
            SecureStorage.keyExpiresAt, creds.expiresAt.toIso8601String()),
        _storage.writeEntitlementExpiry(creds.entitlementExpiresAt),
      ]);

      // Also add/update profile in saved accounts list
      final profiles = await getSavedAccounts();
      final idx = profiles.indexWhere((p) => p.puuid == creds.puuid);
      final newProfile = SavedAccountProfile(
        puuid: creds.puuid,
        displayName: displayName ?? (idx != -1 ? profiles[idx].displayName : 'Account (${creds.puuid.substring(0, 6)})'),
        region: creds.region,
        shard: creds.shard,
        credentials: creds,
      );

      if (idx != -1) {
        profiles[idx] = newProfile;
      } else {
        profiles.add(newProfile);
      }

      await _saveProfiles(profiles);
    });
  }

  Future<List<SavedAccountProfile>> getSavedAccounts() async {
    final raw = await _storage.read(_keySavedAccounts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>? ?? [];
      return list.map((e) => SavedAccountProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeAccount(String puuid) async {
    await AsyncLock.run('credentials_save', () async {
      final profiles = await getSavedAccounts();
      profiles.removeWhere((p) => p.puuid == puuid);
      await _saveProfiles(profiles);

      // If active account was removed, clear current credentials
      final currentPuuid = await _storage.read(SecureStorage.keyPuuid);
      if (currentPuuid == puuid) {
        if (profiles.isNotEmpty) {
          await save(profiles.first.credentials);
        } else {
          await clear();
        }
      }
    });
  }

  Future<void> _saveProfiles(List<SavedAccountProfile> profiles) async {
    final encoded = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(_keySavedAccounts, encoded);
  }

  Future<void> clear() => _storage.deleteAll();
}
