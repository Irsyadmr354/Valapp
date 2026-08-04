import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

// ── Base animated shimmer block ───────────────────────────────────────────────

/// A single animated shimmer rectangle — the building block for all skeletons.
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 4,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.08, end: 0.22).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

// ── Shared shimmer row helper ─────────────────────────────────────────────────

/// A shimmer line that fills available width by default.
class _ShimmerLine extends StatelessWidget {
  const _ShimmerLine({this.width, this.height = 13});
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      LoadingShimmer(width: width, height: height, borderRadius: 4);
}

/// A shimmer block with explicit width × height (for image / card areas).
class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({required this.height, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      LoadingShimmer(width: width, height: height, borderRadius: radius);
}

/// Matches the layout of SkinCard: tall image area + name + price row.
class SkinCardShimmer extends StatelessWidget {
  const SkinCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier accent bar
          _ShimmerBox(height: 3, radius: 2),
          SizedBox(height: 12),
          // Weapon image area
          Expanded(child: _ShimmerBox(height: double.infinity, radius: 10)),
          SizedBox(height: 14),
          // Skin name
          _ShimmerLine(height: 15),
          SizedBox(height: 8),
          // Price chip
          _ShimmerLine(width: 80, height: 11),
        ],
      ),
    );
  }
}

// ── HomeSkeleton ──────────────────────────────────────────────────────────────

/// Full-page skeleton for HomeScreen.
/// Must be used as a Sliver (via [asSliver]) so it sits inside the same
/// CustomScrollView as the actual content — otherwise scroll context differs
/// and the layout won't match what the user sees after data loads.
///
/// Layout mirrors _buildContent exactly:
///   1. Timer bar  (36 px)
///   2. FEATURED BUNDLE header + 190 px banner card
///   3. DAILY SHOP header + single full-width skin card (280 px) + dots row
///   4. 3 quick-stat cards (150 px)
///   5. VALORANT NEWS header + horizontal 196 px news strip
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  /// Returns this skeleton as a [SliverList] so it can be dropped directly
  /// into a [CustomScrollView] alongside other slivers.
  static Widget asSliver() => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        sliver: SliverList(
          delegate: SliverChildListDelegate(const [
            // ── 1. Timer bar ───────────────────────────────────────────────
            _ShimmerBox(height: 36, radius: 10),
            SizedBox(height: 20),

            // ── 2. Featured Bundle ─────────────────────────────────────────
            _ShimmerLine(width: 140, height: 12),
            SizedBox(height: 10),
            _ShimmerBox(height: 190, radius: 16),
            SizedBox(height: 20),

            // ── 3. Daily Shop ──────────────────────────────────────────────
            _ShimmerLine(width: 100, height: 12),
            SizedBox(height: 10),
            SkinCardShimmer(),
            SizedBox(height: 10),
            _HomeSkeletonDotsRow(),
            SizedBox(height: 20),

            // ── 4. Quick Cards ─────────────────────────────────────────────
            _HomeSkeletonQuickCards(),
            SizedBox(height: 20),

            // ── 5. Valorant News ───────────────────────────────────────────
            _ShimmerLine(width: 120, height: 12),
            SizedBox(height: 10),
            _HomeSkeletonNewsRow(),
          ]),
        ),
      );

  // Kept for any call-sites that still use HomeSkeleton() directly.
  @override
  Widget build(BuildContext context) => HomeSkeleton.asSliver();
}

class _HomeSkeletonDotsRow extends StatelessWidget {
  const _HomeSkeletonDotsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _ShimmerBox(width: 110, height: 10, radius: 4),
        const Spacer(),
        Row(
          children: List.generate(
              4,
              (i) => Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                    child: _ShimmerBox(
                      width: i == 0 ? 18 : 6,
                      height: 6,
                      radius: 3,
                    ),
                  )),
        ),
      ],
    );
  }
}

class _HomeSkeletonQuickCards extends StatelessWidget {
  const _HomeSkeletonQuickCards();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
          3,
          (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                  child: const _ShimmerBox(height: 150, radius: 14),
                ),
              )),
    );
  }
}

class _HomeSkeletonNewsRow extends StatelessWidget {
  const _HomeSkeletonNewsRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: Row(
        children: List.generate(
            3,
            (i) => Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : 12),
                  child: const _ShimmerBox(width: 230, height: 196, radius: 14),
                )),
      ),
    );
  }
}

// ── MatchHistorySkeleton ──────────────────────────────────────────────────────

/// Matches the layout of MatchHistoryScreen:
/// stats banner + list of match tiles.
class MatchHistorySkeleton extends StatelessWidget {
  const MatchHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Stats banner
        const _ShimmerBox(height: 90, radius: 16),
        const SizedBox(height: 12),
        // Match tiles
        ...List.generate(
            8,
            (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: _MatchTileShimmer(),
                )),
      ],
    );
  }
}

