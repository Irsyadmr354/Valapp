import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../shared/widgets/skin_card.dart';
import '../../../shared/widgets/countdown_timer.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/storefront.dart';
import '../domain/models/wallet.dart';
import '../domain/models/skin_offer.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _storefrontProvider = FutureProvider.autoDispose<Storefront?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;

  final repo = await ref.watch(storeRepositoryProvider.future);

  // Cache-first: show cache immediately, fetch fresh in background
  final cached = await repo.loadCachedStorefront();
  if (cached != null) {
    // Fire-and-forget: fetch fresh data in background
    repo.fetchStorefront(creds.shard, creds.puuid).ignore();
    return cached;
  }

  return repo.fetchStorefront(creds.shard, creds.puuid);
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

final _wishlistProvider = StateProvider<Set<String>>((ref) => {});

// ── Screen ────────────────────────────────────────────────────────────────────

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    final list = await CacheStorage.instance.getWishlist();
    if (mounted) {
      ref.read(_wishlistProvider.notifier).state = list.toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storefrontAsync = ref.watch(_storefrontProvider);
    final walletAsync = ref.watch(_walletProvider);
    final wishlist = ref.watch(_wishlistProvider);

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
                  : _buildContent(storefront, wishlist),
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
      title: const Text(
        'ValAPP',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
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
          const SizedBox(height: 28),
        ],

        const SizedBox(height: 80), // bottom nav breathing room
      ]),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(_storefrontProvider);
    ref.invalidate(_walletProvider);

    final creds = await ref.read(currentCredentialsProvider.future);
    if (creds == null) return;

    final repo = await ref.read(storeRepositoryProvider.future);
    await repo.fetchStorefront(creds.shard, creds.puuid);
    await repo.fetchWallet(creds.shard, creds.puuid);
  }

  void _toggleWishlist(SkinOffer offer) {
    final notifier = ref.read(_wishlistProvider.notifier);
    final current = ref.read(_wishlistProvider);
    if (current.contains(offer.skinLevelUuid)) {
      notifier.state = {...current}..remove(offer.skinLevelUuid);
      CacheStorage.instance.removeFromWishlist(offer.skinLevelUuid);
    } else {
      notifier.state = {...current, offer.skinLevelUuid};
      CacheStorage.instance.addToWishlist(offer.skinLevelUuid);
    }
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
            style: TextStyle(
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

class _BundleBanner extends ConsumerWidget {
  const _BundleBanner({required this.bundle});
  final FeaturedBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(_bundlesMapProvider);
    final bundleMap = bundlesAsync.asData?.value ?? {};
    final bundleInfo = bundleMap[bundle.bundleUuid.toLowerCase()] ?? bundleMap[bundle.bundleUuid];

    final displayIcon2 = bundleInfo?['displayIcon2'] as String?;
    final verticalImage = bundleInfo?['verticalPromoImage'] as String?;
    final displayIcon = bundleInfo?['displayIcon'] as String?;

    final imageUrl = displayIcon2 ??
        verticalImage ??
        displayIcon ??
        bundle.verticalPromoImage ??
        bundle.displayIcon;

    final discountInt = (bundle.totalDiscountPercent > 1
            ? bundle.totalDiscountPercent
            : bundle.totalDiscountPercent * 100)
        .round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      ],
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
                child: SkinCard(
                  offer: offer.copyWith(isInWishlist: inWishlist),
                  isHighlighted: inWishlist,
                  onWishlistToggle: () => widget.onWishlistToggle(offer),
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
              final discountInt = (offer.discountPercent > 1
                      ? offer.discountPercent
                      : offer.discountPercent * 100)
                  .round();

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFA855F7).withAlpha(140),
                    width: 1.5,
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A153B), Color(0xFF0F0A1A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFA855F7).withAlpha(30),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
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
                                    style: const TextStyle(
                                      color: Color(0xFFA855F7),
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

