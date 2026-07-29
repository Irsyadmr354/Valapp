import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/match_history.dart';

final _queueFilterProvider = StateProvider<String?>((ref) => null);

final _mapsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMapsMap();
});

final _matchMapCacheProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final cached = await CacheStorage.instance.getMatchMaps();
  try {
    final creds = await ref.watch(currentCredentialsProvider.future);
    if (creds != null) {
      final mmrSource = await ref.watch(mmrRemoteSourceProvider.future);
      await mmrSource.fetchCompetitiveUpdates(creds.shard, creds.puuid);
      return await CacheStorage.instance.getMatchMaps();
    }
  } catch (_) {}
  return cached;
});

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
        onRefresh: () async {
          ref.invalidate(_matchHistoryProvider);
          ref.invalidate(_matchMapCacheProvider);
        },
        child: historyAsync.when(
          data: (result) => result == null || result.matches.isEmpty
              ? const Center(
                  child: Text('No matches found.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: result.matches.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16),
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
            child: ChoiceChip(
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
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.entry, required this.onTap});
  final MatchHistoryEntry entry;
  final VoidCallback onTap;

  String _resolveMapName(String rawMap) {
    if (rawMap.isEmpty) return '';
    final raw = rawMap.toLowerCase();

    if (raw.contains('plummet') || raw.contains('infinity') || raw.contains('abyss')) return 'Abyss';
    if (raw.contains('jam') || raw.contains('lotus')) return 'Lotus';
    if (raw.contains('juliett') || raw.contains('sunset')) return 'Sunset';
    if (raw.contains('canyon') || raw.contains('fracture')) return 'Fracture';
    if (raw.contains('port') || raw.contains('icebox')) return 'Icebox';
    if (raw.contains('lowpe') || raw.contains('pitt') || raw.contains('pearl')) return 'Pearl';
    if (raw.contains('foxtrot')) return 'Drift';
    if (raw.contains('ascent')) return 'Ascent';
    if (raw.contains('bind')) return 'Bind';
    if (raw.contains('haven')) return 'Haven';
    if (raw.contains('split')) return 'Split';
    if (raw.contains('breeze')) return 'Breeze';

    final parts = rawMap.split('/');
    final last = parts.last.split('.').first;
    if (last.isEmpty) return '';
    return last[0].toUpperCase() + last.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('MMM d, HH:mm').format(entry.gameStartTime);

    final mapCacheAsync = ref.watch(_matchMapCacheProvider);
    final mapCache = mapCacheAsync.asData?.value ?? {};
    final rawMapId = mapCache[entry.matchId] ?? entry.mapId;
    final mapName = _resolveMapName(rawMapId);

    final mapsAsync = ref.watch(_mapsMapProvider);
    final mapInfo = mapsAsync.asData?.value[mapName.toLowerCase()];
    final mapIconUrl = mapInfo?['listViewIcon'] as String? ?? mapInfo?['displayIcon'] as String?;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Map Image Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 46,
                height: 46,
                color: const Color(0xFF141F2D),
                child: mapIconUrl != null && mapIconUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: mapIconUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: const Color(0xFF141F2D)),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.map, color: Color(0xFFFF4655), size: 20),
                      )
                    : const Icon(Icons.map, color: Color(0xFFFF4655), size: 20),
              ),
            ),
            const SizedBox(width: 14),

            // Match Title & Map Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                      if (mapName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• $mapName',
                          style: const TextStyle(
                            color: Color(0xFFFF4655),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}




