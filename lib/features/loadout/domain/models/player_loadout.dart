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

  factory PlayerLoadout.fromJson(Map<String, dynamic> json) {
    final identity = json['Identity'] as Map<String, dynamic>? ?? {};
    final sprays = json['Sprays'] as Map<String, dynamic>? ?? {};
    final spraySelections =
        (sprays['SpraySelections'] as List<dynamic>?) ?? [];

    // Slot 0 = PreRound spray
    String? preRoundSpray;
    for (final s in spraySelections) {
      if (s is Map && (s['SocketID'] as String? ?? '').contains('01')) {
        preRoundSpray = s['SprayID'] as String?;
        break;
      }
    }
    if (preRoundSpray == null && spraySelections.isNotEmpty) {
      preRoundSpray =
          (spraySelections.first as Map<String, dynamic>)['SprayID']
              as String?;
    }

    final guns = (json['Guns'] as List<dynamic>?) ?? [];
    final weapons =
        guns.map((g) => WeaponLoadout.fromJson(g as Map<String, dynamic>)).toList();

    return PlayerLoadout(
      puuid: json['Subject'] as String? ?? '',
      playerCardId: identity['PlayerCardID'] as String?,
      playerTitleId: identity['PlayerTitleID'] as String?,
      sprayId: preRoundSpray,
      weapons: weapons,
    );
  }
}

/// A single weapon slot in the loadout.
class WeaponLoadout {
  final String weaponId; // e.g. the weapon type UUID
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
    final attachments = json['Attachments'] as List<dynamic>? ?? [];
    String? buddyId;
    for (final a in attachments) {
      if (a is Map) {
        buddyId ??= a['CharmLevelID'] as String?;
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
