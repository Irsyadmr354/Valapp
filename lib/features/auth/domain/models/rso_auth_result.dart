sealed class RsoAuthResult {
  const RsoAuthResult();
}

class RsoAuthSuccess extends RsoAuthResult {
  final String redirectUrl;
  const RsoAuthSuccess(this.redirectUrl);
}

class RsoAuthMultifactor extends RsoAuthResult {
  final String method;
  final List<String> methods;
  final String? email;
  final int codeLength;

  const RsoAuthMultifactor({
    required this.method,
    required this.methods,
    this.email,
    this.codeLength = 6,
  });
}

class RsoAuthError extends RsoAuthResult {
  final String message;
  final bool isCaptcha;

  const RsoAuthError(this.message, {this.isCaptcha = false});
}
