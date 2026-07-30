import '../data/auth_remote_source.dart';
import '../data/credentials_local_source.dart';
import '../data/silent_webview_reauth.dart';
import '../domain/models/credentials.dart';
import '../../../core/exceptions/auth_exception.dart';

/// Orchestrates the full RSO auth flow and token lifecycle.
class AuthRepository {
  const AuthRepository({
    required AuthRemoteSource remoteSource,
    required CredentialsLocalSource localSource,
  })  : _remote = remoteSource,
        _local = localSource;

  final AuthRemoteSource _remote;
  final CredentialsLocalSource _local;

  // ── Load stored credentials ────────────────────────────────────────────────

  Future<Credentials?> loadCredentials() => _local.load();

  // ── Full login flow ────────────────────────────────────────────────────────

  /// Step 1+2: Init session and submit password.
  /// Returns `{'type': 'response'}` or `{'type': 'multifactor', 'email': '...'}`.
  Future<Map<String, dynamic>> login(
      String username, String password) async {
    await _remote.initSession();
    return _remote.submitCredentials(username, password);
  }

  /// Step 3: Complete MFA and finish building credentials.
  Future<Credentials> completeMfa(String code) async {
    final uri = await _remote.submitMfaCode(code);
    return _buildCredentialsFromUri(uri);
  }

  /// Called when Step 2 returned `type: response` (no 2FA needed).
  Future<Credentials> completeLogin(String redirectUri) async {
    return _buildCredentialsFromUri(redirectUri);
  }

  /// Called after WebView login — tokens already parsed, just fetch
  /// entitlement + geo and save credentials.
  Future<Credentials> completeLoginFromWebView({
    required String accessToken,
    required String idToken,
    required int expiresIn,
  }) async {
    final entitlementToken =
        await _remote.fetchEntitlementToken(accessToken);
    final geoData =
        await _remote.fetchRegionAndShard(accessToken, idToken);
    final puuid = AuthRemoteSource.extractPuuid(accessToken);

    final credentials = Credentials(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: geoData['region']!,
      shard: geoData['shard']!,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );

    await _local.save(credentials);
    return credentials;
  }

  Future<Credentials> _buildCredentialsFromUri(String redirectUri) async {
    final tokens = AuthRemoteSource.parseTokensFromUri(redirectUri);
    final accessToken = tokens['access_token']!;
    final idToken = tokens['id_token']!;
    final expiresIn = int.parse(tokens['expires_in']!);

    final entitlementToken =
        await _remote.fetchEntitlementToken(accessToken);
    final geoData =
        await _remote.fetchRegionAndShard(accessToken, idToken);
    final puuid = AuthRemoteSource.extractPuuid(accessToken);

    final credentials = Credentials(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: geoData['region']!,
      shard: geoData['shard']!,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );

    await _local.save(credentials);
    return credentials;
  }

  // ── Silent token refresh ───────────────────────────────────────────────────

  /// Refreshes tokens silently using persisted cookies or background WebView session.
  /// Never throws TokenExpiredException unless both cookie reauth AND silent webview fail.
  Future<Credentials> reauth() async {
    String? uri;
    try {
      uri = await _remote.cookieReauth();
    } catch (_) {
      try {
        uri = await SilentWebviewReauth.instance.refreshTokens();
      } catch (_) {
        throw const TokenExpiredException();
      }
    }

    final tokens = AuthRemoteSource.parseTokensFromUri(uri!);
    final accessToken = tokens['access_token']!;
    final idToken = tokens['id_token']!;
    final expiresIn = int.parse(tokens['expires_in']!);

    final old = await _local.load();
    if (old == null) throw const TokenExpiredException();

    final entitlementToken =
        await _remote.fetchEntitlementToken(accessToken);

    final updated = old.copyWith(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );

    await _local.save(updated);
    return updated;
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() => _local.clear();
}
