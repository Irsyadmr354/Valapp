/// Summary entry from match history endpoint.
class MatchHistoryEntry {
  final String matchId;
  final int gameStartMillis;
  final int queueId;
  final String teamId;
  final bool isRanked;

  const MatchHistoryEntry({
    required this.matchId,
    required this.gameStartMillis,
    required this.queueId,
    required this.teamId,
    required this.isRanked,
  });

  DateTime get gameStartTime =>
      DateTime.fromMillisecondsSinceEpoch(gameStartMillis);

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      matchId: json['MatchID'] as String? ?? '',
      gameStartMillis:
          (json['GameStartTime'] as num?)?.toInt() ?? 0,
      queueId: (json['QueueID'] as num?)?.toInt() ?? 0,
      teamId: json['TeamID'] as String? ?? '',
      isRanked: json['IsRanked'] as bool? ?? false,
    );
  }
}

class MatchHistoryResult {
  final String puuid;
  final int total;
  final int start;
  final int end;
  final List<MatchHistoryEntry> matches;

  const MatchHistoryResult({
    required this.puuid,
    required this.total,
    required this.start,
    required this.end,
    required this.matches,
  });

  factory MatchHistoryResult.fromJson(Map<String, dynamic> json) {
    final matches = (json['History'] as List<dynamic>? ?? [])
        .map((e) => MatchHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return MatchHistoryResult(
      puuid: json['Subject'] as String? ?? '',
      total: (json['Total'] as num?)?.toInt() ?? 0,
      start: (json['BeginIndex'] as num?)?.toInt() ?? 0,
      end: (json['EndIndex'] as num?)?.toInt() ?? 0,
      matches: matches,
    );
  }
}
