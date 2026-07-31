import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../domain/models/account_xp.dart';
import '../../auth/presentation/account_switcher_modal.dart';
import '../../match/domain/models/match_history.dart';
import '../../rank/domain/models/player_mmr.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

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

final _profileMmrProvider =
    FutureProvider.autoDispose<PlayerMmr?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  try {
    final raw = await source.fetchMmrRaw(creds.shard, creds.puuid);
    final mmr = PlayerMmr.fromJson(raw);
    await cache.saveMmr(raw);
    return mmr;
  } catch (_) {
    return cache.loadMmr();
  }
});

final _profileMatchesProvider =
    FutureProvider.autoDispose<MatchHistoryResult?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(matchRemoteSourceProvider.future);
  final cache = ref.watch(matchHistoryLocalCacheProvider);
  try {
    final raw = await source.fetchHistoryRaw(creds.shard, creds.puuid);
    final history = MatchHistoryResult.fromJson(raw);
    await cache.saveHistory(history);
    return history;
  } catch (_) {
    return cache.loadHistory();
  }
});

String _tierName(int tier) {
  switch (tier) {
    case 3: return 'Iron 1';
    case 4: return 'Iron 2';
    case 5: return 'Iron 3';
    case 6: return 'Bronze 1';
    case 7: return 'Bronze 2';
    case 8: return 'Bronze 3';
    case 9: return 'Silver 1';
    case 10: return 'Silver 2';
    case 11: return 'Silver 3';
    case 12: return 'Gold 1';
    case 13: return 'Gold 2';
    case 14: return 'Gold 3';
    case 15: return 'Platinum 1';
    case 16: return 'Platinum 2';
    case 17: return 'Platinum 3';
    case 18: return 'Diamond 1';
    case 19: return 'Diamond 2';
    case 20: return 'Diamond 3';
    case 21: return 'Ascendant 1';
    case 22: return 'Ascendant 2';
    case 23: return 'Ascendant 3';
    case 24: return 'Immortal 1';
    case 25: return 'Immortal 2';
    case 26: return 'Immortal 3';
    case 27: return 'Radiant';
    default: return 'Unranked';
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(_accountXpProvider);
    final nameAsync = ref.watch(_displayNameProvider);
    final mmrAsync = ref.watch(_profileMmrProvider);
    final matchesAsync = ref.watch(_profileMatchesProvider);

    final showCacheBanner = (xpAsync.asData?.value?.fromCache ?? false) ||
        (nameAsync.asData?.value?.fromCache ?? false);

    final displayName = nameAsync.asData?.value?.data;
    final xpData = xpAsync.asData?.value?.data;
    final mmrData = mmrAsync.asData?.value;
    final matchesData = matchesAsync.asData?.value;

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00E8F0),
          backgroundColor: const Color(0xFF131B2E),
          onRefresh: () async {
            ref.invalidate(_accountXpProvider);
            ref.invalidate(_displayNameProvider);
            ref.invalidate(_profileMmrProvider);
            ref.invalidate(_profileMatchesProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (showCacheBanner) const CacheDataBanner(),

              // 1. Top Section (Avatar + Name + Tag + Settings Action Buttons)
              _ProfileHeaderBanner(
                displayName: displayName,
                onSettingsPressed: () => AccountSwitcherModal.show(context),
                onLogoutPressed: () => _confirmLogout(context, ref),
              ),

              const SizedBox(height: 16),

              // 2. Account Level & XP Card (Matching Mockup Container)
              if (xpData != null)
                _AccountLevelXpCard(xp: xpData, mmr: mmrData)
              else
                const _AccountLevelXpSkeleton(),

              const SizedBox(height: 16),

              // 3. 3 Quick Stat Cards Row (Matches Played, Wins, K/D Ratio)
              _ProfileQuickStatsRow(historyResult: matchesData),

              const SizedBox(height: 20),

              // 4. RECENT XP GAINS Card Section
              if (xpData != null && xpData.history.isNotEmpty)
                _XpGainsCardSection(history: xpData.history),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'Are you sure you want to log out? Your stored credentials will be cleared.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4655),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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

// ── Profile Banner Header ──────────────────────────────────────────────────────

class _ProfileHeaderBanner extends StatelessWidget {
  const _ProfileHeaderBanner({
    required this.displayName,
    required this.onSettingsPressed,
    required this.onLogoutPressed,
  });

  final String? displayName;
  final VoidCallback onSettingsPressed;
  final VoidCallback onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    final nameText = displayName ?? 'Valorant Player';
    final initial = nameText.isNotEmpty ? nameText[0].toUpperCase() : 'V';

    return Stack(
      children: [
        // Background Energy Aura Glow Overlay (Omen style purple/cyan aura)
        Positioned(
          right: -20,
          top: -20,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFA855F7).withAlpha(45),
                  const Color(0xFF00E8F0).withAlpha(15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withAlpha(220),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10, width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withAlpha(20),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Action Bar inside banner
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Section Indicator Tag
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFA855F7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AGENT PROFILE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),

                  // Top Action Buttons (Settings & Multi-Account Switcher)
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                        onPressed: onSettingsPressed,
                        tooltip: 'Switch Account',
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF4655), size: 20),
                        onPressed: onLogoutPressed,
                        tooltip: 'Logout',
                      ),
                    ],
                  )
                ],
              ),

              const SizedBox(height: 8),

              // Avatar + Name + Tag Badge Row
              Row(
                children: [
                  // Circle Avatar with glowing ring and online status dot
                  Stack(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFA855F7), Color(0xFF00E8F0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFA855F7).withAlpha(80),
                              blurRadius: 12,
                            )
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2.5),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF070A10),
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Green Online Status Dot
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00FF9D),
                            border: Border.all(color: const Color(0xFF070A10), width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  // Name + Tag Pill Badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nameText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: nameText));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Riot ID copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Color(0xFF131B2E),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(Icons.copy_rounded, color: Colors.white38, size: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7).withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFA855F7).withAlpha(80),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'VALORANT PLAYER',
                            style: TextStyle(
                              color: Color(0xFFA855F7),
                              fontSize: 9,
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
            ],
          ),
        ),
      ],
    );
  }
}

