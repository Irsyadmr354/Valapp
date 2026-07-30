import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../domain/models/match_details.dart';

final _mapsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMapsMap();
});

final _matchDetailFamily = FutureProvider.autoDispose
    .family<CachedFetchResult<MatchDetails>?, String>((ref, matchId) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchDetailLocalCacheProvider);
  try {
    final raw = await source.fetchMatchDetailsRaw(creds.shard, matchId);
    var details = MatchDetails.fromJson(raw);

    final missingPuuids = details.players
        .where((p) => p.displayName.isEmpty)
        .map((p) => p.puuid)
        .where((id) => id.isNotEmpty)
        .toList();

    if (missingPuuids.isNotEmpty) {
      try {
        final accountSource =
            await ref.watch(accountRemoteSourceProvider.future);
        final namesMap = await accountSource.fetchDisplayNames(
            creds.shard, missingPuuids);
        if (namesMap.isNotEmpty) {
          details = details.copyWithResolvedNames(namesMap);
        }
      } catch (_) {}
    }

    await cache.saveMatchDetail(matchId, raw);
    return CachedFetchResult(details);
  } catch (_) {
    final cachedRaw = await cache.loadMatchDetailRaw(matchId);
    if (cachedRaw != null) {
      return CachedFetchResult(MatchDetails.fromJson(cachedRaw),
          fromCache: true);
    }
    rethrow;
  }
});

class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_matchDetailFamily(matchId));

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text('MATCH DETAILS',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
      ),
      body: detailAsync.when(
        data: (result) => result == null
            ? const Center(
                child: Text('Match not found.',
                    style: TextStyle(color: Colors.white38)))
            : _MatchDetailsContent(
                details: result.data,
                showCacheBanner: result.fromCache,
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4655)),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }
}

class _MatchDetailsContent extends ConsumerWidget {
  const _MatchDetailsContent({
    required this.details,
    this.showCacheBanner = false,
  });
  final MatchDetails details;
  final bool showCacheBanner;

  String _mapName(String rawMap) {
    if (rawMap.isEmpty) return 'Unknown Map';
    final raw = rawMap.toLowerCase();

    if (raw.contains('plummet') || raw.contains('infinity') || raw.contains('abyss')) return 'Abyss';
    if (raw.contains('jam') || raw.contains('lotus')) return 'Lotus';
    if (raw.contains('juliett') || raw.contains('sunset')) return 'Sunset';
    if (raw.contains('canyon') || raw.contains('fracture')) return 'Fracture';
    if (raw.contains('port') || raw.contains('icebox')) return 'Icebox';
    if (raw.contains('lowpe') || raw.contains('pitt') || raw.contains('pearl')) return 'Pearl';
    if (raw.contains('foxtrot')) return 'Drift';
    if (raw.contains('triad') || raw.contains('haven')) return 'Haven';
    if (raw.contains('bonsai') || raw.contains('split')) return 'Split';
    if (raw.contains('duality') || raw.contains('bind')) return 'Bind';
    if (raw.contains('ascent')) return 'Ascent';
    if (raw.contains('breeze')) return 'Breeze';

    final parts = rawMap.split('/');
    final last = parts.last.split('.').first;
    if (last.isEmpty) return rawMap;
    return last[0].toUpperCase() + last.substring(1);
  }

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
    if (lower.contains('competitive')) return 'Competitive';
    if (lower.contains('unrated')) return 'Unrated';
    if (lower.contains('spikerush')) return 'Spike Rush';
    if (lower.contains('deathmatch')) return 'Deathmatch';
    if (lower.contains('hurm')) return 'Team Deathmatch';
    if (lower.contains('swiftplay')) return 'Swiftplay';
    if (lower.contains('bomb')) return 'Standard Match';

