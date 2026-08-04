import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/loadout/domain/models/player_loadout.dart';

void main() {
  group('WeaponLoadout attachments', () {
    test('reads buddy level from ItemID list schema', () {
      final weapon = WeaponLoadout.fromJson({
        'ID': 'weapon',
        'Attachments': [
          {'SocketID': 'buddy', 'ItemID': 'buddy-level'},
        ],
      });

      expect(weapon.buddyId, 'buddy-level');
    });

    test('reads buddy level from ItemID map schema', () {
      final weapon = WeaponLoadout.fromJson({
        'ID': 'weapon',
        'Attachments': {
          'buddy': {'ItemID': 'buddy-level'},
        },
      });

      expect(weapon.buddyId, 'buddy-level');
    });
  });
}
