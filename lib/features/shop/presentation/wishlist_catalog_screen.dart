import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/valorant_error_display.dart';
import '../../../shared/widgets/valorant_icons.dart';
import '../../auth/domain/session_reconnect.dart';
import 'skin_detail_modal.dart';

import '../domain/models/skin_offer.dart';
import 'wishlist_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _allSkinsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  final map = await assets.getSkinLevelsMap();
  final uniqueSkins = <String, Map<String, dynamic>>{};

  map.forEach((levelUuid, skinData) {
    if (skinData is Map<String, dynamic>) {
      final skinName = skinData['skinName']?.toString() ??
          skinData['displayName']?.toString() ??
          '';
      final displayIcon = skinData['displayIcon']?.toString();

      final lowerName = skinName.toLowerCase().trim();
      final weaponType =
          (skinData['weaponType'] as String? ?? '').toLowerCase();

      if (skinName.isNotEmpty &&
          !lowerName.startsWith('standard') &&
          displayIcon != null &&
          displayIcon.isNotEmpty) {
        final skinUuid = skinData['skinUuid']?.toString() ?? levelUuid;
        final existing = uniqueSkins[skinUuid];
        final allUuids = existing != null
            ? Set<String>.from(existing['allUuids'] as List<String>)
            : <String>{skinUuid};

        allUuids.add(levelUuid);
        final levels = skinData['levels'] as List<dynamic>? ?? [];
        for (final lvl in levels) {
          if (lvl is Map && lvl['uuid'] != null) {
            allUuids.add(lvl['uuid'].toString());
          }
        }
        final chromas = skinData['chromas'] as List<dynamic>? ?? [];
        for (final chr in chromas) {
          if (chr is Map && chr['uuid'] != null) {
            allUuids.add(chr['uuid'].toString());
          }
        }

        final primaryLevelUuid = levels.isNotEmpty && levels.first is Map
            ? (levels.first['uuid']?.toString() ?? levelUuid)
            : (existing?['skinLevelUuid']?.toString() ?? levelUuid);

        uniqueSkins[skinUuid] = {
          'skinUuid': skinUuid,
          'skinLevelUuid': primaryLevelUuid,
          'allUuids': allUuids.toList(),
          'displayName': skinName,
          'displayIcon': displayIcon,
          'contentTierUuid': skinData['contentTierUuid']?.toString(),
          'weaponType': weaponType,
        };
      }
    }
  });

  final list = uniqueSkins.values.toList();
  list.sort((a, b) =>
      (a['displayName'] as String).compareTo(b['displayName'] as String));
  return list;
});

// ── Weapon category helpers ───────────────────────────────────────────────────

/// Returns whether a skin matches a specific weapon sidebar category.
/// Checks [weaponType] (from Riot's /weapons endpoint) first — this correctly
/// handles melee skins whose names do NOT contain the word "melee" (e.g.
/// "Sovereign Sword", "Knife of the Last Khan"). Falls back to name-contains
/// matching for any skin where weaponType is unavailable.
bool _matchesWeaponId(String skinName, String weaponId,
    {String weaponType = ''}) {
  final id = weaponId.toLowerCase();
  if (weaponType.isNotEmpty) {
    return weaponType == id;
  }
  return skinName.toLowerCase().contains(id);
}

Color _getTierColor(String? tierUuid) {
  // Intentional: Premium uses AppColors.red in the catalog (brand consistency).
  // All other tiers delegate to the shared TierColors utility.
  const premiumUuidFragment = '60bca009';
  if (tierUuid != null &&
      tierUuid.toLowerCase().contains(premiumUuidFragment)) {
    return AppColors.red;
  }
  return TierColors.tierColorForUuid(tierUuid);
}

String _getTierLabel(String? tierUuid) => TierColors.tierLabelForUuid(tierUuid);

// ── Sidebar category definitions ──────────────────────────────────────────────

class _SidebarItem {
  const _SidebarItem(
      {required this.id, required this.label, required this.icon});
  final String id;
  final String label;
  final IconData icon;
}

