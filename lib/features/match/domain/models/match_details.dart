/// High-level match info extracted from match details.
class MatchInfo {
  final String matchId;
  final String mapId;
  final String gameMode;
  final String queueId;
  final int gameLengthMillis;
  final int gameStartMillis;
  final bool isRanked;

  const MatchInfo({
    required this.matchId,
    required this.mapId,
    required this.gameMode,
    required this.queueId,
    required this.gameLengthMillis,
    required this.gameStartMillis,
    required this.isRanked,
  });

  DateTime get gameStartTime =>
      DateTime.fromMillisecondsSinceEpoch(gameStartMillis);

  Duration get gameDuration =>
      Duration(milliseconds: gameLengthMillis);

  factory MatchInfo.fromJson(Map<String, dynamic> json) {
    return MatchInfo(
      matchId: json['matchId'] as String? ?? '',
      mapId: json['mapId'] as String? ?? '',
      gameMode: json['gameMode'] as String? ?? '',
      queueId: json['queueId'] as String? ?? '',
      gameLengthMillis: (json['gameLengthMillis'] as num?)?.toInt() ?? 0,
      gameStartMillis: (json['gameStartMillis'] as num?)?.toInt() ?? 0,
      isRanked: json['isRanked'] as bool? ?? false,
    );
  }
}

/// Per-player stats in a match.
class PlayerStats {
  final String puuid;
  final String displayName;
  final String teamId;
  final String agentId;
  final int kills;
  final int deaths;
  final int assists;
  final int score;
  final int roundsPlayed;
  final int competitiveTier;

  const PlayerStats({
    required this.puuid,
    required this.displayName,
    required this.teamId,
    required this.agentId,
    required this.kills,
    required this.deaths,
    required this.assists,
    required this.score,
    required this.roundsPlayed,
    required this.competitiveTier,
  });

  bool get isPerfectKda => deaths == 0 && roundsPlayed > 0;

  double get kda =>
      roundsPlayed > 0 ? (kills + assists) / (deaths > 0 ? deaths : 1) : 0.0;

  double get averageScore =>
      roundsPlayed > 0 ? score / roundsPlayed : 0.0;

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    final gameName = json['gameName']?.toString() ?? json['GameName']?.toString() ?? '';
    final tagLine = json['tagLine']?.toString() ?? json['TagLine']?.toString() ?? '';
    final name = gameName.isNotEmpty ? '$gameName#$tagLine' : '';

    return PlayerStats(
      puuid: json['subject']?.toString() ?? json['Subject']?.toString() ?? '',
      displayName: name,
      teamId: json['teamId']?.toString() ?? json['TeamId']?.toString() ?? '',
      agentId: json['characterId']?.toString() ?? json['CharacterId']?.toString() ?? '',
      kills: (stats['kills'] as num?)?.toInt() ?? 0,
      deaths: (stats['deaths'] as num?)?.toInt() ?? 0,
      assists: (stats['assists'] as num?)?.toInt() ?? 0,
      score: (stats['score'] as num?)?.toInt() ?? 0,
      roundsPlayed: (stats['roundsPlayed'] as num?)?.toInt() ?? 0,
      competitiveTier: (json['competitiveTier'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Round result summary.
class RoundResult {
  final int roundNum;
  final String roundResult;
  final String roundCeremony;
  final String winningTeam;
  final int plantTime;
  final int defuseTime;

  const RoundResult({
    required this.roundNum,
    required this.roundResult,
    required this.roundCeremony,
    required this.winningTeam,
    required this.plantTime,
    required this.defuseTime,
  });

  factory RoundResult.fromJson(Map<String, dynamic> json) {
    return RoundResult(
      roundNum: (json['roundNum'] as num?)?.toInt() ?? 0,
      roundResult: json['roundResult'] as String? ?? '',
      roundCeremony: json['roundCeremony'] as String? ?? '',
      winningTeam: json['winningTeam'] as String? ?? '',
      plantTime:
          (json['bombPlanter'] != null
              ? (json['plantRoundTime'] as num?)?.toInt()
              : null) ??
              0,
      defuseTime:
          (json['bombDefuser'] != null
              ? (json['defuseRoundTime'] as num?)?.toInt()
              : null) ??
              0,
    );
  }
}

/// Full match details.
class MatchDetails {
  final MatchInfo matchInfo;
  final List<PlayerStats> players;
  final List<RoundResult> roundResults;

  const MatchDetails({
    required this.matchInfo,
    required this.players,
    required this.roundResults,
  });

  String get mapId => matchInfo.mapId;

  /// Returns stats for a specific player by PUUID.
  PlayerStats? playerStats(String puuid) {
    try {
      return players.firstWhere((p) => p.puuid == puuid);
    } catch (_) {
      return null;
    }
  }

  /// Returns a copy of MatchDetails with resolved player names.
  MatchDetails copyWithResolvedNames(Map<String, String> namesMap) {
    final updatedPlayers = players.map((p) {
      if (p.displayName.isEmpty && namesMap.containsKey(p.puuid)) {
        return PlayerStats(
          puuid: p.puuid,
          displayName: namesMap[p.puuid]!,
          teamId: p.teamId,
          agentId: p.agentId,
          kills: p.kills,
          deaths: p.deaths,
          assists: p.assists,
          score: p.score,
          roundsPlayed: p.roundsPlayed,
          competitiveTier: p.competitiveTier,
        );
      }
      return p;
    }).toList();

    return MatchDetails(
      matchInfo: matchInfo,
      players: updatedPlayers,
      roundResults: roundResults,
    );
  }

  factory MatchDetails.fromJson(Map<String, dynamic> json) {
    final matchInfo = MatchInfo.fromJson(
        json['matchInfo'] as Map<String, dynamic>? ?? {});
    final players = (json['players'] as List<dynamic>? ?? [])
        .map((e) => PlayerStats.fromJson(e as Map<String, dynamic>))
        .toList();
    final rounds = (json['roundResults'] as List<dynamic>? ?? [])
        .map((e) => RoundResult.fromJson(e as Map<String, dynamic>))
        .toList();
    return MatchDetails(
        matchInfo: matchInfo, players: players, roundResults: rounds);
  }
}

