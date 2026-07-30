import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_shop_monitor/features/match/domain/models/match_details.dart';

void main() {
  group('PlayerStats KDA tests', () {
    test('Normal KDA calculation when deaths > 0', () {
      const stats = PlayerStats(
        puuid: 'user-1',
        displayName: 'TestAgent#1234',
        teamId: 'Red',
        agentId: 'agent-uuid',
        kills: 15,
        deaths: 5,
        assists: 10,
        score: 3500,
        roundsPlayed: 20,
        competitiveTier: 15,
      );

      expect(stats.kda, equals(5.0)); // (15 + 10) / 5 = 5.0
      expect(stats.isPerfectKda, isFalse);
    });

    test('Perfect KDA detection when deaths == 0', () {
      const stats = PlayerStats(
        puuid: 'user-1',
        displayName: 'AceAgent#1234',
        teamId: 'Red',
        agentId: 'agent-uuid',
        kills: 20,
        deaths: 0,
        assists: 5,
        score: 4500,
        roundsPlayed: 15,
        competitiveTier: 20,
      );

      expect(stats.isPerfectKda, isTrue);
      expect(stats.kda, equals(25.0)); // (20 + 5) / 1 = 25.0 without division by 0 crash
    });

    test('KDA when roundsPlayed == 0', () {
      const stats = PlayerStats(
        puuid: 'user-1',
        displayName: 'NoRounds#1234',
        teamId: 'Red',
        agentId: 'agent-uuid',
        kills: 0,
        deaths: 0,
        assists: 0,
        score: 0,
        roundsPlayed: 0,
        competitiveTier: 0,
      );

      expect(stats.kda, equals(0.0));
      expect(stats.isPerfectKda, isFalse);
    });
  });
}
