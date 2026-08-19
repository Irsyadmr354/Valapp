import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Wishlist Catalog Multi-UUID Matching Logic', () {
    test('matches wishlisted level 1 offer to skin with multiple levels and chromas', () {
      const skinUuid = 'skin-vandal-prime';
      const level1Uuid = 'level-1-uuid';
      const level4Uuid = 'level-4-uuid';
      const chroma1Uuid = 'chroma-1-uuid';

      final skinCatalogItem = {
        'skinUuid': skinUuid,
        'skinLevelUuid': level4Uuid,
        'allUuids': [skinUuid, level1Uuid, level4Uuid, chroma1Uuid],
        'displayName': 'Prime Vandal',
      };

      // Daily shop wishlists level1Uuid
      final wishlist = <String>{level1Uuid};

      final allUuids = skinCatalogItem['allUuids'] as List<String>;
      final isMatch = allUuids.any((id) => wishlist.contains(id));

      expect(isMatch, isTrue,
          reason: 'Daily shop Level 1 wishlist ID must match the catalog item');
    });

    test('unique skin counting matches 1 unique skin even if both levelUuid and skinUuid are in wishlist', () {
      const skinUuid = 'skin-phantom-oni';
      const level1Uuid = 'oni-lvl1';
      const level4Uuid = 'oni-lvl4';

      final skinCatalog = [
        {
          'skinUuid': skinUuid,
          'skinLevelUuid': level4Uuid,
          'allUuids': [skinUuid, level1Uuid, level4Uuid],
          'displayName': 'Oni Phantom',
        },
        {
          'skinUuid': 'skin-sheriff-reaver',
          'skinLevelUuid': 'reaver-lvl1',
          'allUuids': ['skin-sheriff-reaver', 'reaver-lvl1'],
          'displayName': 'Reaver Sheriff',
        },
      ];

      final wishlistWithDuplicates = <String>{skinUuid, level1Uuid};

      final uniqueCount = skinCatalog.where((skin) {
        final allUuids = skin['allUuids'] as List<String>;
        return allUuids.any((id) => wishlistWithDuplicates.contains(id));
      }).length;

      expect(uniqueCount, 1,
          reason: 'Only 1 unique skin is wishlisted even with multiple stored UUIDs');
    });
  });
}
