import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_shop_monitor/features/profile/domain/models/account_health.dart';

void main() {
  group('AccountHealth Model Tests', () {
    test('parses clean account health correctly', () {
      final health = AccountHealth.fromJson(
        penaltiesJson: {'Penalties': []},
        avoidListJson: {'avoidList': []},
        interventionsJson: {'activeFutureInterventions': []},
        hasFetchErrors: false,
      );

      expect(health.status, AccountHealthStatus.clean);
      expect(health.isClean, isTrue);
      expect(health.isUnknown, isFalse);
      expect(health.penalties, isEmpty);
      expect(health.avoidedPlayers, isEmpty);
    });

    test('parses active penalties and interventions correctly', () {
      final health = AccountHealth.fromJson(
        penaltiesJson: {
          'Penalties': [
            {
              'id': 'afk-1',
              'type': 'afk_penalty',
              'description': 'AFK Warning',
              'expiry': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
            }
          ]
        },
        avoidListJson: {
          'avoidList': [
            {
              'puuid': '12345-abcde',
              'gameName': 'ToxPlayer',
              'tagLine': '1234',
            }
          ]
        },
        interventionsJson: {
          'activeFutureInterventions': [
            {
              'id': 'mute-1',
              'type': 'comm_restricted',
              'description': 'Chat Mute',
              'expiry': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            }
          ]
        },
        hasFetchErrors: false,
      );

      expect(health.status, AccountHealthStatus.hasRestrictions);
      expect(health.isClean, isFalse);
      expect(health.penalties.length, 2);
      expect(health.avoidedPlayers.length, 1);
      expect(health.avoidedPlayers.first.displayName, 'ToxPlayer#1234');
    });

    test('returns unknown status when network fetch fails', () {
      final health = AccountHealth.fromJson(
        penaltiesJson: {},
        avoidListJson: {},
        interventionsJson: {},
        hasFetchErrors: true,
      );

      expect(health.status, AccountHealthStatus.unknown);
      expect(health.isUnknown, isTrue);
      expect(health.isClean, isFalse);
    });
  });
}
