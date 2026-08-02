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
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/account_xp.dart';
import '../../auth/presentation/account_switcher_modal.dart';
import 'account_health_modal.dart';
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
  // Delegate to shared enriched history provider — eliminates ~40 lines
  // of duplicated fetch + cache-only enrich logic.
  return ref.watch(enrichedMatchHistoryProvider.future);
});

// Tier name resolution is delegated to TierNameUtil.

// ── Player card art — delegates to shared provider ────────────────────────────
// _PlayerCardInfo wraps both art URLs for the profile header banner.

class _PlayerCardInfo {
  final String? wideArt;
  final String? smallArt;
  const _PlayerCardInfo({this.wideArt, this.smallArt});
}

final _profileCardProvider =
    FutureProvider.autoDispose<_PlayerCardInfo?>((ref) async {
  final info = await ref.watch(playerCardArtProvider.future);
  return _PlayerCardInfo(wideArt: info.wideArt, smallArt: info.smallArt);
});

// ── Level Border provider ─────────────────────────────────────────────────────

class _LevelBorderInfo {
  final Map<String, dynamic>? currentBorder;
  final Map<String, dynamic>? nextBorder;
  final int currentLevel;
  const _LevelBorderInfo({
    this.currentBorder,
    this.nextBorder,
    required this.currentLevel,
  });
}

final _levelBorderProvider =
    FutureProvider.autoDispose<_LevelBorderInfo?>((ref) async {
  try {
    final xpResult = await ref.watch(_accountXpProvider.future);
    if (xpResult == null) return null;
    final level = xpResult.data.level;

    final borders =
        await ref.watch(valorantAssetsProvider).getLevelBordersList();
    if (borders.isEmpty) return _LevelBorderInfo(currentLevel: level);

    // Find the current border = highest border whose startingLevel <= current level
    Map<String, dynamic>? current;
    Map<String, dynamic>? next;

    for (var i = 0; i < borders.length; i++) {
      final startLevel =
          (borders[i]['startingLevel'] as num?)?.toInt() ?? 0;
      if (startLevel <= level) {
        current = borders[i];
        // Next border = the following entry
        next = i + 1 < borders.length ? borders[i + 1] : null;
      }
    }

    return _LevelBorderInfo(
      currentBorder: current,
      nextBorder: next,
      currentLevel: level,
    );
  } catch (_) {
    return null;
  }
});