class _MatchTileShimmer extends StatelessWidget {
  const _MatchTileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: const Row(
        children: [
          // Map thumbnail
          _ShimmerBox(width: 72, height: 56, radius: 8),
          SizedBox(width: 10),
          // Agent circle
          LoadingShimmer(width: 30, height: 30, borderRadius: 15),
          SizedBox(width: 8),
          // Text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerLine(width: 70, height: 11),
                SizedBox(height: 6),
                _ShimmerLine(height: 13),
                SizedBox(height: 5),
                _ShimmerLine(width: 90, height: 11),
              ],
            ),
          ),
          SizedBox(width: 12),
          // KDA column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ShimmerLine(width: 32, height: 9),
              SizedBox(height: 5),
              _ShimmerLine(width: 60, height: 13),
              SizedBox(height: 4),
              _ShimmerLine(width: 44, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

// ── RankSkeleton ──────────────────────────────────────────────────────────────

/// Matches RankScreen leaderboard tab: rank card + sparkline + peak card.
class RankSkeleton extends StatelessWidget {
  const RankSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: const [
        // Rank card (icon + stats)
        _ShimmerBox(height: 160, radius: 16),
        SizedBox(height: 20),
        // Sparkline card
        _ShimmerBox(height: 100, radius: 14),
        SizedBox(height: 20),
        // Peak rank card
        _ShimmerBox(height: 90, radius: 14),
        SizedBox(height: 16),
        // Info notice
        _ShimmerBox(height: 56, radius: 12),
      ],
    );
  }
}

/// Matches RankScreen match-history tab: list of update tiles.
class RankHistorySkeleton extends StatelessWidget {
  const RankHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        const _ShimmerLine(width: 200, height: 12),
        const SizedBox(height: 14),
        ...List.generate(
            10,
            (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 0),
                  child: _UpdateTileShimmer(),
                )),
      ],
    );
  }
}

class _UpdateTileShimmer extends StatelessWidget {
  const _UpdateTileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: const Row(
        children: [
          _ShimmerBox(width: 3, height: 18, radius: 2),
          SizedBox(width: 12),
          _ShimmerBox(width: 18, height: 18, radius: 4),
          SizedBox(width: 10),
          Expanded(child: _ShimmerLine(height: 15)),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ShimmerLine(width: 60, height: 13),
            ],
          ),
        ],
      ),
    );
  }
}

// ── ContractsSkeleton ─────────────────────────────────────────────────────────

/// Mirrors _ContractsContent layout exactly:
///   1. BATTLE PASS header + tall card (with optional banner art area)
///   2. ACTIVE MISSIONS header + 3 mission tiles
///   3. AGENT CONTRACTS header + 6 agent contract tiles (with avatar)
class ContractsSkeleton extends StatelessWidget {
  const ContractsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // ── 1. Battle Pass ─────────────────────────────────────────────────
        const _ShimmerLine(width: 110, height: 12),
        const SizedBox(height: 10),
        // Card: banner image area + content area — mirrors _BattlepassCard
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: const Column(
            children: [
              // Banner art placeholder
              _ShimmerBox(height: 80, radius: 0),
              Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _ShimmerBox(width: 44, height: 44, radius: 10),
                      SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerLine(width: 110, height: 14),
                          SizedBox(height: 6),
                          _ShimmerLine(width: 60, height: 11),
                        ],
                      ),
                    ]),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ShimmerLine(width: 90, height: 10),
                        _ShimmerLine(width: 100, height: 10),
                      ],
                    ),
                    SizedBox(height: 8),
                    _ShimmerBox(height: 8, radius: 4),
                    SizedBox(height: 16),
                    _ShimmerBox(height: 44, radius: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── 2. Active Missions ─────────────────────────────────────────────
        const _ShimmerLine(width: 140, height: 12),
        const SizedBox(height: 10),
        ...List.generate(3, (_) => const _MissionTileShimmer()),
        const SizedBox(height: 24),

        // ── 3. Agent Contracts ─────────────────────────────────────────────
        const _ShimmerLine(width: 150, height: 12),
        const SizedBox(height: 10),
        // Each tile: avatar circle + name + tier + progress bar
        ...List.generate(
            6,
            (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _AgentContractTileShimmer(),
                )),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _AgentContractTileShimmer extends StatelessWidget {
  const _AgentContractTileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        children: [
          // Agent portrait square
          _ShimmerBox(width: 44, height: 44, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerLine(width: 100, height: 13),
                SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ShimmerLine(width: 50, height: 11),
                    _ShimmerLine(width: 80, height: 10),
                  ],
                ),
                SizedBox(height: 6),
                _ShimmerBox(height: 5, radius: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionTileShimmer extends StatelessWidget {
  const _MissionTileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ShimmerBox(width: 18, height: 18, radius: 4),
              SizedBox(width: 8),
              _ShimmerLine(width: 40, height: 10),
              SizedBox(width: 8),
              Expanded(child: _ShimmerLine(height: 13)),
              SizedBox(width: 8),
              _ShimmerLine(width: 60, height: 10),
            ],
          ),
          SizedBox(height: 8),
          _ShimmerBox(height: 6, radius: 4),
        ],
      ),
    );
  }
}

