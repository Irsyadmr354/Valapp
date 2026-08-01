import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/utils/app_colors.dart';
import 'login_controller.dart';

class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final List<TextEditingController> _ctrlList =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusList = List.generate(6, (_) => FocusNode());

  // Resend cooldown
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    for (final c in _ctrlList) { c.dispose(); }
    for (final f in _focusList) { f.dispose(); }
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _code => _ctrlList.map((c) => c.text).join();

  void _startResendCooldown() {
    setState(() => _resendCooldown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);

    final isTotp = state is LoginNeedsMfa && state.method == 'totp';
    final maskedEmail = state is LoginNeedsMfa ? state.maskedEmail : '';
    final isLoading = state is MfaLoading;

    ref.listen(loginControllerProvider, (prev, next) {
      if (next is LoginSuccess) context.go('/shop');
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            controller.reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Icon badge
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.redSubtle,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.red, width: 1.5),
                    boxShadow: AppColors.redGlow(alpha: 0.35, blur: 20),
                  ),
                  child: Center(
                    child: Icon(
                      isTotp ? Icons.security_rounded : Icons.mark_email_unread_outlined,
                      color: AppColors.red,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isTotp ? 'Authenticator Code' : 'Check Your Email',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                isTotp
                    ? 'Enter the 6-digit code from your Authenticator App\n(Google Authenticator, Authy, etc.)'
                    : maskedEmail.isNotEmpty
                        ? 'Enter the 6-digit code sent to $maskedEmail'
                        : 'Enter the 6-digit code sent to your email.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // Error banner
              if (state is LoginError) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.red.withAlpha(20),
                    border: Border.all(color: AppColors.red.withAlpha(100)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.message,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 6-digit boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) => _buildDigitBox(i, isLoading)),
              ),
              const SizedBox(height: 36),

              // Verify button
              GestureDetector(
                onTap: isLoading || _code.length != 6
                    ? null
                    : () => controller.submitMfaCode(_code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: isLoading || _code.length != 6
                        ? const LinearGradient(
                            colors: [Color(0xFF3A1118), Color(0xFF2A0D12)])
                        : AppColors.redGradient,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isLoading || _code.length != 6
                        ? []
                        : AppColors.redGlow(alpha: 0.35, blur: 18),
                  ),
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'VERIFY CODE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Resend row (email MFA only)
              if (!isTotp)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Didn't receive it?  ",
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: _resendCooldown > 0
                          ? null
                          : () {
                              _startResendCooldown();
                              // Re-trigger login flow to resend
                              controller.reset();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please log in again to resend the code.'),
                                  backgroundColor: AppColors.bgCard2,
                                ),
                              );
                            },
                      child: Text(
                        _resendCooldown > 0
                            ? 'Resend in ${_resendCooldown}s'
                            : 'Resend code',
                        style: TextStyle(
                          color: _resendCooldown > 0
                              ? AppColors.textMuted
                              : AppColors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),
              Text(
                isTotp
                    ? 'Open your Authenticator App and enter the current 6-digit code.'
                    : 'The code expires in a few minutes. Check your spam folder if not received.',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitBox(int index, bool disabled) {
    return SizedBox(
      width: 46,
      height: 58,
      child: TextField(
        controller: _ctrlList[index],
        focusNode: _focusList[index],
        enabled: !disabled,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
        keyboardType: TextInputType.number,
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.bgCard2,
          border: OutlineInputBorder(
            borderSide: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: AppColors.red, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border.withAlpha(80)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusList[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusList[index - 1].requestFocus();
          }
          setState(() {});
        },
      ),
    );
  }
}
