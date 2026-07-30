import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/tier_colors.dart';
import '../domain/models/skin_offer.dart';
import 'skin_video_player.dart';
import 'wishlist_provider.dart';

/// Interactive modal showing skin details, level progression (VFX, Finisher),
/// and chroma color swatches.
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
    final assetsAsync = ref.watch(_skinFullDetailProvider(widget.offer.skinLevelUuid));
    final wishlist = ref.watch(wishlistProvider);
    final isWishlisted = wishlist.contains(widget.offer.skinLevelUuid);
    final tierColor = TierColors.forName(widget.offer.contentTierUuid);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1622),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: tierColor.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: tierColor.withAlpha(60),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header with skin name & tier chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.offer.displayName ?? 'Weapon Skin',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: tierColor.withAlpha(40),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: tierColor.withAlpha(120), width: 0.8),
                            ),
                            child: Text(
                              _tierLabel(widget.offer.contentTierUuid ?? '').toUpperCase(),
                              style: TextStyle(
                                color: tierColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.offer.price} VP',
                            style: const TextStyle(
                              color: Color(0xFF00F0FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Modal Body
          Expanded(
            child: assetsAsync.when(
              data: (detail) => detail == null
                  ? _buildFallbackBody(tierColor)
                  : _buildInteractiveBody(detail, tierColor),
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF4655)),
              ),
              error: (_, __) => _buildFallbackBody(tierColor),
            ),
          ),

          // Wishlist Action Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF070A10),
              border: Border(
                top: BorderSide(color: Color(0xFF1B2738), width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isWishlisted
                          ? const Color(0xFF1B2738)
                          : const Color(0xFFFF4655),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      ref
                          .read(wishlistProvider.notifier)
                          .toggle(widget.offer.skinLevelUuid);
                    },
                    icon: Icon(
                      isWishlisted ? Icons.bookmark : Icons.bookmark_border,
                      color: isWishlisted ? const Color(0xFFFF4655) : Colors.white,
                    ),
                    label: Text(
                      isWishlisted ? 'IN WISHLIST' : 'ADD TO WISHLIST',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
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

  Widget _buildInteractiveBody(Map<String, dynamic> detail, Color tierColor) {
    final chromas = (detail['chromas'] as List<dynamic>? ?? []);
    final levels = (detail['levels'] as List<dynamic>? ?? []);

    // Determine video URL or image preview for selected level / chroma
    String? currentVideo;
    String? currentImage;

    if (levels.isNotEmpty && _selectedLevelIndex < levels.length) {
      final level = levels[_selectedLevelIndex] as Map<String, dynamic>;
      final vid = level['streamedVideo'] as String?;
      if (vid != null && vid.isNotEmpty) {
        currentVideo = vid;
      }
    }

    if (chromas.isNotEmpty && _selectedChromaIndex < chromas.length) {
      final chroma = chromas[_selectedChromaIndex] as Map<String, dynamic>;
      final vid = chroma['streamedVideo'] as String?;
      if (currentVideo == null && vid != null && vid.isNotEmpty) {
        currentVideo = vid;
      }
      currentImage = chroma['fullRender'] as String? ??
          chroma['displayIcon'] as String? ??
          widget.offer.displayIcon;
    }
    currentImage ??= widget.offer.displayIcon;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Main Video Preview or Image Preview Box
        if (currentVideo != null && currentVideo.isNotEmpty)
          SkinVideoPlayer(
            key: ValueKey(currentVideo),
            videoUrl: currentVideo,
            tierColor: tierColor,
          )
        else
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFF070A10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tierColor.withAlpha(60)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tierColor.withAlpha(40),
                  const Color(0xFF070A10),
                ],
              ),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: currentImage != null
                    ? CachedNetworkImage(
                        key: ValueKey(currentImage),
                        imageUrl: currentImage,
                        height: 140,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const CircularProgressIndicator(color: Color(0xFFFF4655)),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white24,
                          size: 48,
                        ),
                      )
                    : const Icon(Icons.image_not_supported_outlined,
                        color: Colors.white24, size: 48),
              ),
            ),
          ),
        const SizedBox(height: 20),

        // Color Chromas Swatches
        if (chromas.length > 1) ...[
          Row(
            children: [
              Container(width: 3, height: 12, color: tierColor),
              const SizedBox(width: 8),
              const Text(
                'COLOR VARIANTS (CHROMAS)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 54,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: chromas.length,
              itemBuilder: (context, idx) {
                final chroma = chromas[idx] as Map<String, dynamic>;
                final isSelected = idx == _selectedChromaIndex;
                final swatchUrl = chroma['swatch'] as String?;
                final chromaName = chroma['displayName']?.toString() ?? 'Variant';

                return GestureDetector(
                  onTap: () => setState(() => _selectedChromaIndex = idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tierColor.withAlpha(40)
                          : const Color(0xFF141F2D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? tierColor : Colors.white10,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (swatchUrl != null && swatchUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: CachedNetworkImage(
                              imageUrl: swatchUrl,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: tierColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            chromaName.split('\n').last,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Level Progression
        if (levels.isNotEmpty) ...[
          Row(
            children: [
              Container(width: 3, height: 12, color: const Color(0xFFFF9900)),
              const SizedBox(width: 8),
              const Text(
                'LEVEL UPGRADES & VFX',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(levels.length, (idx) {
            final level = levels[idx] as Map<String, dynamic>;
            final isSelected = idx == _selectedLevelIndex;
            final levelName = level['displayName']?.toString() ?? 'Level ${idx + 1}';
            final levelItem = level['levelItem']?.toString() ?? '';

            return GestureDetector(
              onTap: () => setState(() => _selectedLevelIndex = idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF9900).withAlpha(30)
                      : const Color(0xFF141F2D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF9900)
                        : Colors.white10,
                    width: isSelected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected
                          ? const Color(0xFFFF9900)
                          : Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            levelName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (levelItem.isNotEmpty)
                            Text(
                              _cleanLevelItem(levelItem),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    if (idx > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9900).withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '10 RP',
                          style: TextStyle(
                            color: Color(0xFFFF9900),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFallbackBody(Color tierColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.offer.displayIcon != null)
            CachedNetworkImage(
              imageUrl: widget.offer.displayIcon!,
              height: 120,
              fit: BoxFit.contain,
            )
          else
            const Icon(Icons.image_not_supported_outlined,
                color: Colors.white24, size: 64),
        ],
      ),
    );
  }

  String _cleanLevelItem(String item) {
    final parts = item.split('::');
    final raw = parts.last;
    return raw.replaceAll(RegExp(r'([A-Z])'), ' \$1').trim();
  }

  String _tierLabel(String tierUuid) {
    switch (tierUuid.toLowerCase()) {
      case '12664872-466b-4c78-8b23-66a4c734fa5a':
        return 'Select Edition';
      case '0fe42732-4e20-704e-8e3b-92865d667230':
        return 'Deluxe Edition';
      case '60bca009-4182-7998-dee7-b8a2558dc369':
        return 'Premium Edition';
      case 'e046854e-406c-37f4-6607-11ae36026091':
        return 'Ultra Edition';
      case '12664872-466b-4c78-8b23-66a4c734fa5a_ex':
      case '12664872-466b-4c78-8b23-66a4c734fa5b':
        return 'Exclusive Edition';
      default:
        return 'Skin Offer';
    }
  }
}

final _skinFullDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, uuid) async {
  final assets = ref.watch(valorantAssetsProvider);
  return assets.getSkinLevel(uuid);
});
