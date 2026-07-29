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

  /// Converts Riot's raw map path to a readable name.
  /// e.g. "/Game/Maps/Ascent/Ascent" → "Ascent"
  /// e.g. "BOMBGAMEMODE.BOMBGAMEMODE_C" → "Unknown Map"
  String _mapName(String rawMapId) {
    if (rawMapId.isEmpty) return 'Unknown Map';
    // Riot map paths end with the map name: /Game/Maps/Ascent/Ascent
    final parts = rawMapId.split('/');
    final last = parts.last;
    if (last.isEmpty || last.contains('.')) return 'Unknown Map';
    return last;
  }

  /// Converts raw game mode path to readable name.
  String _modeName(String rawMode) {
    if (rawMode.isEmpty) return 'Unknown Mode';
    final parts = rawMode.split('/');
    final last = parts.last.toLowerCase();
    switch (last) {
      case 'competitive': return 'Competitive';
      case 'unrated': return 'Unrated';
      case 'spikerush': return 'Spike Rush';
      case 'deathmatch': return 'Deathmatch';
      case 'ggteam': return 'Escalation';
      case 'onefa': return 'Replication';
      case 'hurm': return 'Team Deathmatch';
      case 'swiftplay': return 'Swiftplay';
      case 'newmap': return 'New Map';
      default:
        // Handle UE path like ShooterGame.ShooterGameMode_C
        if (last.contains('.')) return 'Unknown Mode';
        return last[0].toUpperCase() + last.substring(1);
    }
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
                _modeName(details.matchInfo.gameMode).toUpperCase(),
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
