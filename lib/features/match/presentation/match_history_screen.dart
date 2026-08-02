import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/match_history.dart';
import '../domain/models/match_details.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _queueFilterProvider = StateProvider<String?>((ref) => null);

final _mapsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMapsMap();
});

final _agentsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getAgentsMap();
});

final _matchHistoryProvider =
    FutureProvider.autoDispose<CachedFetchResult<MatchHistoryResult>?>(
        (ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final queue = ref.watch(_queueFilterProvider);
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchHistoryLocalCacheProvider);

  // ── Step 1: fetch/load history quickly (no detail calls here) ────────────
  MatchHistoryResult result;
  bool fromCache = false;

  try {
    final raw = await source.fetchHistoryRaw(
      creds.shard,
      creds.puuid,
      queue: queue,
    );
    result = MatchHistoryResult.fromJson(raw);
    await cache.saveHistory(result, queue: queue);
  } catch (_) {
    final cached = await cache.loadHistory(queue: queue);
    if (cached != null) {
      result = cached;
      fromCache = true;
    } else {
      rethrow;
    }
  }

  // ── Step 2: enrich only from CACHE (no network here — zero lag) ──────────
  // Entries that already have a cached detail get enriched immediately.
  // Missing details are fetched by _enrichmentProvider in the background.
  final detailCache = ref.watch(matchDetailLocalCacheProvider);
  final quickEnriched = <MatchHistoryEntry>[];
  for (final entry in result.matches) {
    final detailRaw = await detailCache.loadMatchDetailRaw(entry.matchId);
    if (detailRaw == null) {
      quickEnriched.add(entry);
      continue;
    }
    try {
      final details = MatchDetails.fromJson(detailRaw);
      final player = details.players
          .cast<PlayerStats?>()
          .firstWhere((p) => p?.puuid == creds.puuid, orElse: () => null);
      if (player == null) { quickEnriched.add(entry); continue; }

      MatchResult matchResult = MatchResult.unknown;
      if (details.roundResults.isNotEmpty) {
        final pt = player.teamId.toLowerCase();
        final myWins = details.roundResults
            .where((r) => r.winningTeam.toLowerCase() == pt).length;
        final oppWins = details.roundResults.length - myWins;
        matchResult = myWins > oppWins
            ? MatchResult.victory
            : myWins < oppWins ? MatchResult.defeat : MatchResult.draw;
      }

      String? scoreStr;
      if (details.roundResults.isNotEmpty) {
        final pt = player.teamId.toLowerCase();
        final my = details.roundResults
            .where((r) => r.winningTeam.toLowerCase() == pt).length;
        scoreStr = '$my – ${details.roundResults.length - my}';
      }

      final sorted = List<PlayerStats>.from(details.players)
        ..sort((a, b) => b.score.compareTo(a.score));
      final isMvp = sorted.isNotEmpty && sorted.first.puuid == creds.puuid;

      quickEnriched.add(entry.copyWithStats(
        kills: player.kills, deaths: player.deaths, assists: player.assists,
        isMvp: isMvp, matchScore: scoreStr, result: matchResult,
        agentId: player.agentId, mapId: details.mapId,
      ));
    } catch (_) {
      quickEnriched.add(entry);
    }
  }

  return CachedFetchResult(
    MatchHistoryResult(
      puuid: result.puuid, total: result.total,
      start: result.start, end: result.end,
      matches: quickEnriched,
    ),
    fromCache: fromCache,
  );
});

