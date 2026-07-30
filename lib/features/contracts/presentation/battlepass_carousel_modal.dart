import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/models/contracts.dart';

/// Modal displaying the full Battle Pass rewards in a swipeable Chapter Carousel.
class BattlepassCarouselModal extends ConsumerStatefulWidget {
  const BattlepassCarouselModal({
    super.key,
    required this.contract,
  });

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
  final PageController _pageController = PageController();
  int _currentChapterIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(valorantAssetsProvider);
    final contractId = widget.contract.contractId;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1622),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFFF4655), width: 1.5),
        ),
      ),
      child: Column(
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BATTLE PASS CAROUSEL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'CURRENT LEVEL ${widget.contract.progressionLevelReached} • ${widget.contract.progressionTowardsNextLevel} XP',
                        style: const TextStyle(
                          color: Color(0xFF00F0FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
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
          const SizedBox(height: 12),

          // Body Content
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: assets.getContract(contractId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF4655)),
                  );
                }

                final contractData = snapshot.data;
                final content = contractData?['content'] as Map<String, dynamic>?;
                final chapters = (content?['chapters'] as List<dynamic>?) ?? [];

                if (chapters.isEmpty) {
                  return const Center(
                    child: Text(
                      'No Battle Pass chapter data available.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Chapter Pills Bar
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
                              _pageController.animateToPage(
                                idx,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
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
                    const SizedBox(height: 16),

                    // Swipeable PageView Carousel
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (idx) {
                          setState(() => _currentChapterIndex = idx);
                        },
                        itemCount: chapters.length,
                        itemBuilder: (context, chIdx) {
                          final chapter = chapters[chIdx] as Map<String, dynamic>;
                          final levels = (chapter['levels'] as List<dynamic>?) ?? [];
                          final isEpilogue = chIdx == chapters.length - 1;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 14,
                                      color: const Color(0xFFFF4655),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isEpilogue
                                          ? 'EPILOGUE REWARDS'
                                          : 'CHAPTER ${chIdx + 1} REWARDS',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Level Rewards List inside Chapter
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: levels.length,
                                    itemBuilder: (context, lvlIdx) {
                                      final level = levels[lvlIdx] as Map<String, dynamic>;
                                      final reward = level['reward'] as Map<String, dynamic>?;
                                      final isFree = level['isFreeItem'] == true;
                                      final tierNum = (chIdx * 5) + (lvlIdx + 1);

                                      final isUnlocked = widget.contract.progressionLevelReached >= tierNum;

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isUnlocked
                                              ? const Color(0xFF141F2D)
                                              : const Color(0xFF070A10),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isUnlocked
                                                ? const Color(0xFF00F0FF).withAlpha(100)
                                                : Colors.white10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Tier Number Badge
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: isUnlocked
                                                    ? const Color(0xFF00F0FF).withAlpha(30)
                                                    : Colors.white.withAlpha(10),
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
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),

                                            // Reward Description
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    reward?['type']?.toString().replaceAll('Equippable', '') ?? 'Reward Item',
                                                    style: TextStyle(
                                                      color: isUnlocked ? Colors.white : Colors.white70,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      if (isFree) ...[
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF10B981).withAlpha(40),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text(
                                                            'FREE TIER',
                                                            style: TextStyle(
                                                              color: Color(0xFF10B981),
                                                              fontSize: 9,
                                                              fontWeight: FontWeight.w900,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                      ],
                                                      Text(
                                                        isUnlocked ? '✓ UNLOCKED' : 'LOCKED',
                                                        style: TextStyle(
                                                          color: isUnlocked ? const Color(0xFF00F0FF) : Colors.white38,
                                                          fontSize: 10,
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
