import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_name_util.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/valorant_error_display.dart';
import '../domain/models/player_mmr.dart';


// Dynamic season provider
final _activeSeasonProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getActiveSeason();
});

// ── Providers ─────────────────────────────────────────────────────────────────

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
    final mmrAsync = ref.watch(playerMmrProvider);
    final updatesAsync = ref.watch(competitiveUpdatesProvider);
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
              ref.invalidate(playerMmrProvider);
              ref.invalidate(competitiveUpdatesProvider);
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
          ref.invalidate(playerMmrProvider);
          ref.invalidate(competitiveUpdatesProvider);
          // Await the refresh so the spinner stays until the fetches finish.
          await ref.read(playerMmrProvider.future);
          await ref.read(competitiveUpdatesProvider.future);
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
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
          data: (result) =>
              result == null ? const SizedBox() : _RankCard(mmr: result.data),
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
              Icon(Icons.info_outline_rounded,
                  color: AppColors.textMuted, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Regional leaderboard requires Riot\'s official leaderboard endpoint. '
                  'Your personal peak rank and recent performance are shown above.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgCard2,
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
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: const Size(double.infinity, 56),
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
    if (updates.length < 2) return;

    // Cumulative RR so the line shows total trend across the 10 games.
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

    Offset toPoint(int i) {
      final x = i / (values.length - 1) * size.width;
      final norm = (values[i] - minV) / effectiveRange;
      final y = size.height - norm * size.height * 0.85 - size.height * 0.075;
      return Offset(x, y);
    }

    final points = List.generate(values.length, toPoint);
    final isPos = values.last >= 0;
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
          ..color = lineColor.withAlpha(35)
          ..style = PaintingStyle.fill);

    // Zero baseline (dashed).
    final zeroNorm = (0.0 - minV) / effectiveRange;
    final zeroY =
        size.height - zeroNorm * size.height * 0.85 - size.height * 0.075;
    const dashW = 6.0;
    const dashGap = 4.0;
    double dx = 0;
    final baselinePaint = Paint()
      ..color = Colors.white.withAlpha(25)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    while (dx < size.width) {
      canvas.drawLine(
          Offset(dx, zeroY), Offset(dx + dashW, zeroY), baselinePaint);
      dx += dashW + dashGap;
    }

    // Smooth line through all points via cubic bezier.
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
        ..color = lineColor.withAlpha(230)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Hollow dot at each data point, colored per win/loss.
    for (var i = 0; i < points.length; i++) {
      final u = updates[i];
      final dotColor = u.rankedRatingEarned > 0
          ? AppColors.win
          : u.rankedRatingEarned < 0
              ? AppColors.loss
              : Colors.white54;
      canvas.drawCircle(
          points[i],
          3.0,
          Paint()
            ..color = const Color(0xFF0D1420)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          points[i],
          3.0,
          Paint()
            ..color = dotColor.withAlpha(200)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // Larger filled dot at the last (most recent) point.
    canvas.drawCircle(points.last, 4.0, Paint()..color = lineColor);
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
    final tiersMap =
        ref.watch(_competitiveTiersMapProvider).asData?.value ?? {};
    int peakTier = mmr!.currentTier;
    int peakRr = mmr!.currentRankedRating;
    if (updates != null) {
      for (final u in updates!) {
        if (u.tierAfterUpdate > peakTier ||
            (u.tierAfterUpdate == peakTier &&
                u.rankedRatingAfterUpdate > peakRr)) {
          peakTier = u.tierAfterUpdate;
          peakRr = u.rankedRatingAfterUpdate;
        }
      }
    }
    final peakData = tiersMap[peakTier];
    final peakIconUrl = peakData?['largeIcon'] as String? ??
        peakData?['displayIcon'] as String?;
    final peakName =
        peakData?['tierName'] as String? ?? TierNameUtil.name(peakTier);

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
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(Icons.military_tech,
                  color: AppColors.red, size: 40),
            )
          else
            const Icon(Icons.military_tech, color: AppColors.red, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HIGHEST RECORDED RANK (RECENT)',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(peakName.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('$peakRr RR',
                    style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('CURRENT',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
              Text('${mmr!.currentRankedRating} RR',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              if (mmr!.gamesNeededForRating > 0)
                Text('${mmr!.gamesNeededForRating} games for rating',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9)),
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

Color _getCompetitiveTierColor(int tier) {
  if (tier >= 27) return const Color(0xFFFFF7C0); // Radiant
  if (tier >= 24) return const Color(0xFFBB384E); // Immortal
  if (tier >= 21) return const Color(0xFF45B07B); // Ascendant
  if (tier >= 18) return const Color(0xFFB064DD); // Diamond
  if (tier >= 15) return const Color(0xFF3FB3BE); // Platinum
  if (tier >= 12) return const Color(0xFFE2B742); // Gold
  if (tier >= 9) return const Color(0xFFB0B9C6); // Silver
  if (tier >= 6) return const Color(0xFFA67C52); // Bronze
  if (tier >= 3) return const Color(0xFF6A7079); // Iron
  return const Color(0xFF202732); // Unranked
}

class _ActRankTab extends ConsumerStatefulWidget {
  const _ActRankTab({required this.mmrAsync});
  final AsyncValue<CachedFetchResult<PlayerMmr>?> mmrAsync;

  @override
  ConsumerState<_ActRankTab> createState() => _ActRankTabState();
}

class _ActRankTabState extends ConsumerState<_ActRankTab> {
  String? _selectedSeasonId;
  bool _showOnPlayerCard = true;

  @override
  Widget build(BuildContext context) {
    final seasonAsync = ref.watch(_activeSeasonProvider);
    final tiersAsync = ref.watch(_competitiveTiersMapProvider);
    final activeSeasonData = seasonAsync.asData?.value;
    final currentSeasonLabel = activeSeasonData?['label'] ?? '';

    return widget.mmrAsync.when(
      data: (result) {
        if (result == null) {
          return const Center(
            child:
                Text('Not logged in.', style: TextStyle(color: Colors.white38)),
          );
        }
        final mmr = result.data;
        final selectedId = _selectedSeasonId ?? mmr.activeSeasonId;
        final actData = (selectedId != null ? mmr.seasonalData[selectedId] : null) ??
            mmr.activeSeasonData ??
            ActRankSeasonData(
              seasonId: selectedId ?? '',
              tier: mmr.currentTier,
              rankedRating: mmr.currentRankedRating,
              numberOfWins: 0,
              winsByTier: const {},
              borderLevel: 0,
            );

        final displayTier = actData.tier > 0 ? actData.tier : mmr.currentTier;
        final tierData = tiersAsync.asData?.value[displayTier];
        final iconUrl = tierData?['largeIcon'] as String? ??
            tierData?['displayIcon'] as String?;
        final tierName =
            tierData?['tierName'] as String? ?? TierNameUtil.name(displayTier);

        // Build list of seasons available in mmr.seasonalData
        final availableSeasonIds = mmr.seasonalData.keys.toList();
        if (selectedId != null && !availableSeasonIds.contains(selectedId)) {
          availableSeasonIds.insert(0, selectedId);
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            if (result.fromCache) const CacheDataBanner(),

            // ── Top Header Controls: Season Dropdown + Deadline Badge ─────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Act Selector Dropdown
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: availableSeasonIds.contains(selectedId)
                          ? selectedId
                          : null,
                      hint: Text(
                        currentSeasonLabel.isNotEmpty
                            ? currentSeasonLabel
                            : 'CURRENT ACT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      dropdownColor: AppColors.bgCard2,
                      icon: const Icon(Icons.arrow_drop_down_rounded,
                          color: AppColors.red, size: 22),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSeasonId = val);
                        }
                      },
                      items: availableSeasonIds.map((sId) {
                        final isCurrent = sId == mmr.activeSeasonId;
                        final label = isCurrent
                            ? (currentSeasonLabel.isNotEmpty
                                ? currentSeasonLabel
                                : 'CURRENT ACT')
                            : 'ACT $sId';
                        return DropdownMenuItem<String>(
                          value: sId,
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Act Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.red.withAlpha(120)),
                  ),
                  child: const Text(
                    'ACT RANK DETAILS',
                    style: TextStyle(
                      color: AppColors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Act Rank Pyramid Container ────────────────────────────────────
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow & Metallic Border Frame
                  Container(
                    width: 310,
                    height: 280,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getCompetitiveTierColor(actData.peakWinTier)
                            .withAlpha(100),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _getCompetitiveTierColor(actData.peakWinTier)
                              .withAlpha(35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                  // 49-Triangle Pyramid Painter
                  CustomPaint(
                    size: const Size(260, 230),
                    painter: _ActPyramidPainter(
                      winsTierList: actData.winTierList,
                      peakTier: actData.peakWinTier,
                      borderLevel: actData.borderLevel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Tier Name & Details ───────────────────────────────────────────
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (iconUrl != null && iconUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: iconUrl,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      tierName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${actData.rankedRating} RR',
                  style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Border Level Progress Bar Section ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BORDER LEVEL REACHED: ${actData.borderLevel}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '${actData.numberOfWins} WINS',
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress track between LVL N and LVL N+1
                  Row(
                    children: [
                      Text(
                        'LVL ${actData.borderLevel}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: actData.borderLevel >= 5
                                ? 1.0
                                : (actData.numberOfWins /
                                        (actData.numberOfWins +
                                            actData.winsNeededForNextBorder))
                                    .clamp(0.0, 1.0),
                            backgroundColor: Colors.black45,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getCompetitiveTierColor(actData.peakWinTier),
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        actData.borderLevel >= 5
                            ? 'MAX'
                            : 'LVL ${actData.borderLevel + 1}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      actData.borderLevel >= 5
                          ? 'Maximum Border Level Reached!'
                          : '${actData.winsNeededForNextBorder} wins to go for next border level',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Player Card Option Checkbox ────────────────────────────────────
            GestureDetector(
              onTap: () =>
                  setState(() => _showOnPlayerCard = !_showOnPlayerCard),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    _showOnPlayerCard
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: _showOnPlayerCard
                        ? AppColors.red
                        : Colors.white38,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Show previous Act Rank on my Player Card',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
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

// ── 49-Triangle Act Pyramid Painter ────────────────────────────────────────────

class _ActPyramidPainter extends CustomPainter {
  final List<int> winsTierList;
  final int peakTier;
  final int borderLevel;

  _ActPyramidPainter({
    required this.winsTierList,
    required this.peakTier,
    required this.borderLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 7 rows of triangles: row 0 has 13, row 1 has 11, row 2 has 9, row 3 has 7, row 4 has 5, row 5 has 3, row 6 has 1 = 49 triangles!
    const totalRows = 7;
    final rowHeight = height / totalRows;

    var winIndex = 0;

    for (var r = 0; r < totalRows; r++) {
      // Row 0 is at bottom (7th level), Row 6 is top peak
      final rowIndex = totalRows - 1 - r;
      final trianglesInRow = (rowIndex * 2) + 1;
      final triWidth = width / 13; // Max triangles in base row is 13

      final rowStartX = (width - (trianglesInRow * triWidth / 2)) / 2;
      final yTop = r * rowHeight;
      final yBottom = (r + 1) * rowHeight;

      for (var t = 0; t < trianglesInRow; t++) {
        final isPointUp = t % 2 == 0;
        final xLeft = rowStartX + (t * triWidth / 2);
        final xRight = xLeft + triWidth;
        final xCenter = (xLeft + xRight) / 2;

        final path = Path();
        if (isPointUp) {
          path.moveTo(xCenter, yTop);
          path.lineTo(xRight, yBottom);
          path.lineTo(xLeft, yBottom);
        } else {
          path.moveTo(xLeft, yTop);
          path.lineTo(xRight, yTop);
          path.lineTo(xCenter, yBottom);
        }
        path.close();

        final tierForTriangle =
            winIndex < winsTierList.length ? winsTierList[winIndex] : 0;
        winIndex++;

        final isFilled = tierForTriangle > 0;
        final color = _getCompetitiveTierColor(tierForTriangle);

        if (isFilled) {
          final fillPaint = Paint()
            ..color = color
            ..style = PaintingStyle.fill;
          canvas.drawPath(path, fillPaint);

          final strokePaint = Paint()
            ..color = Colors.black45
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawPath(path, strokePaint);
        } else {
          final emptyPaint = Paint()
            ..color = const Color(0xFF161C24)
            ..style = PaintingStyle.fill;
          canvas.drawPath(path, emptyPaint);

          final strokePaint = Paint()
            ..color = const Color(0xFF263242)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          canvas.drawPath(path, strokePaint);
        }
      }
    }

    // Outer Pyramid Frame Accent
    final framePath = Path()
      ..moveTo(width / 2, 0)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final framePaint = Paint()
      ..color = _getCompetitiveTierColor(peakTier).withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(framePath, framePaint);
  }

  @override
  bool shouldRepaint(covariant _ActPyramidPainter oldDelegate) {
    return oldDelegate.winsTierList != winsTierList ||
        oldDelegate.peakTier != peakTier ||
        oldDelegate.borderLevel != borderLevel;
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
    final tierName =
        tierData?['tierName'] as String? ?? TierNameUtil.name(mmr.currentTier);

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
                            color: AppColors.red,
                            size: 56),
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
                          color: isNetPos ? AppColors.win : AppColors.loss,
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
              Text('${update.rankedRatingAfterUpdate} RR',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (update.afkPenalty != 0)
                Text('AFK: ${update.afkPenalty}',
                    style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends ConsumerWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValorantErrorDisplay(
      error: message,
      compact: true,
      onRetry: () {
        ref.invalidate(currentCredentialsProvider);
        ref.invalidate(playerMmrProvider);
        ref.invalidate(competitiveUpdatesProvider);
      },
    );
  }
}
