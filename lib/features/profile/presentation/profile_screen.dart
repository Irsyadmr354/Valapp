import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../domain/models/account_xp.dart';

final _accountXpProvider =
    FutureProvider.autoDispose<CachedFetchResult<AccountXp>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  try {
    final raw = await source.fetchAccountXpRaw(creds.shard, creds.puuid);
    final xp = AccountXp.fromJson(raw);
    await cache.saveAccountXp(raw);
    return CachedFetchResult(xp);
  } catch (_) {
    final cached = await cache.loadAccountXp();
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

final _displayNameProvider =
    FutureProvider.autoDispose<CachedFetchResult<String>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  try {
    final name = await source.fetchDisplayName(creds.shard, creds.puuid);
    if (name != null && name.isNotEmpty) {
      await cache.saveDisplayName(creds.puuid, name);
      return CachedFetchResult(name);
    }
    throw StateError('Display name unavailable');
  } catch (_) {
    final cached = await cache.loadDisplayName(creds.puuid);
    if (cached != null && cached.isNotEmpty) {
      return CachedFetchResult(cached, fromCache: true);
    }
    if (creds.puuid.length >= 8) {
      return CachedFetchResult('Player (${creds.puuid.substring(0, 6)}...)');
    }
    return const CachedFetchResult('Valorant Player');
  }
});


class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(_accountXpProvider);
    final nameAsync = ref.watch(_displayNameProvider);
    final showCacheBanner = (xpAsync.asData?.value?.fromCache ?? false) ||
        (nameAsync.asData?.value?.fromCache ?? false);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070A10),
        title: const Text('AGENT PROFILE',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFF4655)),
            onPressed: () => _confirmLogout(context, ref),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF4655),
        backgroundColor: const Color(0xFF141F2D),
        onRefresh: () async {
          ref.invalidate(_accountXpProvider);
          ref.invalidate(_displayNameProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (showCacheBanner) const CacheDataBanner(),
            // Profile header
            nameAsync.when(
              data: (result) => _ProfileHeader(displayName: result?.data),
              loading: () => const _ProfileHeader(displayName: null),
              error: (_, __) => const _ProfileHeader(displayName: null),
            ),
            const SizedBox(height: 24),

            // Account XP
            xpAsync.when(
              data: (result) => result == null
                  ? const SizedBox()
                  : _XpCard(xp: result.data),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFFF4655)),
                ),
              ),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 28),

            // XP history
            xpAsync.when(
              data: (result) => result == null || result.data.history.isEmpty
                  ? const SizedBox()
                  : _XpHistorySection(history: result.data.history),
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
        backgroundColor: const Color(0xFF0E1622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Logout',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'Are you sure you want to log out? Your stored credentials will be cleared.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
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
              await CacheStorage.instance.clearAll();
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1B2738), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4655).withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFF4655), width: 1.5),
            ),
            child: Center(
              child: Text(
                displayName?.substring(0, 1).toUpperCase() ?? 'V',
                style: const TextStyle(
                  color: Color(0xFFFF4655),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName ?? 'Loading Agent...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF).withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'VALORANT PLAYER',
                    style: TextStyle(
                      color: Color(0xFF00F0FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
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

class _XpCard extends StatelessWidget {
  const _XpCard({required this.xp});
  final AccountXp xp;

  @override
  Widget build(BuildContext context) {
    // Progress.XP from Riot is XP earned within the current level (resets each level).
    // Each level requires 5,000 AP — see https://wiki.playvalorant.com/en-us/Account_Level
    final threshold = AccountXp.xpPerLevel;
    final progress = (xp.xp / threshold).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00F0FF).withAlpha(90), width: 1),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141F2D), Color(0xFF0E1622)],
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACCOUNT LEVEL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${xp.level}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CURRENT XP',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '${xp.xp} / ${AccountXp.xpPerLevel}',
                      style: const TextStyle(
                        color: Color(0xFF00F0FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFF070A10),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00F0FF)),
                    minHeight: 8,
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

class _XpHistorySection extends StatelessWidget {
  const _XpHistorySection({required this.history});
  final List<XpEntry> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 14, color: const Color(0xFFFF4655)),
            const SizedBox(width: 8),
            const Text(
              'RECENT XP GAINS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...history.take(10).map((entry) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFF00F0FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '+${entry.xpEarned} XP',
                      style: const TextStyle(
                        color: Color(0xFF00F0FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.playedAt.month}/${entry.playedAt.day}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

