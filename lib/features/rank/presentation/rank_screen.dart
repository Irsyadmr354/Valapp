import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/tier_name_util.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/rank_badge.dart';
import '../domain/models/player_mmr.dart';

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
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COMPETITIVE RANK',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 16)),
            // Sub-label: Episode / Act (static placeholder — enriched via API later)
            Text('EPISODE 8 // ACT 3',
                style: TextStyle(
                    color: Color(0xFFFF4655),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ],
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
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF141F2D),
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
      color: const Color(0xFF070A10),
      child: TabBar(
        controller: controller,
        indicatorColor: const Color(0xFFFF4655),
        indicatorWeight: 2.5,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8),
        unselectedLabelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600),
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
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: Color(0xFFFF4655)),
          )),
          error: (e, _) => _ErrorCard(message: e.toString()),
        ),
        const SizedBox(height: 20),

        // RR trend summary
        updatesAsync.when(
          data: (result) => _RrTrendSummaryCard(updates: result.data),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),

        // Top players header
        Row(
          children: [
            Container(
                width: 3, height: 14, color: const Color(0xFFFF4655)),
            const SizedBox(width: 8),
            const Text('TOP PLAYERS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
            const Spacer(),
            _GlobalDropdown(),
          ],
        ),
        const SizedBox(height: 12),

        // Column header
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              SizedBox(width: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text('#    PLAYER',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
              Text('RANK RATING',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 20),

        // Static leaderboard entries (top players shown for context;
        // real leaderboard requires Riot's leaderboard API endpoint).
        ...List.generate(6, (i) {
          const names = [
            ('AstraX', '#2024', 27, 723),
            ('Reyna Only', '#777', 27, 689),
            ('ZennKai', '#999', 26, 612),
            ('Midnight', '#1337', 23, 598),
            ('Kuroo', '#666', 22, 584),
            ('Brimstone', '#556', 22, 572),
          ];
          final e = names[i];
          return _LeaderboardRow(
            rank: i + 1,
            name: e.$1,
            tag: e.$2,
            tier: e.$3,
            rr: e.$4,
          );
        }),
      ],
    );
  }
}

class _GlobalDropdown extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10, width: 0.8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('GLOBAL',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white54, size: 16),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends ConsumerWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.name,
    required this.tag,
    required this.tier,
    required this.rr,
  });

  final int rank;
  final String name;
  final String tag;
  final int tier;
  final int rr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(_competitiveTiersMapProvider);
    final tiersMap = tiersAsync.asData?.value ?? {};
    final tierData = tiersMap[tier];
    final iconUrl = tierData?['displayIcon'] as String? ??
        tierData?['smallIcon'] as String?;
    final tierName = tierData?['tierName'] as String? ?? TierNameUtil.name(tier);

    final isTop3 = rank <= 3;
    final rankColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                  color: rankColor,
                  fontSize: isTop3 ? 15 : 13,
                  fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          // Avatar placeholder
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2540),
              border: Border.all(color: Colors.white10, width: 1),
            ),
            child: Center(
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name + tag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(' $tag',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          // Tier badge
          if (iconUrl != null && iconUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CachedNetworkImage(
                imageUrl: iconUrl,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tierName,
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              Text('$rr RR',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab 1 — Match History (competitive updates) ────────────────────────────────

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
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: Color(0xFFFF4655)),
          )),
          error: (e, _) => _ErrorCard(message: e.toString()),
        ),
      ],
    );
  }
}

// ── Tab 2 — Act Rank ──────────────────────────────────────────────────────────

class _ActRankTab extends StatelessWidget {
  const _ActRankTab({required this.mmrAsync});
  final AsyncValue<CachedFetchResult<PlayerMmr>?> mmrAsync;

