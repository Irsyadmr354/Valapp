import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/models/match_details.dart';

final _matchDetailFamily =
    FutureProvider.autoDispose.family<MatchDetails?, String>(
        (ref, matchId) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final details = await source.fetchMatchDetails(creds.shard, matchId);

  // If any player display name is missing, batch resolve them via name-service
  final missingPuuids = details.players
      .where((p) => p.displayName.isEmpty)
      .map((p) => p.puuid)
      .where((id) => id.isNotEmpty)
      .toList();

  if (missingPuuids.isNotEmpty) {
    try {
      final accountSource = await ref.watch(accountRemoteSourceProvider.future);
      final namesMap = await accountSource.fetchDisplayNames(creds.shard, missingPuuids);
      if (namesMap.isNotEmpty) {
        return details.copyWithResolvedNames(namesMap);
      }
    } catch (_) {}
  }

  return details;
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
                child: Text('No data',
                    style: TextStyle(color: Colors.white54)))
            : _MatchDetailContent(details: details),
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white54)),
          ),
        ),
      ),
    );
  }
}

class _MatchDetailContent extends StatelessWidget {
  const _MatchDetailContent({required this.details});
  final MatchDetails details;

  String _mapName(String rawMapId) {
    if (rawMapId.isEmpty) return 'Unknown Map';

    // Lookup table: lowercase path → readable name
    const mapNames = {
      '/game/maps/ascent/ascent': 'Ascent',
      '/game/maps/bind/bind': 'Bind',
      '/game/maps/haven/haven': 'Haven',
      '/game/maps/split/split': 'Split',
      '/game/maps/fracture/canyon': 'Fracture',
      '/game/maps/breeze/breeze': 'Breeze',
      '/game/maps/icebox/port': 'Icebox',
      '/game/maps/lowpe/lowpe': 'Pearl',
      '/game/maps/jam/jam': 'Lotus',
      '/game/maps/juliett/juliett': 'Sunset',
      '/game/maps/infinity/infinity': 'Abyss',
      '/game/maps/pitt/pitt': 'Pearl',
      '/game/maps/foxtrot/foxtrot': 'Drift',
      '/game/maps/triad/triad': 'Haven',
      '/game/maps/range/range': 'The Range',
    };

    final normalized = rawMapId.toLowerCase();
    final match = mapNames[normalized];
    if (match != null) return match;

    // Fallback: try partial match
    for (final entry in mapNames.entries) {
      if (normalized.contains(entry.key.split('/').last)) {
        return entry.value;
      }
    }

    // Last resort: split and capitalize
    final parts = rawMapId.split('/');
    final last = parts.last;
    if (last.isEmpty || last.contains('.')) return 'Unknown Map';
    return last[0].toUpperCase() + last.substring(1);
  }

  /// Converts raw game mode path to readable name.
  String _modeName(String rawMode, String queueId) {
    if (queueId.isNotEmpty) {
      switch (queueId.toLowerCase()) {
        case 'competitive': return 'Competitive';
        case 'unrated': return 'Unrated';
        case 'spikerush': return 'Spike Rush';
        case 'deathmatch': return 'Deathmatch';
        case 'ggteam': return 'Escalation';
        case 'onefa': return 'Replication';
        case 'hurm': return 'Team Deathmatch';
        case 'swiftplay': return 'Swiftplay';
      }
    }

    final lower = rawMode.toLowerCase();
    if (lower.contains('bomb') || lower.contains('standard')) return 'Standard';
    if (lower.contains('deathmatch')) return 'Deathmatch';
    if (lower.contains('spikerush')) return 'Spike Rush';
    if (lower.contains('onefa')) return 'Replication';
    if (lower.contains('ggteam')) return 'Escalation';
    if (lower.contains('hurm')) return 'Team Deathmatch';
    if (lower.contains('swiftplay')) return 'Swiftplay';

    if (rawMode.isEmpty) return 'Custom Match';
    final parts = rawMode.split('/');
    final last = parts.last.split('.').first;
    if (last.isEmpty) return 'Custom Match';
    return last[0].toUpperCase() + last.substring(1);
  }


  @override
  Widget build(BuildContext context) {
    final redTeam = details.players
        .where((p) => p.teamId.toLowerCase() == 'red')
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final blueTeam = details.players
        .where((p) => p.teamId.toLowerCase() == 'blue')
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    // Non-team modes (DM etc)
    final others = details.players
        .where((p) =>
            p.teamId.toLowerCase() != 'red' &&
            p.teamId.toLowerCase() != 'blue')
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

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
                _modeName(details.matchInfo.gameMode, details.matchInfo.queueId).toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFFFF4655),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 4),
              Text(
                _mapName(details.matchInfo.mapId),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                '${details.matchInfo.gameDuration.inMinutes} min'
                '${details.roundResults.isNotEmpty ? ' · ${details.roundResults.length} rounds' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Team-based scoreboard
        if (redTeam.isNotEmpty && blueTeam.isNotEmpty) ...[
          _TeamSection(title: 'ATTACK', players: redTeam, color: const Color(0xFFFF4655)),
          const SizedBox(height: 12),
          _TeamSection(title: 'DEFENSE', players: blueTeam, color: const Color(0xFF0BC4C4)),
        ] else ...[
          const Text(
            'SCOREBOARD',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          ...others.map((p) => _PlayerRow(player: p)),
          if (others.isEmpty)
            ...details.players.map((p) => _PlayerRow(player: p)),
        ],

        const SizedBox(height: 80),
      ],
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.title,
    required this.players,
    required this.color,
  });

  final String title;
  final List<PlayerStats> players;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        ...players.map((p) => _PlayerRow(player: p, accentColor: color)),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, this.accentColor});
  final PlayerStats player;
  final Color? accentColor;

  String get _name {
    if (player.displayName.isNotEmpty && player.displayName != '#') {
      return player.displayName;
    }
    if (player.puuid.length >= 8) {
      return player.puuid.substring(0, 8).toUpperCase();
    }
    return 'Player';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: accentColor ?? Colors.white24,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _name,
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
            width: 52,
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
