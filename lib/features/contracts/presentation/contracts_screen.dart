import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
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

// Contract definitions: contractUuid → { agentUuid, displayName, displayIcon }
final _contractDefsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getContractDefsMap();
});

// Agents map for portrait lookup
final _contractAgentsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getAgentsMap();
});

// Missions map: missionUuid → { title, xpGrant, progressToComplete }
final _missionsMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getMissionsMap();
});

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(_contractsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        title: const Text('PROGRESS',
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
        color: AppColors.red,
        backgroundColor: AppColors.bgCard2,
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
          loading: () => const ContractsSkeleton(),
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

class _BattlepassCard extends ConsumerWidget {
  const _BattlepassCard({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = contract.progressionTowardsNextLevel / 10000;
    // Fetch battlepass banner art from contract defs
    final defsAsync = ref.watch(_contractDefsProvider);
    final contractDef = defsAsync.asData?.value[contract.contractId] as Map<String, dynamic>?;
    final bannerUrl = contractDef?['displayIcon'] as String?;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withAlpha(90), width: 1),
        gradient: AppColors.cardGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner art header
          if (bannerUrl != null && bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: SizedBox(
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(bannerUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: AppColors.bgCard2)),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.bgCard.withAlpha(200),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.red.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.military_tech,
                          color: AppColors.red, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BATTLE PASS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 2),
                        Text('TIER ${contract.progressionLevelReached}',
                            style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('XP PROGRESSION',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    Text(
                      '${contract.progressionTowardsNextLevel.clamp(0, 10000)} / 10,000 XP',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: AppColors.bgCard2,
                    valueColor: const AlwaysStoppedAnimation(AppColors.red),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => BattlepassCarouselModal.show(context, contract),
                    icon: const Icon(Icons.view_carousel, color: AppColors.red, size: 18),
                    label: const Text('VIEW BATTLE PASS REWARDS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
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

class _MissionTile extends ConsumerWidget {
  const _MissionTile({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsMap = ref.watch(_missionsMapProvider).asData?.value ?? {};
    // Resolve title from valorant-api.com — fallback to what the API gave us
    final resolvedTitle = (missionsMap[mission.missionId]?['title'] as String?)
        ?.isNotEmpty == true
        ? missionsMap[mission.missionId]!['title'] as String
        : mission.title;
    final progress = mission.progressFraction;
    final expiryStr = mission.expirationTime != null
        ? 'Expires ${DateFormat('MMM d').format(mission.expirationTime!)}'
        : null;
    // Determine daily vs weekly from expiry window
    final isDaily = mission.expirationTime != null &&
        mission.expirationTime!.difference(DateTime.now()).inHours <= 28;
    final typeIcon = isDaily ? Icons.wb_sunny_outlined : Icons.calendar_month_outlined;
    final typeLabel = isDaily ? 'DAILY' : 'WEEKLY';
    final xpReward = mission.xpGrant > 0 ? mission.xpGrant : null;

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
                mission.isCompleted ? Icons.check_circle : typeIcon,
                color: mission.isCompleted
                    ? AppColors.win
                    : AppColors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(typeLabel,
                    style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resolvedTitle,
                  style: TextStyle(
                    color: mission.isCompleted ? AppColors.textMuted : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: mission.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (xpReward != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.rpAmber.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.rpAmber.withAlpha(80), width: 0.8),
                  ),
                  child: Text('+${_fmtXp(xpReward)} XP',
                      style: const TextStyle(
                          color: AppColors.rpAmber,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              if (expiryStr != null) ...[
                const SizedBox(width: 6),
                Text(expiryStr,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
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
                      color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: AppColors.bgCard2,
                valueColor: const AlwaysStoppedAnimation(AppColors.red),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtXp(int xp) =>
      xp >= 1000 ? '${(xp / 1000).toStringAsFixed(0)}k' : '$xp';
}


// ── Agent Contract Tile ───────────────────────────────────────────────────────

class _AgentContractTile extends ConsumerWidget {
  const _AgentContractTile({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = (contract.progressionTowardsNextLevel / 10000.0).clamp(0.0, 1.0);

    // Two-step lookup: contractDefs gives us agentUuid, agentsMap gives us portrait
    final contractDefsAsync = ref.watch(_contractDefsProvider);
    final agentsAsync = ref.watch(_contractAgentsProvider);

    final contractDef = contractDefsAsync.asData?.value[contract.contractId]
        as Map<String, dynamic>?;
    final agentUuid = contractDef?['agentUuid'] as String?;
    final agentInfo = agentUuid != null
        ? agentsAsync.asData?.value[agentUuid] as Map<String, dynamic>?
        : null;

    final agentName = agentInfo?['displayName'] as String? ??
        contractDef?['displayName'] as String?;
    final agentPortrait = agentInfo?['displayIcon'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.bgCard2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: agentPortrait != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      agentPortrait,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_outline, color: Colors.white24, size: 22),
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
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TIER ${contract.progressionLevelReached}',
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                    Text(
                      '${contract.progressionTowardsNextLevel.clamp(0, 10000)} / 10,000 XP',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.bgCard2,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.red),
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
