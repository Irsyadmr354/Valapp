import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/match/data/match_local_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accountA = 'account-a';
  const accountB = 'account-b';
  const matchId = 'match-1';
  final storage = CacheStorage.instance;
  final cache = MatchDetailLocalCache(storage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.clearAll();
    await storage.setActiveSession(accountA);
  });

  test('match details are isolated per account', () async {
    final transactionA = storage.beginUserTransaction(accountA)!;
    await cache.saveMatchDetail(matchId, {'owner': 'A'},
        puuid: accountA, transaction: transactionA);

    await storage.setActiveSession(accountB);
    final transactionB = storage.beginUserTransaction(accountB)!;
    await cache.saveMatchDetail(matchId, {'owner': 'B'},
        puuid: accountB, transaction: transactionB);

    expect(await cache.loadMatchDetailRaw(matchId, puuid: accountA),
        {'owner': 'A'});
    expect(await cache.loadMatchDetailRaw(matchId, puuid: accountB),
        {'owner': 'B'});
  });

  test('response from a previous activation cannot populate detail cache',
      () async {
    final stale = storage.beginUserTransaction(accountA)!;
    await storage.setActiveSession(accountB);
    await storage.setActiveSession(accountA);

    await cache.saveMatchDetail(matchId, {'stale': true},
        puuid: accountA, transaction: stale);

    expect(await cache.loadMatchDetailRaw(matchId, puuid: accountA), isNull);
  });
}
