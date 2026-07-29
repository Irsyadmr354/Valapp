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
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text('MATCH HISTORY',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
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
          data: (result) => result == null || result.matches.isEmpty
              ? const Center(
                  child: Text('No matches found.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: result.matches.length,
                  itemBuilder: (context, i) => _MatchTile(
                    entry: result.matches[i],
                    onTap: () =>
                        context.push('/match/${result.matches[i].matchId}'),
                  ),
                ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFFF4655)),
            ),
          ),
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
      height: 48,
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
                color: isSelected ? const Color(0xFFFF4655) : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
              backgroundColor: const Color(0xFF0E1622),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF4655)
                    : const Color(0xFF1B2738),
                width: isSelected ? 1.2 : 0.8,
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1622),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1B2738), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF141F2D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00F0FF).withAlpha(60)),
              ),
              child: const Icon(Icons.sports_esports,
                  color: Color(0xFF00F0FF), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.queueDisplayName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}

