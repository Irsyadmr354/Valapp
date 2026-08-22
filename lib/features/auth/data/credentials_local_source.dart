import 'dart:convert';
import '../../../core/storage/secure_storage.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../../../core/utils/async_lock.dart';
import '../domain/models/credentials.dart';
import 'oauth_flow.dart';

/// Class representing a saved account profile.
class SavedAccountProfile {
  final String puuid;
  final String displayName;
  final String region;
  final String shard;
  final String? playerCardId;
  final String? avatarUrl;
  final Credentials credentials;

  const SavedAccountProfile({
    required this.puuid,
    required this.displayName,
    required this.region,
    required this.shard,
    this.playerCardId,
    this.avatarUrl,
    required this.credentials,
  });

  Map<String, dynamic> toJson() => {
        'puuid': puuid,
        'displayName': displayName,
        'region': region,
        'shard': shard,
        'playerCardId': playerCardId,
        'avatarUrl': avatarUrl,
        'accessToken': credentials.accessToken,
        'idToken': credentials.idToken,
        'entitlementToken': credentials.entitlementToken,
        'expiresAt': credentials.expiresAt.toIso8601String(),
        'entitlementExpiresAt':
            credentials.entitlementExpiresAt.toIso8601String(),
      };

  factory SavedAccountProfile.fromJson(Map<String, dynamic> json) {
    final creds = CredentialsLocalSource.credentialsFromJson(json);
    final displayName = json['displayName'];
    final playerCardId = json['playerCardId'];
    final avatarUrl = json['avatarUrl'];
    if (creds == null ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        displayName.length > 128 ||
        (playerCardId != null &&
            (playerCardId is! String || playerCardId.trim().isEmpty)) ||
        (avatarUrl != null &&
            (avatarUrl is! String || !_isSafeHttpsUrl(avatarUrl)))) {
      throw const FormatException('Invalid saved account profile');
    }

    return SavedAccountProfile(
      puuid: creds.puuid,
      displayName: displayName.trim(),
      region: creds.region,
      shard: creds.shard,
      playerCardId: playerCardId as String?,
      avatarUrl: avatarUrl as String?,
      credentials: creds,
    );
  }

  static bool _isSafeHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}

/// Reads and writes [Credentials] and multi-account profiles to/from [SecureStorage].
class CredentialsLocalSource {
  CredentialsLocalSource(this._storage, [this._cache]);

  final SecureStorage _storage;
  final CacheStorage? _cache;
  static const _keySavedAccounts = 'valapp_saved_accounts_v1';

  /// Hot-path variant of [load] with a short instance-local memo (2 s).
  ///
  /// The network interceptor reads credentials TWICE per request (proactive
  /// check + header injection); every read also JWT-decodes twice. This memo
  /// collapses those into one storage read + decode per 2 s window without
  /// changing [load] semantics anywhere else — mutation flows, tests, and
  /// direct-storage writers keep exact freshness guarantees.
  ///
  /// A ≤2 s-stale view is safe here: a mid-window account switch makes the
  /// next API call fail auth, and the reactive retry path re-reads via
  /// [load] (always fresh) before sending.
  Future<Credentials?> loadCached() async {
    final memo = _hotMemo;
    if (memo != null &&
        DateTime.now().difference(_hotMemoAt) < hotMemoTtl) {
      return memo;
    }
    final fresh = await load();
    _hotMemo = fresh;
    _hotMemoAt = DateTime.now();
    return fresh;
  }

  Credentials? _hotMemo;
  DateTime _hotMemoAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const hotMemoTtl = Duration(milliseconds: 2000);

