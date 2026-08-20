import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/shop/data/store_local_cache.dart';
import 'package:valorant_app/features/shop/data/store_remote_source.dart';
import 'package:valorant_app/features/shop/domain/store_repository.dart';
import 'package:valorant_app/shared/utils/valorant_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPuuid = 'test-puuid-store';
  const testShard = 'ap';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheStorage.instance.setActiveSession(testPuuid);
  });

  group('StoreRepository', () {
    test('fetchStorefront handles successful store data and caches it',
        () async {
      final mockData = {
        'FeaturedBundle': {
          'Bundle': {
            'ID': 'bundle-1',
            'DataAssetID': 'bundle-data-1',
            'CurrencyID': 'cur-1',
            'Items': [],
            'DurationRemainingInSeconds': 86400,
          },
          'Bundles': [],
          'BundleRemainingDurationInSeconds': 86400,
        },
        'SkinsPanelLayout': {
          'SingleItemOffers': ['skin-1', 'skin-2'],
          'SingleItemOffersRemainingDurationInSeconds': 43200,
        },
        'BonusStore': null,
      };

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) {
          return ResponseBody.fromString(jsonEncode(mockData), 200);
        });

      final cache = CacheStorage.instance;
      final repo = StoreRepository(
        remoteSource: StoreRemoteSource(dio),
        localCache: StoreLocalCache(cache),
        assets: ValorantAssets.instance,
      );

      final storefront = await repo.fetchStorefront(testShard, testPuuid);
      expect(storefront.dailyOffers.length, 2);
      expect(storefront.dailyOffers.first.offerId, 'skin-1');

      final cached = await repo.loadCachedStorefront(testPuuid);
      expect(cached, isNotNull);
      expect(cached!.dailyOffers.length, 2);
      expect(cached.dailyOffers.first.offerId, 'skin-1');
    });

    test('fetchWallet handles wallet balance and caches it', () async {
      final mockData = {
        'Balances': {
          '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1500, // VP
          'e59aa87c-4cbf-517a-5983-6e81511be9b7': 80, // Radianite
        }
      };

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) {
          return ResponseBody.fromString(jsonEncode(mockData), 200);
        });

      final cache = CacheStorage.instance;
      final repo = StoreRepository(
        remoteSource: StoreRemoteSource(dio),
        localCache: StoreLocalCache(cache),
        assets: ValorantAssets.instance,
      );

      final wallet = await repo.fetchWallet(testShard, testPuuid);
      expect(wallet.valorantPoints, 1500);
      expect(wallet.radianitePoints, 80);

      final cached = await repo.loadCachedWallet(testPuuid);
      expect(cached, isNotNull);
      expect(cached!.valorantPoints, 1500);
      expect(cached.radianitePoints, 80);
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
