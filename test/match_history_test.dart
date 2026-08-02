import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/match/domain/models/match_history.dart';

void main() {
  group('MatchHistoryEntry map resolution tests', () {
    test('getMapDisplayName resolves via mapsMap when available', () {
      const entry = MatchHistoryEntry(
        matchId: 'm1',
        gameStartMillis: 1600000000000,
        queueId: 'competitive',
        teamId: 'Red',
        isRanked: true,
        mapId: '/Game/Maps/Plummet/Plummet',
      );

      final mapsMap = {
        '/game/maps/plummet/plummet': {'displayName': 'Abyss'},
        'plummet': {'displayName': 'Abyss'},
      };

      expect(entry.getMapDisplayName(mapsMap), equals('Abyss'));
    });

    test('getMapDisplayName falls back to mapDisplayName when mapsMap is empty', () {
      const entry = MatchHistoryEntry(
        matchId: 'm2',
        gameStartMillis: 1600000000000,
        queueId: 'competitive',
        teamId: 'Red',
        isRanked: true,
        mapId: '/Game/Maps/Juliett/Juliett',
      );

      expect(entry.getMapDisplayName({}), equals('Sunset'));
      expect(entry.mapDisplayName, equals('Sunset'));
    });

    test('queueDisplayName parses standard queues', () {
      const entry = MatchHistoryEntry(
        matchId: 'm3',
        gameStartMillis: 1600000000000,
        queueId: 'competitive',
        teamId: 'Red',
        isRanked: true,
      );

      expect(entry.queueDisplayName, equals('Competitive'));
    });
  });
}
