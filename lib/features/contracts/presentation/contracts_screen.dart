import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/di/providers.dart';
import '../domain/models/contracts.dart';

final _contractsProvider =
    FutureProvider.autoDispose<PlayerContracts?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(contractsRemoteSourceProvider.future);
  return source.fetchContracts(creds.shard, creds.puuid);
});

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(_contractsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Progress',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () => ref.invalidate(_contractsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        onRefresh: () async => ref.invalidate(_contractsProvider),
        child: contractsAsync.when(
          data: (contracts) => contracts == null
              ? const Center(
                  child: Text('Not logged in.',
                      style: TextStyle(color: Colors.white54)))
              : _ContractsContent(contracts: contracts),
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

class _ContractsContent extends StatelessWidget {
  const _ContractsContent({required this.contracts});
  final PlayerContracts contracts;

  @override
  Widget build(BuildContext context) {
    final battlepass = contracts.activeBattlepass;
    final missions = contracts.missions;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Battlepass
        if (battlepass != null) ...[
          const _SectionHeader(title: 'Battle Pass'),
          _BattlepassCard(contract: battlepass),
          const SizedBox(height: 24),
        ],

        // Active missions
        if (missions.isNotEmpty) ...[
          const _SectionHeader(title: 'Active Missions'),
          ...missions.map((m) => _MissionTile(mission: m)),
        ],

        if (battlepass == null && missions.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 60),
              child: Text('No active contracts or missions.',
                  style: TextStyle(color: Colors.white54)),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2634), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3D4C5E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech,
                  color: Color(0xFFFF4655), size: 24),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Battle Pass',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Level ${contract.progressionLevelReached}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF0F1923),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFF4655)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${contract.progressionTowardsNextLevel.clamp(0, 10000)} / 10,000 XP',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
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
    final progress = mission.progressToComplete > 0
        ? mission.progressionStatus / mission.progressToComplete
        : 0.0;
    final expiryStr = mission.expirationTime != null
        ? 'Expires ${DateFormat('MMM d').format(mission.expirationTime!)}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: mission.isCompleted
              ? const Color(0xFF4CAF50).withAlpha(80)
              : const Color(0xFF3D4C5E),
        ),
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
                    ? const Color(0xFF4CAF50)
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
                    decoration: mission.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (expiryStr != null)
                Text(expiryStr,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
            ],
          ),
          if (!mission.isCompleted) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF0F1923),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF0BC4C4)),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${mission.progressionStatus} / ${mission.progressToComplete}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
