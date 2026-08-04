import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../domain/models/contracts.dart';

/// Modal displaying the full Battle Pass rewards in a swipeable Chapter Carousel.
class BattlepassCarouselModal extends ConsumerStatefulWidget {
  const BattlepassCarouselModal({super.key, required this.contract});
  final Contract contract;

  static Future<void> show(BuildContext context, Contract contract) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BattlepassCarouselModal(contract: contract),
    );
  }

  @override
  ConsumerState<BattlepassCarouselModal> createState() =>
      _BattlepassCarouselModalState();
}

class _BattlepassCarouselModalState
    extends ConsumerState<BattlepassCarouselModal> {
  late final PageController _pageController;
  int _currentChapterIndex = 0;

  // Contract data loaded once — not in build() to avoid PageController reset
  Map<String, dynamic>? _contractData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadContract();
  }

  Future<void> _loadContract() async {
    final assets = ref.read(valorantAssetsProvider);
    final data = await assets.getContract(widget.contract.contractId);
    if (mounted) {
      setState(() {
        _contractData = data;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1622),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFFFF4655), width: 1.5),
          left: BorderSide(color: Color(0xFFFF4655), width: 1.5),
          right: BorderSide(color: Color(0xFFFF4655), width: 1.5),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BATTLE PASS',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 4),
                      Text(
                        'TIER ${widget.contract.progressionLevelReached}  •  ${widget.contract.progressionTowardsNextLevel} / 10,000 XP',
                        style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (widget.contract.progressionTowardsNextLevel / 10000)
                    .clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF141F2D),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF4655)),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Body — data loaded once in initState, not in build
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4655)));
    }

    final content = _contractData?['content'] as Map<String, dynamic>?;
    final chapters = (content?['chapters'] as List<dynamic>?) ?? [];

    if (chapters.isEmpty) {
      return const Center(
        child: Text('No Battle Pass data available.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    return Column(
      children: [
        // Chapter pills
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chapters.length,
            itemBuilder: (context, idx) {
              final isSelected = idx == _currentChapterIndex;
              final isEpilogue = idx == chapters.length - 1;
              final label = isEpilogue ? 'Epilogue' : 'Ch. ${idx + 1}';

              return GestureDetector(
                onTap: () {
                  _pageController.animateToPage(idx,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF4655)
                        : const Color(0xFF141F2D),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF4655)
                          : Colors.white10,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Swipeable chapter pages
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) =>
                setState(() => _currentChapterIndex = idx),
            itemCount: chapters.length,
            itemBuilder: (context, chIdx) {
              final chapter = chapters[chIdx] as Map<String, dynamic>;
              final levels = (chapter['levels'] as List<dynamic>?) ?? [];
              final isEpilogue = chIdx == chapters.length - 1;

              // Pre-compute tierOffset for this chapter
              int tierOffset = 0;
              for (int ci = 0; ci < chIdx; ci++) {
                final prevChapter = chapters[ci] as Map<String, dynamic>;
                tierOffset +=
                    ((prevChapter['levels'] as List<dynamic>?) ?? []).length;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                            width: 3,
                            height: 14,
                            color: const Color(0xFFFF4655)),
                        const SizedBox(width: 8),
                        Text(
                          isEpilogue
                              ? 'EPILOGUE REWARDS'
                              : 'CHAPTER ${chIdx + 1} REWARDS',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: levels.length,
                        itemBuilder: (context, lvlIdx) {
                          final level =
                              levels[lvlIdx] as Map<String, dynamic>;
                          final reward =
                              level['reward'] as Map<String, dynamic>?;
                          final isFree = level['isFreeItem'] == true;
                          final tierNum = tierOffset + (lvlIdx + 1);
                          final isUnlocked = widget
                                  .contract.progressionLevelReached >=
                              tierNum;
                          final rewardUuid = reward?['uuid'] as String?;
                          final rewardType =
                              reward?['type'] as String? ?? '';

                          return _RewardTile(
                            tierNum: tierNum,
                            rewardType: rewardType,
                            rewardUuid: rewardUuid,
                            isFree: isFree,
                            isUnlocked: isUnlocked,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Reward Tile ───────────────────────────────────────────────────────────────

class _RewardTile extends ConsumerWidget {
  const _RewardTile({
    required this.tierNum,
    required this.rewardType,
    required this.rewardUuid,
    required this.isFree,
    required this.isUnlocked,
  });

  final int tierNum;
  final String rewardType;
  final String? rewardUuid;
  final bool isFree;
  final bool isUnlocked;

  String _friendlyType(String raw) {
    return raw
        .replaceAll('Equippable', '')
        .replaceAll('CharmLevel', 'Gun Buddy')
        .replaceAll('SprayLevel', 'Spray')
        .replaceAll('SkinLevel', 'Skin')
        .replaceAll('PlayerCard', 'Player Card')
        .replaceAll('Currency', 'Currency')
        .trim();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Attempt to resolve icon from skin / spray / card asset maps
    String? iconUrl;
    if (rewardUuid != null) {
      final skinMap =
          ref.watch(_skinLevelsFutureProvider).asData?.value ?? {};
      final sprayMap =
          ref.watch(_spraysFutureProvider).asData?.value ?? {};
      final cardMap =
          ref.watch(_cardsFutureProvider).asData?.value ?? {};

      final skinMeta =
          skinMap[rewardUuid] as Map<String, dynamic>?;
      final sprayMeta =
          sprayMap[rewardUuid] as Map<String, dynamic>?;
      final cardMeta =
          cardMap[rewardUuid] as Map<String, dynamic>?;

      iconUrl = skinMeta?['displayIcon'] as String? ??
          sprayMeta?['fullIcon'] as String? ??
          sprayMeta?['displayIcon'] as String? ??
          cardMeta?['smallArt'] as String? ??
          cardMeta?['displayIcon'] as String?;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUnlocked
            ? const Color(0xFF141F2D)
            : const Color(0xFF070A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnlocked
              ? const Color(0xFF00F0FF).withAlpha(90)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          // Tier number badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? const Color(0xFF00F0FF).withAlpha(28)
                  : Colors.white.withAlpha(8),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$tierNum',
                style: TextStyle(
                    color: isUnlocked
                        ? const Color(0xFF00F0FF)
                        : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Reward icon
          if (iconUrl != null)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1622),
                borderRadius: BorderRadius.circular(6),
              ),
              child: CachedNetworkImage(
                imageUrl: iconUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const LoadingShimmer(height: 40),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.card_giftcard,
                        color: Colors.white24, size: 20),
              ),
            ),
          // Reward info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendlyType(rewardType),
                  style: TextStyle(
                      color:
                          isUnlocked ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (isFree) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withAlpha(40),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('FREE',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 8,
                                fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      isUnlocked
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      color: isUnlocked
                          ? const Color(0xFF00F0FF)
                          : Colors.white24,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUnlocked ? 'UNLOCKED' : 'LOCKED',
                      style: TextStyle(
                          color: isUnlocked
                              ? const Color(0xFF00F0FF)
                              : Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
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

// Local asset FutureProviders for reward icon resolution
final _skinLevelsFutureProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
        ref.watch(valorantAssetsProvider).getSkinLevelsMap());

final _spraysFutureProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
        ref.watch(valorantAssetsProvider).getSpraysMap());

final _cardsFutureProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
        ref.watch(valorantAssetsProvider).getPlayerCardsMap());
