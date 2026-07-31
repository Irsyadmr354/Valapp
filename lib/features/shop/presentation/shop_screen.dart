import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/skin_card.dart';
import '../../../shared/widgets/countdown_timer.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/storefront.dart';
import '../domain/models/wallet.dart';
import '../domain/models/skin_offer.dart';
import '../../../core/services/notification_service.dart';
import 'skin_detail_modal.dart';
import 'bundle_detail_modal.dart';
import 'wishlist_provider.dart';
import '../../auth/presentation/account_switcher_modal.dart';
import '../../match/domain/models/match_history.dart';
import '../../profile/domain/models/account_xp.dart';
import '../../rank/domain/models/player_mmr.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _storefrontProvider = FutureProvider.autoDispose<Storefront?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;

  final repo = await ref.watch(storeRepositoryProvider.future);

  try {
    return await repo.fetchStorefront(creds.shard, creds.puuid);
  } catch (_) {
    return repo.loadCachedStorefront();
  }
});

final _walletProvider = FutureProvider.autoDispose<Wallet?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final repo = await ref.watch(storeRepositoryProvider.future);
  try {
    return await repo.fetchWallet(creds.shard, creds.puuid);
  } catch (_) {
    return repo.loadCachedWallet();
  }
});

final _homeAccountXpProvider = FutureProvider.autoDispose<AccountXp?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  try {
    final raw = await source.fetchAccountXpRaw(creds.shard, creds.puuid);
    final xp = AccountXp.fromJson(raw);
    await cache.saveAccountXp(raw);
    return xp;
  } catch (_) {
    return cache.loadAccountXp();
  }
});

final _homeDisplayNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  try {
    final name = await source.fetchDisplayName(creds.shard, creds.puuid);
    if (name != null && name.isNotEmpty) {
      await cache.saveDisplayName(creds.puuid, name);
      return name;
    }
    throw StateError('Unavailable');
  } catch (_) {
    final cached = await cache.loadDisplayName(creds.puuid);
    if (cached != null && cached.isNotEmpty) return cached;
    return 'Valorant ID';
  }
});

final _homeMmrProvider = FutureProvider.autoDispose<PlayerMmr?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  try {
    final raw = await source.fetchMmrRaw(creds.shard, creds.puuid);
    final mmr = PlayerMmr.fromJson(raw);
    await cache.saveMmr(raw);
    return mmr;
  } catch (_) {
    return cache.loadMmr();
  }
});

