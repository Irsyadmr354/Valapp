import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void dispose() {
    for (final c in _ctrlList) {
      c.dispose();
    }
    for (final f in _focusList) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrlList.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);

    // Determine MFA method and labels
    final isTotp = state is LoginNeedsMfa && state.method == 'totp';
    final maskedEmail =
        state is LoginNeedsMfa ? state.maskedEmail : '';
    final isLoading = state is MfaLoading;

    ref.listen(loginControllerProvider, (prev, next) {
      if (next is LoginSuccess) {
        context.go('/shop');
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            controller.reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Icon(
                isTotp ? Icons.security : Icons.email_outlined,
                color: const Color(0xFFFF4655),
                size: 48,
              ),
              const SizedBox(height: 20),
              Text(
                isTotp ? 'Authenticator Code' : 'Check Your Email',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isTotp
                    ? 'Enter the 6-digit code from your Authenticator App\n(Google Authenticator, Authy, etc.)'
                    : maskedEmail.isNotEmpty
                        ? 'Enter the 6-digit code sent to $maskedEmail'
                        : 'Enter the 6-digit code sent to your email.',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Error
              if (state is LoginError) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4655).withAlpha(20),
                    border: Border.all(
                        color: const Color(0xFFFF4655).withAlpha(80)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    state.message,
                    style: const TextStyle(
                        color: Color(0xFFFF4655), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 6-digit input boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) => _buildDigitBox(i, isLoading)),
              ),
              const SizedBox(height: 40),

              // Verify button
              FilledButton(
                onPressed: isLoading || _code.length != 6
                    ? null
                    : () => controller.submitMfaCode(_code),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4655),
                  disabledBackgroundColor:
                      const Color(0xFFFF4655).withAlpha(60),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'VERIFY',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5),
                      ),
              ),

              const SizedBox(height: 20),

              // Hint text
              Text(
                isTotp
                    ? 'Open your Authenticator App and enter the current code.'
                    : 'The code expires in a few minutes. Check your spam folder if not received.',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
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
      height: 56,
      child: TextField(
        controller: _ctrlList[index],
        focusNode: _focusList[index],
        enabled: !disabled,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
        keyboardType: TextInputType.number,
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF1A2634),
          border: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFF3D4C5E)),
            borderRadius: BorderRadius.circular(4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFF3D4C5E)),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFFFF4655), width: 2),
            borderRadius: BorderRadius.circular(4),
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
