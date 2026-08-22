/// Account XP and level info.
class AccountXp {
  /// Account Points (AP) required to advance one account level.
  /// Verified flat at 5,000 AP across ALL levels.
  ///
  /// Source: Riot official blog — "VALORANT Account Leveling Explained"
  /// https://playvalorant.com/en-gb/news/game-updates/valorant-account-leveling-explained/
  /// Quote: "Your account level goes up with every 5,000 AP you earn."
  ///
  /// Note: Riot calls this "Account Points (AP)", not XP. The field name
  /// `xpPerLevel` is kept for code consistency but refers to AP.
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
        .whereType<Map>()
        .map((e) => XpEntry.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
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