  @override
  Widget build(BuildContext context) {
    return mmrAsync.when(
      data: (result) {
        if (result == null) {
          return const Center(
            child: Text('Not logged in.',
                style: TextStyle(color: Colors.white38)),
          );
        }
        final mmr = result.data;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            if (result.fromCache) const CacheDataBanner(),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1622),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF00F0FF).withAlpha(80), width: 1),
              ),
              child: Column(
                children: [
                  const Text('EPISODE 8 // ACT 3',
                      style: TextStyle(
                          color: Color(0xFF00F0FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 20),
                  const Icon(Icons.shield_outlined,
                      color: Color(0xFF00F0FF), size: 64),
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
                        color: Color(0xFF00F0FF),
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (mmr.currentRankedRating / 100).clamp(0.0, 1.0),
                      backgroundColor: const Color(0xFF141F2D),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00F0FF)),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${mmr.currentRankedRating} / 100 RR',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4655))),
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
        border: Border.all(
            color: const Color(0xFF00F0FF).withAlpha(100), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF00F0FF).withAlpha(15),
              blurRadius: 18,
              spreadRadius: 2),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141F2D), Color(0xFF0B101A)],
        ),
      ),
      child: Column(
        children: [
          // Rank icon + name row
          Row(
            children: [
              // Icon
              SizedBox(
                width: 90,
                height: 90,
                child: RankBadge(
                  tierName: tierName,
                  rankedRating: mmr.currentRankedRating,
                  iconUrl: iconUrl,
                  large: true,
                ),
              ),
              const SizedBox(width: 20),
              // Stats column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RANK RATING',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text(
                      '${mmr.currentRankedRating} RR',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.0),
                    ),
                    const SizedBox(height: 10),
                    const Text('LAST 10 GAMES',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text(
                      '${isNetPos ? '▲' : '▼'} ${isNetPos ? '+' : ''}$latestRr RR',
                      style: TextStyle(
                          color: isNetPos
                              ? const Color(0xFF10B981)
                              : const Color(0xFFFF4655),
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // RR progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${mmr.currentRankedRating} / 100 RR',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                  if (mmr.gamesNeededForRating > 0)
                    Text(
                      '${mmr.gamesNeededForRating} games for rating',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rrProgress,
                  backgroundColor: const Color(0xFF141F2D),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF00F0FF)),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── RR Trend Summary Card ─────────────────────────────────────────────────────

class _RrTrendSummaryCard extends StatelessWidget {
  const _RrTrendSummaryCard({required this.updates});
  final List<CompetitiveUpdate> updates;

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) return const SizedBox();

    final recent = updates.take(10).toList();
    final netRr =
        recent.fold<int>(0, (sum, u) => sum + u.rankedRatingEarned);
    final wins = recent.where((u) => u.isWin).length;
    final losses = recent.where((u) => u.isLoss).length;
    final draws = recent.where((u) => u.isDraw).length;
    final isPos = netRr >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isPos
                  ? const Color(0xFF10B981)
                  : const Color(0xFFFF4655))
              .withAlpha(90),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isPos
                      ? const Color(0xFF10B981)
                      : const Color(0xFFFF4655))
                  .withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPos ? Icons.trending_up : Icons.trending_down,
              color: isPos
                  ? const Color(0xFF10B981)
                  : const Color(0xFFFF4655),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LAST 10 GAMES RR TREND',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
                const SizedBox(height: 2),
                Text(
                  '${isPos ? '+' : ''}$netRr RR',
                  style: TextStyle(
                      color: isPos
                          ? const Color(0xFF10B981)
                          : const Color(0xFFFF4655),
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF141F2D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              draws > 0
                  ? '${wins}W · ${losses}L · ${draws}D'
                  : '${wins}W · ${losses}L',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
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
    final color =
        isWin ? const Color(0xFF10B981) : const Color(0xFFFF4655);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Icon(isWin ? Icons.trending_up : Icons.trending_down,
              color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${isWin ? '+' : ''}$rr RR',
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${update.rankedRatingAfterUpdate} RR',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
              if (update.afkPenalty != 0)
                Text(
                  'AFK: ${update.afkPenalty}',
                  style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
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