  /// Returns [Credentials] if all required keys are present, otherwise null.
  Future<Credentials?> load() async {
    // Preferred source: the atomically-written session snapshot (single write,
    // never torn). Falls back to the individual keys (pre-snapshot installs).
    final snapshot = await _storage.read(SecureStorage.keyActiveSession);
    if (snapshot != null && snapshot.isNotEmpty) {
      try {
        final json = jsonDecode(snapshot) as Map<String, dynamic>;
        final creds = credentialsFromJson(json);
        if (creds != null) return creds;
      } catch (_) {
        // Malformed snapshot — fall through to individual keys below.
      }
    }

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

    return credentialsFromJson({
      'accessToken': accessToken,
      'idToken': idToken,
      'entitlementToken': entitlementToken,
      'puuid': puuid,
      'region': region,
      'shard': shard,
      'expiresAt': expiresAtStr,
      'entitlementExpiresAt': entitlementExpiresAtStr,
    });
  }

  /// Saves refreshed credentials only if the same session is still active.
  /// The comparison and write share the credentials lock, so an account switch
  /// cannot land between them and then be overwritten by an older reauth.
  ///
  /// Cross-isolate freshness guard (H2): the workmanager isolate can hold
  /// tokens captured BEFORE the foreground completed a newer reauth for the
  /// same account. Without this guard its late write would REGRESS the stored
  /// `expiresAt`. Skipped-as-stale returns TRUE — the session is fine; a
  /// fresher writer already handled persistence.
  Future<bool> saveIfCurrent(
    Credentials expected,
    Credentials updated,
  ) async {
    return AsyncLock.run('credentials_save', () async {
      final current = await load();
      if (current?.puuid != expected.puuid) {
        return false;
      }
      // Entitlement-only refreshes keep `expiresAt` unchanged (copyWith), so
      // they still pass this guard via equality; full reauths always produce
      // a strictly later expiry.
      if (current != null && updated.expiresAt.isBefore(current.expiresAt)) {
        return true;
      }
      await _saveInternal(updated);
      return true;
    });
  }

