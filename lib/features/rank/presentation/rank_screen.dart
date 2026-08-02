import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_name_util.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/player_mmr.dart';

// Dynamic season provider
final _activeSeasonProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getActiveSeason();
});

// ── Providers ─────────────────────────────────────────────────────────────────

final _mmrProvider =
    FutureProvider.autoDispose<CachedFetchResult<PlayerMmr>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  try {
    final raw = await source.fetchMmrRaw(creds.shard, creds.puuid);
    final mmr = PlayerMmr.fromJson(raw);
    await cache.saveMmr(raw);
    return CachedFetchResult(mmr);
  } catch (_) {
    final cached = await cache.loadMmr();
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

final _competitiveUpdatesProvider =
    FutureProvider.autoDispose<CachedFetchResult<List<CompetitiveUpdate>>>(
        (ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return const CachedFetchResult([]);
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  try {
    final raw =
        await source.fetchCompetitiveUpdatesRaw(creds.shard, creds.puuid);
    final list = source.parseCompetitiveUpdates(raw);
    await cache.saveCompetitiveUpdates(raw);
    return CachedFetchResult(list);
  } catch (_) {
    final cached = await cache.loadCompetitiveUpdates();
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

final _competitiveTiersMapProvider =
    FutureProvider.autoDispose<Map<int, Map<String, dynamic>>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getCompetitiveTiersMap();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RankScreen extends ConsumerStatefulWidget {
  const RankScreen({super.key});

  @override
  ConsumerState<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends ConsumerState<RankScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mmrAsync = ref.watch(_mmrProvider);
    final updatesAsync = ref.watch(_competitiveUpdatesProvider);
    final showCacheBanner = (mmrAsync.asData?.value?.fromCache ?? false) ||
        (updatesAsync.asData?.value.fromCache ?? false);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        title: Consumer(
          builder: (ctx, r, _) {
            final seasonAsync = r.watch(_activeSeasonProvider);
            final label = seasonAsync.asData?.value['label'] ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('COMPETITIVE RANK',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontSize: 16)),
                if (label.isNotEmpty)
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () {
              ref.invalidate(_mmrProvider);
              ref.invalidate(_competitiveUpdatesProvider);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _RankTabBar(controller: _tabController),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        backgroundColor: AppColors.bgCard2,
        onRefresh: () async {
          ref.invalidate(_mmrProvider);
          ref.invalidate(_competitiveUpdatesProvider);
        },
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 0: Leaderboard
            _LeaderboardTab(
              mmrAsync: mmrAsync,
              updatesAsync: updatesAsync,
              showCacheBanner: showCacheBanner,
            ),
            // Tab 1: Match History (competitive updates)
            _MatchHistoryTab(
              updatesAsync: updatesAsync,
              showCacheBanner: showCacheBanner,
            ),
            // Tab 2: Act Rank
            _ActRankTab(mmrAsync: mmrAsync),
          ],
        ),
      ),
    );
  }
}

class _RankTabBar extends StatelessWidget {
  const _RankTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgPanel,
      child: TabBar(
        controller: controller,
        indicatorColor: AppColors.red,
        indicatorWeight: 2.5,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'LEADERBOARD'),
          Tab(text: 'MATCH HISTORY'),
          Tab(text: 'ACT RANK'),
        ],
      ),
    );
  }
}

// ── Tab 0 — Leaderboard ────────────────────────────────────────────────────────

class _LeaderboardTab extends ConsumerWidget {
  const _LeaderboardTab({
    required this.mmrAsync,
    required this.updatesAsync,
    required this.showCacheBanner,
  });

  final AsyncValue<CachedFetchResult<PlayerMmr>?> mmrAsync;
  final AsyncValue<CachedFetchResult<List<CompetitiveUpdate>>> updatesAsync;
  final bool showCacheBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        if (showCacheBanner) const CacheDataBanner(),
        // Rank card
        mmrAsync.when(
          data: (result) => result == null
              ? const SizedBox()
              : _RankCard(mmr: result.data),
          loading: () => const RankSkeleton(),
          error: (e, _) => _ErrorCard(message: e.toString()),
        ),
        const SizedBox(height: 20),

        // RR sparkline
        updatesAsync.when(
          data: (result) => _RrSparklineCard(updates: result.data),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),
        const SizedBox(height: 20),

