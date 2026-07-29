import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../domain/models/match_history.dart';

final _queueFilterProvider = StateProvider<String?>((ref) => null);

final _matchHistoryProvider =
    FutureProvider.autoDispose<MatchHistoryResult?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final queue = ref.watch(_queueFilterProvider);
  final source = await ref.watch(matchRemoteSourceProvider.future);
  return source.fetchHistory(creds.shard, creds.puuid, queue: queue);
});

const _queues = [
  null,
  'competitive',
  'unrated',
  'spikerush',
  'deathmatch',
];

const _queueLabels = {
  null: 'All',
  'competitive': 'Competitive',
  'unrated': 'Unrated',
  'spikerush': 'Spike Rush',
  'deathmatch': 'Deathmatch',
};

class MatchHistoryScreen extends ConsumerWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_matchHistoryProvider);
    final selectedQueue = ref.watch(_queueFilterProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Match History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
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
        onRefresh: () async => ref.invalidate(_matchHistoryProvider),
        child: historyAsync.when(
          data: (result) => result == null || result.matches.isEmpty
              ? const Center(
                  child: Text('No matches found.',
                      style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: result.matches.length,
                  itemBuilder: (context, i) => _MatchTile(
                    entry: result.matches[i],
                    onTap: () =>
                        context.push('/match/${result.matches[i].matchId}'),
                  ),
                ),
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white54)),
          ),
        ),
      ),
    );
  }
}

class _QueueFilter extends StatelessWidget {
  const _QueueFilter({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: _queues.map((q) {
          final isSelected = selected == q;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_queueLabels[q] ?? 'All'),
              selected: isSelected,
              onSelected: (_) => onSelected(q),
              selectedColor: const Color(0xFFFF4655).withAlpha(40),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFFFF4655)
                    : Colors.white54,
                fontSize: 12,
              ),
              backgroundColor: const Color(0xFF1A2634),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF4655)
                    : const Color(0xFF3D4C5E),
              ),
              checkmarkColor: const Color(0xFFFF4655),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.entry, required this.onTap});
  final MatchHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, HH:mm').format(entry.gameStartTime);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2634),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3D4C5E)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0F1923),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sports_esports,
                  color: Colors.white54, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.matchId.substring(0, 8).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(dateStr,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
