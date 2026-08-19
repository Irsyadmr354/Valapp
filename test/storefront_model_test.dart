import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/shop/domain/models/storefront.dart';

void main() {
  group('Storefront.fromJson daily offer pricing', () {
    test('matches prices by OfferID when lists align', () {
      const offerA = '11111111-1111-1111-1111-111111111111';
      const offerB = '22222222-2222-2222-2222-222222222222';

      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': [offerA, offerB],
          'SingleItemStoreOffers': [
            {
              'OfferID': offerA,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 875},
            },
            {
              'OfferID': offerB,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1775},
            },
          ],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
      });

      expect(storefront.dailyOffers.length, 2);
      expect(storefront.dailyOffers[0].offerId, offerA);
      expect(storefront.dailyOffers[0].price, 875);
      expect(storefront.dailyOffers[1].offerId, offerB);
      expect(storefront.dailyOffers[1].price, 1775);
    });

    test('matches prices by OfferID even when store offer order differs', () {
      const offerA = '11111111-1111-1111-1111-111111111111';
      const offerB = '22222222-2222-2222-2222-222222222222';

      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': [offerA, offerB],
          'SingleItemStoreOffers': [
            {
              'OfferID': offerB,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1775},
            },
            {
              'OfferID': offerA,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 875},
            },
          ],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
      });

      expect(storefront.dailyOffers[0].price, 875);
      expect(storefront.dailyOffers[1].price, 1775);
    });

    test('returns zero price when offer ID has no matching store offer', () {
      const offerA = '11111111-1111-1111-1111-111111111111';
      const offerB = '22222222-2222-2222-2222-222222222222';

      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': [offerA, offerB],
          'SingleItemStoreOffers': [
            {
              'OfferID': offerA,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 875},
            },
          ],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
      });

      expect(storefront.dailyOffers[0].price, 875);
      expect(storefront.dailyOffers[1].price, 0);
    });

    test('skips malformed optional offers without dropping valid offers', () {
      const offer = '11111111-1111-1111-1111-111111111111';
      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': [offer, null, 12],
          'SingleItemStoreOffers': [
            {
              'OfferID': offer,
              'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 875},
            },
          ],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'BonusStore': {
          'BonusStoreOffers': [null, 'invalid'],
        },
        'AccessoryStore': {
          'AccessoryStoreOffers': [null, 1],
        },
      });

      expect(storefront.dailyOffers.single.offerId, offer);
      expect(storefront.nightMarket, isEmpty);
      expect(storefront.accessoryStore?.offerIds, isEmpty);
    });
  });

  group('Storefront.fromJson featured bundles parsing', () {
    test('parses multiple bundles from FeaturedBundle.Bundles list', () {
      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': <String>[],
          'SingleItemStoreOffers': <Map<String, dynamic>>[],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'FeaturedBundle': {
          'Bundles': [
            {
              'ID': 'offer-1111',
              'DataAssetID': 'bundle-uuid-1111',
              'Items': [
                {
                  'Item': {'ItemID': 'skin-1'},
                  'BasePrice': 2175,
                }
              ],
              'TotalBaseCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 9500},
              'TotalDiscountedCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 5225},
              'TotalDiscountPercent': 0.45,
              'DurationRemainingInSeconds': 10000,
            },
            {
              'ID': 'offer-2222',
              'DataAssetID': 'bundle-uuid-2222',
              'Items': [
                {
                  'Item': {'ItemID': 'skin-2'},
                  'BasePrice': 1775,
                }
              ],
              'TotalBaseCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 7100},
              'TotalDiscountedCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 7100},
              'TotalDiscountPercent': 0.0,
              'DurationRemainingInSeconds': 5000,
            }
          ],
        },
      });

      expect(storefront.featuredBundles.length, 2);
      expect(storefront.featuredBundles[0].bundleUuid, 'bundle-uuid-1111');
      expect(storefront.featuredBundles[0].totalDiscountedCost, 5225);
      expect(storefront.featuredBundles[1].bundleUuid, 'bundle-uuid-2222');
      expect(storefront.featuredBundles[1].totalDiscountedCost, 7100);
      expect(storefront.featuredBundle?.bundleUuid, 'bundle-uuid-1111');
    });

    test('falls back to ID when DataAssetID is empty string or null', () {
      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': <String>[],
          'SingleItemStoreOffers': <Map<String, dynamic>>[],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'FeaturedBundle': {
          'Bundles': [
            {
              'ID': 'offer-fallback-id',
              'DataAssetID': '',
              'Items': <Map<String, dynamic>>[],
            }
          ],
        },
      });

      expect(storefront.featuredBundles.single.bundleUuid, 'offer-fallback-id');
    });

    test('parses bundle items from ItemOffers schema', () {
      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': <String>[],
          'SingleItemStoreOffers': <Map<String, dynamic>>[],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'FeaturedBundle': {
          'Bundle': {
            'ID': 'bundle-offer-id',
            'DataAssetID': 'bundle-asset-id',
            'ItemOffers': [
              {
                'BundleItemOfferID': 'item-offer-1',
                'Offer': {
                  'OfferID': 'offer-item-1',
                  'Cost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1775},
                  'Rewards': [
                    {'ItemID': 'skin-reward-1'}
                  ]
                },
                'DiscountPercent': 0,
                'DiscountedPrice': 1775,
              }
            ],
            'TotalBaseCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1775},
            'TotalDiscountedCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1775},
            'DurationRemainingInSeconds': 80000,
          },
        },
      });

      expect(storefront.featuredBundles.length, 1);
      final bundle = storefront.featuredBundles.first;
      expect(bundle.bundleUuid, 'bundle-asset-id');
      expect(bundle.itemIds, contains('skin-reward-1'));
      expect(bundle.itemPrices['skin-reward-1'], 1775);
    });

    test('parses bundle when FeaturedBundle is top-level bundle object', () {
      final storefront = Storefront.fromJson({
        'SkinsPanelLayout': {
          'SingleItemOffers': <String>[],
          'SingleItemStoreOffers': <Map<String, dynamic>>[],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'FeaturedBundle': {
          'ID': 'direct-bundle-id',
          'DataAssetID': 'direct-bundle-asset',
          'Items': [
            {
              'ItemID': 'direct-skin-1',
              'BasePrice': 2175,
            }
          ],
          'TotalBaseCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 2175},
          'TotalDiscountedCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 2175},
          'DurationRemainingInSeconds': 50000,
        },
      });

      expect(storefront.featuredBundles.length, 1);
      expect(storefront.featuredBundles.first.bundleUuid, 'direct-bundle-asset');
      expect(storefront.featuredBundles.first.itemIds, contains('direct-skin-1'));
    });

    test('parses Aeris bundle with all weapons and accessories', () {
      final aerisJson = {
        'SkinsPanelLayout': {
          'SingleItemOffers': <String>[],
          'SingleItemStoreOffers': <Map<String, dynamic>>[],
          'SingleItemOffersRemainingDurationInSeconds': 3600,
        },
        'FeaturedBundle': {
          'Bundle': {
            'ID': 'aeris-offer-id',
            'DataAssetID': 'd087f4fd-4942-d782-c76c-5e84dc307a66',
            'Items': [
              {
                'Item': {
                  'ItemTypeID': 'e7c63390-eda7-46e0-bb7a-6f8d24da2cb6',
                  'ItemID': 'b494ddd1-4459-6976-6736-00a563a74376',
                  'Amount': 1,
                },
                'BasePrice': 2175,
                'DiscountedPrice': 2175,
                'DiscountPercent': 0,
              },
              {
                'Item': {
                  'ItemTypeID': 'e7c63390-eda7-46e0-bb7a-6f8d24da2cb6',
                  'ItemID': 'f3333480-459f-cc15-da7a-34869a8fc9df',
                  'Amount': 1,
                },
                'BasePrice': 2175,
                'DiscountedPrice': 2175,
                'DiscountPercent': 0,
              },
            ],
            'TotalBaseCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 8700},
            'TotalDiscountedCost': {'85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 8700},
            'DurationRemainingInSeconds': 1200000,
          },
        },
      };

      final storefront = Storefront.fromJson(aerisJson);
      expect(storefront.featuredBundles.length, 1);
      final bundle = storefront.featuredBundles.first;
      expect(bundle.bundleUuid, 'd087f4fd-4942-d782-c76c-5e84dc307a66');
      expect(bundle.itemIds, contains('b494ddd1-4459-6976-6736-00a563a74376'));
      expect(bundle.itemIds, contains('f3333480-459f-cc15-da7a-34869a8fc9df'));
      expect(bundle.totalBaseCost, 8700);
    });
  });
}