        // Peak rank info card (replaces fake hardcoded leaderboard)
        updatesAsync.when(
          data: (result) => _PeakRankCard(
            updates: result.data,
            mmr: mmrAsync.asData?.value?.data,
          ),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Regional leaderboard requires Riot\'s official leaderboard endpoint. '
                  'Your personal peak rank and recent performance are shown above.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── RR Sparkline Card ─────────────────────────────────────────────────────────

class _RrSparklineCard extends StatelessWidget {
  const _RrSparklineCard({required this.updates});
  final List<CompetitiveUpdate> updates;

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) return const SizedBox();
    final recent = updates.take(10).toList().reversed.toList();
    final netRr = recent.fold<int>(0, (sum, u) => sum + u.rankedRatingEarned);
    final wins = recent.where((u) => u.isWin).length;
    final losses = recent.where((u) => u.isLoss).length;
    final draws = recent.where((u) => u.isDraw).length;
    final isPos = netRr >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isPos ? AppColors.win : AppColors.loss).withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isPos ? AppColors.win : AppColors.loss).withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPos ? Icons.trending_up : Icons.trending_down,
                  color: isPos ? AppColors.win : AppColors.loss,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LAST 10 GAMES RR TREND',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      '${isPos ? '+' : ''}$netRr RR',
                      style: TextStyle(
                          color: isPos ? AppColors.win : AppColors.loss,
                          fontSize: 18,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgCard2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  draws > 0 ? '${wins}W · ${losses}L · ${draws}D' : '${wins}W · ${losses}L',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: CustomPaint(
              size: const Size(double.infinity, 40),
              painter: _SparklinePainter(updates: recent),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.updates});
  final List<CompetitiveUpdate> updates;

  @override
  void paint(Canvas canvas, Size size) {
    if (updates.isEmpty) return;
    final count = updates.length;
    final barW = (size.width / count) * 0.55;
    final gap = (size.width / count) * 0.45;
    final maxAbs = updates
        .map((u) => u.rankedRatingEarned.abs())
        .fold<int>(1, (a, b) => a > b ? a : b);

    for (var i = 0; i < count; i++) {
      final rr = updates[i].rankedRatingEarned;
      final isWin = rr > 0;
      final norm = rr.abs() / maxAbs;
      final barH = math.max(4.0, norm * size.height);
      final x = i * (barW + gap);
      final y = size.height - barH;

      final paint = Paint()
        ..color = (isWin ? AppColors.win : AppColors.loss).withAlpha(200)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, barH), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.updates != updates;
}

// ── Peak Rank Card ────────────────────────────────────────────────────────────

