import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../shared/utils/tier_colors.dart';
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
      backgroundColor: const Color(0xFF0F1923),
      pinned: true,
      expandedHeight: 100,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Daily Shop',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        background: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
          child: walletAsync.when(
            data: (wallet) => wallet != null ? _WalletBar(wallet: wallet) : const SizedBox(),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ),
      ),
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

        // Daily skins grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: storefront.dailyOffers.length,
            itemBuilder: (context, i) {
              final offer = storefront.dailyOffers[i];
              final inWishlist = wishlist.contains(offer.skinLevelUuid);
              return SkinCard(
                offer: offer.copyWith(isInWishlist: inWishlist),
                isHighlighted: inWishlist,
                onWishlistToggle: () => _toggleWishlist(offer),
              );
            },
          ),
        ),
        const SizedBox(height: 28),

        // Featured Bundle
        if (storefront.featuredBundle != null) ...[
          const _SectionHeader(title: 'Featured Bundle'),
          _BundleBanner(bundle: storefront.featuredBundle!),
          const SizedBox(height: 28),
        ],

        // Night Market
        if (storefront.hasNightMarket) ...[
          const _SectionHeader(title: 'Night Market'),
          _NightMarketList(offers: storefront.nightMarket),
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

class _BundleBanner extends StatelessWidget {
  const _BundleBanner({required this.bundle});
  final FeaturedBundle bundle;

  @override
  Widget build(BuildContext context) {
    final imageUrl = bundle.verticalPromoImage ?? bundle.displayIcon;
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
              if (imageUrl != null)
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
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white24),
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
                    const SizedBox(height: 6),

                    // Bundle Title
                    Text(
                      bundle.displayName ?? 'Featured Bundle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // VP Cost
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Color(0xFF00F0FF), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${bundle.totalDiscountedCost} VP',
                          style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (bundle.totalBaseCost > bundle.totalDiscountedCost) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${bundle.totalBaseCost} VP',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
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

class _NightMarketList extends StatelessWidget {
  const _NightMarketList({required this.offers});
  final List<NightMarketOffer> offers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: offers.map((o) {
          final tierColor = TierColors.forName(o.contentTierUuid);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1722),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tierColor.withAlpha(120), width: 1),
              boxShadow: [
                BoxShadow(
                  color: tierColor.withAlpha(20),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Row(
                children: [
                  // Accent Tier Bar
                  Container(width: 4, height: 74, color: tierColor),
                  const SizedBox(width: 10),

                  // Skin Image
                  SizedBox(
                    width: 90,
                    height: 54,
                    child: o.skinIcon != null
                        ? CachedNetworkImage(
                            imageUrl: o.skinIcon!,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => Container(color: const Color(0xFF141F2D)),
                            errorWidget: (_, __, ___) => const Icon(Icons.image, color: Colors.white24),
                          )
                        : const Icon(Icons.image, color: Colors.white24),
                  ),
                  const SizedBox(width: 12),

                  // Title & Price Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.skinName ?? 'Discounted Skin',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${o.discountedPrice} VP',
                              style: TextStyle(
                                color: tierColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (o.basePrice > o.discountedPrice) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${o.basePrice}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Discount Badge Tag
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9900).withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFF9900), width: 0.8),
                    ),
                    child: Text(
                      '-${o.discountPercent}%',
                      style: const TextStyle(
                        color: Color(0xFFFF9900),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