    if (rawMode.isEmpty) return 'Standard Match';
    final parts = rawMode.split('/');
    final last = parts.last.split('.').first;
    if (last.isEmpty) return 'Standard Match';
    return last[0].toUpperCase() + last.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final mapName = _mapName(details.matchInfo.mapId);
    final mapsAsync = ref.watch(_mapsMapProvider);
    final mapInfo = mapsAsync.asData?.value[mapName.toLowerCase()];
    final splashUrl = mapInfo?['splash'] as String? ?? mapInfo?['listViewIcon'] as String?;

    final matchMvpPuuid = details.players.fold<PlayerStats?>(
        null, (prev, curr) => (prev == null || curr.score > prev.score) ? curr : prev)?.puuid ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showCacheBanner) const CacheDataBanner(),
        // Match info header with Map Splash Artwork Background
        Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF141F2D),
            border: Border.all(color: const Color(0xFFFF4655).withAlpha(80), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              children: [
                // Map Artwork Image Background
                if (splashUrl != null && splashUrl.isNotEmpty)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: splashUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      placeholder: (_, __) => Container(color: const Color(0xFF141F2D)),
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF141F2D)),
                    ),
                  ),

                // Dark Overlay for readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF070A10).withAlpha(240),
                          const Color(0xFF070A10).withAlpha(180),
                          const Color(0xFF070A10).withAlpha(100),
                        ],
                      ),
                    ),
                  ),
                ),

                // Text Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4655),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _modeName(details.matchInfo.gameMode, details.matchInfo.queueId).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mapName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${details.matchInfo.gameDuration.inMinutes} min'
                        '${details.roundResults.isNotEmpty ? ' • ${details.roundResults.length} rounds' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Team-based scoreboard
        if (redTeam.isNotEmpty && blueTeam.isNotEmpty) ...[
          _TeamSection(
            title: 'ATTACK',
            players: redTeam,
            color: const Color(0xFFFF4655),
            matchMvpPuuid: matchMvpPuuid,
          ),
          const SizedBox(height: 12),
          _TeamSection(
            title: 'DEFENSE',
            players: blueTeam,
            color: const Color(0xFF0BC4C4),
            matchMvpPuuid: matchMvpPuuid,
          ),
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
          ...others.map((p) => _PlayerRow(
                player: p,
                isMatchMvp: p.puuid == matchMvpPuuid,
              )),
          if (others.isEmpty)
            ...details.players.map((p) => _PlayerRow(
                  player: p,
                  isMatchMvp: p.puuid == matchMvpPuuid,
                )),
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
    required this.matchMvpPuuid,
  });

  final String title;
  final List<PlayerStats> players;
  final Color color;
  final String matchMvpPuuid;

  @override
  Widget build(BuildContext context) {
    final teamMvpPuuid = players.isNotEmpty ? players.first.puuid : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row with Column Titles
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              Container(width: 3, height: 12, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              const Text(
                'K / D / A',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 24),
              const SizedBox(
                width: 48,
                child: Text(
                  'ACS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        ...players.map((p) => _PlayerRow(
              player: p,
              accentColor: color,
              isMatchMvp: p.puuid == matchMvpPuuid,
              isTeamMvp: p.puuid == teamMvpPuuid && p.puuid != matchMvpPuuid,
            )),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    this.accentColor,
    this.isMatchMvp = false,
    this.isTeamMvp = false,
  });

  final PlayerStats player;
  final Color? accentColor;
  final bool isMatchMvp;
  final bool isTeamMvp;

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white10, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: accentColor ?? Colors.white38,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMatchMvp) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withAlpha(40),
                      border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'MATCH MVP',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ] else if (isTeamMvp) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F0FF).withAlpha(30),
                      border: Border.all(color: const Color(0xFF00F0FF), width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'TEAM MVP',
                      style: TextStyle(
                        color: Color(0xFF00F0FF),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${player.kills}/${player.deaths}/${player.assists}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 48,
            child: Text(
              player.averageScore.toStringAsFixed(0),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
