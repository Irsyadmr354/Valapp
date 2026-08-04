import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../shop/presentation/wishlist_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _debugSkinsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  final map = await assets.getSkinLevelsMap();
  final uniqueSkins = <String, Map<String, dynamic>>{};

  map.forEach((levelUuid, skinData) {
    if (skinData is! Map<String, dynamic>) return;
    final skinName = skinData['skinName']?.toString() ??
        skinData['displayName']?.toString() ??
        '';
    final displayIcon = skinData['displayIcon']?.toString();
    final lowerName = skinName.toLowerCase().trim();
    final weaponType = (skinData['weaponType'] as String? ?? '').toLowerCase();

    if (skinName.isEmpty ||
        lowerName.startsWith('standard') ||
        displayIcon == null ||
        displayIcon.isEmpty) {
      return;
    }

    final skinUuid = skinData['skinUuid']?.toString() ?? levelUuid;
    uniqueSkins[skinUuid] = {
      'skinUuid': skinUuid,
      'skinLevelUuid': levelUuid,
      'displayName': skinName,
      'displayIcon': displayIcon,
      'weaponType': weaponType,
    };
  });

  final list = uniqueSkins.values.toList()
    ..sort((a, b) =>
        (a['displayName'] as String).compareTo(b['displayName'] as String));
  return list;
});

// ── Screen ────────────────────────────────────────────────────────────────────

/// Hidden admin page for manually testing wishlist background notifications.
class NotificationDebugScreen extends ConsumerStatefulWidget {
  const NotificationDebugScreen({super.key});

  @override
  ConsumerState<NotificationDebugScreen> createState() =>
      _NotificationDebugScreenState();
}

