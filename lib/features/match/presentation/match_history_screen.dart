import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../domain/models/match_history.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _queueFilterProvider = StateProvider<String?>((ref) => null);

final _mapsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMapsMap();
});

final _matchHistoryProvider =
    FutureProvider.autoDispose<CachedFetchResult<MatchHistoryResult>?>(
        (ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final queue = ref.watch(_queueFilterProvider);
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchHistoryLocalCacheProvider);
  try {
    final raw = await source.fetchHistoryRaw(
      creds.shard,
      creds.puuid,
      queue: queue,
    );
    final result = MatchHistoryResult.fromJson(raw);
    await cache.saveHistory(result, queue: queue);
    return CachedFetchResult(result);
  } catch (_) {
    final cached = await cache.loadHistory(queue: queue);
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
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

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
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
                color: Color(0xFF00F0FF), size: 22),
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
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF141F2D),
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
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFFF4655)),
            ),
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
              selectedColor: const Color(0xFFFF4655).withAlpha(40),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFFFF4655)
                    : Colors.white60,
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
              backgroundColor: const Color(0xFF0E1622),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF4655)
                    : const Color(0xFF1B2738),
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
    final total = matches.length;
    final won =
        matches.where((m) => m.result == MatchResult.victory).length;
    final lost =
        matches.where((m) => m.result == MatchResult.defeat).length;
    final draw =
        matches.where((m) => m.result == MatchResult.draw).length;
    final winRate = total > 0 ? won / total : 0.0;

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
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.8),
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
                const Text('LAST 20 MATCHES',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatCount(value: won, label: 'WON',
                        color: const Color(0xFF00E8F0)),
                    const SizedBox(width: 14),
                    _StatCount(value: lost, label: 'LOST',
                        color: const Color(0xFFFF4655)),
                    const SizedBox(width: 14),
                    _StatCount(value: draw, label: 'DRAW',
                        color: Colors.white38),
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

    // Progress arc (teal from top)
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = const Color(0xFF00E8F0)
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
    final dateStr =
        DateFormat('MMM d, HH:mm').format(entry.gameStartTime);
    final mapsAsync = ref.watch(_mapsMapProvider);
    final mapsMap = mapsAsync.asData?.value ?? {};
    final mapName = entry.getMapDisplayName(mapsMap);

    final rawKey = entry.mapId.toLowerCase();
    final lastSeg =
        rawKey.split('/').last.split('.').first;
    final mapInfo = mapsMap[rawKey] as Map<String, dynamic>? ??
        mapsMap[lastSeg] as Map<String, dynamic>? ??
        mapsMap[mapName.toLowerCase()] as Map<String, dynamic>?;
    final mapSplashUrl = mapInfo?['listViewIcon'] as String? ??
        mapInfo?['displayIcon'] as String? ??
        mapInfo?['splash'] as String?;

    final result = entry.result;
    final resultColor = result == MatchResult.victory
        ? const Color(0xFF00E8F0)
        : result == MatchResult.defeat
            ? const Color(0xFFFF4655)
            : Colors.white38;
    final resultLabel = result == MatchResult.victory
        ? 'VICTORY'
        : result == MatchResult.defeat
            ? 'DEFEAT'
            : 'DRAW';

    final score = entry.matchScore; // e.g. "13 - 8"
    final hasKda = entry.kills != null;
    final kdaStr = hasKda
        ? '${entry.kills} / ${entry.deaths} / ${entry.assists}'
        : null;
    final kdoStr = hasKda && (entry.deaths ?? 0) > 0
        ? ((entry.kills! + (entry.assists ?? 0)) /
                (entry.deaths!))
            .toStringAsFixed(2)
        : null;
    final isMvp = entry.isMvp;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white10, width: 0.8)),
        ),
        child: Row(
          children: [
            // Victory/Defeat tag strip + map image
            Stack(
              children: [
                // Map thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 72,
                    height: 56,
                    color: const Color(0xFF141F2D),
                    child: mapSplashUrl != null &&
                            mapSplashUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: mapSplashUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                color: const Color(0xFF141F2D)),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.map,
                                color: Color(0xFFFF4655),
                                size: 20),
                          )
                        : const Icon(Icons.map,
                            color: Color(0xFFFF4655), size: 20),
                  ),
                ),
                // Result tag overlaid at bottom of thumbnail
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(200),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        resultLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6),
                      ),
                    ),
                  ),
                ),
                // Score badge top-left if available
                if (score != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
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
            const SizedBox(width: 12),

            // Queue + map name + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Queue badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: resultColor.withAlpha(80),
                          width: 0.6),
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
                  Text(
                    dateStr,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                  if (mapName.isNotEmpty)
                    Text(
                      mapName,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),

            // KDA + K/O column
            if (kdaStr != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('KDA',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    kdaStr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900),
                  ),
                  if (kdoStr != null)
                    Text(
                      '$kdoStr K/O',
                      style: TextStyle(
                          color: resultColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  // MVP badge
                  if (isMvp)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withAlpha(35),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFFFD700),
                            width: 0.8),
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

            const Icon(Icons.chevron_right,
                color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}