// ── Main Screen ───────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(_accountXpProvider);
    final nameAsync = ref.watch(_displayNameProvider);
    final mmrAsync = ref.watch(_profileMmrProvider);
    final matchesAsync = ref.watch(_profileMatchesProvider);
    final cardAsync = ref.watch(_profileCardProvider);

    // Show full-page skeleton until at least name or xp resolves
    final isLoading = xpAsync.isLoading && nameAsync.isLoading;
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(child: ProfileSkeleton()),
      );
    }

    final showCacheBanner = (xpAsync.asData?.value?.fromCache ?? false) ||
        (nameAsync.asData?.value?.fromCache ?? false);

    final displayName = nameAsync.asData?.value?.data;
    final xpData = xpAsync.asData?.value?.data;
    final mmrData = mmrAsync.asData?.value;
    final matchesData = matchesAsync.asData?.value;

    final cardInfo = cardAsync.asData?.value;
    final cardWideArt = cardInfo?.wideArt;
    final cardSmallArt = cardInfo?.smallArt;

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
                playerCardSmallArt: cardSmallArt,
                onSettingsPressed: () => AccountSwitcherModal.show(context),
                onLogoutPressed: () => _confirmLogout(context, ref),
              ),

              const SizedBox(height: 12),

              // Account Health Status Quick Banner
              const _AccountHealthBannerCard(),

              const SizedBox(height: 16),

              // 2. Account Level & XP Card
              if (xpData != null)
                _AccountLevelXpCard(xp: xpData, mmr: mmrData)
              else
                const _AccountLevelXpSkeleton(),

              const SizedBox(height: 16),

              // 3. Level Border Showcase
              const _LevelBorderCard(),

              const SizedBox(height: 16),

              // 4. 3 Quick Stat Cards Row (Matches Played, Wins, K/D Ratio)
              if (matchesAsync.isLoading && matchesData == null)
                const _ProfileQuickStatsSkeleton()
              else
                _ProfileQuickStatsRow(historyResult: matchesData),

              const SizedBox(height: 20),

              // 4. RECENT XP GAINS Card Section
              if (xpData != null && xpData.history.isNotEmpty) ...[
                _XpGainsCardSection(history: xpData.history),
                const SizedBox(height: 20),
              ],

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
    this.playerCardSmallArt,
  });

  final String? displayName;
  final String? playerCardWideArt;
  final String? playerCardSmallArt;
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
                            icon: const Icon(Icons.health_and_safety_outlined,
                                color: AppColors.win, size: 20),
                            onPressed: () => AccountHealthModal.show(context),
                            tooltip: 'Account Health',
                          ),
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
                              child: ClipOval(
                                child: playerCardSmallArt != null &&
                                        playerCardSmallArt!.isNotEmpty
                                    // Show the equipped player card portrait
                                    ? CachedNetworkImage(
                                        imageUrl: playerCardSmallArt!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: AppColors.bg,
                                          child: Center(
                                            child: Text(initial,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 26,
                                                    fontWeight:
                                                        FontWeight.w900)),
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppColors.bg,
                                          child: Center(
                                            child: Text(initial,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 26,
                                                    fontWeight:
                                                        FontWeight.w900)),
                                          ),
                                        ),
                                      )
                                    // Fallback: initial letter
                                    : Container(
                                        color: AppColors.bg,
                                        child: Center(
                                          child: Text(initial,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 26,
                                                  fontWeight:
                                                      FontWeight.w900)),
                                        ),
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
                                border: Border.all(color: AppColors.bg, width: 2),
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
                          child: Icon(Icons.shield_outlined, color: AppColors.red, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tierNameText,
                    style: const TextStyle(
                      color: AppColors.red,
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
                                  color: AppColors.red,
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
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LoadingShimmer(width: 60, height: 60, borderRadius: 8),
            SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LoadingShimmer(height: 12),
                  SizedBox(height: 10),
                  LoadingShimmer(height: 8, borderRadius: 4),
                  SizedBox(height: 10),
                  LoadingShimmer(height: 10),
                ],
              ),
            ),
          ],
        ),
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
    // Use total match count (including unknown/unenriched) as denominator
    final matchesCount = historyResult?.total ?? matches.length;
    final winsCount =
        matches.where((m) => m.result == MatchResult.victory).length;
    final knownCount = matches
        .where((m) => m.result != MatchResult.unknown).length;
    // Win% over known results only — avoids 0% when most are unenriched
    final winPct = knownCount > 0 ? (winsCount / knownCount * 100) : 0.0;

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
                  iconColor: AppColors.red,
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
                  iconColor: AppColors.red,
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
                            color: AppColors.red,
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
                  iconColor: AppColors.red,
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

class _ProfileQuickStatsSkeleton extends StatelessWidget {
  const _ProfileQuickStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        3,
        (i) => Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.bgCard2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10, width: 1),
            ),
            padding: const EdgeInsets.all(12),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingShimmer(width: 32, height: 32, borderRadius: 16),
                SizedBox(height: 8),
                LoadingShimmer(height: 9),
                SizedBox(height: 6),
                LoadingShimmer(height: 22),
              ],
            ),
          ),
        ),
      ),
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
                      const Icon(Icons.bolt_rounded, color: AppColors.red, size: 18),
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

// ── Level Border Showcase Card ────────────────────────────────────────────────

class _LevelBorderCard extends ConsumerWidget {
  const _LevelBorderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borderAsync = ref.watch(_levelBorderProvider);

