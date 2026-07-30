import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/tier_colors.dart';
import '../domain/models/skin_offer.dart';
import 'skin_detail_modal.dart';
import 'wishlist_provider.dart';

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
          'contentTierUuid': skinData['contentTierUuid'],
        };
      }
    }
  });

  final list = uniqueSkins.values.toList();
  list.sort((a, b) =>
      (a['displayName'] as String).compareTo(b['displayName'] as String));
  return list;
});

const _categories = [
  'All',
  'Vandal',
  'Phantom',
  'Melee',
  'Operator',
  'Sheriff',
  'Ghost',
  'Classic',
  'Spectre',
  'Outlaw',
  'Marshal',
  'Judge',
  'Bucky',
  'Bulldog',
  'Guardian',
  'Ares',
  'Odin',
  'Frenzy',
  'Shorty',
];

class WishlistCatalogScreen extends ConsumerStatefulWidget {
  const WishlistCatalogScreen({super.key});

  @override
  ConsumerState<WishlistCatalogScreen> createState() =>
      _WishlistCatalogScreenState();
}

class _WishlistCatalogScreenState
    extends ConsumerState<WishlistCatalogScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skinsAsync = ref.watch(_allSkinsListProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text(
          'SKIN CATALOG & WISHLIST',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4655).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF4655), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bookmark, color: Color(0xFFFF4655), size: 14),
                const SizedBox(width: 4),
                Text(
                  '${wishlist.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search skin name (e.g. Prime, Kuronami, Reaver)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFFF4655)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0E1622),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1B2738)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1B2738)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFF4655)),
                ),
              ),
            ),
          ),

          // Category Filter Bar
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF4655)
                          : const Color(0xFF0E1622),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF4655)
                            : const Color(0xFF1B2738),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Skins Grid
          Expanded(
            child: skinsAsync.when(
              data: (skins) {
                final filtered = skins.where((s) {
                  final name = (s['displayName'] as String).toLowerCase();
                  final matchesSearch = _searchQuery.isEmpty ||
                      name.contains(_searchQuery.toLowerCase());

                  bool matchesCategory = true;
                  if (_selectedCategory != 'All') {
                    final catLower = _selectedCategory.toLowerCase();
                    if (catLower == 'melee') {
                      matchesCategory = name.contains('knife') ||
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
                    } else {
                      matchesCategory = name.contains(catLower);
                    }
                  }

                  return matchesSearch && matchesCategory;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching skins found.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final skin = filtered[idx];
                    final levelUuid = skin['skinLevelUuid'] as String;
                    final isWishlisted = wishlist.contains(levelUuid);
                    final tierUuid = skin['contentTierUuid'] as String?;
                    final tierColor = TierColors.forName(tierUuid);

                    final offer = SkinOffer(
                      offerId: levelUuid,
                      skinLevelUuid: levelUuid,
                      price: 0,
                      displayName: skin['displayName'] as String?,
                      displayIcon: skin['displayIcon'] as String?,
                      contentTierUuid: tierUuid,
                      isInWishlist: isWishlisted,
                    );

                    return GestureDetector(
                      onTap: () => SkinDetailModal.show(context, offer),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E1622),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isWishlisted
                                ? const Color(0xFFFF4655)
                                : tierColor.withAlpha(120),
                            width: isWishlisted ? 2 : 1,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tierColor.withAlpha(50),
                              const Color(0xFF0E1622),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Skin Artwork Image
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Center(
                                  child: CachedNetworkImage(
                                    imageUrl: skin['displayIcon'] as String,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF4655),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined,
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Footer with name + Wishlist toggle button
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Color(0xFF070A10),
                                borderRadius: BorderRadius.vertical(
                                    bottom: Radius.circular(11)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      skin['displayName'] as String,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      ref
                                          .read(wishlistProvider.notifier)
                                          .toggle(levelUuid);
                                    },
                                    child: Icon(
                                      isWishlisted
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                      color: isWishlisted
                                          ? const Color(0xFFFF4655)
                                          : Colors.white38,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF4655)),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.white54)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
