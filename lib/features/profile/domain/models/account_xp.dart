/// Account XP and level info.
class AccountXp {
  final String puuid;
  final int level;
  final int xp;
  final List<XpEntry> history;

  const AccountXp({
    required this.puuid,
    required this.level,
    required this.xp,
    required this.history,
  });

  factory AccountXp.fromJson(Map<String, dynamic> json) {
    final progress = json['Progress'] as Map<String, dynamic>? ?? {};
    final history = (json['History'] as List<dynamic>? ?? [])
        .map((e) => XpEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return AccountXp(
      puuid: json['Subject'] as String? ?? '',
      level: (progress['Level'] as num?)?.toInt() ?? 0,
      xp: (progress['XP'] as num?)?.toInt() ?? 0,
      history: history,
    );
  }
}

class XpEntry {
  final String matchId;
  final int xpEarned;
  final int playedAt;

  const XpEntry({
    required this.matchId,
    required this.xpEarned,
    required this.playedAt,
  });

  DateTime get playedAtTime =>
      DateTime.fromMillisecondsSinceEpoch(playedAt);

  factory XpEntry.fromJson(Map<String, dynamic> json) {
    return XpEntry(
      matchId: json['ID'] as String? ?? '',
      xpEarned: (json['XPDelta'] as num?)?.toInt() ?? 0,
      playedAt: (json['Time'] as num?)?.toInt() ?? 0,
    );
  }
}
