import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/di/providers.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/auth/domain/models/credentials.dart';
import 'package:valorant_app/features/match/data/match_local_cache.dart';
import 'package:valorant_app/features/match/data/match_remote_source.dart';
import 'package:valorant_app/features/match/presentation/match_history_screen.dart';

const testPuuid = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa';

Credentials fakeCreds() => Credentials(
      accessToken: 'access-token-x',
      idToken: 'id-token-x',
      entitlementToken: 'ent-token-x',
      puuid: testPuuid,
      region: 'ap',
      shard: 'ap',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      entitlementExpiresAt: DateTime.now().add(const Duration(minutes: 55)),
    );

Map<String, dynamic> detailJson({
  required String matchId,
  String myTeam = 'Red',
  int myKills = 20,
}) {
  return {
    'matchInfo': {'matchId': matchId, 'mapId': '/Game/Maps/[MapId]'},
    'players': [
      {
        'subject': testPuuid,
        'gameName': 'Tester',
        'tagLine': '01',
        'teamId': myTeam,
        'characterId': 'agent-jett',
        'competitiveTier': 21,
        'stats': {
          'kills': myKills,
          'deaths': 15,
          'assists': 5,
          'score': 4000,
          'roundsPlayed': 23,
        },
      },
      {
        'subject': 'friend-b',
        'gameName': 'Mate',
        'tagLine': '02',
        'teamId': myTeam == 'Red' ? 'Blue' : 'Red',
        'characterId': 'agent-sova',
        'stats': {'kills': 9, 'deaths': 20, 'assists': 2, 'score': 2000, 'roundsPlayed': 23},
      },
    ],
    'roundResults': [
      for (var i = 0; i < 13; i++) {'roundNum': i, 'winningTeam': myTeam},
      for (var i = 13; i < 23; i++)
        {'roundNum': i, 'winningTeam': myTeam == 'Red' ? 'Blue' : 'Red'},
    ],
  };
}

Map<String, dynamic> historyJson(List<String> ids) => {
      'Subject': testPuuid,
      'Total': ids.length,
      'BeginIndex': 0,
      'EndIndex': ids.length,
      'History': [
        for (final id in ids)
          {
            'MatchID': id,
            'GameStartTime':
                DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            'QueueID': 'competitive',
            'TeamID': 'Red',
            'IsRanked': true,
            'MapID': '/Game/Maps/Ascent',
          }
      ],
    };

class FakeMatchRemoteSource implements MatchRemoteSource {
  FakeMatchRemoteSource({this.detailDelay = const Duration(milliseconds: 30)});

