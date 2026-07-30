import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/storefront.dart';

const keyNotificationRules = 'notification_rules';

/// Available smart notification category filters.
class NotificationCategory {
  static const wishlist = 'wishlist';
  static const melee = 'melee';
  static const vandal = 'vandal';
  static const phantom = 'phantom';
  static const operator = 'operator';
  static const sheriff = 'sheriff';
  static const nightMarket = 'night_market';
}

final notificationRulesProvider =
    StateNotifierProvider<NotificationRulesNotifier, List<String>>((ref) {
  return NotificationRulesNotifier();
});

class NotificationRulesNotifier extends StateNotifier<List<String>> {
  NotificationRulesNotifier()
      : super([
          NotificationCategory.wishlist,
          NotificationCategory.melee,
          NotificationCategory.vandal,
          NotificationCategory.phantom,
          NotificationCategory.nightMarket,
        ]) {
    _load();
  }

  Future<void> _load() async {
    final list = await CacheStorage.instance.getJsonList(keyNotificationRules);
    if (list != null) {
      state = list.map((e) => e.toString()).toList();
    }
  }

  Future<void> toggleCategory(String category) async {
    if (state.contains(category)) {
      state = state.where((c) => c != category).toList();
    } else {
      state = [...state, category];
    }
    await CacheStorage.instance.setJson(keyNotificationRules, state);
  }

  bool isEnabled(String category) => state.contains(category);

  /// Evaluates today's shop against active smart notification rules.
  List<String> evaluateAlerts(Storefront storefront, List<String> wishlist) {
    final alerts = <String>[];

    if (isEnabled(NotificationCategory.wishlist)) {
      final matches = storefront.dailyOffers
          .where((o) => wishlist.contains(o.skinLevelUuid))
          .toList();
      if (matches.isNotEmpty) {
        final names = matches.map((m) => m.displayName ?? 'Skin').join(', ');
        alerts.add('🌟 Wishlist match in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.melee)) {
      final melees = storefront.dailyOffers.where((o) {
        final name = (o.displayName ?? '').toLowerCase();
        return name.contains('knife') ||
            name.contains('karambit') ||
            name.contains('blade') ||
            name.contains('dagger') ||
            name.contains('axe') ||
            name.contains('sword') ||
            name.contains('scythe') ||
            name.contains('hammer') ||
            name.contains('mace') ||
            name.contains('butterfly') ||
            name.contains('onimaru') ||
            name.contains('fan');
      }).toList();

      if (melees.isNotEmpty) {
        final names = melees.map((m) => m.displayName ?? 'Melee').join(', ');
        alerts.add('🔪 Melee / Knife in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.vandal)) {
      final vandals = storefront.dailyOffers
          .where((o) => (o.displayName ?? '').toLowerCase().contains('vandal'))
          .toList();
      if (vandals.isNotEmpty) {
        final names = vandals.map((m) => m.displayName ?? 'Vandal').join(', ');
        alerts.add('🔫 Vandal in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.phantom)) {
      final phantoms = storefront.dailyOffers
          .where((o) => (o.displayName ?? '').toLowerCase().contains('phantom'))
          .toList();
      if (phantoms.isNotEmpty) {
        final names = phantoms.map((m) => m.displayName ?? 'Phantom').join(', ');
        alerts.add('👻 Phantom in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.operator)) {
      final opes = storefront.dailyOffers
          .where((o) => (o.displayName ?? '').toLowerCase().contains('operator'))
          .toList();
      if (opes.isNotEmpty) {
        final names = opes.map((m) => m.displayName ?? 'Operator').join(', ');
        alerts.add('🎯 Operator in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.sheriff)) {
      final sheriffs = storefront.dailyOffers
          .where((o) => (o.displayName ?? '').toLowerCase().contains('sheriff'))
          .toList();
      if (sheriffs.isNotEmpty) {
        final names = sheriffs.map((m) => m.displayName ?? 'Sheriff').join(', ');
        alerts.add('🤠 Sheriff in shop: $names!');
      }
    }

    if (isEnabled(NotificationCategory.nightMarket) && storefront.hasNightMarket) {
      alerts.add('🟣 Night Market is available with ${storefront.nightMarket.length} discounted offers!');
    }

    return alerts;
  }
}
