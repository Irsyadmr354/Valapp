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
  ConsumerState<AccountSwitcherModal> createState() => _AccountSwitcherModalState();
}

class _AccountSwitcherModalState extends ConsumerState<AccountSwitcherModal> {
  List<SavedAccountProfile> _savedAccounts = [];
  bool _isLoading = true;

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
                            onTap: () async {
                              if (!isActive) {
                                final source = ref.read(credentialsLocalSourceProvider);
                                await source.save(acc.credentials,
                                    displayName: acc.displayName);
                                ref.invalidate(currentCredentialsProvider);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Switched to ${acc.displayName}'),
                                      backgroundColor: AppColors.red,
                                    ),
                                  );
                                }
                              }
                            },
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
                                  color: isActive
                                      ? AppColors.red
                                      : Colors.white10,
                                  width: isActive ? 1.8 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Account Avatar Icon
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.red.withAlpha(40)
                                          : const Color(0xFF070A10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.person,
                                        color: isActive
                                            ? AppColors.red
                                            : Colors.white54,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Account Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                        final source = ref.read(credentialsLocalSourceProvider);
                                        await source.removeAccount(acc.puuid);
                                        await _loadAccounts();
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
