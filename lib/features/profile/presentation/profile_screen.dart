import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/models/account_xp.dart';

final _accountXpProvider = FutureProvider.autoDispose<AccountXp?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  return source.fetchAccountXp(creds.shard, creds.puuid);
});

final _displayNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  return source.fetchDisplayName(creds.shard, creds.puuid);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(_accountXpProvider);
    final nameAsync = ref.watch(_displayNameProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
            onPressed: () => _confirmLogout(context, ref),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        onRefresh: () async {
          ref.invalidate(_accountXpProvider);
          ref.invalidate(_displayNameProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Profile header
            nameAsync.when(
              data: (name) => _ProfileHeader(displayName: name),
              loading: () => const _ProfileHeader(displayName: null),
              error: (_, __) => const _ProfileHeader(displayName: null),
            ),
            const SizedBox(height: 24),

            // Account XP
            xpAsync.when(
              data: (xp) => xp == null
                  ? const SizedBox()
                  : _XpCard(xp: xp),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 24),

            // XP history
            xpAsync.when(
              data: (xp) => xp == null || xp.history.isEmpty
                  ? const SizedBox()
                  : _XpHistorySection(history: xp.history),
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: const Text('Logout',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure? You will need to login again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4655)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = await ref.read(authRepositoryProvider.future);
              await repo.logout();
              ref.invalidate(currentCredentialsProvider);
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.displayName});
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: const Color(0xFF1A2634),
          child: Text(
            displayName?.substring(0, 1).toUpperCase() ?? '?',
            style: const TextStyle(
                color: Color(0xFFFF4655),
                fontSize: 24,
                fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName ?? 'Loading...',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const Text(
              'Valorant Player',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({required this.xp});
  final AccountXp xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2634), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3D4C5E)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LEVEL',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.5)),
              Text(
                '${xp.level}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account XP',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (xp.xp % 10000) / 10000,
                    backgroundColor: const Color(0xFF0F1923),
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFF0BC4C4)),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${xp.xp % 10000} / 10,000 XP',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _XpHistorySection extends StatelessWidget {
  const _XpHistorySection({required this.history});
  final List<XpEntry> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT XP GAINS',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5),
        ),
        const SizedBox(height: 10),
        ...history.take(10).map((entry) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2634),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_outline,
                      color: Color(0xFF0BC4C4), size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '+${entry.xpEarned} XP',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Text(
                    '${entry.playedAtTime.month}/${entry.playedAtTime.day}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
