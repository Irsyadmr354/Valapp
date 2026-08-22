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

/// Act Rank Season Data snapshot (pyramid wins, border level, tier distribution).
class ActRankSeasonData {
  final String seasonId;
  final int tier;
  final int rankedRating;
  final int numberOfWins;
  final Map<int, int> winsByTier;
  final int borderLevel;

  const ActRankSeasonData({
    required this.seasonId,
    required this.tier,
    required this.rankedRating,
    required this.numberOfWins,
    required this.winsByTier,
    required this.borderLevel,
  });

  /// Computes border level 0-5 from wins count if not provided directly by Riot
  static int computeBorderLevel(int wins) {
    if (wins >= 100) return 5;
    if (wins >= 75) return 4;
    if (wins >= 50) return 3;
    if (wins >= 25) return 2;
    if (wins >= 9) return 1;
    return 0;
  }

  /// Calculates wins needed for the next border level
  int get winsNeededForNextBorder {
    if (numberOfWins >= 100) return 0;
    if (numberOfWins >= 75) return 100 - numberOfWins;
    if (numberOfWins >= 50) return 75 - numberOfWins;
    if (numberOfWins >= 25) return 50 - numberOfWins;
    if (numberOfWins >= 9) return 25 - numberOfWins;
    return 9 - numberOfWins;
  }

  /// Returns sorted list of up to 49 win tier IDs for painting the Act Pyramid
  List<int> get winTierList {
    final list = <int>[];
    final sortedKeys = winsByTier.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final tierId in sortedKeys) {
      final count = winsByTier[tierId] ?? 0;
      for (var i = 0; i < count; i++) {
        list.add(tierId);
        if (list.length >= 49) break;
      }
      if (list.length >= 49) break;
    }
    return list;
  }

  /// Highest tier with at least 1 win
  int get peakWinTier {
    if (winsByTier.isEmpty) return tier;
    final keys = winsByTier.keys.where((k) => (winsByTier[k] ?? 0) > 0);
    if (keys.isEmpty) return tier;
    return keys.reduce((a, b) => a > b ? a : b);
  }

  factory ActRankSeasonData.fromJson(
      String seasonId, Map<String, dynamic> json) {
    final tier = (json['CompetitiveTier'] as num?)?.toInt() ?? 0;
    final rr = (json['RankedRating'] as num?)?.toInt() ?? 0;
    final wins = (json['NumberOfWins'] as num?)?.toInt() ?? 0;
    final rawBorder = (json['BorderLevel'] as num?)?.toInt();
    final borderLevel = rawBorder ?? computeBorderLevel(wins);

    final winsMap = <int, int>{};
    final rawWinsByTier = json['WinsByTier'];
    if (rawWinsByTier is Map) {
      rawWinsByTier.forEach((k, v) {
        final tierId = int.tryParse(k.toString());
        final count = (v as num?)?.toInt();
        if (tierId != null && count != null && count > 0) {
          winsMap[tierId] = count;
        }
      });
    }

    return ActRankSeasonData(
      seasonId: seasonId,
      tier: tier,
      rankedRating: rr,
      numberOfWins: wins,
      winsByTier: winsMap,
      borderLevel: borderLevel,
    );
  }
}

/// Player MMR snapshot — extracts current tier + RR + Act Rank seasonal info.
class PlayerMmr {
  final String puuid;
  final int currentTier;
  final int currentRankedRating;
  final int gamesNeededForRating;
  final CompetitiveUpdate? latestUpdate;
  final Map<String, ActRankSeasonData> seasonalData;
  final String? activeSeasonId;

  const PlayerMmr({
    required this.puuid,
    required this.currentTier,
    required this.currentRankedRating,
    required this.gamesNeededForRating,
    this.latestUpdate,
    this.seasonalData = const {},
    this.activeSeasonId,
  });

  ActRankSeasonData? get activeSeasonData =>
      activeSeasonId != null ? seasonalData[activeSeasonId] : null;

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

    int currentTier = latestUpdate?.tierAfterUpdate ?? 0;
    int currentRR = latestUpdate?.rankedRatingAfterUpdate ?? 0;
    int gamesNeeded = 0;
    final seasonalMap = <String, ActRankSeasonData>{};
    String? activeSeasonId;

    try {
      final rawQueueSkills = json['QueueSkills'];
      final queueSkills = rawQueueSkills is Map ? rawQueueSkills : null;
      final rawComp = queueSkills?['competitive'];
      final competitive = rawComp is Map ? rawComp : null;

      if (competitive != null) {
        gamesNeeded = (competitive['CurrentSeasonGamesNeededForRating'] as num?)
                ?.toInt() ??
            0;

        activeSeasonId = latestUpdate?.seasonId ??
            competitive['CurrentSeasonID']?.toString() ??
            json['CurrentSeasonID']?.toString();

        final rawSeasonal = competitive['SeasonalInfoBySeasonID'];
        if (rawSeasonal is Map) {
          rawSeasonal.forEach((key, val) {
            if (key is String && val is Map) {
              seasonalMap[key] = ActRankSeasonData.fromJson(
                key,
                Map<String, dynamic>.from(val),
              );
            }
          });
        }

        if (currentTier == 0 && activeSeasonId != null) {
          final activeData = seasonalMap[activeSeasonId];
          if (activeData != null) {
            currentTier = activeData.tier;
            currentRR = activeData.rankedRating;
          }
        }
      }
    } catch (_) {
      // Fall back to latestUpdate values
    }

    return PlayerMmr(
      puuid: json['Subject']?.toString() ?? '',
      currentTier: currentTier,
      currentRankedRating: currentRR,
      gamesNeededForRating: gamesNeeded,
      latestUpdate: latestUpdate,
      seasonalData: seasonalMap,
      activeSeasonId: activeSeasonId,
    );
  }
}