    return borderAsync.when(
      data: (info) {
        if (info == null || info.currentBorder == null) return const SizedBox();
        return _LevelBorderContent(info: info);
      },
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _LevelBorderContent extends StatelessWidget {
  const _LevelBorderContent({required this.info});
  final _LevelBorderInfo info;

  @override
  Widget build(BuildContext context) {
    final current = info.currentBorder!;
    final next = info.nextBorder;

    final currentName = current['displayName'] as String? ?? 'Level Border';
    // levelNumberAppearance = the glowing circular border ring (correct display icon)
    // smallPlayerCardAppearance = transparent frame, use as secondary/next preview
    final currentIcon = current['levelNumberAppearance'] as String? ??
        current['displayIcon'] as String? ??
        current['smallPlayerCardAppearance'] as String?;

    final nextName = next?['displayName'] as String?;
    final nextStartLevel = (next?['startingLevel'] as num?)?.toInt();
    final nextIcon = next?['levelNumberAppearance'] as String? ??
        next?['displayIcon'] as String? ??
        next?['smallPlayerCardAppearance'] as String?;

    // Progress to next border
    final currentStart =
        (current['startingLevel'] as num?)?.toInt() ?? 0;
    final levelsInRange =
        nextStartLevel != null ? (nextStartLevel - currentStart) : null;
    final levelsGained = info.currentLevel - currentStart;
    final progress = levelsInRange != null && levelsInRange > 0
        ? (levelsGained / levelsInRange).clamp(0.0, 1.0)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.red.withAlpha(80), width: 1),
        boxShadow: AppColors.redGlow(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 3, height: 14,
                color: AppColors.red,
              ),
              const SizedBox(width: 8),
              const Text(
                'LEVEL BORDER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              // Current border icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withAlpha(80), width: 1),
                ),
                child: currentIcon != null && currentIcon.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: CachedNetworkImage(
                          imageUrl: currentIcon,
                          fit: BoxFit.contain,
                          placeholder: (_, __) =>
                              Container(color: AppColors.bgCard),
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.shield_outlined,
                              color: AppColors.red, size: 32),
                        ),
                      )
                    : const Icon(Icons.shield_outlined,
                        color: AppColors.red, size: 32),
              ),
              const SizedBox(width: 14),

              // Border info + progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Level ${info.currentLevel}',
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    if (next != null && nextStartLevel != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'NEXT BORDER',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Lv. $nextStartLevel',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.bgCard,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.red),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$levelsGained / ${levelsInRange ?? '?'} levels',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withAlpha(30),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: const Color(0xFFFFD700).withAlpha(100),
                              width: 0.8),
                        ),
                        child: const Text(
                          'MAX LEVEL BORDER',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Next border preview (if available)
              if (next != null && nextIcon != null && nextIcon.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    children: [
                      Opacity(
                        opacity: 0.45,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.bgCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.border, width: 0.8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: CachedNetworkImage(
                              imageUrl: nextIcon,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nextName ?? '',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
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

class _AccountHealthBannerCard extends ConsumerWidget {
  const _AccountHealthBannerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(accountHealthProvider);
    final health = healthAsync.asData?.value;

    final isUnknown = health == null || health.isUnknown;
    final isClean = health?.isClean ?? false;

    final statusColor = isUnknown
        ? AppColors.textMuted
        : isClean
            ? AppColors.win
            : AppColors.red;
    final statusText = isUnknown
        ? 'STATUS UNKNOWN // VERIFYING'
        : isClean
            ? 'HEALTHY // GOOD STANDING'
            : 'RESTRICTIONS ACTIVE';

    return InkWell(
      onTap: () => AccountHealthModal.show(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withAlpha(80), width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isUnknown
                      ? Icons.help_outline_rounded
                      : isClean
                          ? Icons.shield_outlined
                          : Icons.warning_amber_rounded,
                  color: statusColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACCOUNT HEALTH',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Row(
              children: [
                Text(
                  'VIEW DETAILS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.white24, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


