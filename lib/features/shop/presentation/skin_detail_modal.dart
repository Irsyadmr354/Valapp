import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/modal_drag_handle.dart';
import '../../../shared/widgets/valorant_icons.dart';
import '../domain/models/skin_offer.dart';

import 'skin_video_player.dart';
import 'wishlist_provider.dart';

/// Interactive modal showing skin details, level progression (VFX, Finisher),
/// and chroma color swatches matching user mockup screenshot.
class SkinDetailModal extends ConsumerStatefulWidget {
  const SkinDetailModal({super.key, required this.offer});
  final SkinOffer offer;

  static Future<void> show(BuildContext context, SkinOffer offer) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SkinDetailModal(offer: offer),
    );
  }

  @override
  ConsumerState<SkinDetailModal> createState() => _SkinDetailModalState();
}

class _SkinDetailModalState extends ConsumerState<SkinDetailModal> {
  int _selectedChromaIndex = 0;
  int _selectedLevelIndex = 0;

  @override
  Widget build(BuildContext context) {
    final assetsAsync =
        ref.watch(_skinFullDetailProvider(widget.offer.skinLevelUuid));
    final wishlist = ref.watch(wishlistProvider);
    final isWishlisted = wishlist.contains(widget.offer.skinLevelUuid);
    final tierColor = TierColors.tierColorForUuid(widget.offer.contentTierUuid);
    final tierLabel = TierColors.tierLabelForUuid(widget.offer.contentTierUuid);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF070A10),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: tierColor.withAlpha(100), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: tierColor.withAlpha(50),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const ModalDragHandle(),

