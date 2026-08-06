import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'valorant_icons.dart';

/// Tactical Valorant Protocol Error Display Card.
/// Parses raw exceptions into clear, authentic Valorant telemetry error states with user-friendly explanations.
class ValorantErrorDisplay extends StatelessWidget {
  const ValorantErrorDisplay({
    super.key,
    required this.error,
    required this.onRetry,
    this.onReauth,
    this.title,
    this.compact = false,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onReauth;
  final String? title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final info = _parseError(error);

    if (compact) {
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
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded,
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
        backgroundColor: const Color(0xFF0C0810),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // Top Telemetry Header Tag
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red.withAlpha(40),
                    border: Border.all(color: AppColors.red, width: 0.8),
                    borderRadius: BorderRadius.circular(4),
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
                      const SizedBox(width: 6),
                      Text(
                        info.code,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  'VALORANT // PROTOCOL',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Error Headline
            Text(
              (title ?? info.headline).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),

            // Detailed Tactical Explanation
            Text(
              info.explanation,
              style: const TextStyle(
                color: Color(0xFFB0BAC8),
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),

            if (info.rawMessage != null && info.rawMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10, width: 0.8),
                ),
                child: Text(
                  'DEBUG TELEMETRY: ${info.rawMessage}',
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

            const SizedBox(height: 20),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.red.withAlpha(120),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'SYSTEM RECONNECT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                if (info.isAuthRelated && onReauth != null) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onReauth,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red, width: 1.2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'RE-LOGIN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  _ErrorDetail _parseError(Object error) {
    final str = error.toString();

    if (str.contains('401') ||
        str.contains('AuthException') ||
        str.contains('TokenExpired') ||
        str.contains('InvalidSession')) {
      return _ErrorDetail(
        code: 'ERR // AUTH_SESSION_EXPIRED',
        headline: 'Sesi Autentikasi Riot Berakhir',
        explanation:
            'Sesi token Riot Anda telah kedaluwarsa. Aplikasi akan mencoba memperbarui token secara otomatis saat Anda menekan tombol di bawah.',
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
