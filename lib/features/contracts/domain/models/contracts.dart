/// A single mission with progress tracking.
class Mission {
  final String missionId;
  final String title;
  final int progressToComplete;
  final int progressionStatus;
  final DateTime? expirationTime;
  final List<String> tags;

  const Mission({
    required this.missionId,
    required this.title,
    required this.progressToComplete,
    required this.progressionStatus,
    this.expirationTime,
    required this.tags,
  });

  bool get isCompleted => progressionStatus >= progressToComplete;

  factory Mission.fromJson(Map<String, dynamic> json) {
    final expiry = json['ExpirationTime'] as String?;
    return Mission(
      missionId: json['ID'] as String? ?? '',
      title: json['Title'] as String? ?? 'Mission',
      progressToComplete:
          (json['ProgressToComplete'] as num?)?.toInt() ?? 1,
      progressionStatus:
          (json['ProgressionStatus'] as num?)?.toInt() ?? 0,
      expirationTime:
          expiry != null ? DateTime.tryParse(expiry) : null,
      tags: (json['Tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// A single contract/agent contract with progression.
class Contract {
  final String contractId;
  final int progressionLevelReached;
  final int progressionTowardsNextLevel;
  final bool isActive;

  const Contract({
    required this.contractId,
    required this.progressionLevelReached,
    required this.progressionTowardsNextLevel,
    required this.isActive,
  });

  factory Contract.fromJson(Map<String, dynamic> json, String? activePuuid) {
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
      isActive: json['ContractDefinitionID'] == activePuuid,
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
    final activePuuid = json['ActiveSpecialContract'] as String? ?? '';
    final contracts = (json['Contracts'] as List<dynamic>? ?? [])
        .map((e) => Contract.fromJson(
            e as Map<String, dynamic>, activePuuid))
        .toList();
    final missions = (json['Missions'] as List<dynamic>? ?? [])
        .map((e) => Mission.fromJson(e as Map<String, dynamic>))
        .toList();
    return PlayerContracts(
      activeSpecialContractId: activePuuid,
      contracts: contracts,
      missions: missions,
    );
  }
}
