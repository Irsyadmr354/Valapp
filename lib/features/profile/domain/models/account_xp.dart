/// Account XP and level info.
class AccountXp {
  /// AP required to advance one account level (flat across all levels).
  static const xpPerLevel = 5000;

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
  final DateTime playedAt;

  const XpEntry({
    required this.matchId,
    required this.xpEarned,
    required this.playedAt,
  });

  factory XpEntry.fromJson(Map<String, dynamic> json) {
    // MatchStart can be ISO 8601 string or epoch int
    DateTime parsedTime;
    final rawTime = json['MatchStart'];
    if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    } else if (rawTime is num) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawTime.toInt());
    } else {
      parsedTime = DateTime.now();
    }

    return XpEntry(
      matchId: json['ID'] as String? ?? '',
      xpEarned: (json['XPDelta'] as num?)?.toInt() ?? 0,
      playedAt: parsedTime,
    );
  }
}
