import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/utils/tier_name_util.dart';
import '../../../shared/utils/price_utils.dart' as price_utils;
import '../../news/domain/models/news_article.dart';
import '../../../shared/widgets/skin_card.dart';
import '../../../shared/widgets/countdown_timer.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/valorant_icons.dart';
import '../../../shared/widgets/valorant_error_display.dart';
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

final _storefrontProvider =
    FutureProvider.autoDispose<Storefront?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final repo = await ref.watch(storeRepositoryProvider.future);
  // loadCachedStorefront() now returns null if the cache is from a past
  // rotation (elapsed time >= remainingSeconds), so cached is only non-null
  // when the cached data is still valid for the current shop window.
  final cached = await repo.loadCachedStorefront(creds.puuid);
  try {
    return await repo.fetchStorefront(creds.shard, creds.puuid);
  } catch (e) {
    // Only fall back to cache if it is still valid (not expired).
    // loadCachedStorefront() already filters out expired caches.
    if (cached != null) return cached;
    rethrow;
  }
});

final _walletProvider = FutureProvider.autoDispose<Wallet?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final repo = await ref.watch(storeRepositoryProvider.future);
  final cached = await repo.loadCachedWallet(creds.puuid);
  try {
    return await repo.fetchWallet(creds.shard, creds.puuid);
  } catch (e) {
    if (cached != null) return cached;
    rethrow;
  }
});

final _homePlayerCardProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  // Delegate to the shared provider — returns smallArt for the avatar circle.
  final info = await ref.watch(playerCardArtProvider.future);
  return info.smallArt;
});

final _homeMatchesProvider =
    FutureProvider.autoDispose<MatchHistoryResult?>((ref) async {
  // Delegate to shared enriched history provider — no duplication.
  return ref.watch(enrichedMatchHistoryProvider.future);
});

final _competitiveTiersMapHomeProvider =
    FutureProvider.autoDispose<Map<int, Map<String, dynamic>>>((ref) async =>
        ref.watch(valorantAssetsProvider).getCompetitiveTiersMap());

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

