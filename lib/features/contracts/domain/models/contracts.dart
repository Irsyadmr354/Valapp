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

  double get progressFraction =>
      progressToComplete > 0 ? currentProgress / progressToComplete : 0.0;

  factory Mission.fromJson(Map<String, dynamic> json) {
    final expiry = json['ExpirationTime'] as String?;

    // Objectives is a Map<objectiveId, progressValue>
    // Sum all objective progress values
    final objectives = json['Objectives'] as Map<String, dynamic>? ?? {};
    int totalProgress = 0;
    for (final val in objectives.values) {
      totalProgress += (val as num?)?.toInt() ?? 0;
    }

    return Mission(
      missionId: json['ID'] as String? ?? '',
      title: json['Title'] as String? ?? 'Mission',
      progressToComplete:
          (json['ProgressToComplete'] as num?)?.toInt() ?? totalProgress.clamp(1, 999999),
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
    return Contract(
      contractId: json['ContractDefinitionID'] as String? ?? '',
      progressionLevelReached:
          (json['ContractProgression']?['HighestRewardedLevel']?[
                  'ProgressionLevel'] as num?)
              ?.toInt() ??
              0,
      progressionTowardsNextLevel:
          (json['ContractProgression']?['ProgressionTowardsNextLevel']
                  as num?)
              ?.toInt() ??
              0,
      isActiveBattlepass: json['ContractDefinitionID'] == activeSpecialContractId,
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
    try {
      return contracts.firstWhere((c) => c.contractId == activeSpecialContractId);
    } catch (_) {
      return null;
    }
  }

  factory PlayerContracts.fromJson(Map<String, dynamic> json) {
    final activeContractId = json['ActiveSpecialContract'] as String? ?? '';
    final contracts = (json['Contracts'] as List<dynamic>? ?? [])
        .map((e) => Contract.fromJson(
            e as Map<String, dynamic>, activeContractId))
        .toList();
    final missions = (json['Missions'] as List<dynamic>? ?? [])
        .map((e) => Mission.fromJson(e as Map<String, dynamic>))
        .toList();
    return PlayerContracts(
      activeSpecialContractId: activeContractId,
      contracts: contracts,
      missions: missions,
    );
  }
}
