/// Summary entry from match history endpoint.
class MatchHistoryEntry {
  final String matchId;
  final int gameStartMillis;
  final String queueId;   // Riot returns this as String e.g. "competitive"
  final String teamId;
  final bool isRanked;
  final String mapId;

  const MatchHistoryEntry({
    required this.matchId,
    required this.gameStartMillis,
    required this.queueId,
    required this.teamId,
    required this.isRanked,
    this.mapId = '',
  });

  DateTime get gameStartTime =>
      DateTime.fromMillisecondsSinceEpoch(gameStartMillis);

  String get mapDisplayName {
    if (mapId.isEmpty) return '';
    final raw = mapId.toLowerCase();

    if (raw.contains('plummet') || raw.contains('infinity') || raw.contains('abyss')) return 'Abyss';
    if (raw.contains('jam') || raw.contains('lotus')) return 'Lotus';
    if (raw.contains('juliett') || raw.contains('sunset')) return 'Sunset';
    if (raw.contains('canyon') || raw.contains('fracture')) return 'Fracture';
    if (raw.contains('port') || raw.contains('icebox')) return 'Icebox';
    if (raw.contains('lowpe') || raw.contains('pitt') || raw.contains('pearl')) return 'Pearl';
    if (raw.contains('foxtrot')) return 'Drift';
    if (raw.contains('triad') || raw.contains('haven')) return 'Haven';
    if (raw.contains('bonsai') || raw.contains('split')) return 'Split';
    if (raw.contains('duality') || raw.contains('bind')) return 'Bind';
    if (raw.contains('ascent')) return 'Ascent';
    if (raw.contains('breeze')) return 'Breeze';

    final parts = mapId.split('/');
    final last = parts.last.split('.').first;
    if (last.isEmpty) return '';
    return last[0].toUpperCase() + last.substring(1);
  }

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
      queueId: json['QueueID']?.toString() ?? '',
      teamId: json['TeamID']?.toString() ?? '',
      isRanked: json['IsRanked'] as bool? ?? false,
      mapId: json['MapID']?.toString() ?? json['mapId']?.toString() ?? '',
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