  /// Builds [Credentials] from a snapshot blob, or null if required fields are absent.
  static Credentials? credentialsFromJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken'] as String?;
    final idToken = json['idToken'] as String?;
    final entitlementToken = json['entitlementToken'] as String?;
    final puuid = json['puuid'] as String?;
    final region = json['region'] as String?;
    final shard = json['shard'] as String?;
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    final entitlementExpiresAt =
        DateTime.tryParse(json['entitlementExpiresAt'] as String? ?? '');
    if (accessToken == null ||
        accessToken.trim().isEmpty ||
        idToken == null ||
        idToken.trim().isEmpty ||
        entitlementToken == null ||
        entitlementToken.trim().isEmpty ||
        puuid == null ||
        puuid.trim().isEmpty ||
        puuid.length > 128 ||
        region == null ||
        !Credentials.isSupportedRegion(region) ||
        shard == null ||
        shard != Credentials.shardForRegion(region) ||
        expiresAt == null ||
        entitlementExpiresAt == null) {
      return null;
    }
    try {
      final accessSubject = OAuthFlow.decodeJwtPayload(accessToken)['sub'];
      final idSubject = OAuthFlow.decodeJwtPayload(idToken)['sub'];
      if (accessSubject != puuid ||
          (idSubject is String && idSubject.isNotEmpty && idSubject != puuid)) {
        return null;
      }
    } on AuthException {
      return null;
    }
    return Credentials(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: region,
      shard: shard,
      expiresAt: expiresAt,
      entitlementExpiresAt: entitlementExpiresAt,
    );
  }

  Future<void> save(Credentials creds,
      {String? displayName, String? playerCardId, String? avatarUrl}) async {
    if (credentialsFromJson({
          'accessToken': creds.accessToken,
          'idToken': creds.idToken,
          'entitlementToken': creds.entitlementToken,
          'puuid': creds.puuid,
          'region': creds.region,
          'shard': creds.shard,
          'expiresAt': creds.expiresAt.toIso8601String(),
          'entitlementExpiresAt': creds.entitlementExpiresAt.toIso8601String(),
        }) ==
        null) {
      throw const FormatException('Invalid credentials');
    }
    await AsyncLock.run(
        'credentials_save',
        () => _saveInternal(creds,
            displayName: displayName,
            playerCardId: playerCardId,
            avatarUrl: avatarUrl));
  }

  /// Updates a saved profile without changing the active session.
  Future<void> updateAccountMetadata(
    String puuid, {
    String? displayName,
    String? playerCardId,
    String? avatarUrl,
  }) async {
    _validateProfileMetadata(
      displayName: displayName,
      playerCardId: playerCardId,
      avatarUrl: avatarUrl,
    );
    await AsyncLock.run('credentials_save', () async {
      final profiles = await getSavedAccounts();
      final idx = profiles.indexWhere((profile) => profile.puuid == puuid);
      if (idx == -1) return;

      final existing = profiles[idx];
      profiles[idx] = SavedAccountProfile(
        puuid: existing.puuid,
        displayName: displayName ?? existing.displayName,
        region: existing.region,
        shard: existing.shard,
        playerCardId: playerCardId ?? existing.playerCardId,
        avatarUrl: avatarUrl ?? existing.avatarUrl,
        credentials: existing.credentials,
      );
      await _saveProfiles(profiles);
    });
  }

  /// Core save logic — runs INSIDE an existing lock or standalone.
  /// Do NOT call [save] from within a 'credentials_save' lock; call this
  /// instead to avoid the non-reentrant mutex deadlocking.
  Future<void> _saveInternal(
    Credentials creds, {
    String? displayName,
    String? playerCardId,
    String? avatarUrl,
  }) async {
    final changesAccount = _cache != null && _cache.activePuuid != creds.puuid;

    _validateProfileMetadata(
      displayName: displayName,
      playerCardId: playerCardId,
      avatarUrl: avatarUrl,
    );
    // 1. Write the atomic session snapshot FIRST — a single SecureStorage write
    //    so the active session is never observed torn (P0: the previous
    //    8-key Future.wait could leave a partially-written session if the app
    //    was killed mid-write).
    await _storage.write(
      SecureStorage.keyActiveSession,
      jsonEncode({
        'accessToken': creds.accessToken,
        'idToken': creds.idToken,
        'entitlementToken': creds.entitlementToken,
        'puuid': creds.puuid,
        'region': creds.region,
        'shard': creds.shard,
        'expiresAt': creds.expiresAt.toIso8601String(),
        'entitlementExpiresAt': creds.entitlementExpiresAt.toIso8601String(),
      }),
    );
    if (changesAccount) {
      await _cache.setActiveSession(creds.puuid);
    }

    // 2. Mirror legacy keys for migration compatibility. Multi-field readers
    //    must use the atomic snapshot above, never these independently.
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
    final existing = idx != -1 ? profiles[idx] : null;

    final newProfile = SavedAccountProfile(
      puuid: creds.puuid,
      displayName: displayName ??
          (existing != null
              ? existing.displayName
              : 'Account (${creds.puuid.length > 6 ? creds.puuid.substring(0, 6) : creds.puuid})'),
      region: creds.region,
      shard: creds.shard,
      playerCardId: playerCardId ?? existing?.playerCardId,
      avatarUrl: avatarUrl ?? existing?.avatarUrl,
      credentials: creds,
    );

    if (idx != -1) {
      profiles[idx] = newProfile;
    } else {
      profiles.add(newProfile);
    }

    await _saveProfiles(profiles);
  }

  Future<List<SavedAccountProfile>> getSavedAccounts() async {
    final raw = await _storage.read(_keySavedAccounts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final profiles = <SavedAccountProfile>[];
      for (final value in list) {
        try {
          if (value is Map<String, dynamic>) {
            profiles.add(SavedAccountProfile.fromJson(value));
          }
        } on FormatException {
          // Keep valid accounts if one persisted profile is corrupt.
        }
      }
      return profiles;
    } catch (_) {
      return [];
    }
  }

  Future<void> removeAccount(String puuid) async {
    await AsyncLock.run('credentials_save', () async {
      final profiles = await getSavedAccounts();
      profiles.removeWhere((p) => p.puuid == puuid);
      await _saveProfiles(profiles);
      await _cache?.clearUserCache(puuid: puuid);

      // Also remove the removed account's per-user wishlist namespace —
      // clearUserCache intentionally preserves wishlists on SWITCH, but a
      // deleted account must not leave orphaned keys behind.
      if (_cache != null && puuid.isNotEmpty) {
        await _cache.remove(CacheStorage.wishlistKeyFor(puuid));
      }

      // If active account was removed, tear down its session entirely.
      // Selecting & activating the next account is the CALLER's job
      // (SessionActions) — it must also purge HTTP cookie jars / native
      // WebView stores first, otherwise a stale-cookie silent reauth can
      // resurrect the just-removed account and trip the puuid guard.
      final currentPuuid = (await load())?.puuid;
      await _storage.delete(SecureStorage.keyRiotCookiesFor(puuid));
      if (currentPuuid == puuid) {
        await _clearActiveSessionKeysInternal(currentPuuid);
      }
    });
  }

  Future<void> _saveProfiles(List<SavedAccountProfile> profiles) async {
    final encoded = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(_keySavedAccounts, encoded);
  }

  static void _validateProfileMetadata({
    String? displayName,
    String? playerCardId,
    String? avatarUrl,
  }) {
    if ((displayName != null &&
            (displayName.trim().isEmpty || displayName.length > 128)) ||
        (playerCardId != null && playerCardId.trim().isEmpty) ||
        (avatarUrl != null &&
            !SavedAccountProfile._isSafeHttpsUrl(avatarUrl))) {
      throw const FormatException('Invalid account profile metadata');
    }
  }

  /// Removes only the active session tokens from secure storage, leaving the
  /// saved accounts list intact so other accounts remain switchable.
  /// Call this when a single account's reauth fails permanently (Opsi A:
  /// also remove the failed account's entry from the saved list).
  ///
  /// Serialized under the 'credentials_save' lock: without it, a concurrent
  /// login/switch could write a fresh snapshot between our read and deletes,
  /// and we would wipe a brand-new session.
  Future<void> clearActiveSessionOnly() {
    return AsyncLock.run('credentials_save', () async {
      final currentPuuid = (await load())?.puuid;
      await _clearActiveSessionKeysInternal(currentPuuid);
    });
  }

  /// Core teardown of active-session keys. Runs INSIDE an existing
  /// 'credentials_save' lock — do not wrap again (non-reentrant mutex).
  Future<void> _clearActiveSessionKeysInternal(String? currentPuuid) async {
    await _cache?.setActiveSession('', clearPrevious: true);
    final deletes = <Future<void>>[
      _storage.delete(SecureStorage.keyAccessToken),
      _storage.delete(SecureStorage.keyIdToken),
      _storage.delete(SecureStorage.keyEntitlementToken),
      _storage.delete(SecureStorage.keyPuuid),
      _storage.delete(SecureStorage.keyRegion),
      _storage.delete(SecureStorage.keyShard),
      _storage.delete(SecureStorage.keyExpiresAt),
      _storage.delete(SecureStorage.keyEntitlementExpiresAt),
      _storage.delete(SecureStorage.keyActiveSession),
      _storage.delete(SecureStorage.keyRiotCookiesRaw),
    ];
    if (currentPuuid != null && currentPuuid.isNotEmpty) {
      deletes.add(
        _storage.delete(SecureStorage.keyRiotCookiesFor(currentPuuid)),
      );
    }
    await Future.wait(deletes);
  }

  Future<void> clear() async {
    await _cache?.setActiveSession('', clearPrevious: true);
    await _storage.deleteAll();
  }
}
