import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/contracts/data/contracts_local_cache.dart';
import 'package:valorant_app/features/contracts/data/contracts_remote_source.dart';
import 'package:valorant_app/features/contracts/domain/contracts_repository.dart';
import 'package:valorant_app/features/loadout/data/loadout_local_cache.dart';
import 'package:valorant_app/features/loadout/data/loadout_remote_source.dart';
import 'package:valorant_app/features/loadout/domain/loadout_repository.dart';
import 'package:valorant_app/features/match/data/match_local_cache.dart';
import 'package:valorant_app/features/match/data/match_remote_source.dart';
import 'package:valorant_app/features/match/domain/match_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPuuid = 'test-puuid-1234567890';
  const testShard = 'ap';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheStorage.instance.setActiveSession(testPuuid);
  });

  group('MatchRepository', () {
    test('fetches history, saves to cache and reads back from cache', () async {
      final mockData = {
        'Subject': testPuuid,
        'BeginIndex': 0,
        'EndIndex': 1,
        'Total': 1,
        'History': [
          {
            'MatchID': 'match-123',
            'GameStartTime': 1600000000000,
            'QueueID': 'competitive',
          }
        ]
      };

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) {
          return ResponseBody.fromString(jsonEncode(mockData), 200);
        });

      final cache = CacheStorage.instance;
      final repo = MatchRepository(
        remoteSource: MatchRemoteSource(dio),
        historyCache: MatchHistoryLocalCache(cache),
        detailCache: MatchDetailLocalCache(cache),
      );

      final result = await repo.fetchHistory(testShard, testPuuid);
      expect(result.puuid, testPuuid);
      expect(result.matches.length, 1);
      expect(result.matches.first.matchId, 'match-123');

      final cached = await repo.loadCachedHistory(puuid: testPuuid);
      expect(cached, isNotNull);
      expect(cached!.matches.first.matchId, 'match-123');
    });
  });

  group('ContractsRepository', () {
    test('fetches contracts, saves to cache and reads back from cache',
        () async {
      final mockData = {
        'Subject': testPuuid,
        'Version': 1,
        'Contracts': [],
        'Missions': [],
        'ProcessedMatches': [],
        'ActiveSpecialContract': '',
      };

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) {
          return ResponseBody.fromString(jsonEncode(mockData), 200);
        });

      final cache = CacheStorage.instance;
      final repo = ContractsRepository(
        remoteSource: ContractsRemoteSource(dio),
        localCache: ContractsLocalCache(cache),
      );

      final result = await repo.fetchContracts(testShard, testPuuid);
      expect(result.contracts, isEmpty);

      final cached = await repo.loadCachedContracts(testPuuid);
      expect(cached, isNotNull);
      expect(cached!.contracts, isEmpty);
    });
  });

  group('LoadoutRepository', () {
    test('fetches loadout, saves to cache and reads back from cache', () async {
      final mockData = {
        'Subject': testPuuid,
        'Version': 1,
        'Guns': [],
        'Sprays': [],
        'Identity': {
          'PlayerCardID': 'card-abc-123',
          'PlayerTitleID': '',
          'AccountLevel': 100,
          'PreferredLevelBorderID': '',
          'HideAccountLevel': false,
        },
        'Incognito': false,
      };

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) {
          return ResponseBody.fromString(jsonEncode(mockData), 200);
        });

      final cache = CacheStorage.instance;
      final repo = LoadoutRepository(
        remoteSource: LoadoutRemoteSource(dio),
        localCache: LoadoutLocalCache(cache),
      );

      final result = await repo.fetchLoadout(testShard, testPuuid);
      expect(result.puuid, testPuuid);
      expect(result.playerCardId, 'card-abc-123');

      final cached = await repo.loadCachedLoadout(testPuuid);
      expect(cached, isNotNull);
      expect(cached!.puuid, testPuuid);
      expect(cached.playerCardId, 'card-abc-123');
    });
  });
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