const _sidebarItems = [
  _SidebarItem(id: 'ALL', label: 'ALL', icon: Icons.grid_view_rounded),
  // ── Pistols ──
  _SidebarItem(
      id: 'CLASSIC', label: 'CLASSIC', icon: Icons.radio_button_unchecked),
  _SidebarItem(
      id: 'SHORTY', label: 'SHORTY', icon: Icons.horizontal_rule_rounded),
  _SidebarItem(id: 'FRENZY', label: 'FRENZY', icon: Icons.bolt_rounded),
  _SidebarItem(id: 'GHOST', label: 'GHOST', icon: Icons.nightlight_round),
  _SidebarItem(
      id: 'SHERIFF', label: 'SHERIFF', icon: Icons.star_outline_rounded),
  // ── SMGs ──
  _SidebarItem(id: 'STINGER', label: 'STINGER', icon: Icons.speed_rounded),
  _SidebarItem(id: 'SPECTRE', label: 'SPECTRE', icon: Icons.wind_power_rounded),
  // ── Rifles ──
  _SidebarItem(id: 'BULLDOG', label: 'BULLDOG', icon: Icons.adjust_rounded),
  _SidebarItem(id: 'GUARDIAN', label: 'GUARDIAN', icon: Icons.shield_outlined),
  _SidebarItem(
      id: 'PHANTOM', label: 'PHANTOM', icon: Icons.visibility_off_outlined),
  _SidebarItem(
      id: 'VANDAL', label: 'VANDAL', icon: Icons.military_tech_outlined),
  // ── Snipers ──
  _SidebarItem(
      id: 'MARSHAL', label: 'MARSHAL', icon: Icons.center_focus_weak_rounded),
  _SidebarItem(id: 'OUTLAW', label: 'OUTLAW', icon: Icons.gps_fixed_rounded),
  _SidebarItem(
      id: 'OPERATOR',
      label: 'OPERATOR',
      icon: Icons.center_focus_strong_outlined),
  // ── Shotguns ──
  _SidebarItem(id: 'BUCKY', label: 'BUCKY', icon: Icons.flash_on_rounded),
  _SidebarItem(id: 'JUDGE', label: 'JUDGE', icon: Icons.electric_bolt_rounded),
  // ── Heavy ──
  _SidebarItem(id: 'ARES', label: 'ARES', icon: Icons.rotate_right_rounded),
  _SidebarItem(id: 'ODIN', label: 'ODIN', icon: Icons.settings_rounded),
  // ── Melee ──
  _SidebarItem(id: 'MELEE', label: 'MELEE', icon: Icons.architecture_rounded),
  // ── Wishlist ──
  _SidebarItem(id: 'WISHLIST', label: 'WISHLIST', icon: Icons.bookmark_rounded),
];

// ── Main Screen ───────────────────────────────────────────────────────────────

class WishlistCatalogScreen extends ConsumerStatefulWidget {
  const WishlistCatalogScreen({super.key});

  @override
  ConsumerState<WishlistCatalogScreen> createState() =>
      _WishlistCatalogScreenState();
}

class _WishlistCatalogScreenState extends ConsumerState<WishlistCatalogScreen> {
  String _selectedCategory = 'ALL';
  String _selectedTierFilter = 'ALL';
  String _searchQuery = '';
  String _sortMode = 'name'; // 'name' | 'tier'
  final _searchController = TextEditingController();

