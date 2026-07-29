import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/models/match_details.dart';

final _matchDetailFamily =
    FutureProvider.autoDispose.family<MatchDetails?, String>((ref, matchId) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  return source.fetchMatchDetails(creds.shard, matchId);
});

class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_matchDetailFamily(matchId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Match Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: detailAsync.when(
        data: (details) => details == null
            ? const Center(
                child: Text('No data', style: TextStyle(color: Colors.white54)))
            : _MatchDetailContent(details: details),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }
}

class _MatchDetailContent extends StatelessWidget {
  const _MatchDetailContent({required this.details});
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Match info header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2634),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.matchInfo.gameMode.split('/').last.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFFFF4655),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 4),
              Text(
                details.matchInfo.mapId.split('/').last,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                '${details.matchInfo.gameDuration.inMinutes} min | '
                '${details.roundResults.length} rounds',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'SCOREBOARD',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5),
        ),
        const SizedBox(height: 10),

        // Players
        ...details.players
            .map((p) => _PlayerRow(player: p))
            ,
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});
  final PlayerStats player;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A3540)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              player.displayName.isNotEmpty
                  ? player.displayName
                  : player.puuid.substring(0, 8),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${player.kills}/${player.deaths}/${player.assists}',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(
              '${player.averageScore.toStringAsFixed(0)} ACS',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
