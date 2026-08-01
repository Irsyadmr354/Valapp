import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_name_util.dart';
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

// Tier name resolution is delegated to TierNameUtil.

// ── Loadout provider (for player card background) ─────────────────────────────
final _profileLoadoutProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  // Returns the playerCardId from the equipped loadout, or null
  try {
    final creds = await ref.watch(currentCredentialsProvider.future);
    if (creds == null) return null;
    final source = await ref.watch(loadoutRemoteSourceProvider.future);
    final raw = await source.fetchLoadoutRaw(creds.shard, creds.puuid);
    final identity = raw['Identity'] as Map<String, dynamic>? ?? {};
    return identity['PlayerCardID'] as String?;
  } catch (_) {
    return null;
  }
});

final _profilePlayerCardsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getPlayerCardsMap());

// ── Main Screen ───────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(_accountXpProvider);
    final nameAsync = ref.watch(_displayNameProvider);
    final mmrAsync = ref.watch(_profileMmrProvider);
    final matchesAsync = ref.watch(_profileMatchesProvider);
    final cardIdAsync = ref.watch(_profileLoadoutProvider);
    final cardsMapAsync = ref.watch(_profilePlayerCardsProvider);

    final showCacheBanner = (xpAsync.asData?.value?.fromCache ?? false) ||
        (nameAsync.asData?.value?.fromCache ?? false);

    final displayName = nameAsync.asData?.value?.data;
    final xpData = xpAsync.asData?.value?.data;
    final mmrData = mmrAsync.asData?.value;
    final matchesData = matchesAsync.asData?.value;

    // Player card wideArt for header background
    final cardId = cardIdAsync.asData?.value;
    final cardsMap = cardsMapAsync.asData?.value ?? {};
    final cardInfo = cardId != null ? cardsMap[cardId] as Map<String, dynamic>? : null;
    final cardWideArt = cardInfo?['wideArt'] as String?;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.red,
          backgroundColor: AppColors.bgCard2,
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
                playerCardWideArt: cardWideArt,
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

              const SizedBox(height: 16),

              // 5. Equipped Loadout Quick-link card
              _LoadoutQuickLink(),

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
        backgroundColor: AppColors.bgCard2,
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
              backgroundColor: AppColors.red,
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
    this.playerCardWideArt,
  });

  final String? displayName;
  final String? playerCardWideArt;
  final VoidCallback onSettingsPressed;
  final VoidCallback onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    final nameText = displayName ?? 'Valorant Player';
    final initial = nameText.isNotEmpty ? nameText[0].toUpperCase() : 'V';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.redGlow(alpha: 0.10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          children: [
            // Player card wide art as background
            if (playerCardWideArt != null && playerCardWideArt!.isNotEmpty)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: playerCardWideArt!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorWidget: (_, __, ___) => const SizedBox(),
                ),
              ),
            // Dark overlay for readability
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bgCard2.withAlpha(playerCardWideArt != null ? 160 : 220),
                      AppColors.bgCard2.withAlpha(240),
                    ],
                  ),
                ),
              ),
            ),
            // Red radial glow top-right
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.red.withAlpha(45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top action bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.red,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('AGENT PROFILE',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.settings_outlined,
                                color: Colors.white70, size: 20),
                            onPressed: onSettingsPressed,
                            tooltip: 'Switch Account',
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.logout_rounded,
                                color: AppColors.red, size: 20),
                            onPressed: onLogoutPressed,
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Avatar with red ring
                      Stack(
                        children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.redGradient,
                              boxShadow: AppColors.redGlow(alpha: 0.35, blur: 14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2.5),
                              child: Container(
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle, color: AppColors.bg),
                                child: Center(
                                  child: Text(initial,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 2, bottom: 2,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.win,
                                border: Border.all(
                                    color: AppColors.bg, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(nameText,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.3),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: nameText));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Riot ID copied!'),
                                        duration: Duration(seconds: 2),
                                        backgroundColor: AppColors.bgCard2,
                                      ),
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.copy_rounded,
                                        color: Colors.white38, size: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.red.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.red.withAlpha(80),
                                    width: 0.8),
                              ),
                              child: const Text('VALORANT PLAYER',
                                  style: TextStyle(
                                      color: AppColors.red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8)),
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
        ),
      ),
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
        ? TierNameUtil.name(mmr!.currentTier).toUpperCase()
        : 'UNRANKED';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
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
                          color: AppColors.red.withAlpha(30),
                          border: Border.all(color: AppColors.red, width: 1),
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
                            gradient: AppColors.redGradient,
                            boxShadow: AppColors.redGlow(alpha: 0.25, blur: 6),
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
                                color: AppColors.red.withAlpha(40),
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
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.red),
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
    final matches = historyResult?.matches ?? [];
    final matchesCount = historyResult?.total ?? matches.length;
    final winsCount =
        matches.where((m) => m.result == MatchResult.victory).length;
    final winPct =
        matches.isNotEmpty ? (winsCount / matches.length * 100) : 0.0;

    // Compute real K/D from matches that carry stats
    final withStats = matches.where((m) => m.kills != null).toList();
    final totalKills =
        withStats.fold<int>(0, (s, m) => s + (m.kills ?? 0));
    final totalDeaths =
        withStats.fold<int>(0, (s, m) => s + (m.deaths ?? 0));
    final kd = totalDeaths > 0
        ? totalKills / totalDeaths
        : totalKills.toDouble();

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
                          '$winsCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${winPct.toStringAsFixed(1)}%',
                          style: const TextStyle(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StatHeader(
                  icon: Icons.sports_esports_outlined,
                  iconColor: Color(0xFFA855F7),
                ),
                const SizedBox(height: 8),
                const Text(
                  'K/D RATIO',
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
                      kd.toStringAsFixed(2),
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
          color: AppColors.bgCard2,
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
        color: AppColors.bgCard2,
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

// ── Loadout Quick-Link Card ───────────────────────────────────────────────────

class _LoadoutQuickLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/loadout'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.inventory_2_outlined,
                    color: AppColors.red, size: 22),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EQUIPPED LOADOUT',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'View your equipped weapon skins, sprays & identity',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.red, size: 20),
          ],
        ),
      ),
    );
  }
}
