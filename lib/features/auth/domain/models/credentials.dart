/// Holds all auth credentials for the logged-in account.
class Credentials {
  final String accessToken;
  final String idToken;
  final String entitlementToken;
  final String puuid;
  final String region;
  final String shard;
  final DateTime expiresAt;

  const Credentials({
    required this.accessToken,
    required this.idToken,
    required this.entitlementToken,
    required this.puuid,
    required this.region,
    required this.shard,
    required this.expiresAt,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  /// Returns the correct shard for a given region.
  static String shardForRegion(String region) {
    switch (region.toLowerCase()) {
      case 'na':
      case 'latam':
      case 'br':
        return 'na';
      case 'eu':
        return 'eu';
      case 'ap':
        return 'ap';
      case 'kr':
        return 'kr';
      default:
        return 'na';
    }
  }

  Credentials copyWith({
    String? accessToken,
    String? idToken,
    String? entitlementToken,
    String? puuid,
    String? region,
    String? shard,
    DateTime? expiresAt,
  }) {
    return Credentials(
      accessToken: accessToken ?? this.accessToken,
      idToken: idToken ?? this.idToken,
      entitlementToken: entitlementToken ?? this.entitlementToken,
      puuid: puuid ?? this.puuid,
      region: region ?? this.region,
      shard: shard ?? this.shard,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
