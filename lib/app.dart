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
          elevation: 4,
          shadowColor: AppColors.red.withAlpha(120),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppColors.red, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
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
    ('/shop', Icons.storefront_outlined, Icons.storefront_rounded, 'SHOP'),
    ('/rank', Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'RANK'),
    (
      '/matches',
      Icons.sports_esports_outlined,
      Icons.sports_esports_rounded,
      'CAREER'
    ),
    (
      '/progress',
      Icons.assignment_outlined,
      Icons.assignment_rounded,
      'PROGRESS'
    ),
    ('/profile', Icons.person_outline_rounded, Icons.person_rounded, 'PROFILE'),
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
          top: BorderSide(color: Color(0xFF1F2937), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final isSelected = i == currentIndex;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: tab.$4,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Tactical active top indicator line with glow
                        if (isSelected)
                          Positioned(
                            top: 0,
                            left: 12,
                            right: 12,
                            child: Container(
                              height: 2.5,
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.red.withAlpha(200),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: isSelected
                                  ? BoxDecoration(
                                      color: AppColors.red.withAlpha(24),
                                      borderRadius: BorderRadius.circular(8),
                                    )
                                  : null,
                              child: Icon(
                                isSelected ? tab.$3 : tab.$2,
                                size: 21,
                                color: isSelected
                                    ? AppColors.red
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tab.$4,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isSelected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF6B7280),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
