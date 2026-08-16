/// Central repository for official Valorant constants, UUIDs, CDN asset URLs,
/// and API endpoint templates.
class ValorantCurrencies {
  ValorantCurrencies._();

  static const String vpUuid = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  static const String rpUuid = 'e59aa87c-4cbf-517a-5983-6e81511be9b7';
  static const String kcUuid = '85ca954a-41f2-ce94-9b45-8ca3dd39a00d';
  static const String freeAgentUuid = 'f08d4ae3-939c-4576-ab26-09ce1f23bb37';

  static const String vpCdnUrl =
      'https://media.valorant-api.com/currencies/85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741/displayicon.png';
  static const String kcCdnUrl =
      'https://media.valorant-api.com/currencies/85ca954a-41f2-ce94-9b45-8ca3dd39a00d/displayicon.png';
  static const String rpCdnUrl =
      'https://media.valorant-api.com/currencies/e59aa87c-4cbf-517a-5983-6e81511be9b7/displayicon.png';
}

/// Official Riot Content Tier UUIDs and CDN icon URLs.
class ValorantContentTiers {
  ValorantContentTiers._();

  static const String selectUuid = '12683d76-48d7-84a3-4e09-6985794f0445';
  static const String deluxeUuid = '0cebb8be-46d7-c12a-d306-e9907bfc5a25';
  static const String premiumUuid = '60bca009-4182-7998-dee7-b8a2558dc369';
  static const String ultraUuid = '411e4a55-4e59-7757-41f0-86a53f101bb5';
  static const String exclusiveUuid = 'e046854e-406c-37f4-6607-19a9ba8426fc';

  static const String selectCdnUrl =
      'https://media.valorant-api.com/contenttiers/12683d76-48d7-84a3-4e09-6985794f0445/displayicon.png';
  static const String deluxeCdnUrl =
      'https://media.valorant-api.com/contenttiers/0cebb8be-46d7-c12a-d306-e9907bfc5a25/displayicon.png';
  static const String premiumCdnUrl =
      'https://media.valorant-api.com/contenttiers/60bca009-4182-7998-dee7-b8a2558dc369/displayicon.png';
  static const String ultraCdnUrl =
      'https://media.valorant-api.com/contenttiers/411e4a55-4e59-7757-41f0-86a53f101bb5/displayicon.png';
  static const String exclusiveCdnUrl =
      'https://media.valorant-api.com/contenttiers/e046854e-406c-37f4-6607-19a9ba8426fc/displayicon.png';

  static String? cdnUrlForUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    final lower = uuid.toLowerCase();
    if (lower.contains('12683d76')) return selectCdnUrl;
    if (lower.contains('0cebb8be')) return deluxeCdnUrl;
    if (lower.contains('60bca009')) return premiumCdnUrl;
    if (lower.contains('411e4a55')) return ultraCdnUrl;
    if (lower.contains('e046854e')) return exclusiveCdnUrl;
    return null;
  }
}

/// Base URL builders for Riot PVP endpoints.
class RiotEndpoints {
  RiotEndpoints._();

  static String pd(String shard) =>
      'https://pd.${shard.toLowerCase()}.a.pvp.net';

  static String shared(String shard) =>
      'https://shared.${shard.toLowerCase()}.a.pvp.net';

  static String glz(String shard) {
    final clean = shard.toLowerCase();
    return 'https://glz-$clean-1.$clean.a.pvp.net';
  }
}