final _newsFeedProvider = FutureProvider.autoDispose((ref) async {
  final source = ref.watch(newsRemoteSourceProvider);
  return source.fetchNews();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  void _listenForWishlistOffers() {
    ref.listen<AsyncValue<Storefront?>>(_storefrontProvider, (previous, next) {
      final storefront = next.asData?.value;
      if (storefront == null) return;
      final wishlist = ref.read(wishlistProvider).toSet();
      final shopIdentity = storefront.dailyOffers
          .map((offer) => offer.skinLevelUuid)
          .toList()
        ..sort();
      for (final offer in storefront.dailyOffers) {
        if (wishlist.contains(offer.skinLevelUuid)) {
          NotificationService.instance.showWishlistAlertOnce(
            shopIdentity: shopIdentity.join(','),
            skinId: offer.skinLevelUuid,
            skinName: offer.displayName ?? 'Wishlist Skin',
            price: offer.price,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForWishlistOffers();
    final storefrontAsync = ref.watch(_storefrontProvider);
    final walletAsync = ref.watch(_walletProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.red,
        backgroundColor: AppColors.bgCard2,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(walletAsync),
            storefrontAsync.when(
              data: (storefront) => storefront == null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.storefront_outlined,
                                color: Color(0xFFFF4655), size: 48),
                            const SizedBox(height: 12),
                            const Text('Unable to load shop catalog',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            const SizedBox(height: 6),
                            const Text(
                              'Pull down or tap below to refresh your daily offers',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _refresh,
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF4655)),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('RETRY SHOP'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildContent(storefront, wishlist.toSet()),
              loading: () => HomeSkeleton.asSliver(),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ValorantErrorDisplay(
                    error: e,
                    onRetry: _refresh,
                    title: 'Gagal Memuat Toko Harian',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar(AsyncValue<Wallet?> walletAsync) {
    return SliverAppBar(
      backgroundColor: AppColors.bgPanel,
      pinned: true,
      floating: false,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: 16,
      title: Consumer(
        builder: (context, ref, _) {
          final nameAsync = ref.watch(displayNameProvider);
          final xpAsync = ref.watch(accountXpProvider);
          final cardArtAsync = ref.watch(_homePlayerCardProvider);

          final displayName = nameAsync.asData?.value?.data ?? 'Valorant ID';
          final cardIconUrl = cardArtAsync.asData?.value;
          final rawXp = xpAsync.asData?.value?.data;
          final levelStr = rawXp != null ? 'Level ${rawXp.level}' : 'Level --';
          final xpProgress = rawXp != null
              ? (rawXp.xp / AccountXp.xpPerLevel.toDouble()).clamp(0.0, 1.0)
              : 0.0;

          return Row(
            children: [
              // Avatar circle displaying equipped Player Card artwork
              GestureDetector(
                onTap: () => AccountSwitcherModal.show(context),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.red, AppColors.redDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: ClipOval(
                      child: cardIconUrl != null && cardIconUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: cardIconUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AppColors.bg,
                                child: Center(
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : 'V',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Center(
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'V',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'V',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + level row
              Expanded(
                child: Column(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
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
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: xpProgress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(Icons.bookmarks_outlined,
                color: Color(0xFFFF4655), size: 20),
            tooltip: 'Skin Catalog & Wishlist',
            onPressed: () => context.push('/wishlist'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: walletAsync.when(
            data: (w) => w != null ? _WalletBar(wallet: w) : const SizedBox(),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ),
      ],
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────

  Widget _buildContent(Storefront storefront, Set<String> wishlist) {
    return SliverList(
      delegate: SliverChildListDelegate([
        // Timer bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1622),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF4655).withAlpha(60), width: 0.8),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined,
                    color: Color(0xFFFF4655), size: 14),
                const SizedBox(width: 6),
                const Text('REFRESHES IN ',
                    style: TextStyle(
                        color: Color(0xFFFF4655),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                CountdownTimer(
                  remainingSeconds:
                      storefront.currentDailyOffersRemainingSeconds,
                  deadline: storefront.dailyOffersDeadline,
                  deadlineIdentity: storefront.dailyOffersIdentity,
                  onExpired: _refresh,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${storefront.dailyOffers.length} ITEMS AVAILABLE',
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.info_outline, color: Colors.white24, size: 13),
              ],
            ),
          ),
        ),

        // Wishlist match banner — purely declarative, no side-effects.
        // Notifications are fired via ref.listen in didChangeDependencies.
        Builder(builder: (context) {
          final matches = storefront.dailyOffers
              .where((o) => wishlist.contains(o.skinLevelUuid))
              .toList();
          if (matches.isEmpty) return const SizedBox();
          return _WishlistMatchBanner(matchedSkins: matches);
        }),

        // Featured Bundle
        if (storefront.featuredBundle != null) ...[
          const SizedBox(height: 16),
          const _SectionHeader(title: 'Featured Bundle'),
          _BundleBanner(bundle: storefront.featuredBundle!),
          const SizedBox(height: 20),
        ],

        // Daily Shop
        const SizedBox(height: 4),
        const _SectionHeader(title: 'Daily Shop'),
        _DailyShopCarousel(
          offers: storefront.dailyOffers,
          wishlist: wishlist,
          onWishlistToggle: _toggleWishlist,
        ),
        const SizedBox(height: 24),

        // Night Market
        if (storefront.hasNightMarket) ...[
          const _SectionHeader(title: 'Night Market'),
          _NightMarketCarousel(offers: storefront.nightMarket),
          const SizedBox(height: 24),
        ],

        // Quick cards
        const _HomeQuickCardsRow(),
        const SizedBox(height: 24),

        // Valorant News Feed
        const _SectionHeader(title: 'Valorant News'),
        const _NewsFeedSection(),
        const SizedBox(height: 80),
      ]),
    );
  }

  Future<void> _refresh() async {
    // Invalidate cached storefront timestamp so loadCachedStorefront()
    // won't return a stale cached response as fallback. The actual raw cache
    // is already guarded by the expiry check in StoreLocalCache, but clearing
    // the timestamp key is a belt-and-suspenders measure.
    final cache = CacheStorage.instance;
    await cache.remove(cache.userKey(CacheStorage.keyDailyShop));
    await cache.remove(cache.userKey(CacheStorage.keyDailyShopFetchedAt));
    ref.invalidate(_storefrontProvider);
    ref.invalidate(_walletProvider);
  }

  void _toggleWishlist(SkinOffer offer) {
    if (!ref.read(wishlistProvider).contains(offer.skinLevelUuid)) {
      NotificationService.instance.requestPermissions();
    }
    ref.read(wishlistProvider.notifier).toggle(offer.skinLevelUuid);
  }
}

// ── Wallet Bar ─────────────────────────────────────────────────────────────────

class _WalletBar extends StatelessWidget {
  const _WalletBar({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValorantCurrencyChip(
          amount: wallet.valorantPoints,
          type: 'VP',
          compact: true,
        ),
        const SizedBox(width: 5),
        ValorantCurrencyChip(
          amount: wallet.radianitePoints,
          type: 'RP',
          compact: true,
        ),
        const SizedBox(width: 5),
        ValorantCurrencyChip(
          amount: wallet.kingdomCredits,
          type: 'KC',
          compact: true,
        ),
      ],
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 15,
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withAlpha(140),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.red.withAlpha(80),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bundle Banner ──────────────────────────────────────────────────────────────

class _BundleBanner extends ConsumerWidget {
  const _BundleBanner({required this.bundle});
  final FeaturedBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(_bundlesMapProvider);
    final skinLevelsAsync = ref.watch(_skinLevelsMapProvider);

    final bundleMap = bundlesAsync.asData?.value ?? {};
    final skinMap = skinLevelsAsync.asData?.value ?? {};

    final bundleInfo = bundleMap[bundle.bundleUuid.toLowerCase()] ??
        bundleMap[bundle.bundleUuid];

    final displayIcon2 = bundleInfo?['displayIcon2'] as String?;
    final verticalImage = bundleInfo?['verticalPromoImage'] as String?;
    final displayIcon = bundleInfo?['displayIcon'] as String?;

    String? imageUrl = displayIcon2 ??
        verticalImage ??
        displayIcon ??
        bundle.verticalPromoImage ??
        bundle.displayIcon;

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

    final discountInt =
        price_utils.discountPercent(bundle.totalDiscountPercent);

    final finalImageUrl = imageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => BundleDetailModal.show(context,
            bundle: bundle, bannerImageUrl: finalImageUrl),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFFF4655).withAlpha(110), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4655).withAlpha(25),
                blurRadius: 14,
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
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      placeholder: (_, __) =>
                          Container(color: const Color(0xFF141F2D)),
                      errorWidget: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                // Gradient overlay — heavier at bottom for text legibility
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF070A10).withAlpha(245),
                          const Color(0xFF070A10).withAlpha(120),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top chips row
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
                              child: Text('-$discountInt% OFF',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900)),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(130),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.layers_outlined,
                                    color: Colors.white54, size: 11),
                                const SizedBox(width: 4),
                                Text('${bundle.itemIds.length} ITEMS',
                                    style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (bundle.durationRemainingSeconds > 0)
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    color: Colors.white54, size: 12),
                                const SizedBox(width: 4),
                                CountdownTimer(
                                  remainingSeconds:
                                      bundle.durationRemainingSeconds,
                                  deadlineIdentity: bundle.bundleUuid,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Bundle name
                      Text(
                        (bundle.displayName ?? 'Featured Bundle').toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Price row
                      Row(
                        children: [
                          const VpIcon(size: 16, color: AppColors.red),
                          const SizedBox(width: 5),
                          Text(
                            '${bundle.totalDiscountedCost}',
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (bundle.totalBaseCost >
                              bundle.totalDiscountedCost) ...[
                            const SizedBox(width: 8),
                            const VpIcon(size: 12, color: Colors.white38),
                            const SizedBox(width: 3),
                            Text(
                              '${bundle.totalBaseCost}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4655).withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFFF4655), width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('VIEW ITEMS',
                                    style: TextStyle(
                                        color: Color(0xFFFF4655),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5)),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward,
                                    color: Color(0xFFFF4655), size: 13),
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

// ── Daily Shop Carousel ────────────────────────────────────────────────────────

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
    _pageController = PageController(viewportFraction: 1.0);
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
          height: 280,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.offers.length,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemBuilder: (context, i) {
              final offer = widget.offers[i];
              final inWishlist = widget.wishlist.contains(offer.skinLevelUuid);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
        const SizedBox(height: 10),
        // Page indicator dots
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.offers.length, (index) {
              final isSelected = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isSelected ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF4655) : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Night Market Carousel ─────────────────────────────────────────────────────

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
    _controller = PageController(viewportFraction: 0.80);
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
          height: 230,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.offers.length,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemBuilder: (context, i) {
              final offer = widget.offers[i];
              final tierColor = TierColors.forName(offer.contentTierUuid);
              // discountPercent is already normalised to 0–100 in NightMarketOffer.fromJson,
              // so we use it directly — no multiplication needed.
              final discountInt = offer.discountPercent;

              return GestureDetector(
                onTap: () => SkinDetailModal.show(context, offer.toSkinOffer()),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: tierColor.withAlpha(180), width: 1.4),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tierColor.withAlpha(70),
                        tierColor.withAlpha(20),
                        const Color(0xFF0C131D),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tierColor.withAlpha(40),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      children: [
                        // Top tier accent bar
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(height: 3.5, color: tierColor),
                        ),
                        // Weapon image
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 62),
                            child: offer.skinIcon != null &&
                                    offer.skinIcon!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: offer.skinIcon!,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => const SizedBox(),
                                    errorWidget: (_, __, ___) => const Icon(
                                        Icons.shield,
                                        color: Colors.white24,
                                        size: 48),
                                  )
                                : const Icon(Icons.shield,
                                    color: Colors.white24, size: 48),
                          ),
                        ),
                        // Discount badge top-right
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                            child: Text('-$discountInt% OFF',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                        // Bottom info
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
                                        fontWeight: FontWeight.w800),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${offer.basePrice}',
                                  style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      decoration: TextDecoration.lineThrough),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${offer.discountedPrice} VP',
                                  style: TextStyle(
                                      color: tierColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900),
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
        // Indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.offers.length, (index) {
            final isSelected = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.red : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Wishlist Match Banner ──────────────────────────────────────────────────────

class _WishlistMatchBanner extends StatelessWidget {
  const _WishlistMatchBanner({required this.matchedSkins});
  final List<SkinOffer> matchedSkins;

  @override
  Widget build(BuildContext context) {
    if (matchedSkins.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFFFD700).withAlpha(28),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFFD700).withAlpha(35), blurRadius: 10)
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
                        letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    matchedSkins.map((s) => s.displayName ?? 'Skin').join(', '),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
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

// ── Home Quick Cards Row ───────────────────────────────────────────────────────

class _HomeQuickCardsRow extends ConsumerWidget {
  const _HomeQuickCardsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mmrAsync = ref.watch(playerMmrProvider);
    final historyAsync = ref.watch(_homeMatchesProvider);
    final tiersAsync = ref.watch(_competitiveTiersMapHomeProvider);
    final updatesAsync = ref.watch(competitiveUpdatesProvider);

    final mmr = mmrAsync.asData?.value?.data;
    final matches = historyAsync.asData?.value?.matches ?? [];
    final tiersMap = tiersAsync.asData?.value ?? {};
    // Real competitive updates — most recent first (already sorted by API)
    final updates = updatesAsync.asData?.value.data ?? [];

    final tierData = mmr != null ? tiersMap[mmr.currentTier] : null;
    final rankIconUrl = tierData?['largeIcon'] as String? ??
        tierData?['displayIcon'] as String?;
    final tierName = tierData?['tierName'] as String? ??
        (mmr != null && mmr.currentTier > 0
            ? TierNameUtil.name(mmr.currentTier)
            : 'Unranked');

    // RR trend: last 8 competitive updates for the spark chart
    // Use updates from the shared provider for accuracy.
    // Fall back to mmr.latestUpdate for the "LAST MATCH" text if updates empty.
    final latestRr = updates.isNotEmpty
        ? updates.first.rankedRatingEarned
        : (mmr?.latestUpdate?.rankedRatingEarned ?? 0);
    final isPos = latestRr >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Rank card
          Expanded(
            child: _QuickCard(
              onTap: () => context.go('/rank'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.emoji_events_outlined,
                    iconColor: AppColors.red,
                    title: 'COMPETITIVE RANK',
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: rankIconUrl != null && rankIconUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: rankIconUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            placeholder: (_, __) =>
                                const SizedBox(width: 48, height: 48),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.shield_outlined,
                                color: AppColors.red,
                                size: 36),
                          )
                        : const Icon(Icons.shield_outlined,
                            color: AppColors.red, size: 36),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      tierName.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4),
                      textAlign: TextAlign.center,
                      maxLines: 2,
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
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ((mmr?.currentRankedRating ?? 0) / 100.0)
                          .clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.red),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Match history card
          Expanded(
            child: _QuickCard(
              onTap: () => context.go('/matches'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.sports_esports_outlined,
                    iconColor: AppColors.red,
                    title: 'MATCH HISTORY',
                  ),
                  const SizedBox(height: 6),
                  if (matches.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No recent matches',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 8),
                            textAlign: TextAlign.center),
                      ),
                    )
                  else
                    ...matches.take(3).toList().asMap().entries.map((e) {
                      final colors = [
                        AppColors.red,
                        AppColors.red.withAlpha(180),
                        AppColors.red.withAlpha(120),
                      ];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _MatchMiniTile(
                          queue: e.value.queueDisplayName.toUpperCase(),
                          date: _fmtDate(e.value.gameStartMillis),
                          color: colors[e.key % colors.length],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Recent trend card
          Expanded(
            child: _QuickCard(
              onTap: () => context.go('/rank'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickCardHeader(
                    icon: Icons.trending_up,
                    iconColor: AppColors.red,
                    title: 'RECENT TREND',
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      mmr?.latestUpdate != null
                          ? '${isPos ? '+' : ''}$latestRr RR'
                          : '0 RR',
                      style: TextStyle(
                          color: mmr?.latestUpdate == null
                              ? Colors.white54
                              : (isPos ? AppColors.win : AppColors.loss),
                          fontSize: 15,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Center(
                    child: Text(
                      'LAST MATCH',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 22,
                    child: updates.isEmpty
                        ? const Center(
                            child: Text('—',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 10)),
                          )
                        : _RrMiniChart(updates: updates),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(int ms) {
    if (ms == 0) return 'Recently';
    return DateFormat('MMM d, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }
}

// ── RR Mini Chart (Home Screen trend card) ───────────────────────────────────

/// Renders up to 8 proportional bars representing recent RR changes.
/// Green = gain, red = loss. Heights are normalised to the max absolute value
/// in the displayed set so bars are always proportional — never all the same height.
class _RrMiniChart extends StatelessWidget {
  const _RrMiniChart({required this.updates});
  final List<CompetitiveUpdate> updates;

  @override
  Widget build(BuildContext context) {
    final recent = updates.take(8).toList().reversed.toList();
    if (recent.isEmpty) return const SizedBox();
    return SizedBox(
      height: 28,
      child: CustomPaint(
        size: const Size(double.infinity, 28),
        painter: _MiniLinePainter(updates: recent),
      ),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  const _MiniLinePainter({required this.updates});
  final List<CompetitiveUpdate> updates;

  @override
  void paint(Canvas canvas, Size size) {
    if (updates.length < 2) return;

    // Build cumulative RR values so the line shows trend over time.
    final values = <double>[];
    double running = 0;
    for (final u in updates) {
      running += u.rankedRatingEarned;
      values.add(running);
    }

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    final effectiveRange = range < 1 ? 1.0 : range;

    // Map each value to a y-coordinate (top = positive, bottom = negative).
    Offset toPoint(int i) {
      final x = i / (values.length - 1) * size.width;
      final norm = (values[i] - minV) / effectiveRange;
      // Flip: high value = low y (top of canvas)
      final y = size.height - norm * size.height * 0.85 - size.height * 0.075;
      return Offset(x, y);
    }

    final points = List.generate(values.length, toPoint);

    // Determine overall trend color from last value vs first.
    final isPos = values.last >= values.first;
    final lineColor = isPos ? AppColors.win : AppColors.loss;

    // Filled area under line.
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = lineColor.withAlpha(30)
        ..style = PaintingStyle.fill,
    );

    // Smooth line through points using cubic bezier.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cpX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor.withAlpha(220)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    // Dot at last point.
    canvas.drawCircle(
      points.last,
      2.5,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter old) => old.updates != updates;
}

// ── Quick Cards ───────────────────────────────────────────────────────────────

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: child,
      ),
    );
  }
}

class _QuickCardHeader extends StatelessWidget {
  const _QuickCardHeader(
      {required this.icon, required this.iconColor, required this.title});
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
                letterSpacing: 0.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MatchMiniTile extends StatelessWidget {
  const _MatchMiniTile(
      {required this.queue, required this.date, required this.color});
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
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(queue,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(date,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 7,
                        fontWeight: FontWeight.w600),
                    maxLines: 1),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 12),
        ],
      ),
    );
  }
}

// ── News Feed Section ─────────────────────────────────────────────────────────

class _NewsFeedSection extends ConsumerWidget {
  const _NewsFeedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsync = ref.watch(_newsFeedProvider);

    return newsAsync.when(
      data: (articles) {
        if (articles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded,
                      color: AppColors.textMuted, size: 18),
                  SizedBox(width: 10),
                  Text('News unavailable — check your connection.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          height: 196,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: articles.length,
            itemBuilder: (context, i) => _NewsCard(article: articles[i]),
          ),
        );
      },
      loading: () => SizedBox(
        height: 196,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (_, __) => Container(
            width: 240,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.article});
  final NewsArticle article;

  static const _categoryColors = <String, Color>{
    'PATCH NOTES': Color(0xFF10B981),
    'ESPORTS': AppColors.vpCyan,
    'ANNOUNCEMENT': AppColors.red,
    'DEV DIARY': AppColors.rpAmber,
  };

  @override
  Widget build(BuildContext context) {
    final label = article.categoryLabel;
    final color = _categoryColors[label] ?? AppColors.textSecondary;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _NewsWebViewScreen(
              url: article.url,
              title: article.title,
            ),
          ),
        );
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(50),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Banner image
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 108,
                child:
                    article.bannerUrl != null && article.bannerUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: article.bannerUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppColors.bgCard2),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.bgCard2,
                              child: const Center(
                                child: Icon(Icons.newspaper_outlined,
                                    color: AppColors.textMuted, size: 32),
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.bgCard2,
                            child: const Center(
                              child: Icon(Icons.newspaper_outlined,
                                  color: AppColors.textMuted, size: 32),
                            ),
                          ),
              ),
              // Gradient overlay at bottom of image
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.bgCard.withAlpha(220),
                      ],
                    ),
                  ),
                ),
              ),
              // Category badge top-left
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(40),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: color.withAlpha(120), width: 0.8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Text content below banner
              Positioned(
                top: 108,
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      if (article.publishedAt != null)
                        Text(
                          _formatDate(article.publishedAt!),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
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
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── News Article WebView Screen ───────────────────────────────────────────────

class _NewsWebViewScreen extends StatefulWidget {
  const _NewsWebViewScreen({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_NewsWebViewScreen> createState() => _NewsWebViewScreenState();
}

class _NewsWebViewScreenState extends State<_NewsWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.red),
            ),
        ],
      ),
    );
  }
}
