import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/loading_shimmer.dart';
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
      final skinName =
          skinData['skinName']?.toString() ?? skinData['displayName']?.toString() ?? '';
      final displayIcon = skinData['displayIcon']?.toString();

      final lowerName = skinName.toLowerCase().trim();
      if (skinName.isNotEmpty &&
          !lowerName.startsWith('standard') &&
          lowerName != 'melee' &&
          displayIcon != null &&
          displayIcon.isNotEmpty) {
        final skinUuid = skinData['skinUuid']?.toString() ?? levelUuid;
        uniqueSkins[skinUuid] = {
          'skinUuid': skinUuid,
          'skinLevelUuid': levelUuid,
          'displayName': skinName,
          'displayIcon': displayIcon,
          'contentTierUuid': skinData['contentTierUuid']?.toString(),
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

/// Returns whether a skin name matches a specific individual weapon sidebar ID.
bool _matchesWeaponId(String skinName, String weaponId) {
  final name = skinName.toLowerCase();
  final id = weaponId.toLowerCase();
  return name.contains(id);
}

Color _getTierColor(String? tierUuid) {
  // Intentional: Premium uses AppColors.red in the catalog (brand consistency).
  // All other tiers delegate to the shared TierColors utility.
  const premiumUuidFragment = '60bca009';
  if (tierUuid != null && tierUuid.toLowerCase().contains(premiumUuidFragment)) {
    return AppColors.red;
  }
  return TierColors.tierColorForUuid(tierUuid);
}

String _getTierLabel(String? tierUuid) => TierColors.tierLabelForUuid(tierUuid);

// ── Sidebar category definitions ──────────────────────────────────────────────

class _SidebarItem {
  const _SidebarItem({required this.id, required this.label, required this.icon});
  final String id;
  final String label;
  final IconData icon;
}

const _sidebarItems = [
  _SidebarItem(id: 'ALL',       label: 'ALL',      icon: Icons.grid_view_rounded),
  // ── Pistols ──
  _SidebarItem(id: 'CLASSIC',   label: 'CLASSIC',  icon: Icons.radio_button_unchecked),
  _SidebarItem(id: 'SHORTY',    label: 'SHORTY',   icon: Icons.horizontal_rule_rounded),
  _SidebarItem(id: 'FRENZY',    label: 'FRENZY',   icon: Icons.bolt_rounded),
  _SidebarItem(id: 'GHOST',     label: 'GHOST',    icon: Icons.nightlight_round),
  _SidebarItem(id: 'SHERIFF',   label: 'SHERIFF',  icon: Icons.star_outline_rounded),
  // ── SMGs ──
  _SidebarItem(id: 'STINGER',   label: 'STINGER',  icon: Icons.speed_rounded),
  _SidebarItem(id: 'SPECTRE',   label: 'SPECTRE',  icon: Icons.wind_power_rounded),
  // ── Rifles ──
  _SidebarItem(id: 'BULLDOG',   label: 'BULLDOG',  icon: Icons.adjust_rounded),
  _SidebarItem(id: 'GUARDIAN',  label: 'GUARDIAN', icon: Icons.shield_outlined),
  _SidebarItem(id: 'PHANTOM',   label: 'PHANTOM',  icon: Icons.visibility_off_outlined),
  _SidebarItem(id: 'VANDAL',    label: 'VANDAL',   icon: Icons.military_tech_outlined),
  // ── Snipers ──
  _SidebarItem(id: 'MARSHAL',   label: 'MARSHAL',  icon: Icons.center_focus_weak_rounded),
  _SidebarItem(id: 'OUTLAW',    label: 'OUTLAW',   icon: Icons.gps_fixed_rounded),
  _SidebarItem(id: 'OPERATOR',  label: 'OPERATOR', icon: Icons.center_focus_strong_outlined),
  // ── Shotguns ──
  _SidebarItem(id: 'BUCKY',     label: 'BUCKY',    icon: Icons.flash_on_rounded),
  _SidebarItem(id: 'JUDGE',     label: 'JUDGE',    icon: Icons.electric_bolt_rounded),
  // ── Heavy ──
  _SidebarItem(id: 'ARES',      label: 'ARES',     icon: Icons.rotate_right_rounded),
  _SidebarItem(id: 'ODIN',      label: 'ODIN',     icon: Icons.settings_rounded),
  // ── Melee ──
  _SidebarItem(id: 'MELEE',     label: 'MELEE',    icon: Icons.architecture_rounded),
  // ── Wishlist ──
  _SidebarItem(id: 'WISHLIST',  label: 'WISHLIST', icon: Icons.bookmark_rounded),
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
    {'id': 'ALL',       'label': 'ALL EDITIONS',              'color': const Color(0xB3FFFFFF)},
    {'id': 'Ultra',     'label': 'ULTRA EDITION',             'color': const Color(0xFFFAD663)},
    {'id': 'Exclusive', 'label': 'EXCLUSIVE EDITION',         'color': const Color(0xFFF5955B)},
    {'id': 'Premium',   'label': 'PREMIUM EDITION',           'color': AppColors.red},
    {'id': 'Deluxe',    'label': 'DELUXE EDITION',            'color': const Color(0xFF009587)},
    {'id': 'Select',    'label': 'SELECT EDITION',            'color': const Color(0xFF5A9FE2)},
  ];

  @override
  void dispose() {
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
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w900, letterSpacing: 1.0)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      Container(width: 12, height: 12,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Text(opt['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          )),
                      const Spacer(),
                      if (isSelected) Icon(Icons.check_circle, color: color, size: 18),
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
                            style: TextStyle(color: Colors.white, fontSize: 16,
                                fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        SizedBox(height: 2),
                        Text('COLLECT. CUSTOMIZE. DOMINATE.',
                            style: TextStyle(color: AppColors.red, fontSize: 9,
                                fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                      ],
                    ),
                  ),
                  // VIEW WISHLIST button (replaced old X + summary card)
                  GestureDetector(
                    onTap: () => setState(() => _selectedCategory = 'WISHLIST'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.red.withAlpha(80), width: 1),
                        boxShadow: [BoxShadow(color: AppColors.red.withAlpha(25), blurRadius: 10)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bookmark_rounded, color: AppColors.red, size: 14),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${wishlist.length}',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 14, fontWeight: FontWeight.w900)),
                              const Text('VIEW WISHLIST >',
                                  style: TextStyle(color: AppColors.red, fontSize: 8,
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
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10, width: 1),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search skin name',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tier filter
                  GestureDetector(
                    onTap: _showTierFilterModal,
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedTierFilter != 'ALL' ? AppColors.red : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: AppColors.red, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _selectedTierFilter == 'ALL' ? 'TIERS' : _selectedTierFilter.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 11,
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
                    onTap: () => setState(
                        () => _sortMode = _sortMode == 'name' ? 'tier' : 'name'),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _sortMode == 'tier' ? AppColors.red : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sort_rounded, color: AppColors.red, size: 18),
                          const SizedBox(width: 4),
                          Text(_sortMode == 'name' ? 'A–Z' : 'TIER',
                              style: const TextStyle(color: Colors.white, fontSize: 11,
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
                    width: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(right: BorderSide(color: Colors.white10, width: 0.8)),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _sidebarItems.length,
                      itemBuilder: (context, idx) {
                        final item = _sidebarItems[idx];
                        final isSelected = _selectedCategory == item.id;
                        final isWishlist = item.id == 'WISHLIST';

                        // Section dividers before first item of each group
                        final showDivider = item.id == 'CLASSIC' ||
                            item.id == 'STINGER' || item.id == 'BULLDOG' ||
                            item.id == 'MARSHAL' || item.id == 'BUCKY' ||
                            item.id == 'ARES'    || item.id == 'MELEE'  ||
                            item.id == 'WISHLIST';

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showDivider)
                              const Divider(height: 8, thickness: 0.5,
                                  color: Colors.white10, indent: 10, endIndent: 10),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCategory = item.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 5),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.red.withAlpha(40)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isSelected
                                      ? Border.all(color: AppColors.red, width: 1)
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: isSelected
                                          ? (isWishlist ? AppColors.red : AppColors.red)
                                          : Colors.white38,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.white38,
                                        fontSize: 7,
                                        fontWeight: isSelected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        letterSpacing: 0.2,
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
                          final name = (skin['displayName'] as String).toLowerCase();
                          final levelUuid = skin['skinLevelUuid'] as String;
                          final skinUuid = skin['skinUuid'] as String;
                          final tierUuid = skin['contentTierUuid'] as String?;
                          final tierLabel = _getTierLabel(tierUuid).toLowerCase();

                          // Sidebar category / weapon filter
                          if (_selectedCategory == 'WISHLIST') {
                            if (!wishlist.contains(levelUuid) &&
                                !wishlist.contains(skinUuid)) { return false; }
                          } else if (_selectedCategory != 'ALL') {
                            if (!_matchesWeaponId(name, _selectedCategory)) { return false; }
                          }

                          // Edition tier filter
                          if (_selectedTierFilter != 'ALL') {
                            if (!tierLabel.contains(
                                _selectedTierFilter.toLowerCase())) { return false; }
                          }

                          // Search
                          if (_searchQuery.isNotEmpty) {
                            if (!name.contains(_searchQuery.toLowerCase())) return false;
                          }

                          return true;
                        }).toList();

                        // Sort
                        if (_sortMode == 'tier') {
                          const tierOrder = {
                            '411e4a55': 0,
                            'e046854e': 1,
                            '60bca009': 2,
                            '0cebb8be': 3,
                            '12683d76': 4,
                          };
                          filteredSkins.sort((a, b) {
                            final ta = tierOrder.entries
                                .firstWhere(
                                  (e) => (a['contentTierUuid'] as String? ?? '')
                                      .toLowerCase()
                                      .contains(e.key),
                                  orElse: () => const MapEntry('', 5),
                                )
                                .value;
                            final tb = tierOrder.entries
                                .firstWhere(
                                  (e) => (b['contentTierUuid'] as String? ?? '')
                                      .toLowerCase()
                                      .contains(e.key),
                                  orElse: () => const MapEntry('', 5),
                                )
                                .value;
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
                                    style: TextStyle(color: Colors.white54,
                                        fontSize: 14, fontWeight: FontWeight.w700)),
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
                                          color: AppColors.red.withAlpha(80), width: 0.8),
                                    ),
                                    child: Text(
                                      '${filteredSkins.length} SKINS',
                                      style: const TextStyle(color: AppColors.red,
                                          fontSize: 10, fontWeight: FontWeight.w900,
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
                                  final levelUuid = item['skinLevelUuid'] as String;
                                  final skinUuid = item['skinUuid'] as String;
                                  final name = item['displayName'] as String;
                                  final iconUrl = item['displayIcon'] as String;
                                  final tierUuid = item['contentTierUuid'] as String?;
                                  final isWishlisted = wishlist.contains(levelUuid) ||
                                      wishlist.contains(skinUuid);
                                  final tierColor = _getTierColor(tierUuid);

                                  return _SkinCatalogGridCard(
                                    name: name,
                                    iconUrl: iconUrl,
                                    tierColor: tierColor,
                                    isWishlisted: isWishlisted,
                                    onToggleWishlist: () => ref
                                        .read(wishlistProvider.notifier)
                                        .toggle(levelUuid),
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
                        child: Text('Error: $e',
                            style: const TextStyle(color: Colors.white54)),
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
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onTap,
  });

  final String name;
  final String iconUrl;
  final Color tierColor;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Tier color gradient background — same pattern as shop/daily screen
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tierColor.withAlpha(55),
              AppColors.bgCard2,
            ],
          ),
          border: Border.all(
            color: isWishlisted ? AppColors.red : tierColor.withAlpha(80),
            width: isWishlisted ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wishlist badge — only show when skin is wishlisted
                  if (isWishlisted)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.red.withAlpha(40),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.red, width: 0.8),
                        ),
                        child: const Text(
                          'WISHLIST',
                          style: TextStyle(color: AppColors.red, fontSize: 7,
                              fontWeight: FontWeight.w900, letterSpacing: 0.4),
                        ),
                      ),
                    ),

                  // Weapon image
                  Expanded(
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: iconUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const LoadingShimmer(height: 60),
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.military_tech_outlined,
                            color: Colors.white24, size: 28),
                      ),
                    ),
                  ),

                  // Skin name — no tier label below it
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Bookmark toggle
            Positioned(
              right: 8,
              bottom: 8,
              child: GestureDetector(
                onTap: onToggleWishlist,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isWishlisted ? AppColors.red : Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isWishlisted
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: isWishlisted ? Colors.white : Colors.white54,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