  final List<Map<String, dynamic>> _tierOptions = [
    {'id': 'ALL', 'label': 'ALL EDITIONS', 'color': const Color(0xB3FFFFFF)},
    {'id': 'Ultra', 'label': 'ULTRA EDITION', 'color': const Color(0xFFFAD663)},
    {
      'id': 'Exclusive',
      'label': 'EXCLUSIVE EDITION',
      'color': const Color(0xFFF5955B)
    },
    {'id': 'Premium', 'label': 'PREMIUM EDITION', 'color': AppColors.red},
    {
      'id': 'Deluxe',
      'label': 'DELUXE EDITION',
      'color': const Color(0xFF009587)
    },
    {
      'id': 'Select',
      'label': 'SELECT EDITION',
      'color': const Color(0xFF5A9FE2)
    },
  ];

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showTierFilterModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.red, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('FILTER EDITION TIER',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._tierOptions.map((opt) {
              final isSelected = opt['id'] == _selectedTierFilter;
              final Color color = opt['color'] as Color;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTierFilter = opt['id'] as String);
                  Navigator.of(context).pop();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withAlpha(40) : AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : Colors.white10,
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Text(opt['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                          )),
                      const Spacer(),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 18),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skinsAsync = ref.watch(_allSkinsListProvider);
    final wishlist = ref.watch(wishlistProvider);

    final uniqueWishlistCount = skinsAsync.maybeWhen(
      data: (skins) => skins.where((skin) {
        final allUuids = (skin['allUuids'] as List<dynamic>? ??
            [skin['skinLevelUuid'], skin['skinUuid']]);
        return allUuids.any((id) => wishlist.contains(id));
      }).length,
      orElse: () => wishlist.length,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SKIN CATALOG & WISHLIST',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8)),
                        SizedBox(height: 2),
                        Text('COLLECT. CUSTOMIZE. DOMINATE.',
                            style: TextStyle(
                                color: AppColors.red,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0)),
                      ],
                    ),
                  ),
                  // VIEW WISHLIST button (replaced old X + summary card)
                  GestureDetector(
                    onTap: () => setState(() => _selectedCategory = 'WISHLIST'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.red.withAlpha(80), width: 1),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.red.withAlpha(25),
                              blurRadius: 10)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bookmark_rounded,
                              color: AppColors.red, size: 14),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$uniqueWishlistCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900)),
                              const Text('VIEW WISHLIST >',
                                  style: TextStyle(
                                      color: AppColors.red,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Search & Filter Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10, width: 1),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce =
                              Timer(const Duration(milliseconds: 300), () {
                            if (mounted) setState(() => _searchQuery = v);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search skin name',
                          hintStyle: const TextStyle(
                              color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Colors.white38, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white38, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tier filter
                  GestureDetector(
                    onTap: _showTierFilterModal,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedTierFilter != 'ALL'
                              ? AppColors.red
                              : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded,
                              color: AppColors.red, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _selectedTierFilter == 'ALL'
                                ? 'TIERS'
                                : _selectedTierFilter.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Sort A–Z / TIER
                  GestureDetector(
                    onTap: () => setState(() =>
                        _sortMode = _sortMode == 'name' ? 'tier' : 'name'),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _sortMode == 'tier'
                              ? AppColors.red
                              : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sort_rounded,
                              color: AppColors.red, size: 18),
                          const SizedBox(width: 4),
                          Text(_sortMode == 'name' ? 'A–Z' : 'TIER',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ── Main Body: Sidebar + Grid ───────────────────────────────────
            Expanded(
              child: Row(
                children: [
                  // ── Left Vertical Sidebar ──────────────────────────────────
                  Container(
                    width: 78,
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(
                          right: BorderSide(color: Colors.white10, width: 0.8)),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _sidebarItems.length,
                      itemBuilder: (context, idx) {
                        final item = _sidebarItems[idx];
                        final isSelected = _selectedCategory == item.id;

                        // Section dividers before first item of each group
                        final showDivider = item.id == 'CLASSIC' ||
                            item.id == 'STINGER' ||
                            item.id == 'BULLDOG' ||
                            item.id == 'MARSHAL' ||
                            item.id == 'BUCKY' ||
                            item.id == 'ARES' ||
                            item.id == 'MELEE' ||
                            item.id == 'WISHLIST';

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showDivider)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Colors.white12,
                                    indent: 8,
                                    endIndent: 8),
                              ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _selectedCategory = item.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(
                                    vertical: 3, horizontal: 6),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.red.withAlpha(35)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.red
                                        : Colors.transparent,
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: isSelected
                                          ? AppColors.red
                                          : Colors.white38,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white54,
                                        fontSize: 8.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // ── Right Skin Grid ────────────────────────────────────────
                  Expanded(
                    child: skinsAsync.when(
                      data: (skins) {
                        final filteredSkins = skins.where((skin) {
                          final name =
                              (skin['displayName'] as String).toLowerCase();
                          final tierUuid = skin['contentTierUuid'] as String?;
                          final tierLabel =
                              _getTierLabel(tierUuid).toLowerCase();
                          final allUuids =
                              (skin['allUuids'] as List<dynamic>? ??
                                  [skin['skinLevelUuid'], skin['skinUuid']]);

                          // Sidebar category / weapon filter
                          if (_selectedCategory == 'WISHLIST') {
                            if (!allUuids.any((id) => wishlist.contains(id))) {
                              return false;
                            }
                          } else if (_selectedCategory != 'ALL') {
                            final wt = skin['weaponType'] as String? ?? '';
                            if (!_matchesWeaponId(name, _selectedCategory,
                                weaponType: wt)) {
                              return false;
                            }
                          }

                          // Edition tier filter
                          if (_selectedTierFilter != 'ALL') {
                            if (!tierLabel
                                .contains(_selectedTierFilter.toLowerCase())) {
                              return false;
                            }
                          }

                          // Search
                          if (_searchQuery.isNotEmpty) {
                            if (!name.contains(_searchQuery.toLowerCase())) {
                              return false;
                            }
                          }

                          return true;
                        }).toList();

                        // Sort
                        if (_sortMode == 'tier') {
                          int getTierRank(String? uuid) {
                            if (uuid == null || uuid.isEmpty) return 5;
                            final u = uuid.toLowerCase();
                            if (u.contains('411e4a55')) return 0; // Ultra
                            if (u.contains('e046854e')) return 1; // Exclusive
                            if (u.contains('60bca009')) return 2; // Premium
                            if (u.contains('0cebb8be')) return 3; // Deluxe
                            if (u.contains('12683d76')) return 4; // Select
                            return 5;
                          }

                          filteredSkins.sort((a, b) {
                            final ta =
                                getTierRank(a['contentTierUuid'] as String?);
                            final tb =
                                getTierRank(b['contentTierUuid'] as String?);
                            return ta.compareTo(tb);
                          });
                        }

                        if (filteredSkins.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    color: Colors.white24, size: 48),
                                SizedBox(height: 12),
                                Text('No Skins Found',
                                    style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.red.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppColors.red.withAlpha(80),
                                          width: 0.8),
                                    ),
                                    child: Text(
                                      '${filteredSkins.length} SKINS',
                                      style: const TextStyle(
                                          color: AppColors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(10),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.82,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: filteredSkins.length,
                                itemBuilder: (context, idx) {
                                  final item = filteredSkins[idx];
                                  final levelUuid =
                                      item['skinLevelUuid'] as String;
                                  final name = item['displayName'] as String;
                                  final iconUrl = item['displayIcon'] as String;
                                  final tierUuid =
                                      item['contentTierUuid'] as String?;
                                  final allUuids =
                                      (item['allUuids'] as List<dynamic>? ??
                                          [levelUuid, item['skinUuid']]);
                                  final isWishlisted = allUuids
                                      .any((id) => wishlist.contains(id));
                                  final tierColor = _getTierColor(tierUuid);

                                  return _SkinCatalogGridCard(
                                    name: name,
                                    iconUrl: iconUrl,
                                    tierColor: tierColor,
                                    tierUuid: tierUuid,
                                    isWishlisted: isWishlisted,
                                    onToggleWishlist: () {
                                      final matchedUuids = allUuids
                                          .where((id) => wishlist.contains(id))
                                          .toList();
                                      if (matchedUuids.isNotEmpty) {
                                        for (final id in matchedUuids) {
                                          ref
                                              .read(wishlistProvider.notifier)
                                              .toggle(id.toString());
                                        }
                                      } else {
                                        ref
                                            .read(wishlistProvider.notifier)
                                            .toggle(levelUuid);
                                      }
                                    },
                                    onTap: () {
                                      final offer = SkinOffer(
                                        offerId: levelUuid,
                                        skinLevelUuid: levelUuid,
                                        price: 0,
                                        displayName: name,
                                        displayIcon: iconUrl,
                                        contentTierUuid: tierUuid,
                                        isInWishlist: isWishlisted,
                                      );
                                      SkinDetailModal.show(context, offer);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () => const WishlistCatalogSkeleton(),
                      error: (e, _) => Center(
                        child: ValorantErrorDisplay(
                          error: e,
                          onRetry: () => reconnectAndInvalidate(
                            ref,
                            invalidateData: () =>
                                ref.invalidate(_allSkinsListProvider),
                            onPermanentAuthFailure: () =>
                                context.push('/login/webview'),
                          ),
                          onReauth: () => context.push('/login/webview'),
                          title: 'Gagal Memuat Katalog Senjata',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skin Catalog Grid Card ────────────────────────────────────────────────────
// Card background uses tier color gradient (like shop screen).
// Tier label text removed — color communicates tier visually.

class _SkinCatalogGridCard extends StatelessWidget {
  const _SkinCatalogGridCard({
    required this.name,
    required this.iconUrl,
    required this.tierColor,
    required this.tierUuid,
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onTap,
  });

  final String name;
  final String iconUrl;
  final Color tierColor;
  final String? tierUuid;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tierColor.withAlpha(35),
            const Color(0xFF0C1118),
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWishlisted ? AppColors.red : Colors.white.withAlpha(18),
            width: isWishlisted ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image area ───────────────────────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    // Weapon image
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                        child: CachedNetworkImage(
                          imageUrl: iconUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, __) =>
                              const LoadingShimmer(height: 60),
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.military_tech_outlined,
                              color: Colors.white24,
                              size: 28),
                        ),
                      ),
                    ),

                    // Top-right: Bookmark / Wishlist toggle icon overlaid on image
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onToggleWishlist,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(160),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  isWishlisted ? AppColors.red : Colors.white24,
                              width: 1.0,
                            ),
                          ),
                          child: Icon(
                            isWishlisted
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color:
                                isWishlisted ? AppColors.red : Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Footer (Solid Black Background): Tier Icon + Skin Name ─────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.black, // Solid black background
                  border: Border(
                    top: BorderSide(color: Color(0x22FFFFFF), width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    // Skin Tier Icon (only the icon) to the left of skin name
                    SkinTierIcon(
                      tierUuid: tierUuid,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