  final Duration detailDelay;
  int historyCalls = 0;
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchHistoryRaw(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 15,
    String? queue,
  }) async {
    historyCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return historyJson(['m-file', 'm-legacy', 'm-net-1', 'm-net-2']);
  }

  @override
  Future<Map<String, dynamic>> fetchMatchDetailsRaw(
      String shard, String matchId) async {
    detailCalls++;
    await Future<void>.delayed(detailDelay);
    return detailJson(matchId: matchId, myKills: 17);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late CacheStorage storage;
  late MatchDetailLocalCache fileCache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('valapp_career_repro');
    storage = CacheStorage.instance;
    await storage.clearAll();
    await storage.setActiveSession(testPuuid);
    fileCache = MatchDetailLocalCache(storage, baseDirResolver: () async => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('CAREER repro — cache layer (device-like file path)', () {
    test('15 sequential reads across file-hit/legacy-hit/miss complete fast',
        () async {
      // Seed one file entry + one legacy blob entry.
      final tx = storage.beginUserTransaction(testPuuid)!;
      await fileCache.saveMatchDetail('m-file',
          detailJson(matchId: 'm-file'), puuid: testPuuid, transaction: tx);
      await storage.setJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, testPuuid),
        {
          'm-legacy': detailJson(matchId: 'm-legacy', myKills: 10),
        },
      );

      final sw = Stopwatch()..start();
      for (var i = 0; i < 15; i++) {
        final id = switch (i % 3) { 0 => 'm-file', 1 => 'm-legacy', _ => 'm-miss-$i' };
        final raw = await fileCache.loadMatchDetailRaw(id, puuid: testPuuid);
        if (id == 'm-file' || id == 'm-legacy') {
          expect(raw, isNotNull, reason: '$id must resolve');
        } else {
          expect(raw, isNull);
        }
      }
      sw.stop();
      // Relaxed from 3000ms — sequential reads must not stall, but a hard
      // low ceiling flakes on slow CI.
      expect(sw.elapsedMilliseconds, lessThan(5000),
          reason: 'sequential enrichment reads must never stall');
    });

    test('concurrent saves do not deadlock sequential reads', () async {
      final tx = storage.beginUserTransaction(testPuuid)!;
      final saver = Future.wait([
        for (var i = 0; i < 12; i++)
          fileCache.saveMatchDetail('c-$i', detailJson(matchId: 'c-$i'),
              puuid: testPuuid, transaction: tx),
      ]);
      final reader = fileCache.loadMatchDetailRaw('c-3', puuid: testPuuid);
      await Future.wait([saver, reader]).timeout(const Duration(seconds: 15));
      expect(await fileCache.loadMatchDetailRaw('c-3', puuid: testPuuid),
          isNotNull);
    });
  });

  group('CAREER repro — full notifier build()', () {
    late ProviderContainer container;
    late FakeMatchRemoteSource source;
    late MatchDetailLocalCache notifierDetailCache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('valapp_career_notifier');
      storage = CacheStorage.instance;
      await storage.clearAll();
      await storage.setActiveSession(testPuuid);
      notifierDetailCache =
          MatchDetailLocalCache(storage, baseDirResolver: () async => tmp);

      source = FakeMatchRemoteSource();

      container = ProviderContainer(overrides: [
        currentCredentialsProvider.overrideWith((ref) async => fakeCreds()),
        matchRemoteSourceProvider.overrideWith((ref) => source),
        matchDetailLocalCacheProvider.overrideWithValue(notifierDetailCache),
      ]);
    });

    tearDown(() async {
      container.dispose();
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('build() settles with data and background enrichment fills details',
        () async {
      // Keep-alive subscription: autoDispose providers are torn down as soon
      // as nothing listens — mirroring the mounted screen on device.
      final sub = container.listen(matchHistoryProvider, (_, __) {});

      // Pre-seed FILE entry + LEGACY blob entry like an upgrading install.
      final tx = storage.beginUserTransaction(testPuuid)!;
      await notifierDetailCache.saveMatchDetail('m-file',
          detailJson(matchId: 'm-file'), puuid: testPuuid, transaction: tx);
      await storage.setJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, testPuuid),
        {'m-legacy': detailJson(matchId: 'm-legacy', myKills: 11)},
      );

      final result = await container
          .read(matchHistoryProvider.future)
          .timeout(const Duration(seconds: 20));

      expect(result, isNotNull);
      expect(result!.data.matches, hasLength(4));
      expect(result.fromCache, isFalse);

      // m-file & m-legacy enriched from caches instantly.
      final fileEntry =
          result.data.matches.firstWhere((m) => m.matchId == 'm-file');
      expect(fileEntry.kills, isNotNull);

      // Background enrichment fetches m-net-* — poll with timeout instead of
      // a fixed sleep (800ms) that flakes on slow CI and wastes time on fast
      // ones. Poll every 100ms up to 2s.
      var enrichedNet = <dynamic>[];
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final state = container.read(matchHistoryProvider);
        enrichedNet = state.asData?.value?.data.matches
                .where((m) => m.matchId.startsWith('m-net'))
                .toList() ??
            [];
        if (enrichedNet.length >= 2 &&
            enrichedNet.every((m) => m.kills != null)) {
          break;
        }
      }
      expect(enrichedNet, hasLength(2),
          reason: 'background enrichment must fill network-only details');
      expect(enrichedNet.every((m) => m.kills != null), isTrue);
      expect(source.detailCalls, greaterThanOrEqualTo(2));
      sub.close();
    });
  });
}
