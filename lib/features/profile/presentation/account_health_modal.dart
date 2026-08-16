import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/date_time_utils.dart';
import '../../../shared/widgets/modal_drag_handle.dart';
import '../domain/models/account_health.dart';

final accountHealthProvider =
    FutureProvider.autoDispose<AccountHealth?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(restrictionsRemoteSourceProvider.future);
  return source.fetchAccountHealth(creds.shard, creds.puuid);
});

class AccountHealthModal extends ConsumerWidget {
  const AccountHealthModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AccountHealthModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(accountHealthProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1.2),
        ),
      ),
      child: Column(
        children: [
          const ModalDragHandle(width: 36, bottomMargin: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.health_and_safety_outlined,
                        color: AppColors.red, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'ACCOUNT HEALTH & STATUS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 20),

          // Body
          Expanded(
            child: healthAsync.when(
              data: (health) {
                if (health == null) {
                  return const Center(
                    child: Text('Unable to load account health',
                        style: TextStyle(color: Colors.white38)),
                  );
                }
                return _AccountHealthBody(health: health);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.red),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: $err',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountHealthBody extends StatelessWidget {
  const _AccountHealthBody({required this.health});
  final AccountHealth health;

  @override
  Widget build(BuildContext context) {
    final statusColor = health.isUnknown
        ? AppColors.textMuted
        : health.isClean
            ? AppColors.win
            : AppColors.red;
    final statusText = health.isUnknown
        ? 'STATUS UNKNOWN // UNABLE TO VERIFY'
        : health.isClean
            ? 'EXCELLENT // NO PENALTIES'
            : 'RESTRICTIONS ACTIVE';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Top Health Status Badge Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withAlpha(90), width: 1),
            boxShadow: [
              BoxShadow(
                color: statusColor.withAlpha(30),
                blurRadius: 16,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withAlpha(35),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Center(
                  child: Icon(
                    health.isUnknown
                        ? Icons.help_outline_rounded
                        : health.isClean
                            ? Icons.shield_outlined
                            : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS',
                      style: TextStyle(
                        color: statusColor.withAlpha(200),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      health.isUnknown
                          ? 'Could not verify account restrictions from Riot servers.'
                          : health.isClean
                              ? 'Your account is in good standing with zero active restrictions.'
                              : '${health.penalties.length} active penalty / restriction currently applied.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Section 1: Active Penalties
        Row(
          children: [
            Container(width: 3, height: 12, color: AppColors.red),
            const SizedBox(width: 8),
            const Text(
              'ACTIVE PENALTIES & RESTRICTIONS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (health.penalties.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: AppColors.win, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No active AFK, queue delay, or communication restrictions.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children:
                health.penalties.map((p) => _PenaltyCard(penalty: p)).toList(),
          ),

        const SizedBox(height: 24),

        // Section 2: Avoided Teammates List
        Row(
          children: [
            Container(width: 3, height: 12, color: AppColors.red),
            const SizedBox(width: 8),
            const Text(
              'AVOIDED TEAMMATES LIST',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (health.avoidedPlayers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_off_outlined,
                    color: Colors.white38, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your avoid list is empty.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: health.avoidedPlayers
                .map((p) => _AvoidedPlayerTile(player: p))
                .toList(),
          ),

        const SizedBox(height: 24),

        // Info footer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.white38, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Restrictions and avoid list are enforced directly by Riot Games Community Code of Conduct. Keep your account clean to ensure competitive match eligibility.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PenaltyCard extends StatelessWidget {
  const _PenaltyCard({required this.penalty});
  final AccountPenalty penalty;

  @override
  Widget build(BuildContext context) {
    final expiryStr = DateTimeUtils.formatFullDateTime(penalty.expiryTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withAlpha(90), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  penalty.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  penalty.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'EXPIRATION: ',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(
                      expiryStr,
                      style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
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

class _AvoidedPlayerTile extends StatelessWidget {
  const _AvoidedPlayerTile({required this.player});
  final AvoidedPlayer player;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.person_off, color: AppColors.red, size: 18),
              const SizedBox(width: 10),
              Text(
                player.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: player.puuid));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PUUID copied!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: AppColors.bgCard2,
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, color: Colors.white38, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
