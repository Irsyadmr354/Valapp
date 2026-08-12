/// Centralized source of truth for Valorant API header constants.
class ValorantHeaders {
  ValorantHeaders._();

  /// Standard base64 Client Platform payload expected by Riot Games API endpoints:
  /// {"platformType": "PC", "platformOS": "Windows", "platformOSVersion": "10.0.19042.1.256.64bit", "platformChipset": "Unknown"}
  static const clientPlatform =
      'ew0KCSJwbGF0Zm9ybVR5cGUiOiAiUEMiLA0KCSJwbGF0Zm9ybU9TIjogIldpbmRvd3MiLA0KCSJwbGF0Zm9ybU9TVmVyc2lvbiI6ICIxMC4wLjE5MDQyLjEuMjU2LjY0Yml0IiwNCgkicGxhdGZvcm1DaGlwc2V0IjogIlVua25vd24iDQp9';

  static const headerAuth = 'Authorization';
  static const headerEntitlement = 'X-Riot-Entitlements-JWT';
  static const headerClientVersion = 'X-Riot-ClientVersion';
  static const headerClientPlatform = 'X-Riot-ClientPlatform';
}
