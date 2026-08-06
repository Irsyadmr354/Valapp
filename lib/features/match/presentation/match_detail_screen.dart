import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/match_details.dart';
import '../domain/models/match_history.dart';

final _mapsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMapsMap();
});

final _detailAgentsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getAgentsMap();
});

final _detailTiersMapProvider =
    FutureProvider.autoDispose<Map<int, Map<String, dynamic>>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getCompetitiveTiersMap();
});

final _matchDetailFamily = FutureProvider.autoDispose
    .family<CachedFetchResult<MatchDetails>?, String>((ref, matchId) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchDetailLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);

  Future<MatchDetails> resolveNamesIfNeeded(MatchDetails details) async {
    var updated = details;
    final missingPuuids = updated.players
        .where((p) => p.displayName.isEmpty)
        .map((p) => p.puuid)
        .where((id) => id.isNotEmpty)
        .toList();

    if (missingPuuids.isNotEmpty) {
      try {
        final accountSource =
            await ref.watch(accountRemoteSourceProvider.future);
        final namesMap =
            await accountSource.fetchDisplayNames(creds.shard, missingPuuids);
        if (namesMap.isNotEmpty) {
          updated = updated.copyWithResolvedNames(namesMap);
        }
      } catch (_) {}
    }
    return updated;
  }

  try {
    final raw = await source.fetchMatchDetailsRaw(creds.shard, matchId);
    var details = MatchDetails.fromJson(raw);
    details = await resolveNamesIfNeeded(details);

    if (transaction != null) {
      await cache.saveMatchDetail(matchId, raw,
          puuid: creds.puuid, transaction: transaction);
    }
    return CachedFetchResult(details);
  } catch (_) {
    final cachedRaw =
        await cache.loadMatchDetailRaw(matchId, puuid: creds.puuid);
    if (cachedRaw != null) {
      var details = MatchDetails.fromJson(cachedRaw);
      details = await resolveNamesIfNeeded(details);
      return CachedFetchResult(details, fromCache: true);
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
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
        loading: () => const MatchDetailSkeleton(),
        error: (e, _) => Center(
          child:
              Text('Error: $e', style: const TextStyle(color: Colors.white54)),
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
    final name = MatchHistoryEntry.mapDisplayNameFromId(rawMap);
    return name.isNotEmpty ? name : rawMap;
  }

  String _modeName(String rawMode, String queueId) {
    if (queueId.isNotEmpty) {
      switch (queueId.toLowerCase()) {
        case 'competitive':
          return 'Competitive';
        case 'unrated':
          return 'Unrated';
        case 'spikerush':
          return 'Spike Rush';
        case 'deathmatch':
          return 'Deathmatch';
        case 'ggteam':
          return 'Escalation';
        case 'onefa':
          return 'Replication';
        case 'hurm':
          return 'Team Deathmatch';
        case 'swiftplay':
          return 'Swiftplay';
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
            p.teamId.toLowerCase() != 'red' && p.teamId.toLowerCase() != 'blue')
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final mapsAsync = ref.watch(_mapsMapProvider);
    final mapsMap = mapsAsync.asData?.value ?? {};

    final rawMap = details.matchInfo.mapId.toLowerCase();
    final lastSeg = rawMap.split('/').last.split('.').first;
    final mapInfo = mapsMap[rawMap] as Map<String, dynamic>? ??
        mapsMap[lastSeg] as Map<String, dynamic>?;

    final mapName =
        mapInfo?['displayName'] as String? ?? _mapName(details.matchInfo.mapId);
    final splashUrl = mapInfo?['splash'] as String? ??
        mapInfo?['listViewIcon'] as String? ??
        mapInfo?['displayIcon'] as String?;

    final matchMvpPuuid = details.players
            .fold<PlayerStats?>(
                null,
                (prev, curr) =>
                    (prev == null || curr.score > prev.score) ? curr : prev)
            ?.puuid ??
        '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showCacheBanner) const CacheDataBanner(),
        // Match info header with Map Splash Artwork Background
        Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.bgCard2,
            border: Border.all(color: AppColors.red.withAlpha(80), width: 1),
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
                      placeholder: (_, __) =>
                          Container(color: const Color(0xFF141F2D)),
                      errorWidget: (_, __, ___) =>
                          Container(color: const Color(0xFF141F2D)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4655),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _modeName(details.matchInfo.gameMode,
                                  details.matchInfo.queueId)
                              .toUpperCase(),
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
            color: const Color(0xFF3B82F6),
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

class _PlayerRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsMap = ref.watch(_detailAgentsMapProvider).asData?.value ?? {};
    final tiersMap = ref.watch(_detailTiersMapProvider).asData?.value ?? {};

    final agentInfo = player.agentId.isNotEmpty
        ? agentsMap[player.agentId] as Map<String, dynamic>?
        : null;
    final agentIconUrl = agentInfo?['displayIcon'] as String?;

    final tierData =
        player.competitiveTier > 0 ? tiersMap[player.competitiveTier] : null;
    final rankIconUrl = tierData?['displayIcon'] as String? ??
        tierData?['smallIcon'] as String?;

    final color = accentColor ?? Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // Agent portrait
          if (agentIconUrl != null && agentIconUrl.isNotEmpty)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgCard2,
                border: Border.all(color: color.withAlpha(80), width: 1),
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: agentIconUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(),
                ),
              ),
            )
          else
            const SizedBox(width: 40),
          // Name + MVP badges
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMatchMvp) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withAlpha(40),
                      border: Border.all(
                          color: const Color(0xFFFFD700), width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('MATCH MVP',
                        style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 8,
                            fontWeight: FontWeight.w900)),
                  ),
                ] else if (isTeamMvp) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppColors.red.withAlpha(30),
                      border: Border.all(color: AppColors.red, width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('TEAM MVP',
                        style: TextStyle(
                            color: AppColors.red,
                            fontSize: 8,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
          // Rank icon (competitive matches)
          if (rankIconUrl != null && rankIconUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CachedNetworkImage(
                imageUrl: rankIconUrl,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
          // K/D/A
          Text(
            '${player.kills}/${player.deaths}/${player.assists}',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 42,
            child: Text(
              player.averageScore.toStringAsFixed(0),
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
