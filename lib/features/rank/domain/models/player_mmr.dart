/// Current competitive tier and ranking info.
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
      matchId: json['MatchID'] as String? ?? '',
      tierAfterUpdate:
          (json['TierAfterUpdate'] as num?)?.toInt() ?? 0,
      tierBeforeUpdate:
          (json['TierBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingAfterUpdate:
          (json['RankedRatingAfterUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingBeforeUpdate:
          (json['RankedRatingBeforeUpdate'] as num?)?.toInt() ?? 0,
      rankedRatingEarned:
          (json['RankedRatingEarned'] as num?)?.toInt() ?? 0,
      afkPenalty: (json['AFKPenalty'] as num?)?.toInt() ?? 0,
      gameStartMillis:
          (json['MatchStartTime'] as num?)?.toInt() ?? 0,
      mapId: json['MapID'] as String?,
    );
  }
}

/// Player MMR snapshot.
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
    final latest = json['LatestCompetitiveUpdate'] as Map<String, dynamic>?;
    if (latest != null && latest.isNotEmpty) {
      latestUpdate = CompetitiveUpdate.fromJson(latest);
    }

    return PlayerMmr(
      puuid: json['Subject'] as String? ?? '',
      currentTier:
          (json['QueueSkills']?['competitive']?['CurrentSeasonGamesNeededForRating']
                  as num?)
              ?.toInt() ??
              latestUpdate?.tierAfterUpdate ??
              0,
      currentRankedRating: latestUpdate?.rankedRatingAfterUpdate ?? 0,
      gamesNeededForRating:
          (json['QueueSkills']?['competitive']?['CurrentSeasonGamesNeededForRating']
                  as num?)
              ?.toInt() ??
              0,
      latestUpdate: latestUpdate,
    );
  }
}
