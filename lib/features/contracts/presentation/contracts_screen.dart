import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../domain/models/contracts.dart';
import 'battlepass_carousel_modal.dart';

final _contractsProvider =
    FutureProvider.autoDispose<CachedFetchResult<PlayerContracts>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(contractsRemoteSourceProvider.future);
  final cache = ref.watch(contractsLocalCacheProvider);
  try {
    final raw = await source.fetchContractsRaw(creds.shard, creds.puuid);
    final contracts = PlayerContracts.fromJson(raw);
    await cache.saveContracts(raw);
    return CachedFetchResult(contracts);
  } catch (_) {
    final cached = await cache.loadContracts();
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

// Contract definitions metadata from valorant-api
final _contractDefsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  final agentsMap = await assets.getAgentsMap();
  return agentsMap;
});

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(_contractsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text('ACT PROGRESS & MISSIONS',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () => ref.invalidate(_contractsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF141F2D),
        onRefresh: () async => ref.invalidate(_contractsProvider),
        child: contractsAsync.when(
          data: (result) => result == null
              ? const Center(
                  child: Text('Not logged in.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)))
              : _ContractsContent(
                  contracts: result.data,
                  showCacheBanner: result.fromCache,
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

class _ContractsContent extends StatelessWidget {
  const _ContractsContent({
    required this.contracts,
    this.showCacheBanner = false,
  });
  final PlayerContracts contracts;
  final bool showCacheBanner;

  @override
  Widget build(BuildContext context) {
    final battlepass = contracts.activeBattlepass;
    final missions = contracts.missions;
    // Agent contracts = all contracts that are NOT the active battlepass
    final agentContracts = contracts.contracts
        .where((c) =>
            c.contractId != contracts.activeSpecialContractId &&
            c.progressionLevelReached > 0)
        .toList()
      ..sort((a, b) =>
          b.progressionLevelReached.compareTo(a.progressionLevelReached));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (showCacheBanner) const CacheDataBanner(),

        // Battle Pass
        if (battlepass != null) ...[
          const _SectionHeader(title: 'BATTLE PASS'),
          _BattlepassCard(contract: battlepass),
          const SizedBox(height: 24),
        ],

        // Active Missions
        if (missions.isNotEmpty) ...[
          const _SectionHeader(title: 'ACTIVE MISSIONS'),
          ...missions.map((m) => _MissionTile(mission: m)),
          const SizedBox(height: 24),
        ],

        // Agent Contracts
        if (agentContracts.isNotEmpty) ...[
          const _SectionHeader(title: 'AGENT CONTRACTS'),
          ...agentContracts.take(10).map(
              (c) => _AgentContractTile(contract: c)),
          const SizedBox(height: 24),
        ],

        if (battlepass == null && missions.isEmpty && agentContracts.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 60),
              child: Text('No active contracts or missions.',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          ),

        const SizedBox(height: 80),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: const Color(0xFFFF4655)),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BattlepassCard extends StatelessWidget {
  const _BattlepassCard({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final progress = contract.progressionTowardsNextLevel / 10000;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF4655).withAlpha(90), width: 1),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141F2D), Color(0xFF0E1622)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4655).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.military_tech,
                    color: Color(0xFFFF4655), size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BATTLE PASS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'TIER LEVEL ${contract.progressionLevelReached}',
                    style: const TextStyle(
                      color: Color(0xFF00F0FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'XP PROGRESSION',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                '${contract.progressionTowardsNextLevel.clamp(0, 10000)} / 10,000 XP',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF070A10),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFF4655)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF4655)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                BattlepassCarouselModal.show(context, contract);
              },
              icon: const Icon(Icons.view_carousel, color: Color(0xFFFF4655), size: 18),
              label: const Text(
                'VIEW BATTLE PASS ITEMS & CAROUSEL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final progress = mission.progressFraction;
    final expiryStr = mission.expirationTime != null
        ? 'Expires ${DateFormat('MMM d').format(mission.expirationTime!)}'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mission.isCompleted
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: mission.isCompleted
                    ? const Color(0xFF10B981)
                    : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mission.title,
                  style: TextStyle(
                    color: mission.isCompleted ? Colors.white54 : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: mission.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (expiryStr != null)
                Text(
                  expiryStr,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          if (!mission.isCompleted) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(),
                Text(
                  '${mission.currentProgress} / ${mission.progressToComplete}',
                  style: const TextStyle(
                    color: Color(0xFF00F0FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF141F2D),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00F0FF)),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


// ── Agent Contract Tile ───────────────────────────────────────────────────────

class _AgentContractTile extends ConsumerWidget {
  const _AgentContractTile({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        (contract.progressionTowardsNextLevel / 10000.0).clamp(0.0, 1.0);

    // Try to look up agent portrait from the contract UUID
    final agentsAsync = ref.watch(_contractDefsProvider);
    final agentInfo = agentsAsync.asData?.value[contract.contractId]
        as Map<String, dynamic>?;
    final agentName = agentInfo?['displayName'] as String?;
    final agentPortrait = agentInfo?['displayIcon'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 0.8),
      ),
      child: Row(
        children: [
          // Agent portrait or placeholder
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF141F2D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10, width: 0.8),
            ),
            child: agentPortrait != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      agentPortrait,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_outline,
                          color: Colors.white24,
                          size: 22),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.person_outline,
                        color: Colors.white24, size: 22),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agentName ?? 'Agent Contract',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TIER ${contract.progressionLevelReached}',
                      style: const TextStyle(
                          color: Color(0xFF00F0FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${contract.progressionTowardsNextLevel.clamp(0, 10000)} / 10,000 XP',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFF141F2D),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00F0FF)),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
