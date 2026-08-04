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
}
