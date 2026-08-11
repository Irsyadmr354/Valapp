import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/di/providers.dart';
import 'core/navigation/navigator_key.dart';
import 'shared/utils/app_colors.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/webview_login_screen.dart';
import 'features/match/presentation/match_detail_screen.dart';
import 'features/match/presentation/match_history_screen.dart';
import 'features/rank/presentation/rank_screen.dart';
import 'features/shop/presentation/home_screen.dart';
import 'features/shop/presentation/wishlist_catalog_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/contracts/presentation/contracts_screen.dart';
import 'features/loadout/presentation/loadout_screen.dart';
import 'features/debug/presentation/notification_debug_screen.dart';

// ── Router ────────────────────────────────────────────────────────────────────

/// Notifier that GoRouter watches — fires when credentials change.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(this._ref) {
    _ref.listen(currentCredentialsProvider, (_, __) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final _routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthChangeNotifier(ref);
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/shop',
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final credsAsync = ref.read(currentCredentialsProvider);
      if (credsAsync.isLoading) return null;

      final creds = credsAsync.value;
      final location = state.matchedLocation;
      final isAuthRoute =
          location == '/login' || location.startsWith('/login/');

      if (creds == null && !isAuthRoute) return '/login';
      if (creds != null && location == '/login') return '/shop';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/login/webview',
          builder: (_, __) => const WebViewLoginScreen()),
      GoRoute(
          path: '/wishlist', builder: (_, __) => const WishlistCatalogScreen()),
      GoRoute(
          path: '/debug/notifications',
          builder: (_, __) => const NotificationDebugScreen()),
      GoRoute(path: '/loadout', builder: (_, __) => const LoadoutScreen()),
      GoRoute(
        path: '/match/:id',
        builder: (_, state) =>
            MatchDetailScreen(matchId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) => _ScaffoldWithNav(child: child),
        routes: [
          GoRoute(path: '/shop', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/rank', builder: (_, __) => const RankScreen()),
          GoRoute(
              path: '/matches', builder: (_, __) => const MatchHistoryScreen()),
          GoRoute(
              path: '/progress', builder: (_, __) => const ContractsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

// ── App entry ─────────────────────────────────────────────────────────────────

class ValorantShopApp extends ConsumerWidget {
  const ValorantShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'ValAPP',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.red,
        secondary: AppColors.vpCyan,
        surface: AppColors.bgCard,
        onSurface: Colors.white,
        error: AppColors.red,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPanel,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgPanel,
        selectedItemColor: AppColors.red,
        unselectedItemColor: Color(0xFF5C6B7A),
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.red,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgCard2,
        selectedColor: AppColors.red.withAlpha(50),
        side: const BorderSide(color: AppColors.border, width: 0.8),
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: const BorderSide(color: AppColors.red),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.8,
      ),
    );
  }
}

// ── Shell with Valorant bottom nav ────────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});
  final Widget child;

  // (route, outlinedIcon, filledIcon, label)
  static const _tabs = [
    ('/shop', Icons.storefront_outlined, Icons.storefront_rounded, 'Home'),
    ('/rank', Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'Rank'),
    (
      '/matches',
      Icons.sports_esports_outlined,
      Icons.sports_esports_rounded,
      'Matches'
    ),
    (
      '/progress',
      Icons.assignment_outlined,
      Icons.assignment_rounded,
      'Progress'
    ),
    ('/profile', Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabs.indexWhere((t) => t.$1 == location).clamp(0, 4);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: child,
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i].$1),
        tabs: _tabs,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.tabs,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<(String, IconData, IconData, String)> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(
          top: BorderSide(color: AppColors.red, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x44FF4655),
            blurRadius: 14,
            spreadRadius: -2,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final isSelected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: isSelected
                            ? const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4)
                            : EdgeInsets.zero,
                        decoration: isSelected
                            ? BoxDecoration(
                                color: AppColors.red.withAlpha(35),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.red.withAlpha(130),
                                  width: 1,
                                ),
                              )
                            : null,
                        child: Icon(
                          isSelected ? tab.$3 : tab.$2,
                          size: 22,
                          color: isSelected
                              ? AppColors.red
                              : const Color(0xFF5C6B7A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.$4,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.red
                              : const Color(0xFF5C6B7A),
                          letterSpacing: isSelected ? 0.4 : 0,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
