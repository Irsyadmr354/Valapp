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
          data: (contracts) => contracts == null
              ? const Center(
                  child: Text('Not logged in.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)))
              : _ContractsContent(contracts: contracts),
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
          const _SectionHeader(title: 'BATTLE PASS'),
          _BattlepassCard(contract: battlepass),
          const SizedBox(height: 28),
        ],

        // Active missions
        if (missions.isNotEmpty) ...[
          const _SectionHeader(title: 'ACTIVE MISSIONS'),
          ...missions.map((m) => _MissionTile(mission: m)),
        ],

        if (battlepass == null && missions.isEmpty)
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: mission.isCompleted
              ? const Color(0xFF10B981).withAlpha(100)
              : const Color(0xFF1B2738),
          width: 1,
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
            const SizedBox(height: 10),
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
                backgroundColor: const Color(0xFF070A10),
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

