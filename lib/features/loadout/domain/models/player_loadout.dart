/// Represents the player's currently equipped cosmetic loadout.
class PlayerLoadout {
  final String puuid;
  final String? playerCardId;
  final String? playerTitleId;
  final String? sprayId; // pre-round spray slot 0
  final List<WeaponLoadout> weapons;

  const PlayerLoadout({
    required this.puuid,
    this.playerCardId,
    this.playerTitleId,
    this.sprayId,
    required this.weapons,
  });

  /// Safely coerce any [value] to a `Map<String, dynamic>`, returning an
  /// empty map if [value] is null, a List, a primitive, or otherwise uncastable.
  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      try {
        return Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    return {};
  }

  /// Safely coerce [value] to a `List<dynamic>`, returning [] for anything else.
  static List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) return value;
    if (value is List) return List<dynamic>.from(value);
    return [];
  }

  factory PlayerLoadout.fromJson(Map<String, dynamic> json) {
    // v3 endpoint wraps everything under a "Loadout" key;
    // v2 returns the fields at root — support both.
    final root = json.containsKey('Loadout') ? _asMap(json['Loadout']) : json;

    final identity = _asMap(root['Identity']);
    final spraysBag = _asMap(root['Sprays']);
    final spraySelections = _asList(spraysBag['SpraySelections']);

    // Slot 0 = PreRound spray (SocketID ends with '01')
    String? preRoundSpray;
    for (final s in spraySelections) {
      final sMap = _asMap(s);
      final socketId = sMap['SocketID'] as String? ?? '';
      if (socketId.endsWith('01')) {
        preRoundSpray = sMap['SprayID'] as String?;
        break;
      }
    }
    // Fallback: first spray in the list
    if (preRoundSpray == null && spraySelections.isNotEmpty) {
      preRoundSpray = _asMap(spraySelections.first)['SprayID'] as String?;
    }

    final rawGuns = _asList(root['Guns']);
    final weapons = rawGuns
        .map((g) {
          final gMap = _asMap(g);
          if (gMap.isEmpty) return null;
          return WeaponLoadout.fromJson(gMap);
        })
        .whereType<WeaponLoadout>()
        .toList();

    return PlayerLoadout(
      puuid: root['Subject'] as String? ?? json['Subject'] as String? ?? '',
      playerCardId: identity['PlayerCardID'] as String?,
      playerTitleId: identity['PlayerTitleID'] as String?,
      sprayId: preRoundSpray,
      weapons: weapons,
    );
  }

  /// Extracts the PlayerCardID from a raw loadout JSON response.
  /// Handles both v2 (fields at root) and v3 (`Loadout` wrapper) formats.
  ///
  /// Shared by [playerCardArtProvider] and [AuthRepository.resolveAndSaveMetadata]
  /// to avoid duplicating the `Loadout → Identity → PlayerCardID` extraction.
  static String? extractPlayerCardId(Map<String, dynamic> raw) {
    final root = raw.containsKey('Loadout') ? _asMap(raw['Loadout']) : raw;
    final identity = _asMap(root['Identity'] ?? raw['Identity']);
    return identity['PlayerCardID'] as String? ??
        root['PlayerCardID'] as String? ??
        raw['PlayerCardID'] as String?;
  }

  /// Resolves player card art URLs (smallArt, wideArt) from a valorant-api
  /// player cards map, given a [cardId].
  ///
  /// Returns a `(smallArt, wideArt)` record, either or both of which may be null.
  static ({String? smallArt, String? wideArt}) resolveCardArtUrls(
    String cardId,
    Map<String, dynamic> cardsMap,
  ) {
    final cardInfo = (cardsMap[cardId] ?? cardsMap[cardId.toLowerCase()])
        as Map<String, dynamic>?;
    return (
      smallArt: cardInfo?['smallArt'] as String? ??
          cardInfo?['displayIcon'] as String?,
      wideArt: cardInfo?['largeArt'] as String? ??
          cardInfo?['wideArt'] as String? ??
          cardInfo?['displayIcon'] as String?,
    );
  }
}

/// A single weapon slot in the loadout.
class WeaponLoadout {
  final String weaponId;
  final String? skinLevelId;
  final String? chromaId;
  final String? buddyId; // gun buddy level UUID (nullable)

  const WeaponLoadout({
    required this.weaponId,
    this.skinLevelId,
    this.chromaId,
    this.buddyId,
  });

  factory WeaponLoadout.fromJson(Map<String, dynamic> json) {
    // Attachments can be a List OR a Map depending on Riot API version
    String? buddyId;
    final rawAttachments = json['Attachments'];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map) {
          buddyId ??= a['CharmLevelID'] as String? ?? a['ItemID'] as String?;
        }
      }
    } else if (rawAttachments is Map) {
      // Some responses embed attachments as a Map keyed by socket UUID
      for (final v in rawAttachments.values) {
        if (v is Map) {
          buddyId ??= v['CharmLevelID'] as String? ?? v['ItemID'] as String?;
        }
      }
    }

    return WeaponLoadout(
      weaponId: json['ID'] as String? ?? '',
      skinLevelId: json['SkinLevelID'] as String?,
      chromaId: json['ChromaID'] as String?,
      buddyId: buddyId,
    );
  }
}
