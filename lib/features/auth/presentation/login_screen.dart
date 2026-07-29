import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Login screen — uses WebView to open Riot's real login page.
/// This avoids CAPTCHA/Cloudflare blocks that affect headless HTTP login.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              const _ValorantLogo(),
              const SizedBox(height: 48),

              // Info text
              const Text(
                'Sign in with your Riot Games account to access your shop, rank, and match history.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Login button — opens WebView
              FilledButton.icon(
                onPressed: () => context.push('/login/webview'),
                icon: const Icon(Icons.open_in_browser),
                label: const Text(
                  'LOGIN WITH RIOT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4655),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              const _DisclaimerText(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValorantLogo extends StatelessWidget {
  const _ValorantLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4655),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        const Text(
          'VALORANT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Shop Monitor',
          style: TextStyle(
            color: Color(0xFFFF4655),
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'This app uses the unofficial Valorant API for personal use only. '
      'Your credentials are handled by the official Riot login page and '
      'never seen or stored by this app directly.',
      style: TextStyle(color: Colors.white30, fontSize: 11),
      textAlign: TextAlign.center,
    );
  }
}
