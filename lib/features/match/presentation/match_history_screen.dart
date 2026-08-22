import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/date_time_utils.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/valorant_error_display.dart';
import '../../auth/domain/session_reconnect.dart';
import '../domain/models/match_history.dart';

import '../domain/models/match_details.dart';
import '../../auth/domain/models/credentials.dart';
import '../../../core/storage/cache_storage.dart';
import '../data/match_local_cache.dart';
import '../data/match_remote_source.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _queueFilterProvider = StateProvider<String?>((ref) => null);
final _resultFilterProvider = StateProvider<MatchResult?>((ref) => null);

/// Tracks matchIds that failed to fetch during this app session.
/// Cleared when user performs a manual pull-to-refresh.
final _failedEnrichmentIdsProvider = StateProvider<Set<String>>((ref) => {});

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

class MatchHistoryNotifier
    extends AutoDisposeAsyncNotifier<CachedFetchResult<MatchHistoryResult>?> {
  int _enrichmentGeneration = 0;
  late final Stopwatch _trace = Stopwatch()..start();

  void _log(String msg) =>
      debugPrint('[CAREER +${_trace.elapsedMilliseconds}ms] $msg');

  @override
  Future<CachedFetchResult<MatchHistoryResult>?> build() async {
    _trace.reset();
    final gen = ++_enrichmentGeneration;
    // Register ALL watched dependencies synchronously BEFORE the first await,
    // so a rebuild during any stage restarts cleanly instead of leaving the
    // UI in an endless skeleton.
    final credsFuture = ref.watch(currentCredentialsProvider.future);
    final queue = ref.watch(_queueFilterProvider);
    final sourceFuture = ref.watch(matchRemoteSourceProvider.future);
    final historyCache = ref.watch(matchHistoryLocalCacheProvider);
    final detailCache = ref.watch(matchDetailLocalCacheProvider);

    _log('build#$gen start (queue=$queue)');

    final creds = await credsFuture
        .timeout(const Duration(seconds: 30), onTimeout: () {
      throw TimeoutException('CAREER: credentials load exceeded 30s');
    });
    if (creds == null) {
      _log('no credentials — returning null');
      return null;
    }
    final transaction =
        ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);
    _log('credentials ok puuid=${creds.puuid}');
    final source = await sourceFuture
        .timeout(const Duration(seconds: 30), onTimeout: () {
      throw TimeoutException('CAREER: remote source init exceeded 30s');
    });

    MatchHistoryResult result;
    bool fromCache = false;

    // 1. Fetch live history (with fallback to local history cache)
    try {
      final raw = await source
          .fetchHistoryRaw(
            creds.shard,
            creds.puuid,
            queue: queue,
          )
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw TimeoutException('CAREER: history fetch exceeded 45s');
      });
      result = MatchHistoryResult.fromJson(raw);
      if (transaction != null) {
        await historyCache.saveHistory(result,
            queue: queue, puuid: creds.puuid, transaction: transaction);
      }
      _log('history fetched live: ${result.matches.length} matches');
    } catch (e) {
      _log('live fetch FAILED: $e — trying history cache');
      final cached =
          await historyCache.loadHistory(queue: queue, puuid: creds.puuid);
      if (cached != null) {
        result = cached;
        fromCache = true;
        _log('history from CACHE: ${result.matches.length} matches');
      } else {
        _log('no cache either — rethrowing');
        rethrow;
      }
    }

    // 2. Fast cache-only enrich (0ms lag, no detail network requests here)
    final quickEnriched =
        await _enrichFromCache(result.matches, creds.puuid, detailCache);
    _log('cache-enrich done (${quickEnriched.where((m) => m.kills != null).length}/${quickEnriched.length} known)');

    final initialResult = CachedFetchResult(
      MatchHistoryResult(
        puuid: result.puuid,
        total: result.total,
        start: result.start,
        end: result.end,
        matches: quickEnriched,
      ),
      fromCache: fromCache,
    );

    // 3. Kick off progressive in-place enrichment in the background without UI re-fetches
    _startBackgroundEnrichment(
      matches: quickEnriched,
      creds: creds,
      source: source,
      detailCache: detailCache,
      transaction: transaction,
      generation: gen,
    );

    return initialResult;
  }

  Future<List<MatchHistoryEntry>> _enrichFromCache(
    List<MatchHistoryEntry> entries,
    String puuid,
    MatchDetailLocalCache detailCache,
  ) async {
    final enriched = <MatchHistoryEntry>[];
    for (final entry in entries) {
      final detailRaw =
          await detailCache.loadMatchDetailRaw(entry.matchId, puuid: puuid);
      if (detailRaw == null) {
        enriched.add(entry);
        continue;
      }
      try {
        final details = MatchDetails.fromJson(detailRaw);
        final player = details.players
            .cast<PlayerStats?>()
            .firstWhere((p) => p?.puuid == puuid, orElse: () => null);
        if (player == null) {
          enriched.add(entry);
          continue;
        }

        final matchResult = details.resultForPlayer(puuid);
        final scoreStr = details.scoreStringForPlayer(puuid);
        final sorted = List<PlayerStats>.from(details.players)
          ..sort((a, b) => b.score.compareTo(a.score));
        final isMvp = sorted.isNotEmpty && sorted.first.puuid == puuid;

        enriched.add(entry.copyWithStats(
          kills: player.kills,
          deaths: player.deaths,
          assists: player.assists,
          isMvp: isMvp,
          matchScore: scoreStr,
          result: matchResult,
          agentId: player.agentId,
          mapId: details.mapId,
        ));
      } catch (_) {
        enriched.add(entry);
      }
    }
    return enriched;
  }

  void _startBackgroundEnrichment({
    required List<MatchHistoryEntry> matches,
    required Credentials creds,
    required MatchRemoteSource source,
    required MatchDetailLocalCache detailCache,
    required CacheTransaction? transaction,
    required int generation,
  }) async {
    final failedIds = ref.read(_failedEnrichmentIdsProvider);
    // Enrich top 12 unenriched matches to provide fast responsiveness
    final missing = matches
        .where((e) =>
            (e.result == MatchResult.unknown || e.kills == null) &&
            !failedIds.contains(e.matchId))
        .take(12)
        .toList();

    if (missing.isEmpty) {
      _log('background enrichment: nothing to fetch');
      return;
    }
    _log('background enrichment: ${missing.length} detail(s) to fetch');

    final newlyFailed = <String>{};
    final currentMatchesMap = {for (final m in matches) m.matchId: m};

    const batchSize = 3;
    for (var i = 0; i < missing.length; i += batchSize) {
      if (_enrichmentGeneration != generation) return;
      if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) return;
      final batch = missing.skip(i).take(batchSize).toList();
      bool batchUpdated = false;

      final batchSw = Stopwatch()..start();
      await Future.wait(batch.map((entry) async {
        try {
          final existing = await detailCache.loadMatchDetailRaw(entry.matchId,
              puuid: creds.puuid);
          Map<String, dynamic> raw;
          if (existing != null) {
            raw = existing;
          } else {
            raw = await source.fetchMatchDetailsRaw(creds.shard, entry.matchId);
            if (transaction != null) {
              await detailCache.saveMatchDetail(entry.matchId, raw,
                  puuid: creds.puuid, transaction: transaction);
            }
          }

          final details = MatchDetails.fromJson(raw);
          final player = details.players
              .cast<PlayerStats?>()
              .firstWhere((p) => p?.puuid == creds.puuid, orElse: () => null);

          if (player != null) {
            final matchResult = details.resultForPlayer(creds.puuid);
            final scoreStr = details.scoreStringForPlayer(creds.puuid);
            final sorted = List<PlayerStats>.from(details.players)
              ..sort((a, b) => b.score.compareTo(a.score));
            final isMvp =
                sorted.isNotEmpty && sorted.first.puuid == creds.puuid;

            final updatedEntry = entry.copyWithStats(
              kills: player.kills,
              deaths: player.deaths,
              assists: player.assists,
              isMvp: isMvp,
              matchScore: scoreStr,
              result: matchResult,
              agentId: player.agentId,
              mapId: details.mapId,
            );
            currentMatchesMap[entry.matchId] = updatedEntry;
            batchUpdated = true;
          }
        } catch (e) {
        debugPrint('[CAREER] detail ${entry.matchId} FAILED: $e');
        newlyFailed.add(entry.matchId);
      }
      }));

      _log('batch done in ${batchSw.elapsedMilliseconds}ms '
          '(updated=$batchUpdated, failed=${newlyFailed.length})');

      // Update state incrementally per batch so user sees results appear smoothly without reload
      if (_enrichmentGeneration != generation) return;
      if (batchUpdated &&
          ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
        final currentVal = state.asData?.value;
        if (currentVal != null) {
          final updatedList = currentVal.data.matches
              .map((m) => currentMatchesMap[m.matchId] ?? m)
              .toList();
          state = AsyncData(CachedFetchResult(
            MatchHistoryResult(
              puuid: currentVal.data.puuid,
              total: currentVal.data.total,
              start: currentVal.data.start,
              end: currentVal.data.end,
              matches: updatedList,
            ),
            fromCache: currentVal.fromCache,
          ));
        }
      }
    }

    if (newlyFailed.isNotEmpty &&
        ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
      ref
          .read(_failedEnrichmentIdsProvider.notifier)
          .update((ids) => {...ids, ...newlyFailed});
    }
  }
}