final _homeMatchesProvider = FutureProvider.autoDispose<MatchHistoryResult?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchHistoryLocalCacheProvider);
  try {
    final raw = await source.fetchHistoryRaw(creds.shard, creds.puuid);
    final history = MatchHistoryResult.fromJson(raw);
    await cache.saveHistory(history);
    return history;
  } catch (_) {
    return cache.loadHistory();
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  /// Tracks which skin UUIDs have already triggered a notification this session
  /// to prevent spam on every widget rebuild.
  final Set<String> _notifiedSkins = {};

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final storefrontAsync = ref.watch(_storefrontProvider);
    final walletAsync = ref.watch(_walletProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF1A2634),
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(walletAsync),
            storefrontAsync.when(
              data: (storefront) => storefront == null
                  ? const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'Not logged in',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : _buildContent(storefront, wishlist.toSet()),
              loading: () => SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const SkinCardShimmer(),
                    childCount: 4,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFFF4655), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load shop\n$e',
                        style: const TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _refresh,
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4655)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(AsyncValue<Wallet?> walletAsync) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF070A10),
      pinned: true,
      floating: false,
      centerTitle: false,
      toolbarHeight: 64,
      title: Consumer(
        builder: (context, ref, _) {
          final nameAsync = ref.watch(_homeDisplayNameProvider);
          final xpAsync = ref.watch(_homeAccountXpProvider);

          final displayName = nameAsync.asData?.value ?? 'Valorant ID';
          final rawXp = xpAsync.asData?.value;
          final levelStr = rawXp != null ? 'Level ${rawXp.level}' : 'Level --';
          final xpProgress = rawXp != null ? (rawXp.xp / 10000.0).clamp(0.0, 1.0) : 0.0;

          return Row(
            children: [
              GestureDetector(
                onTap: () => AccountSwitcherModal.show(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF00E8F0), Color(0xFF005841)],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'V',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        levelStr,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 36,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: xpProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E8F0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bookmark_outline, color: Color(0xFFFF4655), size: 20),
          tooltip: 'Skin Catalog & Wishlist',
          onPressed: () => context.push('/wishlist'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: walletAsync.when(
            data: (wallet) => wallet != null ? _WalletBar(wallet: wallet) : const SizedBox(),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(Storefront storefront, Set<String> wishlist) {
    return SliverList(
      delegate: SliverChildListDelegate([
        // Header info bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4655).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFF4655).withAlpha(80), width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        color: Color(0xFFFF4655), size: 14),
                    const SizedBox(width: 6),
                    const Text('RESET IN ',
                        style: TextStyle(
                            color: Color(0xFFFF4655),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    CountdownTimer(
                      remainingSeconds: storefront.dailyOffersRemainingSeconds,
                      onExpired: _refresh,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${storefront.dailyOffers.length} ITEMS AVAILABLE',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 1. Featured Bundle (Moved to TOP!)
        if (storefront.featuredBundle != null) ...[
          const _SectionHeader(title: 'Featured Bundle'),
          _BundleBanner(bundle: storefront.featuredBundle!),
          const SizedBox(height: 24),
        ],

        // 2. Daily Shop (Swipeable Carousel)
        if (storefront.dailyOffers.any((o) => wishlist.contains(o.skinLevelUuid))) ...[
          Builder(builder: (context) {
            final matches = storefront.dailyOffers
                .where((o) => wishlist.contains(o.skinLevelUuid))
                .toList();
            // Notify ONCE per skin per session — prevents spam on every rebuild
            for (final m in matches) {
              if (!_notifiedSkins.contains(m.skinLevelUuid)) {
                _notifiedSkins.add(m.skinLevelUuid);
                // Schedule notification after frame to avoid async in build()
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  NotificationService.instance.showWishlistAlert(
                    skinName: m.displayName ?? 'Wishlist Skin',
                    price: m.price,
                  );
                });
              }
            }
            return _WishlistMatchBanner(matchedSkins: matches);
          }),
        ],

        const _SectionHeader(title: 'Daily Shop'),
        _DailyShopCarousel(
          offers: storefront.dailyOffers,
          wishlist: wishlist,
          onWishlistToggle: _toggleWishlist,
        ),
        const SizedBox(height: 28),

        // 3. Night Market (Distinct Purple Neon Carousel)
        if (storefront.hasNightMarket) ...[
          const _SectionHeader(title: 'Night Market'),
          _NightMarketCarousel(offers: storefront.nightMarket),
          const SizedBox(height: 24),
        ],

        // 4. 3 Quick Cards Row (COMPETITIVE RANK, MATCH HISTORY, RECENT TREND)
        const _HomeQuickCardsRow(),

        const SizedBox(height: 80), // bottom nav breathing room
      ]),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(_storefrontProvider);
    ref.invalidate(_walletProvider);

    await ref.read(_storefrontProvider.future);
    await ref.read(_walletProvider.future);
  }

  void _toggleWishlist(SkinOffer offer) {
    ref.read(wishlistProvider.notifier).toggle(offer.skinLevelUuid);
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _WalletBar extends StatelessWidget {
  const _WalletBar({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _CurrencyChip(
          label: '${wallet.valorantPoints}',
          unit: 'VP',
          color: const Color(0xFF00F0FF),
        ),
        const SizedBox(width: 6),
        _CurrencyChip(
          label: '${wallet.radianitePoints}',
          unit: 'RP',
          color: const Color(0xFFFF9900),
        ),
        const SizedBox(width: 6),
        _CurrencyChip(
          label: '${wallet.kingdomCredits}',
          unit: 'KC',
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.label,
    required this.unit,
    required this.color,
  });
  final String label;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070A10).withAlpha(180),
        border: Border.all(color: color.withAlpha(100), width: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Text(
              unit,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: const Color(0xFFFF4655)),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

final _bundlesMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getBundlesMap();
});

final _skinLevelsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getSkinLevelsMap();
});

class _BundleBanner extends ConsumerWidget {
  const _BundleBanner({required this.bundle});
  final FeaturedBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(_bundlesMapProvider);
    final skinLevelsAsync = ref.watch(_skinLevelsMapProvider);

    final bundleMap = bundlesAsync.asData?.value ?? {};
    final skinMap = skinLevelsAsync.asData?.value ?? {};

    final bundleInfo = bundleMap[bundle.bundleUuid.toLowerCase()] ?? bundleMap[bundle.bundleUuid];

    final displayIcon2 = bundleInfo?['displayIcon2'] as String?;
    final verticalImage = bundleInfo?['verticalPromoImage'] as String?;
    final displayIcon = bundleInfo?['displayIcon'] as String?;

    String? imageUrl = displayIcon2 ??
        verticalImage ??
        displayIcon ??
        bundle.verticalPromoImage ??
        bundle.displayIcon;

    // Fallback: If no direct bundle promo image found, use image of the first skin item in bundle
    if ((imageUrl == null || imageUrl.isEmpty) && bundle.itemIds.isNotEmpty) {
      for (final itemId in bundle.itemIds) {
        final skinMeta = skinMap[itemId] as Map<String, dynamic>? ??
            skinMap[itemId.toLowerCase()] as Map<String, dynamic>?;
        final icon = skinMeta?['displayIcon'] as String?;
        if (icon != null && icon.isNotEmpty) {
          imageUrl = icon;
          break;
        }
      }
    }

    final discountInt = (bundle.totalDiscountPercent > 1
            ? bundle.totalDiscountPercent
            : bundle.totalDiscountPercent * 100)
        .round();

    final finalImageUrl = imageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          BundleDetailModal.show(
            context,
            bundle: bundle,
            bannerImageUrl: finalImageUrl,
          );
        },
        child: Container(
          height: 180,
          decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF4655).withAlpha(120), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4655).withAlpha(30),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E2838), Color(0xFF0D1420)],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Promo Artwork Background Image
              if (imageUrl != null && imageUrl.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    placeholder: (_, __) => Container(color: const Color(0xFF141F2D)),
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                ),

              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFF070A10).withAlpha(240),
                        const Color(0xFF070A10).withAlpha(140),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              // Content Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        if (discountInt > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4655),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '-$discountInt% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(140),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${bundle.itemIds.length} ITEMS',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (bundle.durationRemainingSeconds > 0)
                          CountdownTimer(
                            remainingSeconds: bundle.durationRemainingSeconds,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bundle.displayName ?? 'Featured Bundle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.bolt,
                            color: Color(0xFF00F0FF), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${bundle.totalDiscountedCost} VP',
                          style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (bundle.totalBaseCost > bundle.totalDiscountedCost) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${bundle.totalBaseCost} VP',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4655).withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFF4655), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'VIEW ITEMS',
                                style: TextStyle(
                                  color: Color(0xFFFF4655),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.chevron_right, color: Color(0xFFFF4655), size: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}



class _DailyShopCarousel extends StatefulWidget {
  const _DailyShopCarousel({
    required this.offers,
    required this.wishlist,
    required this.onWishlistToggle,
  });

  final List<SkinOffer> offers;
  final Set<String> wishlist;
  final ValueChanged<SkinOffer> onWishlistToggle;

  @override
  State<_DailyShopCarousel> createState() => _DailyShopCarouselState();
}

class _DailyShopCarouselState extends State<_DailyShopCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.84);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.offers.isEmpty) return const SizedBox();

    return Column(
      children: [
        SizedBox(
          height: 270,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.offers.length,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemBuilder: (context, i) {
              final offer = widget.offers[i];
              final inWishlist = widget.wishlist.contains(offer.skinLevelUuid);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () => SkinDetailModal.show(context, offer),
                  child: SkinCard(
                    offer: offer.copyWith(isInWishlist: inWishlist),
                    isHighlighted: inWishlist,
                    onWishlistToggle: () => widget.onWishlistToggle(offer),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.offers.length, (index) {
            final isSelected = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isSelected ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF4655) : Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _NightMarketCarousel extends StatefulWidget {
  const _NightMarketCarousel({required this.offers});
  final List<NightMarketOffer> offers;

  @override
  State<_NightMarketCarousel> createState() => _NightMarketCarouselState();
}

class _NightMarketCarouselState extends State<_NightMarketCarousel> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.78);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.offers.isEmpty) return const SizedBox();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.offers.length,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemBuilder: (context, i) {
              final offer = widget.offers[i];
              final tierColor = TierColors.forName(offer.contentTierUuid);
              final discountInt = (offer.discountPercent > 1
                      ? offer.discountPercent
                      : offer.discountPercent * 100)
                  .round();

              return GestureDetector(
                onTap: () => SkinDetailModal.show(context, offer.toSkinOffer()),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: tierColor.withAlpha(180),
                    width: 1.4,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tierColor.withAlpha(80),
                      tierColor.withAlpha(25),
                      const Color(0xFF0C131D),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tierColor.withAlpha(45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      // Top Tier Accent Bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3.5,
                          color: tierColor,
                        ),
                      ),

                      // Weapon Image
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 60),
                          child: offer.skinIcon != null && offer.skinIcon!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: offer.skinIcon!,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const SizedBox(),
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.shield, color: Colors.white24, size: 48),
                                )
                              : const Icon(Icons.shield, color: Colors.white24, size: 48),
                        ),
                      ),

                      // Discount Tag on Top Right
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withAlpha(80),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Text(
                            '-$discountInt% OFF',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),

                      // Bottom Info Overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFF0F0A1A).withAlpha(230),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  offer.skinName ?? 'Night Market Offer',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '${offer.basePrice}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${offer.discountedPrice} VP',
                                    style: TextStyle(
                                      color: tierColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          ),
        ),
        const SizedBox(height: 10),
        // Neon Purple Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.offers.length, (index) {
            final isSelected = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFA855F7) : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _WishlistMatchBanner extends StatelessWidget {
  const _WishlistMatchBanner({required this.matchedSkins});
  final List<SkinOffer> matchedSkins;

  @override
  Widget build(BuildContext context) {
    if (matchedSkins.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFFFD700).withAlpha(30),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withAlpha(40),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.star, color: Color(0xFFFFD700), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WISHLIST MATCH IN YOUR SHOP TODAY!',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    matchedSkins.map((s) => s.displayName ?? 'Skin').join(', '),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ── 3 Quick Cards Row (Competitive Rank, Match History, Recent Trend) ─────────

class _HomeQuickCardsRow extends ConsumerWidget {
  const _HomeQuickCardsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mmrAsync = ref.watch(_homeMmrProvider);
    final historyAsync = ref.watch(_homeMatchesProvider);

    final mmr = mmrAsync.asData?.value;
    final matches = historyAsync.asData?.value?.matches ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. COMPETITIVE RANK Card (Clickable -> /rank)
          Expanded(
            child: _QuickCardWrapper(
              onTap: () => context.go('/rank'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.military_tech_outlined,
                    iconColor: Color(0xFF00E8F0),
                    title: 'RANK',
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00E8F0).withAlpha(15),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E8F0).withAlpha(25),
                            blurRadius: 10,
                          )
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.shield_outlined, color: Color(0xFF00E8F0), size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      mmr != null && mmr.currentTier > 0
                          ? _tierName(mmr.currentTier).toUpperCase()
                          : 'UNRANKED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      '${mmr?.currentRankedRating ?? 0} / 100 RR',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 3,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ((mmr?.currentRankedRating ?? 0) / 100.0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E8F0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. MATCH HISTORY Card (CLICKABLE -> /matches)
          Expanded(
            child: _QuickCardWrapper(
              onTap: () => context.go('/matches'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.sports_esports_outlined,
                    iconColor: Color(0xFFA855F7),
                    title: 'MATCHES',
                  ),
                  const SizedBox(height: 8),
                  if (matches.isEmpty) ...[
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No recent matches',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ] else ...[
                    for (int i = 0; i < matches.take(3).length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      _MatchMiniTile(
                        queue: matches[i].queueDisplayName.toUpperCase(),
                        date: _formatShortDate(matches[i].gameStartMillis),
                        color: i == 0
                            ? const Color(0xFFFF4655)
                            : (i == 1 ? const Color(0xFF00E8F0) : const Color(0xFF3B82F6)),
                      ),
                    ]
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. RECENT TREND Card
          Expanded(
            child: _QuickCardWrapper(
              onTap: () => context.go('/rank'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.trending_up,
                    iconColor: Color(0xFF00E8F0),
                    title: 'RECENT TREND',
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final latestRr = mmr?.latestUpdate?.rankedRatingEarned ?? 0;
                      final isPos = latestRr >= 0;
                      return Center(
                        child: Text(
                          mmr?.latestUpdate != null
                              ? '${isPos ? '+' : ''}$latestRr RR'
                              : '0 RR',
                          style: TextStyle(
                            color: mmr?.latestUpdate == null
                                ? Colors.white54
                                : (isPos ? const Color(0xFF00E8F0) : const Color(0xFFFF4655)),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  const Center(
                    child: Text(
                      'LAST MATCH',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(8, (idx) {
                        final latestRr = mmr?.latestUpdate?.rankedRatingEarned ?? 0;
                        final isPositive = latestRr >= 0;
                        final barHeight = ((idx + 1) * 2.2).clamp(4.0, 20.0);
                        return Container(
                          width: 3,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isPositive ? const Color(0xFF00E8F0) : const Color(0xFFFF4655),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCardWrapper extends StatelessWidget {
  const _QuickCardWrapper({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        height: 146,
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A2540), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(50),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: child,
      ),
    );
  }
}

class _QuickCardHeader extends StatelessWidget {
  const _QuickCardHeader({required this.icon, required this.iconColor, required this.title});
  final IconData icon;
  final Color iconColor;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 12),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MatchMiniTile extends StatelessWidget {
  const _MatchMiniTile({required this.queue, required this.date, required this.color});
  final String queue;
  final String date;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1420),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(40), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  queue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 12),
        ],
      ),
    );
  }
}

String _formatShortDate(int timestampMs) {
  if (timestampMs == 0) return 'Just now';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return DateFormat('MMM dd, HH:mm').format(dt);
}

String _tierName(int tier) {
  const names = [
    'Unranked', 'Unused 1', 'Unused 2',
    'Iron 1', 'Iron 2', 'Iron 3',
    'Bronze 1', 'Bronze 2', 'Bronze 3',
    'Silver 1', 'Silver 2', 'Silver 3',
    'Gold 1', 'Gold 2', 'Gold 3',
    'Platinum 1', 'Platinum 2', 'Platinum 3',
    'Diamond 1', 'Diamond 2', 'Diamond 3',
    'Ascendant 1', 'Ascendant 2', 'Ascendant 3',
    'Immortal 1', 'Immortal 2', 'Immortal 3',
    'Radiant'
  ];
  if (tier >= 0 && tier < names.length) return names[tier];
  return 'Ranked';
}

