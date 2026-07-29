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

class RankScreen extends ConsumerWidget {
  const RankScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mmrAsync = ref.watch(_mmrProvider);
    final updatesAsync = ref.watch(_competitiveUpdatesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Rank',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
            const SizedBox(height: 24),

            // RR history
            const Text(
              'RECENT MATCHES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            updatesAsync.when(
              data: (updates) => updates.isEmpty
                  ? const Text('No recent competitive matches.',
                      style: TextStyle(color: Colors.white54))
                  : Column(
                      children: updates
                          .map((u) => _UpdateTile(update: u))
                          .toList(),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.mmr});
  final PlayerMmr mmr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2634), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3D4C5E)),
      ),
      child: Column(
        children: [
          RankBadge(
            tierName: _tierName(mmr.currentTier),
            rankedRating: mmr.currentRankedRating,
            large: true,
          ),
          if (mmr.gamesNeededForRating > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${mmr.gamesNeededForRating} more games to get rated',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
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
    final color = isWin ? const Color(0xFF4CAF50) : const Color(0xFFFF4655);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(isWin ? Icons.trending_up : Icons.trending_down,
              color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${isWin ? '+' : ''}$rrChange RR',
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${update.rankedRatingAfterUpdate} RR',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (update.afkPenalty != 0)
                Text(
                  'AFK: ${update.afkPenalty}',
                  style:
                      const TextStyle(color: Colors.orange, fontSize: 11),
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
        color: const Color(0xFFFF4655).withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4655)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }
}
