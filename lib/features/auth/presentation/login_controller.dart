import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../domain/models/credentials.dart';
/// State for the login flow.
sealed class LoginState {
  const LoginState();
}

class LoginIdle extends LoginState {
  const LoginIdle();
}

class LoginLoading extends LoginState {
  const LoginLoading();
}

class LoginNeedsMfa extends LoginState {
  final String maskedEmail;
  const LoginNeedsMfa(this.maskedEmail);
}

class LoginSuccess extends LoginState {
  final Credentials credentials;
  const LoginSuccess(this.credentials);
}

class LoginError extends LoginState {
  final String message;
  const LoginError(this.message);
}

class MfaLoading extends LoginState {
  const MfaLoading();
}

// ── Controller ────────────────────────────────────────────────────────────────

class LoginController extends StateNotifier<LoginState> {
  LoginController(this._ref) : super(const LoginIdle());

  final Ref _ref;

  Future<void> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = const LoginError('Username and password cannot be empty.');
      return;
    }

    state = const LoginLoading();
    try {
      final repo = await _ref.read(authRepositoryProvider.future);
      final result = await repo.login(username.trim(), password);

      if (result['type'] == 'multifactor') {
        state = LoginNeedsMfa(result['email'] as String? ?? '');
      } else if (result['type'] == 'response') {
        final credentials =
            await repo.completeLogin(result['uri'] as String);
        state = LoginSuccess(credentials);
      }
    } on InvalidCredentialsException {
      state = const LoginError('Invalid username or password.');
    } on CaptchaRequiredException {
      state = const LoginError(
          'CAPTCHA detected. Please try again in a few minutes.');
    } on AuthException catch (e) {
      state = LoginError(e.message);
    } catch (_) {
      state = const LoginError(
          'An unexpected error occurred. Please check your connection.');
    }
  }

  Future<void> submitMfaCode(String code) async {
    if (code.length != 6) {
      state = const LoginError('Please enter the 6-digit code from your email.');
      return;
    }

    state = const MfaLoading();
    try {
      final repo = await _ref.read(authRepositoryProvider.future);
      final credentials = await repo.completeMfa(code);
      state = LoginSuccess(credentials);
    } on InvalidMfaCodeException {
      state = const LoginError('Incorrect or expired code. Try again.');
    } on AuthException catch (e) {
      state = LoginError(e.message);
    } catch (_) {
      state = const LoginError('Failed to verify code. Check your connection.');
    }
  }

  void reset() => state = const LoginIdle();
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>(
  (ref) => LoginController(ref),
);