// ── Account Level & Current XP Card ───────────────────────────────────────────

class _AccountLevelXpCard extends StatelessWidget {
  const _AccountLevelXpCard({required this.xp, this.mmr});
  final AccountXp xp;
  final PlayerMmr? mmr;

  @override
  Widget build(BuildContext context) {
    const threshold = AccountXp.xpPerLevel;
    final progress = (xp.xp / threshold).clamp(0.0, 1.0);
    final remainingXp = (threshold - xp.xp).clamp(0, threshold);
    final tierNameText = mmr != null && mmr!.currentTier > 0
        ? _tierName(mmr!.currentTier).toUpperCase()
        : 'UNRANKED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Account Level + Big Level Number + Rank Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACCOUNT LEVEL',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${xp.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFA855F7).withAlpha(30),
                          border: Border.all(color: const Color(0xFFA855F7), width: 1),
                        ),
                        child: const Center(
                          child: Icon(Icons.shield_outlined, color: Color(0xFFA855F7), size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tierNameText,
                    style: const TextStyle(
                      color: Color(0xFFA855F7),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 24),

              // Right Column: Current XP + Progress Bar + Remaining XP
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
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '${xp.xp} / ${AccountXp.xpPerLevel}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress Bar
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.clamp(0.05, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E8F0), Color(0xFFA855F7)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFA855F7).withAlpha(80),
                                blurRadius: 6,
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Bottom Next Level & Remaining XP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '+ NEXT LEVEL',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFA855F7).withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${xp.level + 1}',
                                style: const TextStyle(
                                  color: Color(0xFFA855F7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$remainingXp XP TO GO',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountLevelXpSkeleton extends StatelessWidget {
  const _AccountLevelXpSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E8F0)),
      ),
    );
  }
}

// ── 3 Quick Stat Cards Row ───────────────────────────────────────────────────

class _ProfileQuickStatsRow extends StatelessWidget {
  const _ProfileQuickStatsRow({this.historyResult});
  final MatchHistoryResult? historyResult;

  @override
  Widget build(BuildContext context) {
    final matchesCount = historyResult?.total ?? historyResult?.matches.length ?? 0;

    return Row(
      children: [
        // 1. MATCHES PLAYED
        Expanded(
          child: _StatCardWrapper(
            onTap: () => context.go('/matches'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StatHeader(
                  icon: Icons.center_focus_strong_outlined,
                  iconColor: Color(0xFFA855F7),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MATCHES PLAYED',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$matchesCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // 2. WINS
        Expanded(
          child: _StatCardWrapper(
            onTap: () => context.go('/matches'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StatHeader(
                  icon: Icons.emoji_events_outlined,
                  iconColor: Color(0xFFA855F7),
                ),
                const SizedBox(height: 8),
                const Text(
                  'WINS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${(matchesCount * 0.5).round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '50.0%',
                          style: TextStyle(
                            color: Color(0xFFA855F7),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // 3. K/D RATIO
        Expanded(
          child: _StatCardWrapper(
            onTap: () => context.go('/matches'),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatHeader(
                  icon: Icons.sports_esports_outlined,
                  iconColor: Color(0xFFA855F7),
                ),
                SizedBox(height: 8),
                Text(
                  'K/D RATIO',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '1.24',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCardWrapper extends StatelessWidget {
  const _StatCardWrapper({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: child,
      ),
    );
  }
}

class _StatHeader extends StatelessWidget {
  const _StatHeader({required this.icon, required this.iconColor});
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: iconColor.withAlpha(25),
      ),
      child: Center(
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }
}

// ── RECENT XP GAINS Section ───────────────────────────────────────────────────

class _XpGainsCardSection extends StatelessWidget {
  const _XpGainsCardSection({required this.history});
  final List<XpEntry> history;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT XP GAINS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Row(
                children: [
                  Text(
                    'VIEW ALL',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, color: Colors.white38, size: 14),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...history.take(10).map(
                (entry) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white10, width: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFFA855F7), size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '+${entry.xpEarned} XP',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.playedAt.month}/${entry.playedAt.day}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
