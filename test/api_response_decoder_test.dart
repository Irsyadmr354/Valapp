import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/exceptions/api_exception.dart';
import 'package:valorant_app/core/network/api_response_decoder.dart';

void main() {
  group('ApiResponseDecoder.decodeMap', () {
    test('returns Map<String, dynamic> unchanged', () {
      final map = {'Subject': 'abc', 'Version': 1};
      expect(ApiResponseDecoder.decodeMap(map), same(map));
    });

    test('converts a raw Map into Map<String, dynamic>', () {
      final result = ApiResponseDecoder.decodeMap({'a': 1} as Map);
      expect(result, {'a': 1});
    });

    test('parses a JSON object string body', () {
      final result =
          ApiResponseDecoder.decodeMap('{"Subject":"abc","Total":4}');
      expect(result['Subject'], 'abc');
      expect(result['Total'], 4);
    });

    test('throws ApiException on an empty map body', () {
      expect(
        () => ApiResponseDecoder.decodeMap(<String, dynamic>{}),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on empty string body', () {
      expect(
        () => ApiResponseDecoder.decodeMap(''),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on a JSON list body', () {
      expect(
        () => ApiResponseDecoder.decodeMap('[1,2,3]'),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on HTML/truncated body', () {
      expect(
        () => ApiResponseDecoder.decodeMap('<html>Service Unavailable</html>'),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on malformed JSON string body', () {
      expect(
        () => ApiResponseDecoder.decodeMap('{"Subject":'),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on null body', () {
      expect(
        () => ApiResponseDecoder.decodeMap(null),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on a primitive body', () {
      expect(
        () => ApiResponseDecoder.decodeMap(42),
        throwsA(isA<ApiException>()),
      );
    });

    test('includes the source label in the exception message', () {
      try {
        ApiResponseDecoder.decodeMap('<html></html>', source: 'mmr/v1');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.message, contains('mmr/v1'));
      }
    });
  });

  group('ApiResponseDecoder endpoint shapes', () {
    test('decodeList accepts JSON arrays and rejects objects', () {
      expect(
          ApiResponseDecoder.decodeList('[{"Subject":"abc"}]'), hasLength(1));
      expect(
        () => ApiResponseDecoder.decodeList('{"Subject":"abc"}'),
        throwsA(isA<ApiException>()),
      );
    });

    test('requireShape rejects missing or incorrectly typed fields', () {
      expect(
        () => ApiResponseDecoder.requireShape(
          {'Matches': <dynamic>[]},
          source: 'competitive updates',
          lists: ['Matches'],
        ),
        returnsNormally,
      );
      expect(
        () => ApiResponseDecoder.requireShape(
          {'Matches': <String, dynamic>{}},
          source: 'competitive updates',
          lists: ['Matches'],
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