class _PeakRankCard extends ConsumerWidget {
  const _PeakRankCard({this.updates, this.mmr});
  final List<CompetitiveUpdate>? updates;
  final PlayerMmr? mmr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mmr == null) return const SizedBox();
    final tiersMap = ref.watch(_competitiveTiersMapProvider).asData?.value ?? {};
    int peakTier = mmr!.currentTier;
    int peakRr = mmr!.currentRankedRating;
    if (updates != null) {
      for (final u in updates!) {
        if (u.tierAfterUpdate > peakTier ||
            (u.tierAfterUpdate == peakTier && u.rankedRatingAfterUpdate > peakRr)) {
          peakTier = u.tierAfterUpdate;
          peakRr = u.rankedRatingAfterUpdate;
        }
      }
    }
    final peakData = tiersMap[peakTier];
    final peakIconUrl = peakData?['largeIcon'] as String? ?? peakData?['displayIcon'] as String?;
    final peakName = peakData?['tierName'] as String? ?? TierNameUtil.name(peakTier);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withAlpha(70)),
        boxShadow: AppColors.redGlow(alpha: 0.07),
      ),
      child: Row(
        children: [
          if (peakIconUrl != null && peakIconUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: peakIconUrl,
              width: 56, height: 56, fit: BoxFit.contain,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.military_tech, color: AppColors.red, size: 40),
            )
          else
            const Icon(Icons.military_tech, color: AppColors.red, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HIGHEST RECORDED RANK (RECENT)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(peakName.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('$peakRr RR',
                    style: const TextStyle(color: AppColors.red, fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('CURRENT', style: TextStyle(color: AppColors.textMuted,
                  fontSize: 9, fontWeight: FontWeight.w700)),
              Text('${mmr!.currentRankedRating} RR',
                  style: const TextStyle(color: Colors.white70, fontSize: 12,
                      fontWeight: FontWeight.w800)),
              if (mmr!.gamesNeededForRating > 0)
                Text('${mmr!.gamesNeededForRating} games for rating',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MatchHistoryTab extends StatelessWidget {
  const _MatchHistoryTab(
      {required this.updatesAsync, required this.showCacheBanner});

  final AsyncValue<CachedFetchResult<List<CompetitiveUpdate>>> updatesAsync;
  final bool showCacheBanner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        if (showCacheBanner) const CacheDataBanner(),
        Row(
          children: [
            Container(width: 3, height: 14, color: const Color(0xFFFF4655)),
            const SizedBox(width: 8),
            const Text('RECENT COMPETITIVE UPDATES',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
          ],
        ),
        const SizedBox(height: 14),
        updatesAsync.when(
          data: (result) => result.data.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('No recent competitive matches.',
                        style: TextStyle(color: Colors.white38)),
                  ),
                )
              : Column(
                  children:
                      result.data.map((u) => _UpdateTile(update: u)).toList()),
          loading: () => const RankHistorySkeleton(),
          error: (e, _) => _ErrorCard(message: e.toString()),
        ),
      ],
    );
  }
}

// ── Tab 2 — Act Rank ──────────────────────────────────────────────────────────

class _ActRankTab extends ConsumerWidget {
  const _ActRankTab({required this.mmrAsync});
  final AsyncValue<CachedFetchResult<PlayerMmr>?> mmrAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonAsync = ref.watch(_activeSeasonProvider);
    final tiersAsync = ref.watch(_competitiveTiersMapProvider);
    final seasonLabel = seasonAsync.asData?.value['label'] ?? '';

    return mmrAsync.when(
      data: (result) {
        if (result == null) {
          return const Center(
            child: Text('Not logged in.',
                style: TextStyle(color: Colors.white38)),
          );
        }
        final mmr = result.data;
        final tierData = tiersAsync.asData?.value[mmr.currentTier];
        final iconUrl = tierData?['largeIcon'] as String? ??
            tierData?['displayIcon'] as String?;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            if (result.fromCache) const CacheDataBanner(),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.red.withAlpha(80), width: 1),
                boxShadow: AppColors.redGlow(alpha: 0.08),
              ),
              child: Column(
                children: [
                  if (seasonLabel.isNotEmpty)
                    Text(seasonLabel,
                        style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  if (seasonLabel.isNotEmpty) const SizedBox(height: 20),
                  if (iconUrl != null && iconUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: iconUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.shield_outlined,
                          color: AppColors.red, size: 64),
                    )
                  else
                    const Icon(Icons.shield_outlined,
                        color: AppColors.red, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    TierNameUtil.name(mmr.currentTier).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${mmr.currentRankedRating} RR',
                    style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (mmr.currentRankedRating / 100).clamp(0.0, 1.0),
                      backgroundColor: AppColors.bgCard2,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.red),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${mmr.currentRankedRating} / 100 RR',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const RankSkeleton(),
      error: (e, _) => Center(child: _ErrorCard(message: e.toString())),
    );
  }
}

// ── Rank Card ─────────────────────────────────────────────────────────────────

class _RankCard extends ConsumerWidget {
  const _RankCard({required this.mmr});
  final PlayerMmr mmr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersMapAsync = ref.watch(_competitiveTiersMapProvider);
    final tierData = tiersMapAsync.asData?.value[mmr.currentTier];
    final iconUrl = tierData?['largeIcon'] as String? ??
        tierData?['displayIcon'] as String?;
    final tierName = tierData?['tierName'] as String? ??
        TierNameUtil.name(mmr.currentTier);

    final rrProgress = (mmr.currentRankedRating.clamp(0, 100)) / 100.0;

    // Wins/Losses from latest update context is not available here directly,
    // so we show RR stats from mmr model.
    final latestRr = mmr.latestUpdate?.rankedRatingEarned ?? 0;
    final isNetPos = latestRr >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.red.withAlpha(100), width: 1.2),
        boxShadow: AppColors.redGlow(alpha: 0.10),
        gradient: AppColors.cardGradient,
      ),
      child: Column(
        children: [
          // Rank icon + stats row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Rank icon only — no text inside, prevents overflow
              SizedBox(
                width: 80,
                height: 80,
                child: iconUrl != null && iconUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: iconUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(),
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.shield_outlined,
                            color: AppColors.red, size: 56),
                      )
                    : const Icon(Icons.shield_outlined,
                        color: AppColors.red, size: 56),
              ),
              const SizedBox(width: 16),
              // Stats column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tier name here — not inside the icon widget
                    Text(
                      tierName.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    const Text('RANK RATING',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      '${mmr.currentRankedRating} RR',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    const Text('LAST MATCH',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      '${isNetPos ? '▲ +' : '▼ '}$latestRr RR',
                      style: TextStyle(
                          color: isNetPos
                              ? AppColors.win
                              : AppColors.loss,
                          fontSize: 14,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // RR progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${mmr.currentRankedRating} / 100 RR',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (mmr.gamesNeededForRating > 0)
                Text(
                  '${mmr.gamesNeededForRating} games for rating',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rrProgress,
              backgroundColor: AppColors.bgCard2,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.red),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Update Tile ────────────────────────────────────────────────────────────────

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update});
  final CompetitiveUpdate update;

  @override
  Widget build(BuildContext context) {
    final rr = update.rankedRatingEarned;
    final isWin = rr > 0;
    final color = isWin ? AppColors.win : AppColors.loss;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 3, height: 18,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Icon(isWin ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${isWin ? '+' : ''}$rr RR',
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${update.rankedRatingAfterUpdate} RR',
                  style: const TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (update.afkPenalty != 0)
                Text('AFK: ${update.afkPenalty}',
                    style: const TextStyle(color: Colors.orange, fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4655).withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFFF4655).withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4655)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
