/// Represents a single active restriction/penalty.
class AccountPenalty {
  final String id;
  final String type; // e.g. "queue_delay", "communication_restricted", "afk_penalty"
  final String title;
  final String description;
  final DateTime? expiryTime;

  const AccountPenalty({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.expiryTime,
  });

  bool get isExpired =>
      expiryTime != null && expiryTime!.isBefore(DateTime.now());

  factory AccountPenalty.fromJson(Map<String, dynamic> json) {
    final expiryStr = json['expiry']?.toString() ??
        json['expiryTime']?.toString() ??
        json['expiration']?.toString();
    DateTime? expiry;
    if (expiryStr != null && expiryStr.isNotEmpty) {
      try {
        expiry = DateTime.parse(expiryStr);
      } catch (_) {}
    }

    final rawType = json['type']?.toString() ??
        json['interventionType']?.toString() ??
        json['reason']?.toString() ??
        'restriction';

    String title = 'ACCOUNT RESTRICTION';
    if (rawType.contains('afk')) {
      title = 'AFK / DISCONNECT PENALTY';
    } else if (rawType.contains('comm') || rawType.contains('mute')) {
      title = 'COMMUNICATION RESTRICTION';
    } else if (rawType.contains('queue')) {
      title = 'MATCHMAKING QUEUE DELAY';
    } else if (rawType.contains('queue_ban') || rawType.contains('ban')) {
      title = 'MATCHMAKING SUSPENSION';
    }

    return AccountPenalty(
      id: json['id']?.toString() ?? json['Subject']?.toString() ?? '',
      type: rawType,
      title: title,
      description: json['description']?.toString() ??
          json['details']?.toString() ??
          'Active restriction applied to your Riot account.',
      expiryTime: expiry,
    );
  }
}

/// Represents an avoided player in the avoid list.
class AvoidedPlayer {
  final String puuid;
  final String displayName;
  final DateTime? addedAt;

  const AvoidedPlayer({
    required this.puuid,
    required this.displayName,
    this.addedAt,
  });

  factory AvoidedPlayer.fromJson(Map<String, dynamic> json) {
    return AvoidedPlayer(
      puuid: json['puuid']?.toString() ?? json['Subject']?.toString() ?? '',
      displayName: json['gameName'] != null
          ? '${json['gameName']}#${json['tagLine'] ?? ''}'
          : (json['displayName']?.toString() ?? 'Avoided Player'),
    );
  }
}

/// Aggregated account health status.
class AccountHealth {
  final bool isClean;
  final List<AccountPenalty> penalties;
  final List<AvoidedPlayer> avoidedPlayers;

  const AccountHealth({
    required this.isClean,
    required this.penalties,
    required this.avoidedPlayers,
  });

  factory AccountHealth.fromJson({
    Map<String, dynamic>? penaltiesJson,
    Map<String, dynamic>? avoidListJson,
  }) {
    final rawPenalties = (penaltiesJson?['Penalties'] as List<dynamic>?) ??
        (penaltiesJson?['interventions'] as List<dynamic>?) ??
        (penaltiesJson?['activeFutureInterventions'] as List<dynamic>?) ??
        [];

    final penalties = rawPenalties
        .map((e) => AccountPenalty.fromJson(e as Map<String, dynamic>))
        .where((p) => !p.isExpired)
        .toList();

    final rawAvoid = (avoidListJson?['avoidList'] as List<dynamic>?) ??
        (avoidListJson?['players'] as List<dynamic>?) ??
        [];

    final avoided = rawAvoid
        .map((e) => AvoidedPlayer.fromJson(e as Map<String, dynamic>))
        .toList();

    return AccountHealth(
      isClean: penalties.isEmpty,
      penalties: penalties,
      avoidedPlayers: avoided,
    );
  }
}
