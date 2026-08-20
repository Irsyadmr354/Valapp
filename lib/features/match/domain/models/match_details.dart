// ── Shared MatchResult import for extension ─────────────────────────────────
// match_history.dart defines MatchResult (Victory/Defeat/Draw/Unknown).
// ignore: always_use_package_imports
import 'match_history.dart' show MatchResult;

// ── Match info ────────────────────────────────────────────────────────────────

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

  Duration get gameDuration => Duration(milliseconds: gameLengthMillis);

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

  double get averageScore => roundsPlayed > 0 ? score / roundsPlayed : 0.0;

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    final gameName =
        json['gameName']?.toString() ?? json['GameName']?.toString() ?? '';
    final tagLine =
        json['tagLine']?.toString() ?? json['TagLine']?.toString() ?? '';
    final name = gameName.isNotEmpty ? '$gameName#$tagLine' : '';

    return PlayerStats(
      puuid: json['subject']?.toString() ?? json['Subject']?.toString() ?? '',
      displayName: name,
      teamId: json['teamId']?.toString() ?? json['TeamId']?.toString() ?? '',
      agentId: json['characterId']?.toString() ??
          json['CharacterId']?.toString() ??
          '',
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
      plantTime: (json['bombPlanter'] != null
              ? (json['plantRoundTime'] as num?)?.toInt()
              : null) ??
          0,
      defuseTime: (json['bombDefuser'] != null
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
    final matchInfo =
        MatchInfo.fromJson(json['matchInfo'] as Map<String, dynamic>? ?? {});

    // Parse playerIdentities map: subject -> "GameName#TagLine"
    final playerIdentitiesMap = <String, String>{};
    final identities = (json['playerIdentities'] as List<dynamic>? ?? []);
    for (final item in identities) {
      if (item is Map) {
        final subject = item['subject']?.toString() ??
            item['Subject']?.toString() ??
            item['puuid']?.toString() ??
            '';
        final gName =
            item['gameName']?.toString() ?? item['GameName']?.toString() ?? '';
        final tag =
            item['tagLine']?.toString() ?? item['TagLine']?.toString() ?? '';
        if (subject.isNotEmpty && gName.isNotEmpty) {
          playerIdentitiesMap[subject] = tag.isNotEmpty ? '$gName#$tag' : gName;
        }
      }
    }

    final players = (json['players'] as List<dynamic>? ?? []).map((e) {
      final pMap = e as Map<String, dynamic>;
      final player = PlayerStats.fromJson(pMap);
      if (player.displayName.isEmpty &&
          playerIdentitiesMap.containsKey(player.puuid)) {
        return PlayerStats(
          puuid: player.puuid,
          displayName: playerIdentitiesMap[player.puuid]!,
          teamId: player.teamId,
          agentId: player.agentId,
          kills: player.kills,
          deaths: player.deaths,
          assists: player.assists,
          score: player.score,
          roundsPlayed: player.roundsPlayed,
          competitiveTier: player.competitiveTier,
        );
      }
      return player;
    }).toList();

    final rounds = (json['roundResults'] as List<dynamic>? ?? [])
        .map((e) => RoundResult.fromJson(e as Map<String, dynamic>))
        .toList();

    return MatchDetails(
        matchInfo: matchInfo, players: players, roundResults: rounds);
  }
}

// ── Match Result Extension ────────────────────────────────────────────────────

/// Calculates match result for a given player from round results.
/// Extracted to a single place to avoid duplicating this logic across
/// providers and screens.
///
/// Note: Riot's private match-details API does not expose a top-level
/// `teams[].Won` boolean in the responses observed (only the public
/// VAL-MATCH-V1 endpoint does). We therefore derive result from
/// roundResults, which is accurate for all standard game modes.
extension MatchResultCalculator on MatchDetails {
  ({int mine, int opponents})? _roundWinsForPlayer(String puuid) {
    final player = players
        .cast<PlayerStats?>()
        .firstWhere((p) => p?.puuid == puuid, orElse: () => null);
    if (player == null || player.teamId.isEmpty || roundResults.isEmpty) {
      return null;
    }
    final playerTeam = player.teamId.toLowerCase();
    final winners = roundResults
        .map((round) => round.winningTeam.toLowerCase())
        .where((team) => team.isNotEmpty);
    return (
      mine: winners.where((team) => team == playerTeam).length,
      opponents: winners.where((team) => team != playerTeam).length,
    );
  }

  /// Returns the match outcome for [puuid] based on round wins/losses.
  /// Returns [MatchResult.unknown] if the player is not found or there are
  /// no round results (e.g. Deathmatch, or incomplete data).
  MatchResult resultForPlayer(String puuid) {
    final wins = _roundWinsForPlayer(puuid);
    if (wins == null) return MatchResult.unknown;
    final myWins = wins.mine;
    final oppWins = wins.opponents;
    if (myWins == 0 && oppWins == 0) return MatchResult.unknown;
    if (myWins > oppWins) {
      return MatchResult.victory;
    }
    if (myWins < oppWins) {
      return MatchResult.defeat;
    }
    return MatchResult.draw;
  }

  /// Builds the round-score string (e.g. "13 – 8") for [puuid].
  /// Returns null when the player is not found or there are no round results.
  /// Single source of truth for the score string — used by the shared
  /// enriched-history provider and the match history screen.
  String? scoreStringForPlayer(String puuid) {
    final wins = _roundWinsForPlayer(puuid);
    if (wins == null || (wins.mine == 0 && wins.opponents == 0)) return null;
    return '${wins.mine} – ${wins.opponents}';
  }
}
