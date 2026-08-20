import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/match/data/match_local_cache.dart';
import 'package:valorant_app/features/match/domain/models/match_details.dart';
import 'package:valorant_app/features/match/domain/models/match_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPuuid = 'player-puuid-9999-8888';
  final storage = CacheStorage.instance;
  final historyCache = MatchHistoryLocalCache(storage);
  final detailCache = MatchDetailLocalCache(storage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.clearAll();
    await storage.setActiveSession(testPuuid);
  });

  group('Match History Progressive & Instant Cache Tests', () {
    test('instant cache loading provides non-blocking 0ms history display',
        () async {
      final transaction = storage.beginUserTransaction(testPuuid)!;
      final rawEntry = MatchHistoryEntry(
        matchId: 'match-alpha-101',
        gameStartMillis: DateTime.now().millisecondsSinceEpoch,
        queueId: 'competitive',
        teamId: 'Blue',
        isRanked: true,
        mapId: '/Game/Maps/Ascent/Ascent',
      );

      final initialResult = MatchHistoryResult(
        puuid: testPuuid,
        total: 1,
        start: 0,
        end: 1,
        matches: [rawEntry],
      );

      await historyCache.saveHistory(initialResult,
          puuid: testPuuid, transaction: transaction);

      final cached = await historyCache.loadHistory(puuid: testPuuid);
      expect(cached, isNotNull);
      expect(cached!.matches.length, equals(1));
      expect(cached.matches.first.matchId, equals('match-alpha-101'));
      expect(cached.matches.first.queueId, equals('competitive'));
    });

    test(
        'progressive in-place enrichment preserves core match info while adding stats',
        () async {
      const baseEntry = MatchHistoryEntry(
        matchId: 'match-bravo-202',
        gameStartMillis: 1700000000000,
        queueId: 'unrated',
        teamId: 'Red',
        isRanked: false,
        mapId: '/Game/Maps/Breeze/Breeze',
      );

      expect(baseEntry.kills, isNull);
      expect(baseEntry.result, equals(MatchResult.unknown));

      final enrichedEntry = baseEntry.copyWithStats(
        kills: 24,
        deaths: 12,
        assists: 8,
        isMvp: true,
        matchScore: '13 – 7',
        result: MatchResult.victory,
        agentId: 'agent-jett-uuid',
        mapId: '/Game/Maps/Breeze/Breeze',
      );

      expect(enrichedEntry.kills, equals(24));
      expect(enrichedEntry.deaths, equals(12));
      expect(enrichedEntry.assists, equals(8));
      expect(enrichedEntry.isMvp, isTrue);
      expect(enrichedEntry.matchScore, equals('13 – 7'));
      expect(enrichedEntry.result, equals(MatchResult.victory));
      expect(enrichedEntry.matchId, equals('match-bravo-202'));
      expect(enrichedEntry.gameStartMillis, equals(1700000000000));
      expect(enrichedEntry.queueId, equals('unrated'));
      expect(enrichedEntry.teamId, equals('Red'));
    });

    test('enrichment from detail cache resolves stats immediately', () async {
      final transaction = storage.beginUserTransaction(testPuuid)!;
      final matchDetailJson = {
        'matchInfo': {
          'matchId': 'match-charlie-303',
          'mapId': '/Game/Maps/Haven/Haven',
          'gameLengthMillis': 1800000,
          'gameStartMillis': 1700000000000,
          'provisioningFlowId': 'Matchmaking',
          'isCompleted': true,
          'customGameName': '',
          'queueId': 'competitive',
          'gameMode': '/Game/GameModes/Bomb/BombGameMode.BombGameMode_C',
          'isRanked': true,
          'seasonId': 'season-uuid',
        },
        'players': [
          {
            'subject': testPuuid,
            'gameName': 'TacticalPlayer',
            'tagLine': 'VAL',
            'teamId': 'Blue',
            'partyId': 'party-1',
            'characterId': 'agent-omen-uuid',
            'stats': {
              'score': 5400,
              'roundsPlayed': 20,
              'kills': 18,
              'deaths': 10,
              'assists': 6,
              'playtimeMillis': 1800000,
            },
            'competitiveTier': 15,
            'playerCard': 'card-uuid',
            'playerTitle': 'title-uuid',
            'accountLevel': 85,
          }
        ],
        'teams': [
          {'teamId': 'Blue', 'won': true, 'roundsPlayed': 20, 'roundsWon': 13},
          {'teamId': 'Red', 'won': false, 'roundsPlayed': 20, 'roundsWon': 7},
        ],
        'roundResults': [
          {
            'roundNum': 0,
            'winningTeam': 'Blue',
            'roundResult': 'Elimination',
            'roundCeremony': '',
            'plantTime': 0,
            'defuseTime': 0
          },
          {
            'roundNum': 1,
            'winningTeam': 'Blue',
            'roundResult': 'Elimination',
            'roundCeremony': '',
            'plantTime': 0,
            'defuseTime': 0
          },
          {
            'roundNum': 2,
            'winningTeam': 'Red',
            'roundResult': 'Elimination',
            'roundCeremony': '',
            'plantTime': 0,
            'defuseTime': 0
          },
        ],
      };

      await detailCache.saveMatchDetail('match-charlie-303', matchDetailJson,
          puuid: testPuuid, transaction: transaction);

      final rawDetail = await detailCache
          .loadMatchDetailRaw('match-charlie-303', puuid: testPuuid);
      expect(rawDetail, isNotNull);

      final details = MatchDetails.fromJson(rawDetail!);
      final player = details.players.firstWhere((p) => p.puuid == testPuuid);

      expect(player.kills, equals(18));
      expect(player.deaths, equals(10));
      expect(player.assists, equals(6));
      expect(details.resultForPlayer(testPuuid), equals(MatchResult.victory));
    });
  });
}
