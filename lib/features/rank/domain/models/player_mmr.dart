/// RR change from a single competitive match.
class CompetitiveUpdate {
  final String matchId;
  final int tierAfterUpdate;
  final int tierBeforeUpdate;
  final int rankedRatingAfterUpdate;
  final int rankedRatingBeforeUpdate;
  final int rankedRatingEarned;
  final int afkPenalty;
  final int gameStartMillis;
  final String? mapId;

  const CompetitiveUpdate({
    required this.matchId,
    required this.tierAfterUpdate,
    required this.tierBeforeUpdate,
    required this.rankedRatingAfterUpdate,
    required this.rankedRatingBeforeUpdate,
    required this.rankedRatingEarned,
    required this.afkPenalty,
    required this.gameStartMillis,
    this.mapId,
  });

  DateTime get gameStartTime =>
      DateTime.fromMillisecondsSinceEpoch(gameStartMillis);

  bool get isWin => rankedRatingEarned > 0;

  factory CompetitiveUpdate.fromJson(Map<String, dynamic> json) {
    return CompetitiveUpdate(
      matchId: json['MatchID']?.toString() ?? '',
      tierAfterUpdate: (json['TierAfterUpdate'] as num?)?.toInt() ?? 0,
      tierBeforeUpdate: (json['TierBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingAfterUpdate:
          (json['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingBeforeUpdate:
          (json['RankedRatingBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingEarned:
          (json['RankedRatingEarned'] as num?)?.toInt() ?? 0,
      afkPenalty: (json['AFKPenalty'] as num?)?.toInt() ?? 0,
      gameStartMillis: (json['MatchStartTime'] as num?)?.toInt() ?? 0,
      mapId: json['MapID']?.toString(),
    );
  }
}

/// Player MMR snapshot — extracts current tier + RR from the MMR endpoint.
class PlayerMmr {
  final String puuid;
  final int currentTier;
  final int currentRankedRating;
  final int gamesNeededForRating;
  final CompetitiveUpdate? latestUpdate;

  const PlayerMmr({
    required this.puuid,
    required this.currentTier,
    required this.currentRankedRating,
    required this.gamesNeededForRating,
    this.latestUpdate,
  });

  factory PlayerMmr.fromJson(Map<String, dynamic> json) {
    CompetitiveUpdate? latestUpdate;

    // LatestCompetitiveUpdate can be an empty map {} when unranked
    final latest = json['LatestCompetitiveUpdate'];
    if (latest is Map && latest.isNotEmpty) {
      try {
        latestUpdate =
            CompetitiveUpdate.fromJson(Map<String, dynamic>.from(latest));
      } catch (_) {}
    }

    // QueueSkills.competitive.SeasonalInfoBySeasonID has current tier
    int currentTier = latestUpdate?.tierAfterUpdate ?? 0;
    int currentRR = latestUpdate?.rankedRatingAfterUpdate ?? 0;
    int gamesNeeded = 0;

    try {
      final queueSkills = json['QueueSkills'] as Map<String, dynamic>?;
      final competitive =
          queueSkills?['competitive'] as Map<String, dynamic>?;

      if (competitive != null) {
        gamesNeeded =
            (competitive['CurrentSeasonGamesNeededForRating'] as num?)
                    ?.toInt() ??
                0;

        // If latestUpdate tier was 0, fallback to SeasonalInfoBySeasonID
        if (currentTier == 0) {
          final seasonal = competitive['SeasonalInfoBySeasonID']
              as Map<String, dynamic>?;
          if (seasonal != null && seasonal.isNotEmpty) {
            // Find active season with non-zero tier / games
            for (final seasonData in seasonal.values.toList().reversed) {
              if (seasonData is Map) {
                final tier = (seasonData['CompetitiveTier'] as num?)?.toInt() ?? 0;
                final rr = (seasonData['RankedRating'] as num?)?.toInt() ?? 0;
                final games = (seasonData['NumberOfGames'] as num?)?.toInt() ?? 0;
                if (tier > 0 || games > 0) {
                  currentTier = tier;
                  currentRR = rr;
                  break;
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Fall back to latestUpdate values already set above
    }

    return PlayerMmr(
      puuid: json['Subject']?.toString() ?? '',
      currentTier: currentTier,
      currentRankedRating: currentRR,
      gamesNeededForRating: gamesNeeded,
      latestUpdate: latestUpdate,
    );
  }
}

