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
  final String? seasonId;

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
    this.seasonId,
  });

  DateTime get gameStartTime =>
      DateTime.fromMillisecondsSinceEpoch(gameStartMillis);

  bool get isWin => rankedRatingEarned > 0;

  bool get isLoss => rankedRatingEarned < 0;

  /// A match is a draw when no RR was earned or lost and there was no AFK
  /// penalty. We intentionally do NOT additionally require tier equality
  /// because Riot can adjust tiers independently of RR in edge cases (e.g.
  /// provisional placements), which would make those entries appear as
  /// neither win, loss, nor draw.
  bool get isDraw => rankedRatingEarned == 0 && afkPenalty == 0;

  factory CompetitiveUpdate.fromJson(Map<String, dynamic> json) {
    return CompetitiveUpdate(
      matchId: json['MatchID']?.toString() ?? '',
      tierAfterUpdate: (json['TierAfterUpdate'] as num?)?.toInt() ?? 0,
      tierBeforeUpdate: (json['TierBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingAfterUpdate:
          (json['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingBeforeUpdate:
          (json['RankedRatingBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingEarned: (json['RankedRatingEarned'] as num?)?.toInt() ?? 0,
      afkPenalty: (json['AFKPenalty'] as num?)?.toInt() ?? 0,
      gameStartMillis: (json['MatchStartTime'] as num?)?.toInt() ?? 0,
      mapId: json['MapID']?.toString(),
      seasonId: json['SeasonID']?.toString(),
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
      final competitive = queueSkills?['competitive'] as Map<String, dynamic>?;

      if (competitive != null) {
        gamesNeeded = (competitive['CurrentSeasonGamesNeededForRating'] as num?)
                ?.toInt() ??
            0;

        // Map iteration order is not chronology. Only use seasonal data when
        // Riot identifies which season is current.
        if (currentTier == 0) {
          final rawSeasonal = competitive['SeasonalInfoBySeasonID'];
          final seasonal = rawSeasonal is Map ? rawSeasonal : null;
          final activeSeasonId = latestUpdate?.seasonId ??
              competitive['CurrentSeasonID']?.toString() ??
              json['CurrentSeasonID']?.toString();
          final seasonData =
              activeSeasonId == null ? null : seasonal?[activeSeasonId];
          if (seasonData is Map) {
            currentTier = (seasonData['CompetitiveTier'] as num?)?.toInt() ?? 0;
            currentRR = (seasonData['RankedRating'] as num?)?.toInt() ?? 0;
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