// ── LoadoutSkeleton ───────────────────────────────────────────────────────────

/// Matches LoadoutScreen: identity card + weapon tiles by category.
class LoadoutSkeleton extends StatelessWidget {
  const LoadoutSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Section header + identity card
        const _ShimmerLine(width: 80, height: 12),
        const SizedBox(height: 10),
        const _ShimmerBox(height: 180, radius: 16),
        const SizedBox(height: 20),
        // Weapon categories
        ...List.generate(
            4,
            (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ShimmerLine(width: 70, height: 12),
                    const SizedBox(height: 10),
                    ...List.generate(
                        3,
                        (__) => const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: _WeaponTileShimmer(),
                            )),
                    const SizedBox(height: 12),
                  ],
                )),
      ],
    );
  }
}

class _WeaponTileShimmer extends StatelessWidget {
  const _WeaponTileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        children: [
          _ShimmerBox(width: 82, height: 48, radius: 8),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerLine(height: 13),
                SizedBox(height: 6),
                _ShimmerLine(width: 80, height: 9),
              ],
            ),
          ),
          SizedBox(width: 12),
          _ShimmerBox(width: 34, height: 34, radius: 8),
        ],
      ),
    );
  }
}

// ── ProfileSkeleton ───────────────────────────────────────────────────────────

/// Matches ProfileScreen: header banner + level card + stats row + xp section.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Profile header banner (avatar + name)
        const _ShimmerBox(height: 150, radius: 20),
        const SizedBox(height: 12),
        // Account health banner
        const _ShimmerBox(height: 44, radius: 14),
        const SizedBox(height: 16),
        // Level + XP card
        const _ShimmerBox(height: 110, radius: 20),
        const SizedBox(height: 16),
        // Level border card
        const _ShimmerBox(height: 100, radius: 16),
        const SizedBox(height: 16),
        // 3 quick stat cards
        Row(
          children: List.generate(
              3,
              (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: const _ShimmerBox(height: 90, radius: 16),
                    ),
                  )),
        ),
        const SizedBox(height: 20),
        // XP gains section
        const _ShimmerBox(height: 200, radius: 20),
        const SizedBox(height: 16),
        // Loadout link
        const _ShimmerBox(height: 64, radius: 16),
      ],
    );
  }
}

// ── MatchDetailSkeleton ───────────────────────────────────────────────────────

/// Matches MatchDetailScreen: map header + two team sections + player rows.
class MatchDetailSkeleton extends StatelessWidget {
  const MatchDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Map header card
        const _ShimmerBox(height: 130, radius: 14),
        const SizedBox(height: 20),
        // Team section header + player rows
        ...[
          for (var t = 0; t < 2; t++) ...[
            const _ShimmerLine(width: 80, height: 12),
            const SizedBox(height: 10),
            ...List.generate(
                5,
                (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 0),
                      child: _PlayerRowShimmer(),
                    )),
            const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }
}

class _PlayerRowShimmer extends StatelessWidget {
  const _PlayerRowShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.8)),
      ),
      child: const Row(
        children: [
          _ShimmerBox(width: 3, height: 16, radius: 2),
          SizedBox(width: 8),
          LoadingShimmer(width: 32, height: 32, borderRadius: 16),
          SizedBox(width: 8),
          Expanded(child: _ShimmerLine(height: 13)),
          SizedBox(width: 16),
          _ShimmerLine(width: 20, height: 20),
          SizedBox(width: 8),
          _ShimmerLine(width: 70, height: 13),
          SizedBox(width: 16),
          _ShimmerLine(width: 42, height: 12),
        ],
      ),
    );
  }
}

// ── WishlistCatalogSkeleton ───────────────────────────────────────────────────

/// Matches WishlistCatalogScreen: sidebar + 2-column skin grid.
class WishlistCatalogSkeleton extends StatelessWidget {
  const WishlistCatalogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left sidebar
        Container(
          width: 72,
          decoration: const BoxDecoration(
            border:
                Border(right: BorderSide(color: Colors.white10, width: 0.8)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            children: List.generate(
                8,
                (i) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          _ShimmerBox(width: 24, height: 24, radius: 6),
                          SizedBox(height: 4),
                          _ShimmerLine(width: 44, height: 7),
                        ],
                      ),
                    )),
          ),
        ),
        // Right grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: 6,
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: AppColors.bgCard2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              padding: const EdgeInsets.all(12),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _ShimmerBox(height: double.infinity, radius: 10)),
                  SizedBox(height: 10),
                  _ShimmerLine(height: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