class _NotificationDebugScreenState
    extends ConsumerState<NotificationDebugScreen> {
  final _mockShopIds = <String>{};
  String _searchQuery = '';
  String _weaponFilter = 'ALL';
  bool _isTriggering = false;
  String? _lastResult;
  final _searchController = TextEditingController();

  static const _weaponFilters = [
    'ALL',
    'VANDAL',
    'PHANTOM',
    'OPERATOR',
    'MELEE',
    'CLASSIC',
    'SHERIFF',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _triggerNotifications() async {
    if (_isTriggering) return;
    setState(() {
      _isTriggering = true;
      _lastResult = null;
    });

    try {
      await NotificationService.instance.requestPermissions();
      final wishlist = ref.read(wishlistProvider).toSet();

      if (wishlist.isEmpty) {
        setState(() => _lastResult = 'Wishlist kosong — tambahkan skin dulu.');
        return;
      }
      if (_mockShopIds.isEmpty) {
        setState(
          () => _lastResult =
              'Mock shop kosong — tap skin untuk menambahkan ke shop simulasi.',
        );
        return;
      }

      final skins = await ref.read(_debugSkinsProvider.future);
      final nameByLevelId = <String, String>{
        for (final skin in skins)
          skin['skinLevelUuid'] as String: skin['displayName'] as String,
      };

      final matched = _mockShopIds
          .where((id) => wishlist.contains(id))
          .toList()
        ..sort();

      if (matched.isEmpty) {
        setState(
          () => _lastResult =
              'Tidak ada match — skin di mock shop tidak ada di wishlist.',
        );
        return;
      }

      final shopIdentity = 'debug_${DateTime.now().millisecondsSinceEpoch}';
      var notifiedCount = 0;

      for (final skinId in matched) {
        final shown = await NotificationService.instance.showWishlistAlertOnce(
          shopIdentity: shopIdentity,
          skinId: skinId,
          skinName: nameByLevelId[skinId] ?? 'Wishlist Skin',
          price: 1775,
        );
        if (shown) notifiedCount++;
      }

      final skinNames = matched
          .map((id) => nameByLevelId[id] ?? id.substring(0, 8))
          .toList();
      await NotificationService.instance.showShopResetAlert(
        skinNames: skinNames,
        wishlistMatchCount: matched.length,
      );

      setState(() {
        _lastResult =
            'Triggered! $notifiedCount wishlist alert(s), ${matched.length} match(es).';
      });
    } catch (e) {
      setState(() => _lastResult = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  Future<void> _resetDedupeLedger() async {
    final creds = await ref.read(currentCredentialsProvider.future);
    if (creds == null) return;
    final key = CacheStorage.userKeyFor(
      CacheStorage.keyWishlistNotificationDedupe,
      creds.puuid,
    );
    await CacheStorage.instance.remove(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification dedupe ledger cleared'),
          backgroundColor: AppColors.bgCard2,
        ),
      );
    }
  }

  void _toggleMockShop(String levelUuid) {
    setState(() {
      if (_mockShopIds.contains(levelUuid)) {
        _mockShopIds.remove(levelUuid);
      } else {
        _mockShopIds.add(levelUuid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skinsAsync = ref.watch(_debugSkinsProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('NOTIFICATION DEBUG'),
        backgroundColor: AppColors.bgPanel,
      ),
      body: Column(
        children: [
          // ── Control panel ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.red.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BACKGROUND NOTIFICATION TESTER',
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wishlist: ${wishlist.length} · Mock shop: ${_mockShopIds.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1. Tap skin untuk menambah ke mock shop\n'
                  '2. Trigger akan cocokkan mock shop vs wishlist\n'
                  '3. Notifikasi muncul jika ID match',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (_lastResult != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _lastResult!,
                    style: TextStyle(
                      color: _lastResult!.startsWith('Triggered')
                          ? AppColors.win
                          : Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isTriggering ? null : _triggerNotifications,
                        icon: _isTriggering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.notifications_active_rounded,
                                size: 18),
                        label: Text(
                          _isTriggering
                              ? 'TRIGGERING...'
                              : 'TRIGGER NOTIFICATION',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _resetDedupeLedger,
                      child: const Text('RESET', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Search & weapon filter ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search skin...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.bgCard2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _weaponFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final filter = _weaponFilters[i];
                final selected = _weaponFilter == filter;
                return FilterChip(
                  label: Text(filter,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : Colors.white54,
                      )),
                  selected: selected,
                  onSelected: (_) => setState(() => _weaponFilter = filter),
                  backgroundColor: AppColors.bgCard2,
                  selectedColor: AppColors.red.withAlpha(60),
                  checkmarkColor: AppColors.red,
                  side: BorderSide(
                    color: selected ? AppColors.red : Colors.white10,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // ── Skin grid ───────────────────────────────────────────────────
          Expanded(
            child: skinsAsync.when(
              data: (skins) {
                final filtered = skins.where((skin) {
                  final name =
                      (skin['displayName'] as String).toLowerCase();
                  final weaponType = skin['weaponType'] as String? ?? '';
                  if (_searchQuery.isNotEmpty &&
                      !name.contains(_searchQuery.toLowerCase())) {
                    return false;
                  }
                  if (_weaponFilter != 'ALL') {
                    final id = _weaponFilter.toLowerCase();
                    if (weaponType.isNotEmpty) {
                      if (weaponType != id) return false;
                    } else if (!name.contains(id)) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final skin = filtered[i];
                    final levelUuid = skin['skinLevelUuid'] as String;
                    final name = skin['displayName'] as String;
                    final iconUrl = skin['displayIcon'] as String;
                    final weaponType = skin['weaponType'] as String? ?? '';
                    final inMockShop = _mockShopIds.contains(levelUuid);
                    final inWishlist = wishlist.contains(levelUuid);

                    return GestureDetector(
                      onTap: () => _toggleMockShop(levelUuid),
                      onLongPress: () {
                        ref.read(wishlistProvider.notifier).toggle(levelUuid);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgCard2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inMockShop
                                ? AppColors.win
                                : inWishlist
                                    ? AppColors.red
                                    : Colors.white10,
                            width: inMockShop || inWishlist ? 1.5 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (inMockShop || inWishlist)
                                    Row(
                                      children: [
                                        if (inMockShop)
                                          _badge('SHOP', AppColors.win),
                                        if (inMockShop && inWishlist)
                                          const SizedBox(width: 4),
                                        if (inWishlist)
                                          _badge('WISH', AppColors.red),
                                      ],
                                    ),
                                  Expanded(
                                    child: Center(
                                      child: CachedNetworkImage(
                                        imageUrl: iconUrl,
                                        fit: BoxFit.contain,
                                        placeholder: (_, __) =>
                                            const LoadingShimmer(height: 50),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    weaponType.isNotEmpty
                                        ? weaponType.toUpperCase()
                                        : 'SKIN',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (inMockShop)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.win,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
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

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