          // Top Header Action Bar (Back, Wishlist Bookmark, Close)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        ref
                            .read(wishlistProvider.notifier)
                            .toggle(widget.offer.skinLevelUuid);
                      },
                      icon: Icon(
                        isWishlisted
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_outline_rounded,
                        color: isWishlisted ? AppColors.red : Colors.white70,
                        size: 22,
                      ),
                      tooltip: isWishlisted
                          ? 'Remove from Wishlist'
                          : 'Add to Wishlist',
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 22),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Body
          Expanded(
            child: assetsAsync.when(
              data: (detail) => detail == null
                  ? _buildFallbackBody(tierColor, tierLabel, isWishlisted)
                  : _buildInteractiveBody(
                      detail, tierColor, tierLabel, isWishlisted),
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.vpCyan),
              ),
              error: (_, __) =>
                  _buildFallbackBody(tierColor, tierLabel, isWishlisted),
            ),
          ),

          // Bottom Action Footer Bar (Gift to Friend + Add to Wishlist)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0F18),
              border: Border(top: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: Row(
              children: [
                // Gift to Friend Button
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Gift feature available in upcoming Riot update!'),
                            backgroundColor: Color(0xFF131B2E),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.card_giftcard_rounded,
                              color: AppColors.red, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'GIFT TO FRIEND',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Add to Wishlist Button (Glowing Gradient Filled Button)
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: isWishlisted
                            ? [AppColors.bgCard2, AppColors.bgCard]
                            : [AppColors.red, AppColors.redDark],
                      ),
                      boxShadow: isWishlisted
                          ? []
                          : AppColors.redGlow(alpha: 0.35, blur: 12),
                    ),
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(wishlistProvider.notifier)
                            .toggle(widget.offer.skinLevelUuid);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isWishlisted
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_outline_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isWishlisted ? 'IN WISHLIST' : 'ADD TO WISHLIST',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildInteractiveBody(
    Map<String, dynamic> detail,
    Color tierColor,
    String tierLabel,
    bool isWishlisted,
  ) {
    final chromas = (detail['chromas'] as List<dynamic>? ?? []);
    final levels = (detail['levels'] as List<dynamic>? ?? []);

    // Theme name for lore text (from /v1/themes)
    final themeUuid = detail['themeUuid'] as String?;
    final themesMap = ref.watch(_themesMapProvider).asData?.value ?? {};
    final themeInfo = themeUuid != null
        ? themesMap[themeUuid] as Map<String, dynamic>?
        : null;
    final themeName = themeInfo?['displayName'] as String? ??
        (widget.offer.displayName ?? 'Weapon Skin').split(' ').first;

    // Check if skin actually has a finisher level
    final hasFinisher = levels.any((l) {
      final levelItem = (l['levelItem']?.toString() ?? '').toLowerCase();
      final levelName = (l['displayName']?.toString() ?? '').toLowerCase();
      return levelItem.contains('finisher') || levelName.contains('finisher');
    });

    // Determine current image and video
    String? currentImage;
    String? currentChromaVideo;

    if (chromas.isNotEmpty && _selectedChromaIndex < chromas.length) {
      final chroma = chromas[_selectedChromaIndex] as Map<String, dynamic>;
      currentImage = chroma['fullRender'] as String? ??
          chroma['displayIcon'] as String? ??
          widget.offer.displayIcon;
      final vid = chroma['streamedVideo'] as String?;
      if (vid != null && vid.isNotEmpty) {
        currentChromaVideo = vid;
      }
    }
    currentImage ??= widget.offer.displayIcon;

    // Split skin name into 2 title lines (Collection & Weapon Type)
    final nameParts = (widget.offer.displayName ?? 'Weapon Skin').split(' ');
    final collectionName =
        nameParts.isNotEmpty ? nameParts.first.toUpperCase() : 'WEAPON';
    final weaponTypeName = nameParts.length > 1
        ? nameParts.sublist(1).join(' ').toUpperCase()
        : 'SKIN';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // 1. Skin Title & Price Header Row
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              collectionName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                height: 1.0,
              ),
            ),
            Text(
              weaponTypeName,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            // Tier Tag & VP Price Row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tierColor.withAlpha(45),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: tierColor.withAlpha(140), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SkinTierIcon(
                        tierUuid: widget.offer.contentTierUuid,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tierLabel.toUpperCase(),
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.offer.price > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VpIcon(size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.offer.price}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 10),
            Text(
              'Part of the $themeName Collection.',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 2. Quick Info Chips Row
        Row(
          children: [
            _QuickInfoChip(
              customIcon: SkinTierIcon(
                tierUuid: widget.offer.contentTierUuid,
                size: 14,
              ),
              label: tierLabel,
              color: tierColor,
            ),
            if (widget.offer.price > 0) ...[
              const SizedBox(width: 8),
              _QuickInfoChip(
                customIcon: const VpIcon(size: 13, color: AppColors.vpCyan),
                label: '${widget.offer.price}',
                color: AppColors.vpCyan,
              ),
            ],
            if (hasFinisher) ...[
              const SizedBox(width: 8),
              const _QuickInfoChip(
                icon: Icons.shield_outlined,
                label: 'Finisher Included',
                color: AppColors.red,
              ),
            ],
          ],
        ),

        const SizedBox(height: 20),

        // 3. Main Weapon Image Showcase Container with Energy Glow
        Stack(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tierColor.withAlpha(70), width: 1),
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    tierColor.withAlpha(50),
                    const Color(0xFF0A0F18),
                  ],
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: currentImage != null
                      ? CachedNetworkImage(
                          key: ValueKey(currentImage),
                          imageUrl: currentImage,
                          height: 150,
                          fit: BoxFit.contain,
                          placeholder: (_, __) =>
                              const CircularProgressIndicator(
                                  color: AppColors.vpCyan),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.white24,
                            size: 48,
                          ),
                        )
                      : const Icon(Icons.broken_image,
                          color: Colors.white24, size: 48),
                ),
              ),
            ),

            // Floating Video Preview Button on Top Right
            if (currentChromaVideo != null)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    SkinVideoDialog.show(
                      context,
                      videoUrl: currentChromaVideo!,
                      title: '${widget.offer.displayName} - Chroma Video',
                      tierColor: tierColor,
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4655),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF4655).withAlpha(80),
                          blurRadius: 8,
                        )
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 24),

        // 4. COLOR VARIANTS (CHROMAS) Section
        if (chromas.length > 1) ...[
          Row(
            children: [
              Container(width: 3, height: 14, color: AppColors.red),
              const SizedBox(width: 8),
              const Text(
                'COLOR VARIANTS (CHROMAS)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: chromas.length,
              itemBuilder: (context, idx) {
                final chroma = chromas[idx] as Map<String, dynamic>;
                final isSelected = idx == _selectedChromaIndex;
                final swatchUrl = chroma['swatch'] as String?;
                final chromaName =
                    chroma['displayName']?.toString() ?? 'Variant';

                return GestureDetector(
                  onTap: () => setState(() => _selectedChromaIndex = idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.red.withAlpha(40)
                          : const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppColors.red : Colors.white10,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (swatchUrl != null && swatchUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: swatchUrl,
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: tierColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  chromaName.split('\n').last,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.check_rounded,
                                      color: AppColors.red, size: 14),
                                ]
                              ],
                            ),
                            if (idx > 0) ...[
                              const SizedBox(height: 2),
                              const Text(
                                '15 RP',
                                style: TextStyle(
                                  color: Color(0xFFFF9900),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ]
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 5. LEVEL UPGRADES & VFX Section
        if (levels.isNotEmpty) ...[
          Row(
            children: [
              Container(width: 3, height: 14, color: AppColors.red),
              const SizedBox(width: 8),
              const Text(
                'LEVEL UPGRADES & VFX',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(levels.length, (idx) {
            final level = levels[idx] as Map<String, dynamic>;
            final isSelected = idx == _selectedLevelIndex;
            final levelName =
                level['displayName']?.toString() ?? 'Level ${idx + 1}';
            final levelItem = level['levelItem']?.toString() ?? '';
            final videoUrl = level['streamedVideo'] as String?;

            return GestureDetector(
              onTap: () => setState(() => _selectedLevelIndex = idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.red.withAlpha(40)
                      : const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.red : Colors.white10,
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Level Number Circle with Lock Indicator
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? AppColors.red : Colors.white12,
                      ),
                      child: Center(
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Level Name & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            levelName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (levelItem.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _cleanLevelItem(levelItem),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),

                    // 1. RP Cost Tag (Always FIRST right after title text: [RpIcon] 10)
                    if (idx > 0) ...[
                      const SizedBox(width: 8),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RpIcon(size: 16, color: Color(0xFFFF9900)),
                          SizedBox(width: 4),
                          Text(
                            '10',
                            style: TextStyle(
                              color: Color(0xFFFF9900),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // 2. FINISHER badge (Placed AFTER RP cost if item has finisher)
                    if (idx >= 3 ||
                        levelItem.toLowerCase().contains('finisher')) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFFFD700).withAlpha(120),
                              width: 0.8),
                        ),
                        child: const Text(
                          'FINISHER',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],

                    // Video Preview Button (Placed AFTER RP cost)
                    if (videoUrl != null && videoUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          final selectedChromaVid = (chromas.isNotEmpty &&
                                  _selectedChromaIndex < chromas.length)
                              ? chromas[_selectedChromaIndex]['streamedVideo']
                                  as String?
                              : null;
                          final activeVid = (selectedChromaVid != null &&
                                  selectedChromaVid.isNotEmpty)
                              ? selectedChromaVid
                              : videoUrl;
                          SkinVideoDialog.show(
                            context,
                            videoUrl: activeVid,
                            title: '$levelName - Video Preview',
                            tierColor: tierColor,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 2),
                              Text(
                                'VIDEO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFallbackBody(
      Color tierColor, String tierLabel, bool isWishlisted) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.offer.displayIcon != null)
            CachedNetworkImage(
              imageUrl: widget.offer.displayIcon!,
              height: 140,
              fit: BoxFit.contain,
            )
          else
            const Icon(Icons.broken_image, color: Colors.white24, size: 64),
        ],
      ),
    );
  }

  String _cleanLevelItem(String item) {
    final parts = item.split('::');
    final raw = parts.last;
    // Insert a space before every capital letter to split CamelCase into words,
    // then trim any leading space that results from a leading capital.
    return raw
        .splitMapJoin(
          RegExp(r'([A-Z])'),
          onMatch: (m) => ' ${m.group(0)!}',
          onNonMatch: (s) => s,
        )
        .trim();
  }
}

class _QuickInfoChip extends StatelessWidget {
  const _QuickInfoChip({
    this.icon,
    this.customIcon,
    required this.label,
    required this.color,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (customIcon != null)
              customIcon!
            else if (icon != null)
              Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _themesMapProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) async => ref.watch(valorantAssetsProvider).getThemesMap());

final _skinFullDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, uuid) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getSkinLevel(uuid);
});
