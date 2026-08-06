/// A single mission with progress tracking.
class Mission {
  final String missionId;
  final String title;
  final int progressToComplete;
  final int currentProgress;
  final bool isCompleted;
  final DateTime? expirationTime;
  final int xpGrant;

  const Mission({
    required this.missionId,
    required this.title,
    required this.progressToComplete,
    required this.currentProgress,
    required this.isCompleted,
    this.expirationTime,
    this.xpGrant = 0,
  });

  double get progressFraction => isCompleted
      ? 1.0
      : progressToComplete > 0
          ? currentProgress / progressToComplete
          : 0.0;

  factory Mission.fromJson(Map<String, dynamic> json) {
    final expiry = json['ExpirationTime'] as String?;

    // Objectives is a Map<objectiveId, progressValue>
    // Sum all objective progress values
    final rawObjectives = json['Objectives'];
    final objectives = rawObjectives is Map ? rawObjectives : const {};
    int totalProgress = 0;
    for (final val in objectives.values) {
      totalProgress += (val as num?)?.toInt() ?? 0;
    }

    return Mission(
      missionId: json['ID'] as String? ?? '',
      title: json['Title'] as String? ?? 'Mission',
      progressToComplete: (json['ProgressToComplete'] as num?)?.toInt() ?? 0,
      currentProgress: totalProgress,
      isCompleted: json['Complete'] as bool? ?? false,
      expirationTime: expiry != null ? DateTime.tryParse(expiry) : null,
      xpGrant: (json['XPGrant'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single contract/agent contract with progression.
class Contract {
  final String contractId;
  final int progressionLevelReached;
  final int progressionTowardsNextLevel;
  final bool isActiveBattlepass;

  const Contract({
    required this.contractId,
    required this.progressionLevelReached,
    required this.progressionTowardsNextLevel,
    required this.isActiveBattlepass,
  });

  factory Contract.fromJson(
      Map<String, dynamic> json, String? activeSpecialContractId) {
    int level = 0;
    int nextLevelXp = 0;

    final prog = json['ContractProgression'];
    if (prog is Map) {
      final map = Map<String, dynamic>.from(prog);
      final rawLevel = map['ProgressionLevelReached'] ??
          (map['HighestRewardedLevel'] is Map
              ? map['HighestRewardedLevel']['ProgressionLevel'] ??
                  map['HighestRewardedLevel']['Amount']
              : map['HighestRewardedLevel']) ??
          map['ProgressionLevel'];

      if (rawLevel is num) {
        level = rawLevel.toInt();
      } else if (rawLevel is String) {
        level = int.tryParse(rawLevel) ?? 0;
      }

      final rawNext = map['ProgressionTowardsNextLevel'] ??
          map['ProgressionTowardsNextLevelXP'] ??
          map['XPTowardsNextLevel'];
      if (rawNext is num) {
        nextLevelXp = rawNext.toInt();
      } else if (rawNext is String) {
        nextLevelXp = int.tryParse(rawNext) ?? 0;
      }
    } else {
      final rawLevel = json['ProgressionLevelReached'] ??
          json['HighestRewardedLevel'] ??
          json['ProgressionLevel'];
      if (rawLevel is num) {
        level = rawLevel.toInt();
      }
    }

    final contractId = json['ContractDefinitionID'] as String? ?? '';
    return Contract(
      contractId: contractId,
      progressionLevelReached: level,
      progressionTowardsNextLevel: nextLevelXp,
      isActiveBattlepass:
          contractId.isNotEmpty && contractId == activeSpecialContractId,
    );
  }
}

/// Full contracts snapshot for a player.
class PlayerContracts {
  final String activeSpecialContractId;
  final List<Contract> contracts;
  final List<Mission> missions;

  const PlayerContracts({
    required this.activeSpecialContractId,
    required this.contracts,
    required this.missions,
  });

  Contract? get activeBattlepass {
    if (activeSpecialContractId.isEmpty) return null;
    // Primary: match by activeSpecialContractId (most accurate)
    try {
      return contracts
          .firstWhere((c) => c.contractId == activeSpecialContractId);
    } catch (_) {}
    return null;
  }

  factory PlayerContracts.fromJson(Map<String, dynamic> json) {
    final activeContractId = json['ActiveSpecialContract'] as String? ?? '';
    final contracts = (json['Contracts'] is List
            ? json['Contracts'] as List
            : const <dynamic>[])
        .whereType<Map>()
        .map((e) =>
            Contract.fromJson(Map<String, dynamic>.from(e), activeContractId))
        .toList();
    final missions = (json['Missions'] is List
            ? json['Missions'] as List
            : const <dynamic>[])
        .whereType<Map>()
        .map((e) => Mission.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return PlayerContracts(
      activeSpecialContractId: activeContractId,
      contracts: contracts,
      missions: missions,
    );
  }
}
