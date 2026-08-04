import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../data/credentials_local_source.dart';

/// Modal dialog for managing and switching between multiple saved Valorant accounts.
class AccountSwitcherModal extends ConsumerStatefulWidget {
  const AccountSwitcherModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AccountSwitcherModal(),
    );
  }

  @override
  ConsumerState<AccountSwitcherModal> createState() =>
      _AccountSwitcherModalState();
}

class _AccountSwitcherModalState extends ConsumerState<AccountSwitcherModal> {
  List<SavedAccountProfile> _savedAccounts = [];
  bool _isLoading = true;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final source = ref.read(credentialsLocalSourceProvider);
    final list = await source.getSavedAccounts();
    if (mounted) {
      setState(() {
        _savedAccounts = list;
        _isLoading = false;
      });
    }

    // Auto-resolve real Riot ID and Player Card Avatar for saved accounts
    _resolveAccountMetadata(list);
  }

  Future<void> _switchAccount(SavedAccountProfile account) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await ref.read(sessionActionsProvider).switchAccount(account);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${account.displayName}'),
          backgroundColor: AppColors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to switch account: $error')),
      );
    }
  }

  Future<void> _resolveAccountMetadata(List<SavedAccountProfile> list) async {
    try {
      final remoteSource = await ref.read(accountRemoteSourceProvider.future);
      final loadoutSource = await ref.read(loadoutRemoteSourceProvider.future);
      final assets = ref.read(valorantAssetsProvider);
      final localSource = ref.read(credentialsLocalSourceProvider);
      final activeCredentials = await localSource.load();
      final cardsMap = await assets.getPlayerCardsMap();

      for (final acc in list) {
        // Private account metadata must be fetched with that account's token.
        if (acc.puuid != activeCredentials?.puuid) continue;
        String? newName = acc.displayName;
        String? newAvatar = acc.avatarUrl;
        String? newCardId = acc.playerCardId;
        bool needsUpdate = false;

        if (newName.startsWith('Account (') ||
            newName == 'Valorant Account' ||
            newName == 'Valorant Player') {
          final realName =
              await remoteSource.fetchDisplayName(acc.shard, acc.puuid);
          if (realName != null && realName.isNotEmpty) {
            newName = realName;
            needsUpdate = true;
          }
        }

        if (newAvatar == null || newAvatar.isEmpty) {
          try {
            final rawLoadout =
                await loadoutSource.fetchLoadoutRaw(acc.shard, acc.puuid);
            final loadoutRoot = rawLoadout.containsKey('Loadout')
                ? (rawLoadout['Loadout'] as Map<String, dynamic>? ?? {})
                : rawLoadout;
            final identity = loadoutRoot['Identity'] as Map<String, dynamic>? ??
                rawLoadout['Identity'] as Map<String, dynamic>? ??
                {};
            final cardId = identity['PlayerCardID'] as String? ??
                loadoutRoot['PlayerCardID'] as String? ??
                rawLoadout['PlayerCardID'] as String?;
            if (cardId != null && cardId.isNotEmpty) {
              newCardId = cardId;
              final cardInfo = (cardsMap[cardId] ??
                  cardsMap[cardId.toLowerCase()]) as Map<String, dynamic>?;
              newAvatar = cardInfo?['smallArt'] as String? ??
                  cardInfo?['displayIcon'] as String?;
              if (newAvatar != null && newAvatar.isNotEmpty) {
                needsUpdate = true;
              }
            }
          } catch (_) {}
        }

        if (needsUpdate) {
          await localSource.updateAccountMetadata(
            acc.puuid,
            displayName: newName,
            playerCardId: newCardId,
            avatarUrl: newAvatar,
          );
        }
      }

      final updated = await localSource.getSavedAccounts();
      if (mounted) {
        setState(() {
          _savedAccounts = updated;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final currentCredsAsync = ref.watch(currentCredentialsProvider);
    final activePuuid = currentCredsAsync.asData?.value?.puuid;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1622),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFFF4655), width: 1.5),
        ),
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MULTI-ACCOUNT MANAGER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Switch between main and alt accounts instantly',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
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

          // Saved Accounts List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF4655)),
                  )
                : _savedAccounts.isEmpty
                    ? const Center(
                        child: Text(
                          'No saved accounts found.',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _savedAccounts.length,
                        itemBuilder: (context, idx) {
                          final acc = _savedAccounts[idx];
                          final isActive = acc.puuid == activePuuid;

                          return GestureDetector(
                            onTap: isActive || _actionInProgress
                                ? null
                                : () => _switchAccount(acc),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.red.withAlpha(20)
                                    : AppColors.bgCard2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      isActive ? AppColors.red : Colors.white10,
                                  width: isActive ? 1.8 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Account Avatar Icon displaying Player Card artwork
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.red.withAlpha(40)
                                          : const Color(0xFF070A10),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isActive
                                            ? AppColors.red
                                            : Colors.white10,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: acc.avatarUrl != null &&
                                              acc.avatarUrl!.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: acc.avatarUrl!,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Center(
                                                child: Text(
                                                  acc.displayName.isNotEmpty
                                                      ? acc.displayName[0]
                                                          .toUpperCase()
                                                      : 'V',
                                                  style: TextStyle(
                                                    color: isActive
                                                        ? Colors.white
                                                        : Colors.white70,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  Center(
                                                child: Text(
                                                  acc.displayName.isNotEmpty
                                                      ? acc.displayName[0]
                                                          .toUpperCase()
                                                      : 'V',
                                                  style: TextStyle(
                                                    color: isActive
                                                        ? Colors.white
                                                        : Colors.white70,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                acc.displayName.isNotEmpty
                                                    ? acc.displayName[0]
                                                        .toUpperCase()
                                                    : 'V',
                                                style: TextStyle(
                                                  color: isActive
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Account Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          acc.displayName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Region: ${acc.region.toUpperCase()} • Shard: ${acc.shard.toUpperCase()}',
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (isActive) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.red.withAlpha(40),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: AppColors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.white38, size: 20),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor:
                                                const Color(0xFF0E1622),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              side: const BorderSide(
                                                  color: AppColors.red,
                                                  width: 1.5),
                                            ),
                                            title: const Text(
                                              'Hapus Akun?',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            content: Text(
                                              'Akun "${acc.displayName}" akan dihapus dari daftar. Kamu bisa login kembali kapan saja.',
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                            actionsPadding:
                                                const EdgeInsets.fromLTRB(
                                                    16, 0, 16, 16),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx)
                                                        .pop(false),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.white54,
                                                ),
                                                child: const Text(
                                                  'BATAL',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.red,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 20,
                                                      vertical: 10),
                                                ),
                                                child: const Text(
                                                  'HAPUS',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          if (_actionInProgress) return;
                                          setState(
                                              () => _actionInProgress = true);
                                          try {
                                            await ref
                                                .read(sessionActionsProvider)
                                                .removeAccount(acc.puuid);
                                            if (mounted) await _loadAccounts();
                                          } finally {
                                            if (mounted) {
                                              setState(() =>
                                                  _actionInProgress = false);
                                            }
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Add New Account Action Button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/login/webview');
                },
                icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                label: const Text(
                  '+ ADD ANOTHER RIOT ACCOUNT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
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