/// Background enrichment provider — fetches missing match details from
/// network without blocking the UI. Invalidates [_matchHistoryProvider]
/// when done so the list rebuilds with full KDA/result data.
final _backgroundEnrichmentProvider =
    FutureProvider.autoDispose<void>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return;
  // Watch queue filter so this provider re-runs when the filter changes
  ref.watch(_queueFilterProvider);
  final historyResult = await ref.watch(_matchHistoryProvider.future);
  if (historyResult == null) return;

  final source = await ref.watch(matchRemoteSourceProvider.future);
  final detailCache = ref.watch(matchDetailLocalCacheProvider);

  // Only fetch details that are NOT already cached
  final missing = historyResult.data.matches
      .where((e) => e.result == MatchResult.unknown || e.kills == null)
      .toList();
  if (missing.isEmpty) return;

  bool anyNewData = false;
  const batchSize = 5;
  for (var i = 0; i < missing.length; i += batchSize) {
    final batch = missing.skip(i).take(batchSize).toList();
    await Future.wait(batch.map((entry) async {
      // Skip if already cached (race-free check)
      final existing = await detailCache.loadMatchDetailRaw(entry.matchId);
      if (existing != null) return;
      try {
        final raw =
            await source.fetchMatchDetailsRaw(creds.shard, entry.matchId);
        await detailCache.saveMatchDetail(entry.matchId, raw);
        anyNewData = true;
      } catch (_) {}
    }));
  }

  // Trigger re-render only if we actually fetched new data.
  // Only invalidate the history provider (not self) — invalidating self would
  // cause this provider to re-run immediately after _matchHistoryProvider
  // rebuilds, potentially looping if the fresh history still has unknowns.
  // Being autoDispose, this provider is re-created naturally by the screen.
  if (anyNewData) {
    ref.invalidate(_matchHistoryProvider);
  }
});

// ── Queue filter config ───────────────────────────────────────────────────────

const _queues = [null, 'competitive', 'unrated', 'spikerush', 'deathmatch'];

