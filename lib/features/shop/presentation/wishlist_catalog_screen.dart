import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
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

      // Filter out base 'Standard' default skins
      if (skinName.isNotEmpty &&
          !skinName.toLowerCase().startsWith('standard') &&
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

String _getWeaponCategory(String skinName) {
  final name = skinName.toLowerCase();
  if (name.contains('ghost') ||
      name.contains('classic') ||
      name.contains('sheriff') ||
      name.contains('frenzy') ||
      name.contains('shorty')) {
    return 'SIDEARMS';
  }
  if (name.contains('spectre') || name.contains('stinger')) {
    return 'SMGS';
  }
  if (name.contains('vandal') ||
      name.contains('phantom') ||
      name.contains('bulldog') ||
      name.contains('guardian')) {
    return 'RIFLES';
  }
  if (name.contains('operator') ||
      name.contains('outlaw') ||
      name.contains('marshal')) {
    return 'SNIPER';
  }
  if (name.contains('judge') || name.contains('bucky')) {
    return 'SHOTGUNS';
  }
  if (name.contains('melee') ||
      name.contains('knife') ||
      name.contains('axe') ||
      name.contains('blade') ||
      name.contains('sword') ||
      name.contains('dagger') ||
      name.contains('karambit') ||
      name.contains('scythe') ||
      name.contains('staff') ||
      name.contains('mace') ||
      name.contains('katana')) {
    return 'MELEE';
  }
  return 'RIFLES';
}

String _getTierLabel(String? tierUuid) {
  if (tierUuid == null || tierUuid.isEmpty) return 'Standard Edition';
  final uuid = tierUuid.toLowerCase();
  if (uuid.contains('12683d76')) return 'Select Edition';
  if (uuid.contains('0cebb8be')) return 'Deluxe Edition';
  if (uuid.contains('60bca009')) return 'Premium Edition';
  if (uuid.contains('411e4a55')) return 'Ultra Edition';
  if (uuid.contains('e046854e')) return 'Exclusive Edition';
  return TierColors.tierLabel(tierUuid);
}

Color _getTierColor(String? tierUuid) {
  if (tierUuid == null || tierUuid.isEmpty) return const Color(0xFF5A9FE2);
  final uuid = tierUuid.toLowerCase();
  // Absolute Tier Colors (Official Valorant Color Palette)
  if (uuid.contains('12683d76')) return const Color(0xFF5A9FE2); // Select (Light Blue)
  if (uuid.contains('0cebb8be')) return const Color(0xFF009587); // Deluxe (Teal Green)
  if (uuid.contains('60bca009')) return const Color(0xFFD1548D); // Premium (Pink/Magenta)
  if (uuid.contains('411e4a55')) return const Color(0xFFFAD663); // Ultra (Gold/Yellow)
  if (uuid.contains('e046854e')) return const Color(0xFFF5955B); // Exclusive (Orange)
  return TierColors.forName(tierUuid);
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class WishlistCatalogScreen extends ConsumerStatefulWidget {
  const WishlistCatalogScreen({super.key});

  @override
  ConsumerState<WishlistCatalogScreen> createState() =>
      _WishlistCatalogScreenState();
}

class _WishlistCatalogScreenState
    extends ConsumerState<WishlistCatalogScreen> {
  String _selectedCategory = 'ALL';
  String _selectedQuickFilter = 'ALL';
  String _selectedTierFilter = 'ALL';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<Map<String, dynamic>> _quickFilterPills = [
    {'id': 'ALL', 'label': 'ALL'},
    {'id': 'VANDAL', 'label': 'VANDAL'},
    {'id': 'PHANTOM', 'label': 'PHANTOM'},
    {'id': 'MELEE', 'label': 'MELEE'},
    {'id': 'OPERATOR', 'label': 'OPERATOR'},
    {'id': 'SHERIFF', 'label': 'SHERIFF'},
    {'id': 'GHOST', 'label': 'GHOST'},
  ];

  final List<Map<String, dynamic>> _sidebarCategories = [
    {'id': 'ALL', 'label': 'ALL', 'icon': Icons.grid_view_rounded},
    {'id': 'SIDEARMS', 'label': 'SIDEARMS', 'icon': Icons.shield_outlined},
    {'id': 'SMGS', 'label': 'SMGS', 'icon': Icons.speed_rounded},
    {'id': 'RIFLES', 'label': 'RIFLES', 'icon': Icons.military_tech_outlined},
    {'id': 'SNIPER', 'label': 'SNIPER', 'icon': Icons.center_focus_strong_outlined},
    {'id': 'SHOTGUNS', 'label': 'SHOTGUNS', 'icon': Icons.flash_on_rounded},
    {'id': 'MELEE', 'label': 'MELEE', 'icon': Icons.architecture_rounded},
    {'id': 'WISHLIST', 'label': 'WISHLIST', 'icon': Icons.bookmark_rounded},
  ];

  final List<Map<String, dynamic>> _tierOptions = [
    {'id': 'ALL', 'label': 'ALL EDITIONS', 'color': Colors.white70},
    {'id': 'Ultra', 'label': 'ULTRA EDITION (GOLD)', 'color': const Color(0xFFFAD663)},
    {'id': 'Exclusive', 'label': 'EXCLUSIVE EDITION (ORANGE)', 'color': const Color(0xFFF5955B)},
    {'id': 'Premium', 'label': 'PREMIUM EDITION (PINK)', 'color': const Color(0xFFD1548D)},
    {'id': 'Deluxe', 'label': 'DELUXE EDITION (GREEN)', 'color': const Color(0xFF009587)},
    {'id': 'Select', 'label': 'SELECT EDITION (BLUE)', 'color': const Color(0xFF5A9FE2)},
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
          color: const Color(0xFF131B2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFFA855F7), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'FILTER EDITION TIER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
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
                    color: isSelected ? color.withAlpha(40) : const Color(0xFF070A10),
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
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        opt['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
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

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Bar Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SKIN CATALOG & WISHLIST',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'COLLECT. CUSTOMIZE. DOMINATE.',
                          style: TextStyle(
                            color: Color(0xFFA855F7),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top Right Wishlist Summary Card
                  _WishlistHeaderSummaryCard(
                    wishlistCount: wishlist.length,
                    onTap: () {
                      setState(() => _selectedCategory = 'WISHLIST');
                    },
                  ),
                ],
              ),
            ),

            // 2. Search & Filter Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E),
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
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
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

                  // Tier Filter Dropdown Button
                  GestureDetector(
                    onTap: _showTierFilterModal,
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedTierFilter != 'ALL'
                              ? const Color(0xFFA855F7)
                              : Colors.white10,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: Color(0xFFA855F7), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _selectedTierFilter == 'ALL'
                                ? 'ALL EDITIONS'
                                : _selectedTierFilter.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Quick Weapon Type Filter Horizontal Pills
            SizedBox(
              height: 34,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _quickFilterPills.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, idx) {
                  final pill = _quickFilterPills[idx];
                  final isSelected = _selectedQuickFilter == pill['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedQuickFilter = pill['id'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFA855F7) : const Color(0xFF131B2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFA855F7) : Colors.white10,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          pill['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // 4. Main Body (Left Vertical Sidebar + Right Grid View)
            Expanded(
              child: Row(
                children: [
                  // Left Vertical Sidebar Menu
                  Container(
                    width: 78,
                    decoration: const BoxDecoration(
                      color: Color(0xFF070A10),
                      border: Border(right: BorderSide(color: Colors.white10, width: 0.8)),
                    ),
                    child: ListView.builder(
                      itemCount: _sidebarCategories.length,
                      itemBuilder: (context, idx) {
                        final cat = _sidebarCategories[idx];
                        final isSelected = _selectedCategory == cat['id'];
                        final isWishlistCat = cat['id'] == 'WISHLIST';

                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat['id'] as String),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isWishlistCat
                                      ? const Color(0xFFD1548D).withAlpha(40)
                                      : const Color(0xFFA855F7).withAlpha(40))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(
                                      color: isWishlistCat
                                          ? const Color(0xFFD1548D)
                                          : const Color(0xFFA855F7),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  cat['icon'] as IconData,
                                  color: isSelected
                                      ? (isWishlistCat ? const Color(0xFFD1548D) : const Color(0xFFA855F7))
                                      : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat['label'] as String,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white38,
                                    fontSize: 8,
                                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Right Skin Grid View
                  Expanded(
                    child: skinsAsync.when(
                      data: (skins) {
                        // Apply Filter Rules
                        final filteredSkins = skins.where((skin) {
                          final name = (skin['displayName'] as String).toLowerCase();
                          final levelUuid = skin['skinLevelUuid'] as String;
                          final skinUuid = skin['skinUuid'] as String;
                          final category = _getWeaponCategory(name);
                          final tierUuid = skin['contentTierUuid'] as String?;
                          final tierLabel = _getTierLabel(tierUuid).toLowerCase();

                          // Wishlist Category Filter
                          if (_selectedCategory == 'WISHLIST') {
                            final isWishlisted = wishlist.contains(levelUuid) || wishlist.contains(skinUuid);
                            if (!isWishlisted) return false;
                          } else if (_selectedCategory != 'ALL') {
                            if (category != _selectedCategory) return false;
                          }

                          // Quick Weapon Filter
                          if (_selectedQuickFilter != 'ALL') {
                            if (!name.contains(_selectedQuickFilter.toLowerCase())) return false;
                          }

                          // Edition Tier Filter
                          if (_selectedTierFilter != 'ALL') {
                            if (!tierLabel.contains(_selectedTierFilter.toLowerCase())) return false;
                          }

                          // Search Query Filter
                          if (_searchQuery.isNotEmpty) {
                            if (!name.contains(_searchQuery.toLowerCase())) return false;
                          }

                          return true;
                        }).toList();

                        if (filteredSkins.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, color: Colors.white24, size: 48),
                                SizedBox(height: 12),
                                Text(
                                  'No Skins Found',
                                  style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          );
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

                            final isWishlisted = wishlist.contains(levelUuid) || wishlist.contains(skinUuid);
                            final tierColor = _getTierColor(tierUuid);
                            final tierLabel = _getTierLabel(tierUuid);

                            return _SkinCatalogGridCard(
                              name: name,
                              iconUrl: iconUrl,
                              tierColor: tierColor,
                              tierLabel: tierLabel,
                              isWishlisted: isWishlisted,
                              onToggleWishlist: () {
                                ref.read(wishlistProvider.notifier).toggle(levelUuid);
                              },
                              onTap: () {
                                final offer = SkinOffer(
                                  offerId: levelUuid,
                                  skinLevelUuid: levelUuid,
                                  price: 0, // price shown in detail modal from live store data
                                  displayName: name,
                                  displayIcon: iconUrl,
                                  contentTierUuid: tierUuid,
                                  isInWishlist: isWishlisted,
                                );
                                SkinDetailModal.show(context, offer);
                              },
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00E8F0)),
                      ),
                      error: (e, _) => Center(
                        child: Text('Error: $e', style: const TextStyle(color: Colors.white54)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 5. Bottom Dock: WISHLIST PREVIEW (Matching Mockup Footer)
            if (wishlist.isNotEmpty)
              skinsAsync.when(
                data: (allSkins) {
                  final wishlistedSkins = allSkins.where((s) {
                    final lUuid = s['skinLevelUuid'] as String;
                    final sUuid = s['skinUuid'] as String;
                    return wishlist.contains(lUuid) || wishlist.contains(sUuid);
                  }).toList();

                  return _WishlistPreviewBottomDock(
                    wishlistedSkins: wishlistedSkins,
                    onViewAllTap: () => setState(() => _selectedCategory = 'WISHLIST'),
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Top Header Wishlist Summary Card ──────────────────────────────────────────

class _WishlistHeaderSummaryCard extends StatelessWidget {
  const _WishlistHeaderSummaryCard({
    required this.wishlistCount,
    required this.onTap,
  });

  final int wishlistCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1548D).withAlpha(80), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1548D).withAlpha(25),
              blurRadius: 10,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.bookmark_rounded, color: Color(0xFFD1548D), size: 14),
                SizedBox(width: 4),
                Text(
                  'WISHLIST',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '$wishlistCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'VIEW WISHLIST',
                  style: TextStyle(
                    color: Color(0xFFD1548D),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFD1548D), size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skin Catalog Grid Card ───────────────────────────────────────────────────

class _SkinCatalogGridCard extends StatelessWidget {
  const _SkinCatalogGridCard({
    required this.name,
    required this.iconUrl,
    required this.tierColor,
    required this.tierLabel,
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onTap,
  });

  final String name;
  final String iconUrl;
  final Color tierColor;
  final String tierLabel;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWishlisted ? const Color(0xFFD1548D) : Colors.white10,
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
                  // Top Status Badge (WISHLIST or OWNED)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isWishlisted
                            ? const Color(0xFFD1548D).withAlpha(40)
                            : const Color(0xFFA855F7).withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isWishlisted ? const Color(0xFFD1548D) : const Color(0xFFA855F7),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isWishlisted ? 'WISHLIST' : 'OWNED',
                        style: TextStyle(
                          color: isWishlisted ? const Color(0xFFD1548D) : const Color(0xFFA855F7),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),

                  // Weapon Image
                  Expanded(
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: iconUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const LoadingShimmer(height: 60),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24),
                      ),
                    ),
                  ),

                  // Bottom Name & Edition Subtitle in Absolute Tier Color
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tierLabel,
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Bottom Right Bookmark Toggle Button
            Positioned(
              right: 8,
              bottom: 8,
              child: GestureDetector(
                onTap: onToggleWishlist,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isWishlisted ? const Color(0xFFD1548D) : Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isWishlisted ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
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

// ── WISHLIST PREVIEW Bottom Dock ──────────────────────────────────────────────

class _WishlistPreviewBottomDock extends StatelessWidget {
  const _WishlistPreviewBottomDock({
    required this.wishlistedSkins,
    required this.onViewAllTap,
  });

  final List<Map<String, dynamic>> wishlistedSkins;
  final VoidCallback onViewAllTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF070A10),
        border: Border(top: BorderSide(color: Colors.white10, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_rounded, color: Color(0xFFA855F7), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'WISHLIST PREVIEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onViewAllTap,
                child: Row(
                  children: [
                    Text(
                      '${wishlistedSkins.length} ITEMS',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, color: Colors.white38, size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: wishlistedSkins.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final item = wishlistedSkins[idx];
                final iconUrl = item['displayIcon'] as String;
                final tierUuid = item['contentTierUuid'] as String?;
                final tierColor = _getTierColor(tierUuid);

                return Container(
                  width: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tierColor.withAlpha(80), width: 1),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(
                          child: CachedNetworkImage(
                            imageUrl: iconUrl,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => const LoadingShimmer(height: 30),
                            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24, size: 16),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tierColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
