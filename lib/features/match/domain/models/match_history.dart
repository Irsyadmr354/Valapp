/// Summary entry from match history endpoint.
class MatchHistoryEntry {
  final String matchId;
  final int gameStartMillis;
  final String queueId;   // Riot returns this as String e.g. "competitive"
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

  String get queueDisplayName {
    switch (queueId.toLowerCase()) {
      case 'competitive': return 'Competitive';
      case 'unrated': return 'Unrated';
      case 'spikerush': return 'Spike Rush';
      case 'deathmatch': return 'Deathmatch';
      case 'ggteam': return 'Escalation';
      case 'onefa': return 'Replication';
      case 'hurm': return 'Team Deathmatch';
      case 'swiftplay': return 'Swiftplay';
      default: return queueId.isEmpty ? 'Custom' : queueId;
    }
  }

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      matchId: json['MatchID'] as String? ?? '',
      gameStartMillis: (json['GameStartTime'] as num?)?.toInt() ?? 0,
      // QueueID is a String in Riot's API, not a num
      queueId: json['QueueID']?.toString() ?? '',
      teamId: json['TeamID']?.toString() ?? '',
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