const _queueLabels = {
  null: 'All',
  'competitive': 'Competitive',
  'unrated': 'Unrated',
  'spikerush': 'Spike Rush',
  'deathmatch': 'Deathmatch',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class MatchHistoryScreen extends ConsumerWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_matchHistoryProvider);
    final selectedQueue = ref.watch(_queueFilterProvider);

    // Kick off background enrichment — non-blocking, updates list when done
    ref.watch(_backgroundEnrichmentProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        centerTitle: false,
        title: const Text('MATCH HISTORY',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded,
                color: AppColors.red, size: 22),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _QueueFilter(
            selected: selectedQueue,
            onSelected: (q) {
              ref.read(_queueFilterProvider.notifier).state = q;
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        backgroundColor: AppColors.bgCard2,
        onRefresh: () async => ref.invalidate(_matchHistoryProvider),
        child: historyAsync.when(
          data: (result) {
            if (result == null || result.data.matches.isEmpty) {
              return const Center(
                child: Text('No matches found.',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              );
            }
            final matches = result.data.matches;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: matches.length +
                  1 + // stats banner
                  (result.fromCache ? 1 : 0),
              itemBuilder: (context, i) {
                // Cache banner
                if (result.fromCache && i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: CacheDataBanner(),
                  );
                }
                final offset = result.fromCache ? 1 : 0;
                // Stats banner row (first real item)
                if (i == offset) {
                  return _StatsSummaryBanner(matches: matches);
                }
                final match = matches[i - offset - 1];
                return _MatchTile(
                  entry: match,
                  onTap: () => context.push('/match/${match.matchId}'),
                );
              },
            );
          },
          loading: () => const SizedBox(
            width: double.infinity,
            child: SkinCardShimmer(),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_toggle_off,
                      color: Colors.white38, size: 48),
                  const SizedBox(height: 12),
                  const Text('Unable to load match history',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Pull down to refresh or tap retry below.',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      ref.invalidate(currentCredentialsProvider);
                      ref.invalidate(_matchHistoryProvider);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4655)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Queue Filter Bar ──────────────────────────────────────────────────────────

class _QueueFilter extends StatelessWidget {
  const _QueueFilter({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: _queues.map((q) {
          final isSelected = selected == q;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_queueLabels[q] ?? 'All'),
              selected: isSelected,
              onSelected: (_) => onSelected(q),
              selectedColor: AppColors.red.withAlpha(40),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.red : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
              backgroundColor: AppColors.bgCard,
              side: BorderSide(
                color: isSelected ? AppColors.red : AppColors.border,
                width: isSelected ? 1.2 : 0.8,
              ),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Stats Summary Banner ──────────────────────────────────────────────────────

class _StatsSummaryBanner extends StatelessWidget {
  const _StatsSummaryBanner({required this.matches});
  final List<MatchHistoryEntry> matches;

  @override
  Widget build(BuildContext context) {
    // Use all matches as the total — include unknown (unenriched) entries
    final total = matches.length;
    final won =
        matches.where((m) => m.result == MatchResult.victory).length;
    final lost =
        matches.where((m) => m.result == MatchResult.defeat).length;
    final draw =
        matches.where((m) => m.result == MatchResult.draw).length;
    final unknown =
        matches.where((m) => m.result == MatchResult.unknown).length;
    // Win rate over matches with known results
    final knownTotal = won + lost + draw;
    final winRate = knownTotal > 0 ? won / knownTotal : 0.0;

    // K/D across matches that have stats
    final matchesWithStats =
        matches.where((m) => m.kills != null).toList();
    final totalKills =
        matchesWithStats.fold<int>(0, (s, m) => s + (m.kills ?? 0));
    final totalDeaths =
        matchesWithStats.fold<int>(0, (s, m) => s + (m.deaths ?? 0));
    final kd = totalDeaths > 0
        ? totalKills / totalDeaths
        : totalKills.toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          // Win-rate circle
          _WinRateCircle(winRate: winRate),
          const SizedBox(width: 16),
          // W / L / D counts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST $total MATCHES',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatCount(value: won, label: 'WON',
                        color: AppColors.win),
                    const SizedBox(width: 14),
                    _StatCount(value: lost, label: 'LOST',
                        color: AppColors.loss),
                    const SizedBox(width: 14),
                    _StatCount(value: draw, label: 'DRAW',
                        color: Colors.white38),
                    if (unknown > 0) ...[
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 10, height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text('$unknown',
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      height: 1.0)),
                            ],
                          ),
                          const Text('LOADING',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // K/D ratio
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('K/D RATIO',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(
                kd.toStringAsFixed(2),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.0),
              ),
              const Text('KILLS / DEATHS',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 8,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _WinRateCircle extends StatelessWidget {
  const _WinRateCircle({required this.winRate});
  final double winRate;

  @override
  Widget build(BuildContext context) {
    final pct = (winRate * 100).round();
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(72, 72),
            painter: _RingPainter(progress: winRate.clamp(0.0, 1.0)),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$pct%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.0),
              ),
              const Text('WIN RATE',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 5.0;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc — red
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress;
}

class _StatCount extends StatelessWidget {
  const _StatCount(
      {required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
              color: color, fontSize: 22, fontWeight: FontWeight.w900,
              height: 1.0),
        ),
        Text(label,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Match Tile ────────────────────────────────────────────────────────────────

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.entry, required this.onTap});
  final MatchHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('MMM d, HH:mm').format(entry.gameStartTime);
    final mapsMap = ref.watch(_mapsMapProvider).asData?.value ?? {};
    final agentsMap = ref.watch(_agentsMapProvider).asData?.value ?? {};
    final mapName = entry.getMapDisplayName(mapsMap);

    final rawKey = entry.mapId.toLowerCase();
    // Try: full path, each segment, segment without _wp/_wip suffixes, and resolved display name
    final segments = rawKey.split('/').where((s) => s.isNotEmpty).toList();
    Map<String, dynamic>? mapInfo;
    // 1. Full raw path
    mapInfo = mapsMap[rawKey] as Map<String, dynamic>?;
    // 2. Each path segment and cleaned variants
    if (mapInfo == null) {
      for (final seg in segments.reversed) {
        mapInfo = mapsMap[seg] as Map<String, dynamic>?;
        if (mapInfo != null) break;
        final cleaned = seg
            .replaceAll(RegExp(r'_wp$'), '')
            .replaceAll(RegExp(r'_wip$'), '')
            .replaceAll(RegExp(r'_p\d*$'), '')
            .replaceAll(RegExp(r'_\d+$'), '');
        if (cleaned != seg) {
          mapInfo = mapsMap[cleaned] as Map<String, dynamic>?;
          if (mapInfo != null) break;
        }
      }
    }
    // 3. Display name from model fallback
    if (mapInfo == null && mapName.isNotEmpty) {
      mapInfo = mapsMap[mapName.toLowerCase()] as Map<String, dynamic>?;
    }
    final mapSplashUrl = mapInfo?['listViewIcon'] as String? ??
        mapInfo?['splash'] as String? ??
        mapInfo?['displayIcon'] as String?;

    final result = entry.result;
    // Victory = green, Defeat = red, Draw = grey, Unknown = show queue color
    final resultColor = result == MatchResult.victory
        ? AppColors.win
        : result == MatchResult.defeat
            ? AppColors.loss
            : result == MatchResult.draw
                ? AppColors.draw
                : AppColors.textMuted;
    final resultLabel = result == MatchResult.victory
        ? 'VICTORY'
        : result == MatchResult.defeat
            ? 'DEFEAT'
            : result == MatchResult.draw
                ? 'DRAW'
                : '—';

    final score = entry.matchScore;
    final hasKda = entry.kills != null;
    final kdaStr = hasKda
        ? '${entry.kills} / ${entry.deaths} / ${entry.assists}'
        : null;
    final kdoStr = hasKda && (entry.deaths ?? 0) > 0
        ? ((entry.kills! + (entry.assists ?? 0)) / (entry.deaths!))
            .toStringAsFixed(2)
        : null;
    final isMvp = entry.isMvp;

    // Agent icon from agentId field (added in match history enrichment)
    final agentId = entry.agentId;
    final agentInfo = agentId != null ? agentsMap[agentId] as Map<String, dynamic>? : null;
    final agentIconUrl = agentInfo?['displayIcon'] as String?;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
        ),
        child: Row(
          children: [
            // Map thumbnail + result tag
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72, height: 56,
                    child: mapSplashUrl != null && mapSplashUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: mapSplashUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppColors.bgCard2),
                            // On error: styled fallback with map name
                            errorWidget: (_, __, ___) =>
                                _MapFallback(mapName: mapName),
                          )
                        : _MapFallback(mapName: mapName),
                  ),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(210),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Center(
                      child: Text(resultLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6)),
                    ),
                  ),
                ),
                if (score != null)
                  Positioned(
                    top: 4, left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(score,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),

            // Agent icon (small circle)
            if (agentIconUrl != null && agentIconUrl.isNotEmpty)
              Container(
                width: 30, height: 30,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard2,
                  border: Border.all(color: resultColor.withAlpha(80), width: 1),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: agentIconUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),

            // Queue + map + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: resultColor.withAlpha(80), width: 0.6),
                    ),
                    child: Text(
                      entry.queueDisplayName.toUpperCase(),
                      style: TextStyle(
                          color: resultColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(dateStr,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                  if (mapName.isNotEmpty)
                    Text(mapName,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            // KDA column
            if (kdaStr != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('KDA',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(kdaStr,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  if (kdoStr != null)
                    Text('$kdoStr K/O',
                        style: TextStyle(
                            color: resultColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  if (isMvp)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withAlpha(35),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
                      ),
                      child: const Text('MVP',
                          style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                    ),
                ],
              ),
              const SizedBox(width: 8),
            ],

            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}



// ── Map Fallback placeholder ──────────────────────────────────────────────────
// Shown when map splash image is unavailable — styled dark card with map name.

class _MapFallback extends StatelessWidget {
  const _MapFallback({required this.mapName});
  final String mapName;

  @override
  Widget build(BuildContext context) {
    final label = mapName.isNotEmpty ? mapName.toUpperCase() : 'MAP';
    return Container(
      width: 72,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Stack(
        children: [
          // Subtle diagonal stripe texture
          Positioned.fill(
            child: CustomPaint(painter: _StripePainter()),
          ),
          // Map name + icon centred
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, color: AppColors.red, size: 16),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const spacing = 8.0;
    var x = -size.height.toDouble();
    while (x < size.width + size.height) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
      x += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
