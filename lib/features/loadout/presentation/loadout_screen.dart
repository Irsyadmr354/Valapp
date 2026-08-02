import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cached_fetch_result.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/cache_data_banner.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/player_loadout.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _loadoutProvider =
    FutureProvider.autoDispose<CachedFetchResult<PlayerLoadout>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(loadoutRemoteSourceProvider.future);
  final cache = ref.watch(loadoutLocalCacheProvider);
  try {
    final raw = await source.fetchLoadoutRaw(creds.shard, creds.puuid);
    final loadout = PlayerLoadout.fromJson(raw);
    await cache.saveLoadout(raw);
    return CachedFetchResult(loadout);
  } catch (_) {
    final cached = await cache.loadLoadout();
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

final _skinMetaProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getSkinLevelsMap());

final _playerCardsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getPlayerCardsMap());

final _spraysProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getSpraysMap());

final _titlesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getPlayerTitlesMap());

final _buddiesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getBuddiesMap());

final _weaponsBaseProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
        ref.watch(valorantAssetsProvider).getWeaponsMap());

// ── Screen ────────────────────────────────────────────────────────────────────

class LoadoutScreen extends ConsumerWidget {
  const LoadoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadoutAsync = ref.watch(_loadoutProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('EQUIPPED LOADOUT',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () => ref.invalidate(_loadoutProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        backgroundColor: AppColors.bgCard2,
        onRefresh: () async => ref.invalidate(_loadoutProvider),
        child: loadoutAsync.when(
          data: (result) => result == null
              ? const Center(
                  child: Text('Not logged in.',
                      style: TextStyle(color: Colors.white38)))
              : _LoadoutContent(
                  loadout: result.data,
                  showCacheBanner: result.fromCache,
                ),
          loading: () => const LoadoutSkeleton(),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: Colors.white24, size: 56),
                  const SizedBox(height: 16),
                  const Text('Could not load loadout.',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(e.toString(),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => ref.invalidate(_loadoutProvider),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Weapon category grouping ──────────────────────────────────────────────────

const _weaponCategories = <String, List<String>>{
  'PISTOLS':   ['Classic', 'Shorty', 'Frenzy', 'Ghost', 'Sheriff'],
  'SMGs':      ['Stinger', 'Spectre'],
  'RIFLES':    ['Bulldog', 'Guardian', 'Phantom', 'Vandal'],
  'SHOTGUNS':  ['Bucky', 'Judge'],
  'SNIPERS':   ['Marshal', 'Outlaw', 'Operator'],
  'HEAVY':     ['Ares', 'Odin'],
  'MELEE':     ['Melee'],
};

String _categoryFor(String weaponName) {
  final lower = weaponName.toLowerCase();
  for (final entry in _weaponCategories.entries) {
    for (final wep in entry.value) {
      if (lower.contains(wep.toLowerCase())) return entry.key;
    }
  }
  return 'OTHER';
}

// ── Content ────────────────────────────────────────────────────────────────────

class _LoadoutContent extends ConsumerWidget {
  const _LoadoutContent({required this.loadout, this.showCacheBanner = false});
  final PlayerLoadout loadout;
  final bool showCacheBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skinMap   = ref.watch(_skinMetaProvider).asData?.value ?? {};
    final cardMap   = ref.watch(_playerCardsProvider).asData?.value ?? {};
    final sprayMap  = ref.watch(_spraysProvider).asData?.value ?? {};
    final titleMap  = ref.watch(_titlesProvider).asData?.value ?? {};
    final buddyMap  = ref.watch(_buddiesProvider).asData?.value ?? {};
    final baseMap   = ref.watch(_weaponsBaseProvider).asData?.value ?? {};

    final cardInfo  = loadout.playerCardId != null ? cardMap[loadout.playerCardId] as Map<String, dynamic>? : null;
    final sprayInfo = loadout.sprayId != null ? sprayMap[loadout.sprayId] as Map<String, dynamic>? : null;
    final titleInfo = loadout.playerTitleId != null ? titleMap[loadout.playerTitleId] as Map<String, dynamic>? : null;

    // Group weapons by category
    final grouped = <String, List<WeaponLoadout>>{};
    for (final w in loadout.weapons) {
      final weaponBase = baseMap[w.weaponId] as Map<String, dynamic>?;
      final wName = weaponBase?['displayName'] as String? ?? '';
      final cat = _categoryFor(wName);
      grouped.putIfAbsent(cat, () => []).add(w);
    }
    // Sort categories in order
    final orderedCats = _weaponCategories.keys.toList()..add('OTHER');
    final sortedEntries = orderedCats
        .where((c) => grouped.containsKey(c))
        .map((c) => MapEntry(c, grouped[c]!))
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        if (showCacheBanner) const CacheDataBanner(),

        // Identity card
        const _SectionHeader(title: 'IDENTITY'),
        _IdentityCard(
          cardInfo: cardInfo,
          titleText: titleInfo?['titleText'] as String? ?? titleInfo?['displayName'] as String?,
          sprayInfo: sprayInfo,
        ),
        const SizedBox(height: 20),

        // Weapon sections by category
        for (final entry in sortedEntries) ...[
          _SectionHeader(title: entry.key),
          for (final w in entry.value)
            _WeaponSkinTile(
              weapon: w,
              skinInfo: w.skinLevelId != null ? skinMap[w.skinLevelId] as Map<String, dynamic>? : null,
              buddyInfo: w.buddyId != null ? buddyMap[w.buddyId] as Map<String, dynamic>? : null,
              defaultWeaponInfo: baseMap[w.weaponId] as Map<String, dynamic>?,
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ── Identity Card ─────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.cardInfo,
    required this.titleText,
    required this.sprayInfo,
  });

  final Map<String, dynamic>? cardInfo;
  final String? titleText;
  final Map<String, dynamic>? sprayInfo;

  @override
  Widget build(BuildContext context) {
    final wideArt = cardInfo?['wideArt'] as String? ??
        cardInfo?['largeArt'] as String? ??
        cardInfo?['smallArt'] as String?;
    final sprayIcon = sprayInfo?['fullIcon'] as String? ??
        sprayInfo?['displayIcon'] as String?;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.red.withAlpha(80), width: 1),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgCard2, Color(0xFF0B101A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Player Card art
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(15)),
            child: wideArt != null
                ? CachedNetworkImage(
                    imageUrl: wideArt,
                    height: 100,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const LoadingShimmer(height: 100),
                    errorWidget: (_, __, ___) => Container(
                        height: 100, color: AppColors.bgCard),
                  )
                : Container(height: 100, color: AppColors.bgCard),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PLAYER TITLE',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text(
                        titleText?.isNotEmpty == true
                            ? titleText!
                            : 'No Title Equipped',
                        style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                // Spray preview
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('PRE-ROUND SPRAY',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6)),
                    const SizedBox(height: 6),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.white12, width: 0.8),
                      ),
                      child: sprayIcon != null
                          ? CachedNetworkImage(
                              imageUrl: sprayIcon,
                              fit: BoxFit.contain,
                              placeholder: (_, __) =>
                                  const LoadingShimmer(height: 52),
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.tag_faces_outlined,
                                  color: Colors.white24,
                                  size: 28),
                            )
                          : const Icon(Icons.tag_faces_outlined,
                              color: Colors.white24, size: 28),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sprayInfo?['displayName'] as String? ?? 'Default',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Weapon Skin Tile ─────────────────────────────────────────────────────────

class _WeaponSkinTile extends StatelessWidget {
  const _WeaponSkinTile({
    required this.weapon,
    required this.skinInfo,
    required this.buddyInfo,
    this.defaultWeaponInfo,
  });

  final WeaponLoadout weapon;
  final Map<String, dynamic>? skinInfo;
  final Map<String, dynamic>? buddyInfo;
  final Map<String, dynamic>? defaultWeaponInfo;

  @override
  Widget build(BuildContext context) {
    final isDefault = skinInfo == null;
    final skinName = isDefault
        ? (defaultWeaponInfo?['displayName'] as String? ?? 'Default Skin')
        : (skinInfo?['skinName'] as String? ??
            skinInfo?['displayName'] as String? ??
            'Default Skin');

    // Icon: use skin level icon, fall back to weapon base icon
    final iconUrl = isDefault
        ? (defaultWeaponInfo?['displayIcon'] as String? ??
            defaultWeaponInfo?['killStreamIcon'] as String?)
        : (skinInfo?['displayIcon'] as String?);

    final tierUuid = isDefault ? null : skinInfo?['contentTierUuid'] as String?;
    final tierColor = TierColors.forName(tierUuid);
    final tierLabel = isDefault ? 'Default' : TierColors.tierLabel(tierUuid).replaceAll(' Edition', '');

    // Chroma indicator — non-default chroma equipped?
    final hasNonDefaultChroma = weapon.chromaId != null &&
        weapon.chromaId!.isNotEmpty &&
        !(weapon.chromaId!.endsWith('01'));

    // Resolve chroma swatch color from skin chromas array
    Color? chromaColor;
    if (hasNonDefaultChroma && skinInfo?['chromas'] != null) {
      final chromas = skinInfo!['chromas'] as List<dynamic>? ?? [];
      for (final ch in chromas) {
        if (ch is Map && ch['uuid'] == weapon.chromaId) {
          final hex = ch['swatch'] as String?;
          if (hex != null && hex.isNotEmpty) {
            chromaColor = _parseHexColor(hex);
            if (chromaColor != null) break;
          }
        }
      }
    }

    final buddyIcon = buddyInfo?['displayIcon'] as String?;
    final buddyName = buddyInfo?['displayName'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDefault
              ? AppColors.border
              : tierColor.withAlpha(120),
          width: isDefault ? 0.8 : 1.2,
        ),
      ),
      child: Row(
        children: [
          // Weapon image
          Container(
            width: 82, height: 48,
            decoration: BoxDecoration(
              color: isDefault ? AppColors.bgCard2 : tierColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: iconUrl != null
                ? CachedNetworkImage(
                    imageUrl: iconUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const LoadingShimmer(height: 48),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.shield_outlined, color: Colors.white24, size: 28),
                  )
                : const Center(child: Icon(Icons.shield_outlined,
                    color: Colors.white24, size: 28)),
          ),
          const SizedBox(width: 12),
          // Skin name + tier + chroma dot
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skinName,
                  style: TextStyle(
                    color: isDefault ? AppColors.textSecondary : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: isDefault ? AppColors.textMuted : tierColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tierLabel,
                      style: TextStyle(
                          color: isDefault ? AppColors.textMuted : tierColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
                    ),
                    // Chroma indicator dot
                    if (hasNonDefaultChroma) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.rpAmber.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.rpAmber.withAlpha(80),
                              width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: chromaColor ?? AppColors.rpAmber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('CHROMA',
                                style: TextStyle(
                                    color: AppColors.rpAmber,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Gun buddy
          if (buddyIcon != null) ...[
            Column(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.bgCard2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: buddyIcon,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const LoadingShimmer(height: 34),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.emoji_nature_outlined,
                        color: Colors.white24, size: 18),
                  ),
                ),
                if (buddyName != null)
                  SizedBox(
                    width: 44,
                    child: Text(
                      buddyName,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 7),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: AppColors.red),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }
}

Color? _parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var cleaned = hex.replaceAll('#', '');
  if (cleaned.length == 6) cleaned = 'FF$cleaned';
  if (cleaned.length == 8 && !cleaned.startsWith('FF')) {
    // If format is RRGGBBAA, convert to AARRGGBB for Flutter Color
    final rrggbb = cleaned.substring(0, 6);
    final aa = cleaned.substring(6, 8);
    cleaned = '$aa$rrggbb';
  }
  final value = int.tryParse(cleaned, radix: 16);
  return value != null ? Color(value) : null;
}
