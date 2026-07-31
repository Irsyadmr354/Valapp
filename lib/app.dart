import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/di/providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/mfa_screen.dart';
import 'features/auth/presentation/webview_login_screen.dart';
import 'features/match/presentation/match_detail_screen.dart';
import 'features/match/presentation/match_history_screen.dart';
import 'features/rank/presentation/rank_screen.dart';
import 'features/shop/presentation/shop_screen.dart';
import 'features/shop/presentation/wishlist_catalog_screen.dart';
import 'features/profile/presentation/profile_screen.dart';

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

  return GoRouter(
    initialLocation: '/shop',
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final credsAsync = ref.read(currentCredentialsProvider);
      // While loading, don't redirect
      if (credsAsync.isLoading) return null;

      final creds = credsAsync.value;
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' ||
          location == '/mfa' ||
          location.startsWith('/login/');

      if (creds == null && !isAuthRoute) return '/login';
      if (creds != null && location == '/login') return '/shop';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/login/webview', builder: (_, __) => const WebViewLoginScreen()),
      GoRoute(path: '/mfa', builder: (_, __) => const MfaScreen()),
      GoRoute(path: '/wishlist', builder: (_, __) => const WishlistCatalogScreen()),
      GoRoute(
        path: '/match/:id',
        builder: (_, state) =>
            MatchDetailScreen(matchId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _ScaffoldWithNav(child: child),
        routes: [
          GoRoute(path: '/shop', builder: (_, __) => const ShopScreen()),
          GoRoute(path: '/rank', builder: (_, __) => const RankScreen()),
          GoRoute(path: '/matches', builder: (_, __) => const MatchHistoryScreen()),
          GoRoute(
              path: '/progress', builder: (_, __) => const WishlistCatalogScreen()),
          GoRoute(
              path: '/profile', builder: (_, __) => const ProfileScreen()),
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
        primary: Color(0xFFFF4655),
        secondary: Color(0xFF00F0FF),
        surface: Color(0xFF0E1622),
        onSurface: Colors.white,
        error: Color(0xFFFF4655),
      ),
      scaffoldBackgroundColor: const Color(0xFF070A10),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF070A10),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF070A10),
        selectedItemColor: Color(0xFFFF4655),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFFFF4655),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF4655),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ── Shell with futuristic Valorant bottom nav ─────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});
  final Widget child;

  static const _tabs = [
    ('/shop', Icons.home_outlined, Icons.home_rounded, 'Home'),
    ('/rank', Icons.military_tech_outlined, Icons.military_tech, 'Rank'),
    ('/matches', Icons.sports_esports_outlined, Icons.sports_esports, 'Matches'),
    ('/progress', Icons.grid_view_outlined, Icons.grid_view_rounded, 'Catalog'),
    ('/profile', Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        _tabs.indexWhere((t) => t.$1 == location).clamp(0, 4);

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0F18),
          border: Border(
            top: BorderSide(color: Color(0xFFFF4655), width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFFF4655),
              blurRadius: 10,
              spreadRadius: -4,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFFF4655),
          unselectedItemColor: Colors.white38,
          selectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          onTap: (i) => context.go(_tabs[i].$1),
          items: _tabs.map((t) {
            return BottomNavigationBarItem(
              icon: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Icon(t.$2, size: 22),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4655).withAlpha(35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF4655).withAlpha(120), width: 1),
                  ),
                  child: Icon(t.$3, size: 22, color: const Color(0xFFFF4655)),
                ),
              ),
              label: t.$4,
            );
          }).toList(),
        ),
      ),
    );
  }
}
