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

    test('PlayerContracts.activeBattlepass matches activeSpecialContractId', () {
      final json = {
        'ActiveSpecialContract': 'bp-uuid-1234',
        'Contracts': [
          {
            'ContractDefinitionID': 'agent-contract-1',
            'ContractProgression': {'HighestRewardedLevel': {'ProgressionLevel': 5}},
          },
          {
            'ContractDefinitionID': 'bp-uuid-1234',
            'ContractProgression': {'HighestRewardedLevel': {'ProgressionLevel': 45}},
          },
        ],
        'Missions': [],
      };

      final playerContracts = PlayerContracts.fromJson(json);
      expect(playerContracts.activeSpecialContractId, equals('bp-uuid-1234'));
      expect(playerContracts.activeBattlepass, isNotNull);
      expect(playerContracts.activeBattlepass!.contractId, equals('bp-uuid-1234'));
      expect(playerContracts.activeBattlepass!.isActiveBattlepass, isTrue);
    });
  });
}
