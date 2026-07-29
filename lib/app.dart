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
import 'features/contracts/presentation/contracts_screen.dart';
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
              path: '/progress', builder: (_, __) => const ContractsScreen()),
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
      title: 'Valorant Shop Monitor',
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
        secondary: Color(0xFF0BC4C4),
        surface: Color(0xFF1A2634),
        onSurface: Colors.white,
        error: Color(0xFFFF4655),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F1923),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1923),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0F1923),
        selectedItemColor: Color(0xFFFF4655),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFFFF4655),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF4655),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

// ── Shell with bottom nav ─────────────────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});
  final Widget child;

  static const _tabs = [
    ('/shop', Icons.storefront_outlined, Icons.storefront, 'Shop'),
    ('/rank', Icons.emoji_events_outlined, Icons.emoji_events, 'Rank'),
    ('/matches', Icons.history_outlined, Icons.history, 'Matches'),
    ('/progress', Icons.task_alt_outlined, Icons.task_alt, 'Progress'),
    ('/profile', Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        _tabs.indexWhere((t) => t.$1 == location).clamp(0, 4);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i].$1),
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.$2),
                  activeIcon: Icon(t.$3),
                  label: t.$4,
                ))
            .toList(),
      ),
    );
  }
}
