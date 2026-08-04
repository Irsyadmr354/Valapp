import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/exceptions/auth_exception.dart';
import 'package:valorant_app/features/auth/data/oauth_flow.dart';

void main() {
  group('OAuthFlow', () {
    test('accepts an exact redirect with matching state and nonce', () {
      final access = _jwt({'sub': 'player-1'});
      final id = _jwt({'sub': 'player-1', 'nonce': 'nonce-1'});
      final redirect = Uri.https('playvalorant.com', '/opt_in').replace(
        fragment: Uri(queryParameters: {
          'access_token': access,
          'id_token': id,
          'expires_in': '3600',
          'state': 'state-1',
        }).query,
      );

      final tokens = OAuthFlow.parseTokenRedirect(
        redirect.toString(),
        expectedState: 'state-1',
        expectedNonce: 'nonce-1',
      );

      expect(tokens['access_token'], access);
      expect(tokens['expires_in'], '3600');
    });

    test('rejects lookalike redirect origins and paths', () {
      for (final value in [
        'https://playvalorant.com.evil.test/opt_in#state=s',
        'https://playvalorant.com/opt_in/extra#state=s',
        'https://user@playvalorant.com/opt_in#state=s',
        'http://playvalorant.com/opt_in#state=s',
      ]) {
        expect(
          () => OAuthFlow.parseTokenRedirect(
            value,
            expectedState: 's',
            expectedNonce: 'n',
          ),
          throwsA(isA<AuthException>()),
        );
      }
    });

    test('rejects missing or mismatched state and nonce', () {
      final access = _jwt({'sub': 'player-1'});
      final id = _jwt({'sub': 'player-1', 'nonce': 'wrong'});
      final redirect = Uri.https('playvalorant.com', '/opt_in').replace(
        fragment: Uri(queryParameters: {
          'access_token': access,
          'id_token': id,
          'expires_in': '3600',
          'state': 'wrong',
        }).query,
      );

      expect(
        () => OAuthFlow.parseTokenRedirect(
          redirect.toString(),
          expectedState: 'expected',
          expectedNonce: 'nonce-1',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('creates unique high-entropy attempts', () {
      final first = OAuthAttempt.create();
      final second = OAuthAttempt.create();

      expect(first.state, isNot(second.state));
      expect(first.nonce, isNot(second.nonce));
      expect(first.state.length, greaterThanOrEqualTo(40));
      expect(first.authorizeUri.queryParameters['state'], first.state);
      expect(first.authorizeUri.queryParameters['nonce'], first.nonce);
    });
  });
}

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(payload)}.signature';
}
