import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/widgets/rank_badge.dart';
import '../domain/models/player_mmr.dart';

final _mmrProvider = FutureProvider.autoDispose<PlayerMmr?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  return source.fetchMmr(creds.shard, creds.puuid);
});

final _competitiveUpdatesProvider =
    FutureProvider.autoDispose<List<CompetitiveUpdate>>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return [];
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  return source.fetchCompetitiveUpdates(creds.shard, creds.puuid);
});

final _competitiveTiersMapProvider =
    FutureProvider.autoDispose<Map<int, Map<String, dynamic>>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getCompetitiveTiersMap();
});

class RankScreen extends ConsumerWidget {
  const RankScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mmrAsync = ref.watch(_mmrProvider);
    final updatesAsync = ref.watch(_competitiveUpdatesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text('COMPETITIVE RANK',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () {
              ref.invalidate(_mmrProvider);
              ref.invalidate(_competitiveUpdatesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF141F2D),
        onRefresh: () async {
          ref.invalidate(_mmrProvider);
          ref.invalidate(_competitiveUpdatesProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Current rank card
            mmrAsync.when(
              data: (mmr) =>
                  mmr == null ? const SizedBox() : _RankCard(mmr: mmr),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFFF4655)),
                ),
              ),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
            const SizedBox(height: 28),

            // RR history header
            Row(
              children: [
                Container(width: 3, height: 14, color: const Color(0xFFFF4655)),
                const SizedBox(width: 8),
                const Text(
                  'RECENT COMPETITIVE UPDATES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            updatesAsync.when(
              data: (updates) => updates.isEmpty
                  ? const Text('No recent competitive matches found.',
                      style: TextStyle(color: Colors.white38, fontSize: 13))
                  : Column(
                      children: updates
                          .map((u) => _UpdateTile(update: u))
                          .toList(),
                    ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFFF4655)),
                ),
              ),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _RankCard extends ConsumerWidget {
  const _RankCard({required this.mmr});
  final PlayerMmr mmr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersMapAsync = ref.watch(_competitiveTiersMapProvider);
    final tierData = tiersMapAsync.asData?.value[mmr.currentTier];
    final iconUrl = tierData?['largeIcon'] as String? ?? tierData?['displayIcon'] as String?;
    final tierName = tierData?['tierName'] as String? ?? _tierName(mmr.currentTier);

    final rrProgress = (mmr.currentRankedRating.clamp(0, 100)) / 100.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00F0FF).withAlpha(120),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F0FF).withAlpha(20),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141F2D), Color(0xFF0B101A)],
        ),
      ),
      child: Column(
        children: [
          RankBadge(
            tierName: tierName,
            rankedRating: mmr.currentRankedRating,
            iconUrl: iconUrl,
            large: true,
          ),
          const SizedBox(height: 16),

          // Rating progress
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF070A10).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1B2738)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'RANK RATING',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '${mmr.currentRankedRating} / 100 RR',
                      style: const TextStyle(
                        color: Color(0xFF00F0FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rrProgress,
                    backgroundColor: const Color(0xFF141F2D),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00F0FF)),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),

          if (mmr.gamesNeededForRating > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${mmr.gamesNeededForRating} more games needed for rating',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _tierName(int tier) {
    const tierNames = {
      0: 'Unranked',
      1: 'Unranked',
      2: 'Unranked',
      3: 'Iron 1',
      4: 'Iron 2',
      5: 'Iron 3',
      6: 'Bronze 1',
      7: 'Bronze 2',
      8: 'Bronze 3',
      9: 'Silver 1',
      10: 'Silver 2',
      11: 'Silver 3',
      12: 'Gold 1',
      13: 'Gold 2',
      14: 'Gold 3',
      15: 'Platinum 1',
      16: 'Platinum 2',
      17: 'Platinum 3',
      18: 'Diamond 1',
      19: 'Diamond 2',
      20: 'Diamond 3',
      21: 'Ascendant 1',
      22: 'Ascendant 2',
      23: 'Ascendant 3',
      24: 'Immortal 1',
      25: 'Immortal 2',
      26: 'Immortal 3',
      27: 'Radiant',
    };
    return tierNames[tier] ?? 'Unranked';
  }
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update});
  final CompetitiveUpdate update;

  @override
  Widget build(BuildContext context) {
    final rrChange = update.rankedRatingEarned;
    final isWin = rrChange > 0;
    final accentColor = isWin ? const Color(0xFF10B981) : const Color(0xFFFF4655);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B2738), width: 1),
      ),
      child: Row(
        children: [
          // Accent left bar
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          Icon(
            isWin ? Icons.trending_up : Icons.trending_down,
            color: accentColor,
            size: 20,
          ),
          const SizedBox(width: 10),

          // RR Delta
          Expanded(
            child: Text(
              '${isWin ? '+' : ''}$rrChange RR',
              style: TextStyle(
                color: accentColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          // Result After
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${update.rankedRatingAfterUpdate} RR',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (update.afkPenalty != 0)
                Text(
                  'AFK: ${update.afkPenalty}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
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
        border: Border.all(color: const Color(0xFFFF4655).withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4655)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

