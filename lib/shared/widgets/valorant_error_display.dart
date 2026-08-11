import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'valorant_icons.dart';

/// Tactical Valorant Protocol Error Display Card.
/// Parses raw exceptions into clear, authentic Valorant telemetry error states with user-friendly explanations.
class ValorantErrorDisplay extends StatefulWidget {
  const ValorantErrorDisplay({
    super.key,
    required this.error,
    required this.onRetry,
    this.onReauth,
    this.title,
    this.compact = false,
  });

  final Object error;
  final FutureOr<void> Function() onRetry;
  final VoidCallback? onReauth;
  final String? title;
  final bool compact;

  @override
  State<ValorantErrorDisplay> createState() => _ValorantErrorDisplayState();
}

class _ValorantErrorDisplayState extends State<ValorantErrorDisplay> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      await widget.onRetry();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _parseError(widget.error);

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF140A0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.red.withAlpha(120), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info.code,
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isRetrying ? null : _handleRetry,
              icon: _isRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.red, strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded,
                      color: AppColors.red, size: 20),
              tooltip: 'Retry',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ValorantHudBox(
        accentColor: AppColors.red,
        backgroundColor: const Color(0xFF0F0B12),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Telemetry Header Tag
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.red.withAlpha(35),
                    border: Border.all(color: AppColors.red.withAlpha(180), width: 1),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withAlpha(40),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        info.code,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  'VALORANT // PROTOCOL',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Error Headline
            Text(
              (widget.title ?? info.headline).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            // Detailed Tactical Explanation
            Text(
              info.explanation,
              style: const TextStyle(
                color: Color(0xFFB5C1D0),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),

            if (info.rawMessage != null && info.rawMessage!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Text(
                  'TELEMETRY LOG: ${info.rawMessage}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Single Full-Width Primary Reconnect Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isRetrying ? null : _handleRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: AppColors.red.withAlpha(140),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: _isRetrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(
                  _isRetrying ? 'CONNECTING TO RIOT...' : 'SYSTEM RECONNECT',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ErrorDetail _parseError(Object error) {
    final str = error.toString();

    if (str.contains('401') ||
        str.contains('403') ||
        str.contains('400') ||
        str.contains('bad response') ||
        str.contains('AuthException') ||
        str.contains('TokenExpired') ||
        str.contains('InvalidSession') ||
        str.contains('unauthorized') ||
        str.contains('forbidden')) {
      return _ErrorDetail(
        code: 'ERR // AUTH_SESSION_EXPIRED',
        headline: 'Sesi Autentikasi Terputus',
        explanation:
            'Sesi token Riot Games Anda membutuhkan pembaruan. Tekan SYSTEM RECONNECT untuk mereset dan menghubungkan kembali sesi Anda.',
        isAuthRelated: true,
        rawMessage: str,
      );
    }

    if (str.contains('429') || str.contains('RateLimited')) {
      return _ErrorDetail(
        code: 'ERR // RATE_LIMIT_THROTTLED',
        headline: 'Batas Permintaan Terlampaui (429)',
        explanation:
            'Peladen Riot Games sedang menerima terlalu banyak permintaan sekaligus. Harap tunggu beberapa saat lalu coba hubungkan kembali.',
        isAuthRelated: false,
        rawMessage: str,
      );
    }

    if (str.contains('SocketException') ||
        str.contains('Timeout') ||
        str.contains('connection') ||
        str.contains('Network')) {
      return _ErrorDetail(
        code: 'ERR // CONNECTION_TIMEOUT',
        headline: 'Jaringan Terputus / Disconnected',
        explanation:
            'Gagal terhubung ke peladen Valorant Riot. Pastikan perangkat Anda terhubung ke internet dan coba lagi.',
        isAuthRelated: false,
        rawMessage: str,
      );
    }

    return _ErrorDetail(
      code: 'ERR // PROTOCOL_RESPONSE_FAIL',
      headline: 'Gagal Memuat Data Peladen',
      explanation:
          'Terjadi kendala saat mengambil data dari API Riot Games. Tekan tombol Reconnect untuk mencoba lagi.',
      isAuthRelated: false,
      rawMessage: str,
    );
  }
}

class _ErrorDetail {
  final String code;
  final String headline;
  final String explanation;
  final bool isAuthRelated;
  final String? rawMessage;

  const _ErrorDetail({
    required this.code,
    required this.headline,
    required this.explanation,
    required this.isAuthRelated,
    this.rawMessage,
  });
}
