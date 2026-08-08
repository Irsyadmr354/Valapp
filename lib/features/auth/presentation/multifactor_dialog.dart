import 'package:flutter/material.dart';
import '../../../shared/utils/app_colors.dart';
import '../domain/models/rso_auth_result.dart';

class MultifactorDialog extends StatefulWidget {
  final RsoAuthMultifactor challenge;
  final Future<void> Function(String code, bool rememberDevice) onVerify;

  const MultifactorDialog({
    super.key,
    required this.challenge,
    required this.onVerify,
  });

  @override
  State<MultifactorDialog> createState() => _MultifactorDialogState();
}

class _MultifactorDialogState extends State<MultifactorDialog> {
  final _codeController = TextEditingController();
  bool _rememberDevice = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.length < widget.challenge.codeLength) {
      setState(() {
        _errorMessage = 'Please enter the full ${widget.challenge.codeLength}-digit verification code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onVerify(code, _rememberDevice);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('AuthException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = widget.challenge.method.toLowerCase() == 'email';
    final emailText = widget.challenge.email ?? '';

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.redSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.red.withAlpha(128)),
                ),
                child: Icon(
                  isEmail ? Icons.mark_email_read_rounded : Icons.security_rounded,
                  color: AppColors.red,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'TWO-FACTOR AUTHENTICATION',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isEmail
                  ? 'Enter the ${widget.challenge.codeLength}-digit verification code sent to your email${emailText.isNotEmpty ? ' ($emailText)' : ''}.'
                  : 'Enter the ${widget.challenge.codeLength}-digit code from your Authenticator App or approve the request in Riot Mobile.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // PIN Input TextField
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: widget.challenge.codeLength,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 10,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                hintText: '•' * widget.challenge.codeLength,
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withAlpha(128),
                  fontSize: 22,
                  letterSpacing: 10,
                ),
                filled: true,
                fillColor: AppColors.bgCard2,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.red, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 16),

            // Remember device checkbox
            GestureDetector(
              onTap: () {
                setState(() {
                  _rememberDevice = !_rememberDevice;
                });
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberDevice,
                      onChanged: (val) {
                        setState(() {
                          _rememberDevice = val ?? true;
                        });
                      },
                      activeColor: AppColors.red,
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Remember this device for 30 days',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                disabledBackgroundColor: AppColors.red.withAlpha(128),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'VERIFY & SIGN IN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),

            const SizedBox(height: 8),

            // Cancel Button
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
