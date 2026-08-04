import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/contracts/domain/models/contracts.dart';

void main() {
  group('Contract & PlayerContracts tests', () {
    test('Contract.fromJson sets isActiveBattlepass correctly', () {
      final json = {
        'ContractDefinitionID': 'bp-uuid-1234',
        'ContractProgression': {
          'HighestRewardedLevel': {'ProgressionLevel': 10},
          'ProgressionTowardsNextLevel': 500,
        },
      };

      final activeBp = Contract.fromJson(json, 'bp-uuid-1234');
      final inactiveBp = Contract.fromJson(json, 'other-bp-uuid');

      expect(activeBp.isActiveBattlepass, isTrue);
      expect(inactiveBp.isActiveBattlepass, isFalse);
      expect(activeBp.progressionLevelReached, equals(10));
      expect(activeBp.progressionTowardsNextLevel, equals(500));
    });

    test('PlayerContracts.activeBattlepass matches activeSpecialContractId',
        () {
      final json = {
        'ActiveSpecialContract': 'bp-uuid-1234',
        'Contracts': [
          {
            'ContractDefinitionID': 'agent-contract-1',
            'ContractProgression': {
              'HighestRewardedLevel': {'ProgressionLevel': 5}
            },
          },
          {
            'ContractDefinitionID': 'bp-uuid-1234',
            'ContractProgression': {
              'HighestRewardedLevel': {'ProgressionLevel': 45}
            },
          },
        ],
        'Missions': [],
      };

      final playerContracts = PlayerContracts.fromJson(json);
      expect(playerContracts.activeSpecialContractId, equals('bp-uuid-1234'));
      expect(playerContracts.activeBattlepass, isNotNull);
      expect(
          playerContracts.activeBattlepass!.contractId, equals('bp-uuid-1234'));
      expect(playerContracts.activeBattlepass!.isActiveBattlepass, isTrue);
    });

    test('does not guess an agent contract when active id is unknown', () {
      final contracts = PlayerContracts.fromJson({
        'ActiveSpecialContract': 'missing-battlepass',
        'Contracts': [
          {
            'ContractDefinitionID': 'agent-contract',
            'ContractProgression': {
              'HighestRewardedLevel': {'ProgressionLevel': 50}
            },
          },
        ],
        'Missions': [],
      });

      expect(contracts.activeBattlepass, isNull);
    });

    test('mission progress does not treat current progress as its target', () {
      final mission = Mission.fromJson({
        'ID': 'mission-1',
        'Objectives': {'objective-1': 7},
      });

      expect(mission.currentProgress, 7);
      expect(mission.progressToComplete, 0);
      expect(mission.progressFraction, 0);
    });

    test('completed mission always reports complete progress', () {
      final mission = Mission.fromJson({
        'ID': 'mission-1',
        'Complete': true,
        'Objectives': <String, dynamic>{},
      });

      expect(mission.progressFraction, 1);
    });

    test('skips malformed contract and mission list entries', () {
      final contracts = PlayerContracts.fromJson({
        'Contracts': [
          null,
          'bad',
          {'ContractDefinitionID': 'valid'}
        ],
        'Missions': [
          3,
          {'ID': 'mission'}
        ],
      });

      expect(contracts.contracts.single.contractId, 'valid');
      expect(contracts.missions.single.missionId, 'mission');
    });
  });
}
