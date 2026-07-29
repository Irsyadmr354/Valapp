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
        // Countdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              const Text('Resets in ',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              CountdownTimer(
                remainingSeconds: storefront.dailyOffersRemainingSeconds,
                onExpired: _refresh,
                style: const TextStyle(
                  color: Color(0xFFFF4655),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
              childAspectRatio: 0.75,
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
        const SizedBox(height: 24),

        // Featured Bundle
        if (storefront.featuredBundle != null) ...[
          const _SectionHeader(title: 'Featured Bundle'),
          _BundleBanner(bundle: storefront.featuredBundle!),
          const SizedBox(height: 24),
        ],

        // Night Market
        if (storefront.hasNightMarket) ...[
          const _SectionHeader(title: 'Night Market'),
          _NightMarketList(offers: storefront.nightMarket),
          const SizedBox(height: 24),
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
      children: [
        _CurrencyChip(
            label: '${wallet.valorantPoints} VP',
            color: const Color(0xFF0BC4C4)),
        const SizedBox(width: 8),
        _CurrencyChip(
            label: '${wallet.radianitePoints} RP',
            color: const Color(0xFFFF9900)),
        const SizedBox(width: 8),
        _CurrencyChip(
            label: '${wallet.kingdomCredits} KC',
            color: const Color(0xFF4CAF50)),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _BundleBanner extends StatelessWidget {
  const _BundleBanner({required this.bundle});
  final FeaturedBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2634), Color(0xFF0D1B2A)],
          ),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: const Color(0xFF3D4C5E)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${bundle.totalDiscountedCost} VP',
                      style: const TextStyle(
                        color: Color(0xFFFF4655),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (bundle.totalDiscountPercent > 0)
                      Text(
                        '${(bundle.totalDiscountPercent * 100).toStringAsFixed(0)}% off',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${bundle.itemIds.length} items included',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              CountdownTimer(
                remainingSeconds: bundle.durationRemainingSeconds,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
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
  final List<dynamic> offers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: offers
            .map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2634),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFF3D4C5E)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_offer,
                            color: Color(0xFFFF9900), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Discounted offer',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                        Text(
                          '${(o.discountPercent * 100).toStringAsFixed(0)}% off',
                          style: const TextStyle(
                              color: Color(0xFFFF9900),
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