final matchHistoryProvider = AutoDisposeAsyncNotifierProvider<
    MatchHistoryNotifier,
    CachedFetchResult<MatchHistoryResult>?>(MatchHistoryNotifier.new);

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
    final historyAsync = ref.watch(matchHistoryProvider);
    final selectedQueue = ref.watch(_queueFilterProvider);
    final selectedResult = ref.watch(_resultFilterProvider);
    final hasResultFilter = selectedResult != null;

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
            icon: Icon(Icons.filter_list_rounded,
                color: hasResultFilter ? AppColors.red : Colors.white54,
                size: 22),
            tooltip: 'Filter by Result',
            onPressed: () =>
                _showResultFilterSheet(context, ref, selectedResult),
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
        onRefresh: () async {
          // Reset failed enrichment set so pull-to-refresh retries everything
          ref.read(_failedEnrichmentIdsProvider.notifier).state = {};
          ref.invalidate(matchHistoryProvider);
          // Await the refresh so the spinner stays until the fetch finishes.
          await ref.read(matchHistoryProvider.future);
        },
        child: historyAsync.when(
          data: (result) {
            if (result == null || result.data.matches.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Icon(Icons.sports_esports_outlined,
                      color: Colors.white24, size: 44),
                  SizedBox(height: 12),
                  Center(
                    child: Text('No matches found. Pull down to refresh.',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                ],
              );
            }
            // Apply result filter if set
            final allMatches = result.data.matches;
            final matches = selectedResult == null
                ? allMatches
                : allMatches.where((m) => m.result == selectedResult).toList();
            if (matches.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.filter_alt_off_outlined,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'No ${_resultLabel(selectedResult!)} matches found.',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          ref.read(_resultFilterProvider.notifier).state = null,
                      child: const Text('Clear filter',
                          style: TextStyle(color: AppColors.red)),
                    ),
                  ],
                ),
              );
            }
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
          loading: () => const MatchHistorySkeleton(),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 60),
            children: [
              ValorantErrorDisplay(
                error: e,
                title: 'Gagal Memuat Riwayat Pertandingan',
                onRetry: () => reconnectAndInvalidate(
                  ref,
                  invalidateData: () => ref.invalidate(matchHistoryProvider),
                  onPermanentAuthFailure: () => context.push('/login/webview'),
                ),
                onReauth: () => context.push('/login/webview'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResultFilterSheet(
      BuildContext context, WidgetRef ref, MatchResult? current) {
    const options = [
      (null, 'All Results', Colors.white70, Icons.apps_rounded),
      (
        MatchResult.victory,
        'Victory',
        AppColors.win,
        Icons.emoji_events_rounded
      ),
      (MatchResult.defeat, 'Defeat', AppColors.loss, Icons.close_rounded),
      (MatchResult.draw, 'Draw', Colors.white38, Icons.remove_rounded),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.red, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('FILTER BY RESULT',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final (value, label, color, icon) = opt;
              final isSelected = current == value;
              return GestureDetector(
                onTap: () {
                  ref.read(_resultFilterProvider.notifier).state = value;
                  Navigator.of(context).pop();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withAlpha(30) : AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : Colors.white10,
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 12),
                      Text(label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                          )),
                      const Spacer(),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 18),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _resultLabel(MatchResult r) => switch (r) {
        MatchResult.victory => 'Victory',
        MatchResult.defeat => 'Defeat',
        MatchResult.draw => 'Draw',
        MatchResult.unknown => 'Unknown',
      };
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
    final won = matches.where((m) => m.result == MatchResult.victory).length;
    final lost = matches.where((m) => m.result == MatchResult.defeat).length;
    final draw = matches.where((m) => m.result == MatchResult.draw).length;
    final unknown =
        matches.where((m) => m.result == MatchResult.unknown).length;
    // Win rate over matches with known results
    final knownTotal = won + lost + draw;
    final winRate = knownTotal > 0 ? won / knownTotal : 0.0;

    // K/D across matches that have stats
    final matchesWithStats = matches.where((m) => m.kills != null).toList();
    final totalKills =
        matchesWithStats.fold<int>(0, (s, m) => s + (m.kills ?? 0));
    final totalDeaths =
        matchesWithStats.fold<int>(0, (s, m) => s + (m.deaths ?? 0));
    final kd =
        totalDeaths > 0 ? totalKills / totalDeaths : totalKills.toDouble();

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
                    _StatCount(value: won, label: 'WON', color: AppColors.win),
                    const SizedBox(width: 14),
                    _StatCount(
                        value: lost, label: 'LOST', color: AppColors.loss),
                    const SizedBox(width: 14),
                    _StatCount(
                        value: draw, label: 'DRAW', color: Colors.white38),
                    if (unknown > 0) ...[
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 10,
                                height: 10,
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
          RepaintBoundary(
            child: CustomPaint(
              size: const Size(72, 72),
              painter: _RingPainter(progress: winRate.clamp(0.0, 1.0)),
            ),
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
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
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
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
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
    final dateStr = DateTimeUtils.formatMatchTime(entry.gameStartMillis);
    final mapsMap = ref.watch(_mapsMapProvider).asData?.value ?? {};
    final agentsMap = ref.watch(_agentsMapProvider).asData?.value ?? {};
    final mapName = entry.getMapDisplayName(mapsMap);

    // getMapsMap() pre-indexes the full URL, every path segment, and cleaned
    // variants at cache-build time, so a single lookup on the lowercased raw
    // key is sufficient here — no need to re-split/re-strip in build().
    final rawKey = entry.mapId.toLowerCase();
    final mapInfo = mapsMap[rawKey] as Map<String, dynamic>?;

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
    final kdaStr =
        hasKda ? '${entry.kills} / ${entry.deaths} / ${entry.assists}' : null;
    final kdoStr = hasKda && (entry.deaths ?? 0) > 0
        ? ((entry.kills! + (entry.assists ?? 0)) / (entry.deaths!))
            .toStringAsFixed(2)
        : null;
    final isMvp = entry.isMvp;

    // Agent icon from agentId field (added in match history enrichment)
    final agentId = entry.agentId;
    final agentInfo =
        agentId != null ? agentsMap[agentId] as Map<String, dynamic>? : null;
    final agentIconUrl = agentInfo?['displayIcon'] as String?;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: resultColor.withAlpha(40),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Map thumbnail + result tag
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 76,
                    height: 56,
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
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(220),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Center(
                      child: Text(resultLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8)),
                    ),
                  ),
                ),
                if (score != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(score,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Agent icon (small circle with status border)
            if (agentIconUrl != null && agentIconUrl.isNotEmpty)
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard2,
                  border:
                      Border.all(color: resultColor.withAlpha(100), width: 1.2),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: resultColor.withAlpha(80), width: 0.8),
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
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500)),
                  if (mapName.isNotEmpty)
                    Text(mapName.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3)),
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
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text(kdaStr,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  if (kdoStr != null)
                    Text('$kdoStr K/D',
                        style: TextStyle(
                            color: resultColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  if (isMvp)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withAlpha(35),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFFFD700), width: 0.8),
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
            child: RepaintBoundary(
              child: CustomPaint(painter: _StripePainter()),
            ),
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
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height, size.height), paint);
      x += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
